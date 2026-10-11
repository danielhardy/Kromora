import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

/// Which kind of source the in-app import selector is showing. Both are scanned and selected the
/// same way; only wording and the import status prefix differ.
enum MediaImportSource: Sendable, Equatable {
    case removableMedia
    case folder

    var statusPrefix: String {
        switch self {
        case .removableMedia: return "Removable media import"
        case .folder: return "Folder import"
        }
    }
}

/// The value handed to the composition root after a removable-media selection has been
/// scanned and selected. The coordinator deliberately does not know whether the destination is the
/// portable package or the legacy presentation projection.
struct RemovableMediaImportRequest: Sendable {
    let volume: MediaVolume
    let source: MediaImportSource
    let files: [MediaVolumeFile]
    let totalSelected: Int
    let operationID: UUID
    let access: SecurityScopedResourceAccess?

    init(
        volume: MediaVolume,
        source: MediaImportSource = .removableMedia,
        files: [MediaVolumeFile],
        totalSelected: Int? = nil,
        operationID: UUID = UUID(),
        access: SecurityScopedResourceAccess? = nil
    ) {
        self.volume = volume
        self.source = source
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
    @Published private(set) var importSource: MediaImportSource = .removableMedia
    @Published private(set) var removableMediaFiles: [MediaVolumeFile] = []
    @Published private(set) var removableMediaWarnings: [String] = []
    @Published private(set) var isRemovableMediaScanning = false
    @Published private(set) var removableMediaSelection = MediaVolumeSelectionModel()
    @Published private(set) var removableMediaImportProgress: MediaVolumeImportProgress?
    /// Ids of scanned files whose bytes are already in the open library. Filled progressively.
    @Published private(set) var removableMediaInLibrary: Set<String> = []
    /// How many scanned files have been compared with the library so far.
    @Published private(set) var removableMediaLibraryChecked = 0
    @Published private(set) var isCheckingRemovableMediaLibrary = false
    @Published var hidesInLibraryRemovableMedia = false

    private let provider: any MediaVolumeProviding
    private let fileDialog: any FileDialogProviding
    private let fileDropActionPolicy: FileDropActionPolicy
    private var discoveryTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var importRequestTask: Task<Void, Never>?
    private var removableMediaAccess: SecurityScopedResourceAccess?
    private var isShuttingDown = false
    private var importOperationID = UUID()
    /// Streamed files are selected on arrival until the user takes over the selection, which
    /// matches the select-everything default of a finished scan.
    private var selectsScanArrivals = true
    private var libraryCheckTask: Task<Void, Never>?
    private var libraryCheckInput: AsyncStream<[MediaVolumeFile]>.Continuation?

    /// Loads the open library's content hashes off the main actor. Nil when no library is open,
    /// in which case nothing is tagged.
    var libraryMatcherLoader: (@Sendable () async throws -> LibraryMembershipMatcher)?

    var onStatus: (@MainActor (String) -> Void)?
    var onError: (@MainActor (String) -> Void)?
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

    /// The files the selector grid shows: everything, or only files not yet in the library.
    var visibleRemovableMediaFiles: [MediaVolumeFile] {
        guard hidesInLibraryRemovableMedia else { return removableMediaFiles }
        return removableMediaFiles.filter { !removableMediaInLibrary.contains($0.id) }
    }

    func chooseSourceFolder(startingAt directoryURL: URL?) {
        guard let url = fileDialog.chooseFolder(
            title: "Choose Source Folder", prompt: "Use Folder", startingAt: directoryURL,
            canCreateDirectories: false
        ) else { return }
        openFolder(url, access: .systemGranted(for: url))
    }

    /// A folder is scanned and shown in the same selector as a removable volume, so already
    /// imported photos are tagged and left out of the default selection. The selector owns
    /// `access` until the import request takes it or the selector closes.
    func openFolder(_ url: URL, access: SecurityScopedResourceAccess?) {
        openRemovableMedia(
            MediaVolume(name: url.lastPathComponent, url: url), source: .folder, access: access
        )
    }

    func handleDroppedURL(_ url: URL) {
        switch fileDropActionPolicy.action(for: url) {
        case .openImage(let imageURL):
            guard let dropAccess = accessForDrop(imageURL) else { return }
            onImageURL?(imageURL, scope(from: dropAccess))
        case .openFolder(let folderURL):
            guard let dropAccess = accessForDrop(folderURL) else { return }
            openFolder(folderURL, access: scope(from: dropAccess))
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
                openFolder(folderURL, access: scope(from: dropAccess))
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

    func openRemovableMedia(
        _ volume: MediaVolume, source: MediaImportSource = .removableMedia,
        access: SecurityScopedResourceAccess? = nil
    ) {
        let operationID = beginImportOperation()
        importSource = source
        removableMediaAccess = access
        scanTask?.cancel()
        importRequestTask?.cancel()
        removableMediaVolume = volume
        removableMediaFiles = []
        removableMediaWarnings = []
        removableMediaSelection.clear()
        selectsScanArrivals = true
        removableMediaImportProgress = nil
        startLibraryCheck()
        isRemovableMediaScanning = true
        isRemovableMediaSelectorPresented = true

        let provider = self.provider
        let access = removableMediaAccess
        scanTask = Task { [weak self] in
            do {
                guard let self else { return }
                try await self.consumeScan(
                    of: volume, access: access, operationID: operationID
                )
            } catch is CancellationError {
                // Closing the selector is a normal cancellation.
            } catch {
                guard let self, self.isCurrentImport(operationID) else { return }
                guard case .permissionDenied = error as? MediaVolumeError,
                      provider.supportsInteractiveAccessGrant else {
                    guard self.isCurrentImport(operationID) else { return }
                    self.finishFailedScan(error)
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
                    try await self.consumeScan(
                        of: grant.volume, access: grant.access, operationID: operationID
                    )
                } catch is CancellationError {
                    // A replacement operation drops the coordinator owner; this scan keeps its
                    // local grant alive until the provider has finished its read.
                } catch {
                    guard self.isCurrentImport(operationID) else { return }
                    self.removableMediaAccess = nil
                    self.finishFailedScan(error)
                }
            }
        }
    }

    func toggleRemovableMediaSelection(_ file: MediaVolumeFile) {
        selectsScanArrivals = false
        removableMediaSelection.toggle(file)
    }

    func selectRemovableMediaRange(to file: MediaVolumeFile) {
        selectsScanArrivals = false
        removableMediaSelection.selectRange(to: file, in: visibleRemovableMediaFiles)
    }

    func selectAllRemovableMedia() {
        selectsScanArrivals = true
        removableMediaSelection.selectAll(in: removableMediaFiles, excluding: removableMediaInLibrary)
    }

    func selectNoRemovableMedia() {
        selectsScanArrivals = false
        removableMediaSelection.clear()
    }

    func cancelRemovableMediaImport() {
        _ = beginImportOperation()
        scanTask?.cancel()
        importRequestTask?.cancel()
        stopLibraryCheck()
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
        importRequestTask?.cancel()
        removableMediaImportProgress = MediaVolumeImportProgress(
            total: selected.count, processed: 0, imported: 0, skipped: 0,
            currentName: nil, cancelled: false
        )
        importRequestTask = Task { [weak self, access] in
            var transferredAccess = false
            defer {
                if !transferredAccess { access?.release() }
            }
            guard let self, !self.isShuttingDown else { return }
            guard self.isCurrentImport(operationID), !Task.isCancelled else { return }
            // Scan already established readability. Open each source only in the package worker;
            // a removal or permission change is then an isolated import failure, without a second
            // metadata pass or one main-actor observation update/yield per selected file.
            guard let onImportRequest = self.onImportRequest else {
                self.onError?("Removable media import could not start.")
                self.removableMediaImportProgress = nil
                return
            }
            onImportRequest(
                RemovableMediaImportRequest(
                    volume: volume, source: importSource, files: selected, totalSelected: selected.count,
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
        onStatus?(summary.status(prefix: importSource.statusPrefix))
    }

    func finishImport(imported: Int, skipped: Int, cancelled: Bool, total: Int) {
        finishImport(
            summary: ImportOutcomeSummary(
                total: total, imported: imported, skipped: skipped, cancelled: cancelled
            )
        )
    }

    /// Publishes each scan batch into the selector as it arrives. The list stays in final display
    /// order throughout, and selection and the shift-click anchor are keyed by file id, so both
    /// remain valid while the list grows. Import stays disabled until the stream ends.
    private func consumeScan(
        of volume: MediaVolume,
        access: SecurityScopedResourceAccess?,
        operationID: UUID
    ) async throws {
        for try await batch in provider.scanBatches(volume, access: access) {
            guard isCurrentImport(operationID), !Task.isCancelled else { return }
            publishScanBatch(batch)
        }
        guard isCurrentImport(operationID), !Task.isCancelled else { return }
        scanTask = nil
        isRemovableMediaScanning = false
        libraryCheckInput?.finish()
        if removableMediaFiles.isEmpty {
            removableMediaWarnings.append("No supported images were found on this volume.")
        }
    }

    private func publishScanBatch(_ batch: MediaVolumeScanBatch) {
        let previousCount = removableMediaFiles.count
        removableMediaFiles = MediaVolumeFile.merging(removableMediaFiles, batch.files)
        removableMediaWarnings.append(contentsOf: batch.warnings)
        if selectsScanArrivals, removableMediaFiles.count > previousCount {
            removableMediaSelection.select(batch.files, excluding: removableMediaInLibrary)
        }
        libraryCheckInput?.yield(batch.files)
    }

    private func startLibraryCheck() {
        stopLibraryCheck()
        removableMediaInLibrary = []
        removableMediaLibraryChecked = 0
        hidesInLibraryRemovableMedia = false
        guard let loader = libraryMatcherLoader else { return }
        let (stream, continuation) = AsyncStream<[MediaVolumeFile]>.makeStream()
        libraryCheckInput = continuation
        isCheckingRemovableMediaLibrary = true
        let operationID = importOperationID
        libraryCheckTask = Task { [weak self] in
            let matcher = try? await loader()
            for await batch in stream {
                for chunk in batch.chunked(into: Self.libraryCheckChunk) {
                    guard !Task.isCancelled else { return }
                    let members = await Self.members(of: chunk, in: matcher)
                    guard let self, self.isCurrentImport(operationID), !Task.isCancelled else { return }
                    self.recordLibraryMembers(members, checked: chunk.count)
                }
            }
            guard let self, self.isCurrentImport(operationID) else { return }
            self.isCheckingRemovableMediaLibrary = false
        }
    }

    private func stopLibraryCheck() {
        libraryCheckInput?.finish()
        libraryCheckInput = nil
        libraryCheckTask?.cancel()
        libraryCheckTask = nil
        isCheckingRemovableMediaLibrary = false
    }

    /// Tags matches and drops them from the default selection. Files the user already clicked
    /// keep their selection state, so late results never undo a deliberate choice.
    private func recordLibraryMembers(_ members: Set<String>, checked: Int) {
        removableMediaLibraryChecked += checked
        guard !members.isEmpty else { return }
        removableMediaInLibrary.formUnion(members)
        removableMediaSelection.deselectDefaults(members)
    }

    private static let libraryCheckChunk = 16

    /// Hashing runs on a detached task so neither the main actor nor the caller's executor reads
    /// file bytes; cancelling the caller cancels the hashing between chunks.
    private nonisolated static func members(
        of files: [MediaVolumeFile], in matcher: LibraryMembershipMatcher?
    ) async -> Set<String> {
        guard let matcher else { return [] }
        let work = Task.detached(priority: .utility) {
            matcher.memberIDs(in: files, isCancelled: { Task.isCancelled })
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    /// An error part-way through a scan keeps the images already found, and says why it stopped.
    private func finishFailedScan(_ error: Error) {
        isRemovableMediaScanning = false
        libraryCheckInput?.finish()
        removableMediaWarnings.append(error.localizedDescription)
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
        importRequestTask?.cancel()
        let checkTask = libraryCheckTask
        stopLibraryCheck()
        let tasks = [discoveryTask, scanTask, importRequestTask, checkTask]
        discoveryTask = nil
        scanTask = nil
        importRequestTask = nil
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
