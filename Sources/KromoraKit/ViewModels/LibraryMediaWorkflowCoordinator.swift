import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// The value handed to the composition root after a removable-media selection has been
/// validated.  The coordinator deliberately does not know whether the destination is the
/// portable package or the legacy presentation projection.
struct RemovableMediaImportRequest: Sendable {
    let volume: MediaVolume
    let files: [MediaVolumeFile]
    let totalSelected: Int
    let operationID: UUID
    let access: SecurityScopedResourceAccess?

    init(
        volume: MediaVolume,
        files: [MediaVolumeFile],
        totalSelected: Int? = nil,
        operationID: UUID = UUID(),
        access: SecurityScopedResourceAccess? = nil
    ) {
        self.volume = volume
        self.files = files
        self.totalSelected = totalSelected ?? files.count
        self.operationID = operationID
        self.access = access
    }
}
/// Owns library-adjacent presentation work that can outlive a menu action: mounted-volume
/// discovery, volume scanning, selection, source-folder dialog/drop routing, and cancellation.
///
/// Durable admission remains a value handoff to the composition root. This keeps package writes,
/// managed-versus-referenced policy, and active-source navigation in one place while preventing
/// provider tasks and security-scoped access from becoming another AppViewModel concern.
@MainActor
final class LibraryMediaWorkflowCoordinator: ObservableObject {
    private enum DropAccess {
        case scoped(SecurityScopedResourceAccess)
        case unscoped
    }

    private struct MediaAccessGrant {
        let volume: MediaVolume
        let access: SecurityScopedResourceAccess
    }

    @Published private(set) var removableMediaVolumes: [MediaVolume] = []
    @Published var isRemovableMediaSelectorPresented = false
    @Published private(set) var removableMediaVolume: MediaVolume?
    @Published private(set) var removableMediaFiles: [MediaVolumeFile] = []
    @Published private(set) var removableMediaWarnings: [String] = []
    @Published private(set) var isRemovableMediaScanning = false
    @Published private(set) var removableMediaSelection = MediaVolumeSelectionModel()
    @Published private(set) var removableMediaImportProgress: MediaVolumeImportProgress?

    private let provider: any MediaVolumeProviding
    private let fileDialog: any FileDialogProviding
    private let fileDropActionPolicy: FileDropActionPolicy
    private var discoveryTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var importValidationTask: Task<Void, Never>?
    private var removableMediaAccess: SecurityScopedResourceAccess?
    private var isShuttingDown = false
    private var importOperationID = UUID()

    var onStatus: (@MainActor (String) -> Void)?
    var onError: (@MainActor (String) -> Void)?
    var onSourceFolder: (@MainActor (URL, SecurityScopedResourceAccess?) -> Void)?
    var onImageURL: (@MainActor (URL, SecurityScopedResourceAccess?) -> Void)?
    var onImageURLs: (@MainActor ([URL], [SecurityScopedResourceAccess]) -> Void)?
    var onImportRequest: (@MainActor (RemovableMediaImportRequest) -> Void)?

    init(
        provider: any MediaVolumeProviding,
        fileDialog: any FileDialogProviding,
        fileDropActionPolicy: FileDropActionPolicy = FileDropActionPolicy()
    ) {
        self.provider = provider
        self.fileDialog = fileDialog
        self.fileDropActionPolicy = fileDropActionPolicy
    }

    var selectedRemovableMediaFiles: [MediaVolumeFile] {
        removableMediaFiles.filter { removableMediaSelection.contains($0) }
    }

    func chooseSourceFolder(startingAt directoryURL: URL?) {
        guard let url = fileDialog.chooseFolder(
            title: "Choose Source Folder", prompt: "Use Folder", startingAt: directoryURL,
            canCreateDirectories: false
        ) else { return }
        onSourceFolder?(url, .systemGranted(for: url))
    }

    func handleDroppedURL(_ url: URL) {
        switch fileDropActionPolicy.action(for: url) {
        case .openImage(let imageURL):
            guard let dropAccess = accessForDrop(imageURL) else { return }
            onImageURL?(imageURL, scope(from: dropAccess))
        case .openFolder(let folderURL):
            guard let dropAccess = accessForDrop(folderURL) else { return }
            onSourceFolder?(folderURL, scope(from: dropAccess))
        case .invalid: break
        }
    }

    /// Preserve the existing single-URL policy (including folder drops), while allowing a
    /// materialized multi-file drag to enter the library as one incremental import.
    func handleDroppedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if urls.count == 1 {
            handleDroppedURL(urls[0])
            return
        }

        var imageURLs: [URL] = []
        var accesses: [SecurityScopedResourceAccess] = []
        for url in urls {
            switch fileDropActionPolicy.action(for: url) {
            case .openImage(let imageURL):
                guard let dropAccess = accessForDrop(imageURL) else { continue }
                imageURLs.append(imageURL)
                if let access = scope(from: dropAccess) { accesses.append(access) }
            case .openFolder(let folderURL):
                guard let dropAccess = accessForDrop(folderURL) else { continue }
                onSourceFolder?(folderURL, scope(from: dropAccess))
            case .invalid: break
            }
        }
        if !imageURLs.isEmpty {
            onImageURLs?(imageURLs, accesses)
        }
    }

    private func accessForDrop(_ url: URL) -> DropAccess? {
        if let access = SecurityScopedResourceAccess.startAccessing(url) {
            return .scoped(access)
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            onError?("Kromora can't access the dropped item. Drop it again or use an Open panel to grant access.")
            return nil
        }
        return .unscoped
    }

    private func scope(from access: DropAccess) -> SecurityScopedResourceAccess? {
        guard case .scoped(let scope) = access else { return nil }
        return scope
    }

    func refreshRemovableMedia() {
        let operationID = beginImportOperation()
        discoveryTask?.cancel()
        let provider = self.provider
        discoveryTask = Task { [weak self] in
            let volumes = await provider.discover()
            guard let self, self.isCurrentImport(operationID), !Task.isCancelled else { return }
            self.removableMediaVolumes = volumes
        }
    }

    func importFromRemovableMedia() {
        let operationID = beginImportOperation()
        discoveryTask?.cancel()
        let provider = self.provider
        discoveryTask = Task { [weak self] in
            let volumes = await provider.discover()
            guard let self, self.isCurrentImport(operationID), !Task.isCancelled else { return }
            self.removableMediaVolumes = volumes
            guard let volume = volumes.first else {
                self.onStatus?("No supported removable media is mounted")
                return
            }
            self.openRemovableMedia(volume)
        }
    }

    func openRemovableMedia(_ volume: MediaVolume) {
        let operationID = beginImportOperation()
        scanTask?.cancel()
        importValidationTask?.cancel()
        removableMediaVolume = volume
        removableMediaFiles = []
        removableMediaWarnings = []
        removableMediaSelection.clear()
        removableMediaImportProgress = nil
        isRemovableMediaScanning = true
        isRemovableMediaSelectorPresented = true

        let provider = self.provider
        let access = removableMediaAccess
        scanTask = Task { [weak self] in
            do {
                let result = try await provider.scan(volume, access: access)
                guard let self, self.isCurrentImport(operationID), !Task.isCancelled else {
                    return
                }
                self.scanTask = nil
                self.publishScan(result)
            } catch is CancellationError {
                // Closing the selector is a normal cancellation.
            } catch {
                guard let self, self.isCurrentImport(operationID) else { return }
                guard case .permissionDenied = error as? MediaVolumeError,
                      provider.supportsInteractiveAccessGrant else {
                    guard self.isCurrentImport(operationID) else { return }
                    self.isRemovableMediaScanning = false
                    self.removableMediaWarnings = [error.localizedDescription]
                    return
                }
                guard let grant = self.requestAccess(for: volume) else {
                    self.isRemovableMediaScanning = false
                    self.removableMediaWarnings = ["Access to \(volume.name) was not granted."]
                    return
                }
                self.removableMediaAccess = grant.access
                self.removableMediaVolume = grant.volume
                self.removableMediaVolumes = self.removableMediaVolumes.map { candidate in
                    candidate.id == volume.id ? grant.volume : candidate
                }
                do {
                    let result = try await provider.scan(grant.volume, access: grant.access)
                    guard self.isCurrentImport(operationID), !Task.isCancelled else { return }
                    self.scanTask = nil
                    self.publishScan(result)
                } catch is CancellationError {
                    // A replacement operation drops the coordinator owner; this scan keeps its
                    // local grant alive until the provider has finished its read.
                } catch {
                    guard self.isCurrentImport(operationID) else { return }
                    self.removableMediaAccess = nil
                    self.isRemovableMediaScanning = false
                    self.removableMediaWarnings = [error.localizedDescription]
                }
            }
        }
    }

    func toggleRemovableMediaSelection(_ file: MediaVolumeFile) {
        removableMediaSelection.toggle(file)
    }

    func selectAllRemovableMedia() {
        removableMediaSelection.selectAll(in: removableMediaFiles)
    }

    func selectNoRemovableMedia() {
        removableMediaSelection.clear()
    }

    func cancelRemovableMediaImport() {
        _ = beginImportOperation()
        scanTask?.cancel()
        importValidationTask?.cancel()
        isRemovableMediaScanning = false
        isRemovableMediaSelectorPresented = false
        removableMediaImportProgress = nil
    }

    /// Validate the selected URLs while the granted volume scope is held, then publish a single
    /// immutable request. The destination owns the actual package/managed-library transaction.
    func importSelectedRemovableMedia() {
        guard let volume = removableMediaVolume else { return }
        let selected = selectedRemovableMediaFiles
        guard !selected.isEmpty else {
            onStatus?("Select at least one image to import")
            return
        }

        let access = removableMediaAccess
        removableMediaAccess = nil
        let operationID = beginImportOperation()
        importValidationTask?.cancel()
        removableMediaImportProgress = MediaVolumeImportProgress(
            total: selected.count, processed: 0, imported: 0, skipped: 0,
            currentName: nil, cancelled: false
        )
        importValidationTask = Task { [weak self, access] in
            var transferredAccess = false
            defer {
                if !transferredAccess { access?.release() }
            }
            guard let self, !self.isShuttingDown else { return }
            var usable: [MediaVolumeFile] = []
            for file in selected {
                guard self.isCurrentImport(operationID), !Task.isCancelled else {
                    if self.isCurrentImport(operationID) {
                        self.finishImport(
                            summary: ImportOutcomeSummary(
                                total: selected.count,
                                imported: usable.count,
                                skipped: selected.count - usable.count,
                                cancelled: true
                            ),
                            operationID: operationID
                        )
                    }
                    return
                }
                var progress = self.removableMediaImportProgress ?? .init(
                    total: selected.count, processed: 0, imported: 0, skipped: 0,
                    currentName: nil, cancelled: false
                )
                progress.currentName = file.filename
                if FileManager.default.isReadableFile(atPath: file.url.path) {
                    usable.append(file)
                    progress.imported += 1
                } else {
                    progress.skipped += 1
                    self.removableMediaWarnings.append(
                        "Skipped \(file.filename): the volume was removed or became unreadable."
                    )
                }
                progress.processed += 1
                self.removableMediaImportProgress = progress
                await Task.yield()
            }
            guard self.isCurrentImport(operationID), !Task.isCancelled else { return }
            guard !usable.isEmpty else {
                self.finishImport(
                    summary: ImportOutcomeSummary(
                        total: selected.count, skipped: selected.count
                    ),
                    operationID: operationID
                )
                self.isRemovableMediaSelectorPresented = false
                return
            }
            guard let onImportRequest = self.onImportRequest else {
                self.onError?("Removable media import could not start.")
                return
            }
            onImportRequest(
                RemovableMediaImportRequest(
                    volume: volume, files: usable, totalSelected: selected.count,
                    operationID: operationID, access: access
                )
            )
            transferredAccess = true
        }
    }

    func finishImport(summary: ImportOutcomeSummary, operationID: UUID? = nil) {
        if let operationID, !isCurrentImport(operationID) { return }
        removableMediaImportProgress = MediaVolumeImportProgress(
            total: summary.total,
            processed: summary.imported + summary.duplicates + summary.skipped + summary.failed,
            imported: summary.imported,
            duplicates: summary.duplicates,
            skipped: summary.skipped,
            failed: summary.failed,
            failureReasons: summary.failureReasons,
            currentName: nil,
            cancelled: summary.cancelled
        )
        onStatus?(summary.status(prefix: "Removable media import"))
    }

    func finishImport(imported: Int, skipped: Int, cancelled: Bool, total: Int) {
        finishImport(
            summary: ImportOutcomeSummary(
                total: total, imported: imported, skipped: skipped, cancelled: cancelled
            )
        )
    }

    private func publishScan(_ result: MediaVolumeScanResult) {
        removableMediaFiles = result.files
        removableMediaWarnings = result.warnings
        removableMediaSelection.selectAll(in: result.files)
        isRemovableMediaScanning = false
        if result.files.isEmpty {
            removableMediaWarnings.append("No supported images were found on this volume.")
        }
    }

    private func requestAccess(for volume: MediaVolume) -> MediaAccessGrant? {
        guard let url = fileDialog.chooseFolder(
            title: "Grant Access to \(volume.name)",
            prompt: "Grant Access",
            startingAt: volume.url,
            canCreateDirectories: false
        ) else { return nil }
        return MediaAccessGrant(
            volume: MediaVolume(id: volume.id, name: volume.name, url: url),
            access: .systemGranted(for: url)
        )
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        _ = beginImportOperation()
        discoveryTask?.cancel()
        scanTask?.cancel()
        importValidationTask?.cancel()
        let tasks = [discoveryTask, scanTask, importValidationTask]
        discoveryTask = nil
        scanTask = nil
        importValidationTask = nil
        for task in tasks { await task?.value }
    }

    private func beginImportOperation() -> UUID {
        // A running scan keeps its own strong reference until the provider finishes. Clearing this
        // owner releases a completed selector grant immediately when another operation replaces it.
        removableMediaAccess = nil
        let id = UUID()
        importOperationID = id
        return id
    }

    private func isCurrentImport(_ id: UUID) -> Bool {
        importOperationID == id && !isShuttingDown
    }
}
