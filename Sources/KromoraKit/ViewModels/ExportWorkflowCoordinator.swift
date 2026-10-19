import AppKit
import Foundation
import UniformTypeIdentifiers

/// The values a single-photo export snapshots from the active document.
struct ExportSingleRequest {
    let source: ImageSource
    let document: EditDocument
    let lut: CubeLUT?
    let baseName: String
}

/// The values a batch export snapshots from the collection. Items carry only `Sendable` data.
struct ExportBatchRequest {
    let items: [ExportCoordinator.BatchItem]
    let document: EditDocument
    let lut: CubeLUT?
}

/// Snapshots and presentation stay at the composition root; the workflow never reads the model.
@MainActor
protocol ExportWorkflowDestination: AnyObject {
    var exportSelectionCount: Int { get }
    var exportActiveAssetID: PhotoAssetID? { get }
    var exportSourceName: String { get }
    var exportSingleRequest: ExportSingleRequest? { get }
    func exportBatchRequest(selectedOnly: Bool) -> ExportBatchRequest
    func setExportStatus(_ message: String)
    func presentExportError(_ message: String)
}

/// Owns export entry points: the save/folder panels, Share, Edit in External Editor, and the
/// original + settings bundle, plus the handoff state that follows a completed render. Rendering and
/// disk writes remain in `ExportCoordinator`.
@MainActor
final class ExportWorkflowCoordinator {
    /// The destination flow used by the Edit toolbar's Share action. A single selected photo keeps
    /// the save-panel behavior, while a multi-selection is exported to one temporary folder.
    enum ShareDialogMode: Equatable {
        case singlePhoto
        case selectedPhotos
    }

    typealias SingleRequest = ExportSingleRequest
    typealias BatchRequest = ExportBatchRequest

    weak var destination: (any ExportWorkflowDestination)?
    private let export: ExportCoordinator
    private let sheets: any SheetPresenting
    private(set) var externalEditorHandoffURL: URL?
    /// The Share control the picker anchors to, registered by `ShareAnchorView`.
    weak var shareAnchorView: NSView?
    private var activeShareDirectories: Set<URL> = []
    private var sharePickerSessions: [URL: SharePickerSession] = [:]
    private let shareRoot: URL
    /// Presents the picker at the Share control. Tests replace it to observe ordering.
    var showPicker: ([Any], NSSharingServicePicker, NSView) -> Void = { _, picker, view in
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    init(
        export: ExportCoordinator,
        sheets: any SheetPresenting = AppKitSheetPresenter(),
        destination: (any ExportWorkflowDestination)? = nil,
        shareRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kromora Share Exports", isDirectory: true)
    ) {
        self.export = export
        self.sheets = sheets
        self.destination = destination
        self.shareRoot = shareRoot
    }

    static func shareDialogMode(for selectionCount: Int) -> ShareDialogMode {
        selectionCount > 1 ? .selectedPhotos : .singlePhoto
    }

    // MARK: - Completion routing

    func exportFailed() {
        externalEditorHandoffURL = nil
    }

    func exportCompleted(at url: URL) {
        if externalEditorHandoffURL == url {
            externalEditorHandoffURL = nil
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Entry points

    /// Refuses a new export, Share, or bundle command while one is running. The running job is
    /// left alone and the user sees why nothing happened.
    private func refusedWhileBusy() -> Bool {
        guard export.isExporting else { return false }
        destination?.setExportStatus("Another export is already running. Wait for it to finish.")
        return true
    }

    /// Share the active photo, or every selected photo when the selection has more than one item.
    func shareDialog() {
        guard let destination, !refusedWhileBusy() else { return }
        switch Self.shareDialogMode(for: destination.exportSelectionCount) {
        case .singlePhoto: shareCurrentExport()
        case .selectedPhotos: shareSelectedExports()
        }
    }

    /// The one edited-image export: the explicit Library selection, or the active photo when
    /// nothing is selected. Each photo renders from its own edit and Look into a chosen folder, so
    /// one photo and many share the same options. Holding Space to compare never changes it.
    func exportDialog() {
        guard !refusedWhileBusy() else { return }
        guard let destination else { return }
        let request = destination.exportBatchRequest(selectedOnly: true)
        guard !request.items.isEmpty else {
            destination.setExportStatus("Open an image first")
            return
        }
        export.batchExportDialog(items: request.items, document: request.document, lut: request.lut)
    }

    /// Render a full-resolution TIFF for the system's default TIFF editor. The active source remains
    /// read-only; the returned TIFF is imported through Open Image as a new library item.
    @discardableResult
    func editInExternalEditor() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self, !self.refusedWhileBusy() else { return }
            guard let destination = self.destination,
                  let request = destination.exportSingleRequest else {
                self.destination?.setExportStatus("Open an image first")
                return
            }
            let directoryURL = self.export.defaultFolderURL?()
            guard let url = await self.sheets.chooseSaveURL(configure: { panel in
                panel.title = "Edit in External Editor"
                panel.nameFieldStringValue = request.baseName + "_external.tiff"
                panel.allowedContentTypes = [.tiff]
                panel.directoryURL = directoryURL
            }) else { return }
            self.externalEditorHandoffURL = url
            self.export.performExport(
                source: request.source,
                assetID: destination.exportActiveAssetID,
                document: request.document,
                lut: request.lut,
                options: ExportOptions(
                    format: .tiff,
                    destination: .file(url),
                    metadata: .preserve,
                    location: .exclude
                ),
                to: url,
                access: .systemGranted(for: url)
            )
        }
    }

    /// Copy the untouched source and its edit recipe into a checksum-verified portable bundle.
    @discardableResult
    func exportOriginalWithSettings() -> Task<Void, Never> {
        Task { [weak self] in
            await self?.runExportOriginalWithSettings()
        }
    }

    private func runExportOriginalWithSettings() async {
        guard !refusedWhileBusy() else { return }
        guard let destination, let request = destination.exportSingleRequest else {
            self.destination?.setExportStatus("Open an image first")
            return
        }
        let sourceName = destination.exportSourceName
        guard await sheets.confirm(
            message: "Keep the original's embedded metadata?",
            informativeText: "The bundle preserves the original file byte-for-byte. It may contain location metadata such as GPS coordinates. The active library original will remain unchanged.",
            style: .warning,
            buttons: ["Keep Original Metadata", "Cancel"]
        ) else { return }
        let directoryURL = export.defaultFolderURL?()
        guard let parent = await sheets.chooseOpenURLs(configure: { panel in
            panel.title = "Choose Bundle Location"
            panel.prompt = "Export Bundle"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = directoryURL
        })?.first else { return }
        // The sheet suspended this method, so the open photo may have changed. The snapshot taken
        // before the prompts is what the user confirmed and is what gets bundled.
        // Another export may have started while the prompts were up.
        guard !refusedWhileBusy() else { return }
        let access = SecurityScopedResourceAccess.systemGranted(for: parent)
        let stem = URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
        let name = stem.isEmpty ? "Photo" : stem
        let bundleURL = parent.appendingPathComponent(
            "\(name).\(OriginalSettingsBundle.fileExtension)", isDirectory: true
        )
        destination.setExportStatus("Preparing original + settings bundle…")
        // Registered with the export coordinator so quit and shutdown see and cancel it.
        let source = request.source
        let document = request.document
        do {
            try await export.runJob(.originalBundle) {
                defer { access.release() }
                try await OriginalSettingsBundle.create(
                    source: source,
                    sourceName: sourceName,
                    document: document,
                    destination: bundleURL,
                    locationMetadataIncluded: true
                )
            }
            self.destination?.setExportStatus(
                "Original + settings bundle exported; the original remains read-only."
            )
        } catch is ExportJobBusyError {
            access.release()
        } catch is CancellationError {
            return
        } catch {
            self.destination?.presentExportError("Bundle export failed: \(error.localizedDescription)")
        }
    }

    /// Apply the current look to every imported image and export them all to a chosen folder.
    func batchExportDialog() {
        guard let destination, !refusedWhileBusy() else { return }
        let request = destination.exportBatchRequest(selectedOnly: false)
        export.batchExportDialog(items: request.items, document: request.document, lut: request.lut)
    }

    // MARK: - Share

    /// Removes abandoned exports from earlier launches, while keeping directories still owned by
    /// an in-flight export or sharing service, then returns a fresh directory.
    private func makeShareDirectory() -> URL {
        removeAbandonedShareExports()
        let directory = shareRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .standardizedFileURL
        activeShareDirectories.insert(directory)
        return directory
    }

    /// Sweeps directories left by a previous launch without disturbing live share sessions.
    private func removeAbandonedShareExports() {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: shareRoot, includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where !activeShareDirectories.contains(url.standardizedFileURL) {
            try? fileManager.removeItem(at: url)
        }
        if activeShareDirectories.isEmpty {
            try? fileManager.removeItem(at: shareRoot)
        }
    }

    private func removeShareExport(at directory: URL) {
        let directory = directory.standardizedFileURL
        activeShareDirectories.remove(directory)
        sharePickerSessions.removeValue(forKey: directory)
        try? FileManager.default.removeItem(at: directory)
        if activeShareDirectories.isEmpty {
            try? FileManager.default.removeItem(at: shareRoot)
        }
    }

    private func shareSelectedExports() {
        guard let destination else { return }
        let request = destination.exportBatchRequest(selectedOnly: true)
        guard !request.items.isEmpty else {
            destination.setExportStatus("Select at least one photo to share")
            return
        }
        let directory = makeShareDirectory()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            removeShareExport(at: directory)
            destination.presentExportError("Could not prepare share exports: \(error.localizedDescription)")
            return
        }
        // The picker appears before any render. Each item is a lazy file representation that
        // renders only when the chosen service loads it, from the snapshot taken here.
        var usedNameKeys = Set<String>()
        let providers = request.items.map { item -> NSItemProvider in
            let stem = URL(fileURLWithPath: item.name).deletingPathExtension().lastPathComponent
            let base = stem.isEmpty ? "Photo" : stem
            var candidate = base
            var counter = 2
            // The share directory usually lives on a case-insensitive APFS volume. Distinct
            // source names that differ only by case (or Unicode canonical form) must not map to
            // the same lazily written file there.
            while !usedNameKeys.insert(Self.shareFilenameCollisionKey(candidate)).inserted {
                candidate = "\(base) \(counter)"
                counter += 1
            }
            let name = candidate
            let provider = NSItemProvider()
            provider.suggestedName = name
            provider.registerFileRepresentation(
                forTypeIdentifier: ShareExportPolicy.providerContentType.identifier,
                fileOptions: [],
                visibility: .all
            ) { [weak self] completion in
                let task = Task { @MainActor in
                    guard let self else {
                        completion(nil, false, CocoaError(.userCancelled))
                        return
                    }
                    do {
                        let url = try await self.export.runJob(.share) {
                            try await self.renderShareFile(
                                name: name, into: directory
                            ) { options in
                                try await self.export.renderEncodedData(
                                    for: item, document: request.document, lut: request.lut,
                                    options: options
                                )
                            }
                        }
                        completion(url, false, nil)
                    } catch {
                        completion(nil, false, error)
                    }
                }
                return Self.cancellationProgress(for: task)
            }
            return provider
        }
        presentSharePicker(for: providers, in: directory)
    }

    /// The handle a sharing service uses to cancel a lazy render it no longer wants.
    nonisolated private static func cancellationProgress(for task: Task<Void, Never>) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        progress.cancellationHandler = { task.cancel() }
        return progress
    }

    private static func shareFilenameCollisionKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive], locale: nil)
            .precomposedStringWithCanonicalMapping
    }

    /// Shows the picker at once. The photo renders when the user picks a service, so there is no
    /// silent delay and nothing is written for a cancelled picker.
    private func shareCurrentExport() {
        guard let destination, let request = destination.exportSingleRequest else {
            self.destination?.setExportStatus("Open an image first")
            return
        }
        let directory = makeShareDirectory()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            removeShareExport(at: directory)
            destination.presentExportError("Could not prepare a share export: \(error.localizedDescription)")
            return
        }
        let assetID = destination.exportActiveAssetID
        let provider = NSItemProvider()
        provider.suggestedName = request.baseName
        provider.registerFileRepresentation(
            forTypeIdentifier: ShareExportPolicy.providerContentType.identifier,
            fileOptions: [],
            visibility: .all
        ) { [weak self] completion in
            let task = Task { @MainActor in
                guard let self else {
                    completion(nil, false, CocoaError(.userCancelled))
                    return
                }
                do {
                    let url = try await self.export.runJob(.share) {
                        try await self.renderShareFile(
                            request, assetID: assetID, into: directory
                        )
                    }
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return Self.cancellationProgress(for: task)
        }
        presentSharePicker(for: [provider], in: directory)
    }

    /// Renders the share file into `directory`: HEIC, or JPEG when HEIC encoding fails.
    func renderShareFile(
        _ request: SingleRequest, assetID: PhotoAssetID?, into directory: URL
    ) async throws -> URL {
        try await renderShareFile(name: request.baseName, into: directory) { options in
            try await self.export.renderEncodedData(
                source: request.source, assetID: assetID, document: request.document,
                lut: request.lut, options: options
            )
        }
    }

    /// Encodes with the share policy, retrying as JPEG when HEIC fails so no item is dropped.
    func renderShareFile(
        name: String, into directory: URL,
        encode: (ExportOptions) async throws -> Data
    ) async throws -> URL {
        var format = ShareExportPolicy.preferredFormat
        let data: Data
        do {
            data = try await encode(ShareExportPolicy.options(format: format))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            format = ShareExportPolicy.fallbackFormat
            data = try await encode(ShareExportPolicy.options(format: format))
        }
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name + "_share." + format.fileExtension)
        try await Self.write(data, to: url)
        return url
    }

    nonisolated private static func write(_ data: Data, to url: URL) async throws {
        try data.write(to: url, options: .atomic)
    }

    private func presentSharePicker(for items: [Any], in directory: URL) {
        // Prefer the toolbar control; fall back to the key window so a missing anchor never
        // discards a share that is ready to present.
        let fallback = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView
        let anchor = shareAnchorView.flatMap { $0.window != nil ? $0 : nil }
        guard let view = anchor ?? fallback else {
            removeShareExport(at: directory)
            destination?.setExportStatus("Share unavailable: no window to present the sharing menu")
            return
        }
        let picker = NSSharingServicePicker(items: items)
        let delegate = SharePickerDelegate { [weak self] in
            self?.removeShareExport(at: directory)
        }
        picker.delegate = delegate
        sharePickerSessions[directory.standardizedFileURL] = SharePickerSession(
            picker: picker,
            delegate: delegate
        )
        showPicker(items, picker, view)
    }
}

/// What Share exports: a message-sized file, never the full-resolution 16-bit TIFF used for
/// editing handoff. All values live here so the policy has one place to change.
enum ShareExportPolicy {
    /// HEIC keeps files small with good quality; JPEG is the fallback when HEIC encoding fails.
    static let preferredFormat: ExportFormat = .heif
    static let fallbackFormat: ExportFormat = .jpeg
    /// Rendering starts after the picker is shown, so the final concrete format is not known
    /// when the provider registers. Advertise their shared image type; each returned file keeps
    /// the extension that matches the encoder that succeeded.
    static let providerContentType = UTType.image
    /// Longest side in pixels; larger photos are scaled down, smaller ones are never upscaled.
    static let longEdge = 4096
    static let quality = 0.85

    /// Encodes in `WorkingSpace.current` (sRGB or Display P3), with location metadata excluded.
    static func options(
        format: ExportFormat = preferredFormat, destination: ExportDestination? = nil
    ) -> ExportOptions {
        ExportOptions(
            format: format,
            quality: quality,
            sizing: .longEdge(longEdge),
            colorSpace: .current,
            destination: destination,
            metadata: .preserve,
            location: .exclude
        )
    }
}

@MainActor
private final class SharePickerSession {
    let picker: NSSharingServicePicker
    let delegate: SharePickerDelegate

    init(picker: NSSharingServicePicker, delegate: SharePickerDelegate) {
        self.picker = picker
        self.delegate = delegate
    }
}

/// Keeps temporary share files alive until the chosen service finishes, fails, or the picker is
/// dismissed without a choice.
@MainActor
final class SharePickerDelegate: NSObject, @MainActor NSSharingServicePickerDelegate, @MainActor NSSharingServiceDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard let service else {
            onFinish()
            return
        }
        service.delegate = self
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        onFinish()
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        onFinish()
    }
}
