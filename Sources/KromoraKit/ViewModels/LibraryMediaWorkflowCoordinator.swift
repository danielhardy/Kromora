import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// The value handed to the composition root after a removable-media selection has been
/// validated.  The coordinator deliberately does not know whether the destination is the
/// portable package or the legacy presentation projection.
struct RemovableMediaImportRequest: Sendable, Equatable {
    let volume: MediaVolume
    let files: [MediaVolumeFile]
    let totalSelected: Int
    let operationID: UUID

    init(
        volume: MediaVolume,
        files: [MediaVolumeFile],
        totalSelected: Int? = nil,
        operationID: UUID = UUID()
    ) {
        self.volume = volume
        self.files = files
        self.totalSelected = totalSelected ?? files.count
        self.operationID = operationID
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
    private var isShuttingDown = false
    private var importOperationID = UUID()

    var onStatus: (@MainActor (String) -> Void)?
    var onError: (@MainActor (String) -> Void)?
    var onSourceFolder: (@MainActor (URL) -> Void)?
    var onImageURL: (@MainActor (URL) -> Void)?
    var onImageURLs: (@MainActor ([URL]) -> Void)?
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
        onSourceFolder?(url)
    }

    func handleDroppedURL(_ url: URL) {
        switch fileDropActionPolicy.action(for: url) {
        case .openImage(let imageURL): onImageURL?(imageURL)
        case .openFolder(let folderURL): onSourceFolder?(folderURL)
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
        for url in urls {
            switch fileDropActionPolicy.action(for: url) {
            case .openImage(let imageURL): imageURLs.append(imageURL)
            case .openFolder(let folderURL): onSourceFolder?(folderURL)
            case .invalid: break
            }
        }
        if !imageURLs.isEmpty {
            onImageURLs?(imageURLs)
        }
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
        scanTask = Task { [weak self] in
            do {
                let result = try await provider.scan(volume)
                guard let self, self.isCurrentImport(operationID), !Task.isCancelled else {
                    return
                }
                self.publishScan(result)
            } catch is CancellationError {
                // Closing the selector is a normal cancellation.
            } catch {
                guard let self, self.isCurrentImport(operationID) else { return }
                if case .permissionDenied = error as? MediaVolumeError,
                    provider.supportsInteractiveAccessGrant,
                    let granted = self.requestAccess(for: volume)
                {
                    self.removableMediaVolume = granted
                    self.removableMediaVolumes = self.removableMediaVolumes.map { candidate in
                        candidate.id == volume.id ? granted : candidate
                    }
                    do {
                        let result = try await provider.scan(granted)
                        guard self.isCurrentImport(operationID), !Task.isCancelled else {
                            return
                        }
                        self.publishScan(result)
                    } catch is CancellationError {
                    } catch {
                        guard self.isCurrentImport(operationID) else { return }
                        self.isRemovableMediaScanning = false
                        self.removableMediaWarnings = [error.localizedDescription]
                    }
                } else {
                    guard self.isCurrentImport(operationID) else { return }
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

        let operationID = beginImportOperation()
        importValidationTask?.cancel()
        removableMediaImportProgress = MediaVolumeImportProgress(
            total: selected.count, processed: 0, imported: 0, skipped: 0,
            currentName: nil, cancelled: false
        )
        importValidationTask = Task { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            let accessURL = volume.resolvedAccessURL()
            let hasScope = accessURL.startAccessingSecurityScopedResource()
            defer { if hasScope { accessURL.stopAccessingSecurityScopedResource() } }
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
            self.onImportRequest?(
                RemovableMediaImportRequest(
                    volume: volume, files: usable, totalSelected: selected.count,
                    operationID: operationID
                )
            )
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

    private func requestAccess(for volume: MediaVolume) -> MediaVolume? {
        guard let url = fileDialog.chooseFolder(
            title: "Grant Access to \(volume.name)",
            prompt: "Grant Access",
            startingAt: volume.url,
            canCreateDirectories: false
        ) else { return nil }
        return MediaVolume(
            id: volume.id, name: volume.name, url: url,
            bookmarkData: PhotoAssetSource.bookmarkData(for: url)
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
        let id = UUID()
        importOperationID = id
        return id
    }

    private func isCurrentImport(_ id: UUID) -> Bool {
        importOperationID == id && !isShuttingDown
    }
}
