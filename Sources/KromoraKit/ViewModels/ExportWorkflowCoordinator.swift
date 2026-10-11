import AppKit
import Foundation

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
    private(set) var pendingShareURL: URL?
    private(set) var externalEditorHandoffURL: URL?
    private var pendingShareExports: [URL: URL] = [:]
    private var activeShareDirectories: Set<URL> = []
    private var sharePickerSessions: [URL: SharePickerSession] = [:]
    private let shareRoot: URL

    init(
        export: ExportCoordinator,
        destination: (any ExportWorkflowDestination)? = nil,
        shareRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Kromora Share Exports", isDirectory: true)
    ) {
        self.export = export
        self.destination = destination
        self.shareRoot = shareRoot
    }

    static func shareDialogMode(for selectionCount: Int) -> ShareDialogMode {
        selectionCount > 1 ? .selectedPhotos : .singlePhoto
    }

    // MARK: - Completion routing

    func exportFailed() {
        externalEditorHandoffURL = nil
        let directories = Set(pendingShareExports.values)
        pendingShareExports.removeAll()
        pendingShareURL = nil
        for directory in directories {
            removeShareExport(at: directory)
        }
    }

    func exportCompleted(at url: URL) {
        if externalEditorHandoffURL == url {
            externalEditorHandoffURL = nil
            NSWorkspace.shared.open(url)
        } else if let directory = pendingShareExports.removeValue(forKey: url) {
            if pendingShareURL == url { pendingShareURL = nil }
            presentSharePicker(for: [url], in: directory)
        }
    }

    // MARK: - Entry points

    /// Share the active photo, or every selected photo when the selection has more than one item.
    /// File ▸ Export remains the single-photo save-panel command.
    func shareDialog() {
        guard let destination else { return }
        switch Self.shareDialogMode(for: destination.exportSelectionCount) {
        case .singlePhoto: shareCurrentExport()
        case .selectedPhotos: shareSelectedExports()
        }
    }

    /// Export the open image at full resolution. It exports `document`, not the display request —
    /// holding Space to compare must not change what ⌘S writes.
    func exportDialog() {
        guard let destination, let request = destination.exportSingleRequest else {
            self.destination?.setExportStatus("Open an image first")
            return
        }
        export.exportDialog(
            source: request.source,
            assetID: destination.exportActiveAssetID,
            document: request.document,
            lut: request.lut,
            suggestedBaseName: request.baseName
        )
    }

    /// Render a full-resolution TIFF for the system's default TIFF editor. The active source remains
    /// read-only; the returned TIFF is imported through Open Image as a new library item.
    func editInExternalEditor() {
        guard let destination, let request = destination.exportSingleRequest else {
            self.destination?.setExportStatus("Open an image first")
            return
        }
        let panel = NSSavePanel()
        panel.title = "Edit in External Editor"
        panel.nameFieldStringValue = request.baseName + "_external.tiff"
        panel.allowedContentTypes = [.tiff]
        panel.directoryURL = export.defaultFolderURL?()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        externalEditorHandoffURL = url
        export.performExport(
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

    /// Copy the untouched source and its edit recipe into a checksum-verified portable bundle.
    func exportOriginalWithSettings() {
        guard let destination, let request = destination.exportSingleRequest else {
            self.destination?.setExportStatus("Open an image first")
            return
        }
        let privacyAlert = NSAlert()
        privacyAlert.messageText = "Keep the original's embedded metadata?"
        privacyAlert.informativeText = "The bundle preserves the original file byte-for-byte. It may contain location metadata such as GPS coordinates. The active library original will remain unchanged."
        privacyAlert.addButton(withTitle: "Keep Original Metadata")
        privacyAlert.addButton(withTitle: "Cancel")
        guard privacyAlert.runModal() == .alertFirstButtonReturn else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose Bundle Location"
        panel.prompt = "Export Bundle"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = export.defaultFolderURL?()
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        let access = SecurityScopedResourceAccess.systemGranted(for: parent)
        let sourceName = destination.exportSourceName
        let stem = URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
        let name = stem.isEmpty ? "Photo" : stem
        let bundleURL = parent.appendingPathComponent(
            "\(name).\(OriginalSettingsBundle.fileExtension)", isDirectory: true
        )
        destination.setExportStatus("Preparing original + settings bundle…")
        Task { @MainActor [weak self, access] in
            defer { access.release() }
            do {
                try await OriginalSettingsBundle.create(
                    source: request.source,
                    sourceName: sourceName,
                    document: request.document,
                    destination: bundleURL,
                    locationMetadataIncluded: true
                )
                self?.destination?.setExportStatus(
                    "Original + settings bundle exported; the original remains read-only."
                )
            } catch {
                self?.destination?.presentExportError("Bundle export failed: \(error.localizedDescription)")
            }
        }
    }

    /// Apply the current look to every imported image and export them all to a chosen folder.
    func batchExportDialog() {
        guard let destination else { return }
        let request = destination.exportBatchRequest(selectedOnly: false)
        export.batchExportDialog(items: request.items, document: request.document, lut: request.lut)
    }

    /// Export exactly the library selection. Selection and edit focus are separate in the grid model.
    func exportSelectedDialog() {
        guard let destination else { return }
        let request = destination.exportBatchRequest(selectedOnly: true)
        guard !request.items.isEmpty else {
            destination.setExportStatus("Select at least one photo to export")
            return
        }
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
        destination.setExportStatus("Preparing selected photos for sharing…")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.export.performBatchExport(
                request.items,
                document: request.document,
                lut: request.lut,
                options: ExportOptions(format: .tiff, destination: .folder(directory)),
                to: directory
            )
            guard outcome.exported > 0,
                  let urls = try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil
                  ).filter({ $0.pathExtension.lowercased() == "tif" || $0.pathExtension.lowercased() == "tiff" }),
                  !urls.isEmpty else {
                self.removeShareExport(at: directory)
                return
            }
            self.presentSharePicker(for: urls, in: directory)
        }
    }

    private func shareCurrentExport() {
        guard let destination, let request = destination.exportSingleRequest else {
            self.destination?.setExportStatus("Open an image first")
            return
        }
        let directory = makeShareDirectory()
        let url = directory.appendingPathComponent(request.baseName + "_share.tiff")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            removeShareExport(at: directory)
            destination.presentExportError("Could not prepare a share export: \(error.localizedDescription)")
            return
        }
        pendingShareURL = url
        pendingShareExports[url] = directory
        export.performExport(
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
            to: url
        )
    }

    private func presentSharePicker(for urls: [URL], in directory: URL) {
        guard let view = NSApplication.shared.keyWindow?.contentView else {
            removeShareExport(at: directory)
            destination?.setExportStatus("Share unavailable: no window to present the sharing menu")
            return
        }
        let picker = NSSharingServicePicker(items: urls)
        let delegate = SharePickerDelegate { [weak self] in
            self?.removeShareExport(at: directory)
        }
        picker.delegate = delegate
        sharePickerSessions[directory.standardizedFileURL] = SharePickerSession(
            picker: picker,
            delegate: delegate
        )
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
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
