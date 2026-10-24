import Foundation
import Photos
import PhotosUI
import Synchronization
import SwiftUI
import UniformTypeIdentifiers

struct PhotosImportProgress: Equatable, Sendable {
    enum Phase: String, Sendable {
        case transferring
        case inserting

        var label: String {
            switch self {
            case .transferring: return "Transferring"
            case .inserting: return "Adding"
            }
        }
    }

    let total: Int
    var processed: Int
    var imported: Int
    var duplicates: Int
    var skipped: Int
    var failed: Int
    var currentName: String?
    var phase: Phase
    /// Byte progress (0...1) of the item currently transferring, when the provider reports it,
    /// such as while an iCloud original downloads. Nil between items and for local transfers.
    var transferFraction: Double?

    var fraction: Double {
        guard total > 0 else { return 1 }
        let current = phase == .transferring ? (transferFraction ?? 0) : 0
        return min(1, (Double(processed) + current) / Double(total))
    }
}

/// The value that crosses the Photos picker/UI boundary. The picker item itself stays inside the
/// provider so the import workflow can be exercised with a deterministic test provider.
struct PhotosImportSelection: Equatable, Sendable {
    let ordinal: Int
    let localIdentifier: String?
    /// The resolved display name, stamped by `PhotosImportNaming.resolve` so the review sheet and
    /// the import agree. Nil until resolved.
    var name: String? = nil
}

/// The small provider boundary needed by the import workflow. Production code adapts
/// `PhotosPickerItem`; tests can provide bytes, names, failures, and cancellation behavior without
/// constructing PhotosUI objects.
@MainActor
protocol PhotosImportProviding: AnyObject {
    /// Settles PhotoKit authorization before names are resolved: the picker's private access does
    /// not authorize PhotoKit, so a lookup made before the first grant cannot see the original
    /// filename. The default does nothing.
    func prepareForNaming() async
    func originalFilename(for selection: PhotosImportSelection) -> String?
    /// The asset's capture date, used to name items whose original filename is unavailable.
    func captureDate(for selection: PhotosImportSelection) -> Date?
    func transferData(for selection: PhotosImportSelection) async throws -> Data?
    /// Like `transferData(for:)`, reporting the item's transfer fraction (0...1) as it advances.
    /// Providers deliver monotonic, bounded updates on the main actor; the default reports none.
    func transferData(
        for selection: PhotosImportSelection,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> Data?
    /// Transfers the original for review inspection. A provider may keep the transferred file so
    /// the import's later `transferData` reuses it instead of fetching the original again.
    func inspectionData(for selection: PhotosImportSelection) async throws -> Data?
    /// Drops any retained review transfers except the given ordinals. Review calls it on cancel
    /// (keeping none) and on confirm (keeping the chosen items).
    func discardRetainedTransfers(keeping ordinals: Set<Int>)
}

extension PhotosImportProviding {
    func prepareForNaming() async {}
    func captureDate(for selection: PhotosImportSelection) -> Date? { nil }
    func transferData(
        for selection: PhotosImportSelection,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> Data? {
        try await transferData(for: selection)
    }
    func inspectionData(for selection: PhotosImportSelection) async throws -> Data? {
        try await transferData(for: selection)
    }
    func discardRetainedTransfers(keeping ordinals: Set<Int>) {}
}

/// The PhotosUI/Photos implementation of the provider boundary. Filename lookup intentionally
/// remains here because it is provider metadata, not durable collection policy.
@MainActor
final class PhotosPickerImportProvider: PhotosImportProviding {
    /// Review stops transferring once it holds this many bytes of originals; see
    /// `PhotosReviewTransferCache`.
    static let retainedByteLimit = PhotosReviewTransferCache.defaultByteLimit

    private let items: [PhotosPickerItem]
    private let cache = PhotosReviewTransferCache()

    init(items: [PhotosPickerItem]) {
        self.items = items
    }

    func prepareForNaming() async {
        _ = await Self.photoKitStatus()
    }

    func originalFilename(for selection: PhotosImportSelection) -> String? {
        Self.originalResource(for: selection)?.originalFilename
    }

    func captureDate(for selection: PhotosImportSelection) -> Date? {
        guard let identifier = selection.localIdentifier else { return nil }
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            .firstObject?.creationDate
    }

    /// Consumes a transfer retained by review when there is one; the file is unlinked immediately
    /// and the mapping keeps it readable, so nothing outlives the import.
    func transferData(for selection: PhotosImportSelection) async throws -> Data? {
        try await transferData(for: selection, progress: { _ in })
    }

    func transferData(
        for selection: PhotosImportSelection,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws -> Data? {
        if let data = cache.consume(ordinal: selection.ordinal) { return data }
        let resource = try await Self.resolveOriginalResource(for: selection)
        let directory = Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("original")
        try await Self.writeOriginal(resource, to: file, progress: progress)
        return try Data(contentsOf: file, options: .mappedIfSafe)
    }

    func inspectionData(for selection: PhotosImportSelection) async throws -> Data? {
        try await cache.inspect(ordinal: selection.ordinal) { file in
            let resource = try await Self.resolveOriginalResource(for: selection)
            try await Self.writeOriginal(resource, to: file)
        }
    }

    func discardRetainedTransfers(keeping ordinals: Set<Int>) {
        cache.discard(keeping: ordinals)
    }

    /// The camera original, never an edited rendition. A RAW+JPEG pair exposes the RAW as
    /// `.alternatePhoto` and the JPEG as `.photo`; `.fullSizePhoto` is the edited render and is
    /// deliberately never used (KRMA-1031).
    private static func originalResource(for selection: PhotosImportSelection) -> PHAssetResource? {
        guard let identifier = selection.localIdentifier,
            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        else { return nil }
        return originalResource(of: asset)
    }

    private static func originalResource(of asset: PHAsset) -> PHAssetResource? {
        let resources = PHAssetResource.assetResources(for: asset)
            .filter { !$0.originalFilename.isEmpty }
        if let raw = resources.first(where: {
            $0.type == .alternatePhoto && UTType($0.uniformTypeIdentifier)?.conforms(to: .rawImage) == true
        }) {
            return raw
        }
        return resources.first(where: { $0.type == .photo })
    }

    /// The current PhotoKit status, asking once when it has not been determined.
    private static func photoKitStatus() async -> PHAuthorizationStatus {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .notDetermined else { return status }
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Looks the original up, naming the first failing boundary: PhotoKit authorization, asset
    /// lookup, or the asset having no original resource. The picker's private access does not
    /// authorize PhotoKit, so an unauthorized fetch silently returns nothing (KRMA-991).
    private static func resolveOriginalResource(
        for selection: PhotosImportSelection
    ) async throws -> PHAssetResource {
        let status = await photoKitStatus()
        let asset = selection.localIdentifier.flatMap {
            PHAsset.fetchAssets(withLocalIdentifiers: [$0], options: nil).firstObject
        }
        let resource = asset.flatMap(originalResource(of:))
        if let failure = PhotosOriginalError.lookupFailure(
            authorized: status == .authorized || status == .limited,
            limited: status == .limited,
            hasIdentifier: selection.localIdentifier != nil,
            assetFound: asset != nil, resourceFound: resource != nil
        ) { throw failure }
        return resource!
    }

    private static func scratchDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KromoraPhotosImport-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Streams the original to `file`, allowing iCloud download.
    /// `progress` is throttled to whole-percent steps and delivered on the main actor.
    private static func writeOriginal(
        _ resource: PHAssetResource, to file: URL,
        progress: @escaping @MainActor @Sendable (Double) -> Void = { _ in }
    ) async throws {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = PhotosDownloadProgress.handler(deliveringTo: progress)
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: file, options: options)
        } catch {
            throw PhotosOriginalError.unavailable(error.localizedDescription)
        }
        try Task.checkCancellation()
    }
}

/// Builds the PhotoKit download progress handler. PhotoKit calls it on its XPC queue, so it must be
/// nonisolated: declared outside any `@MainActor` type, a closure literal cannot inherit main-actor
/// isolation and trap at the runtime executor check. Percent steps are throttled to whole,
/// strictly increasing values and delivered to `deliver` on the main actor. Internal so tests can
/// invoke the production closure from a non-main queue.
enum PhotosDownloadProgress {
    static func handler(
        deliveringTo deliver: @escaping @MainActor @Sendable (Double) -> Void
    ) -> @Sendable (Double) -> Void {
        let lastPercent = Mutex(-1)
        return { fraction in
            let percent = Int((min(1, max(0, fraction)) * 100).rounded(.down))
            let advanced = lastPercent.withLock { last in
                guard percent > last else { return false }
                last = percent
                return true
            }
            guard advanced else { return }
            Task { @MainActor in deliver(Double(percent) / 100) }
        }
    }
}

/// Review's retained originals. Every item the cache transfers is kept until import consumes it
/// or review discards it, so an imported original is fetched once. The disk cost is bounded by
/// refusing to start another transfer once `byteLimit` is held: later items are not inspected
/// (they stay untagged in review) and are transferred a single time, at import. The bound can be
/// exceeded by at most the one item whose transfer crossed it.
@MainActor
final class PhotosReviewTransferCache {
    static let defaultByteLimit: Int64 = 2 << 30

    let byteLimit: Int64
    private let directory: URL
    private var entries: [Int: (url: URL, bytes: Int64)] = [:]
    private(set) var retainedBytes: Int64 = 0

    init(byteLimit: Int64 = PhotosReviewTransferCache.defaultByteLimit, directory: URL? = nil) {
        self.byteLimit = byteLimit
        self.directory = directory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("KromoraPhotosReview-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    var retainedOrdinals: Set<Int> { Set(entries.keys) }

    /// The retained original for review, transferring it with `fetch` when it is not held. Nil
    /// when the budget is spent, without transferring anything.
    func inspect(ordinal: Int, fetch: (URL) async throws -> Void) async throws -> Data? {
        if let entry = entries[ordinal], let data = try? Data(contentsOf: entry.url, options: .mappedIfSafe) {
            return data
        }
        guard retainedBytes < byteLimit else { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(String(ordinal))
        do {
            try await fetch(file)
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let data: Data
        do {
            data = try Data(contentsOf: file, options: .mappedIfSafe)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        if let previous = entries.updateValue((file, bytes), forKey: ordinal) {
            retainedBytes -= previous.bytes
        }
        retainedBytes += bytes
        return data
    }

    /// Hands the retained original to import and unlinks it; the mapping keeps it readable.
    func consume(ordinal: Int) -> Data? {
        guard let entry = entries.removeValue(forKey: ordinal) else { return nil }
        retainedBytes -= entry.bytes
        defer { try? FileManager.default.removeItem(at: entry.url) }
        return try? Data(contentsOf: entry.url, options: .mappedIfSafe)
    }

    func discard(keeping ordinals: Set<Int>) {
        for (ordinal, entry) in entries where !ordinals.contains(ordinal) {
            try? FileManager.default.removeItem(at: entry.url)
            entries[ordinal] = nil
            retainedBytes -= entry.bytes
        }
        if entries.isEmpty { try? FileManager.default.removeItem(at: directory) }
    }
}

enum PhotosOriginalError: LocalizedError, Equatable {
    case accessDenied
    case assetNotFound(limitedAccess: Bool)
    case noOriginalResource
    case unavailable(String)

    /// The first failing lookup boundary, or nil when the original resource was found.
    static func lookupFailure(
        authorized: Bool, limited: Bool, hasIdentifier: Bool, assetFound: Bool, resourceFound: Bool
    ) -> Self? {
        guard authorized else { return .accessDenied }
        guard hasIdentifier, assetFound else { return .assetNotFound(limitedAccess: limited) }
        return resourceFound ? nil : .noOriginalResource
    }

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Kromora does not have access to Photos. Allow it in System Settings > Privacy & Security > Photos, then import again."
        case .assetNotFound(let limited):
            return limited
                ? "This photo is outside the set Kromora may access. Choose Full Access in System Settings > Privacy & Security > Photos, then import again."
                : "Photos could not find this item. It may have been deleted or is not available in the system photo library."
        case .noOriginalResource:
            return "Photos has no original file for this item, so it was not imported."
        case .unavailable(let detail):
            return "The original could not be retrieved from Photos or iCloud (\(detail))."
        }
    }
}

/// A provider failure is item-local: the controller records it and continues with the remaining
/// selections so successful originals are never discarded because a later transfer failed.
struct PhotosImportFailure: Equatable, Sendable {
    let ordinal: Int
    let name: String
    let reason: String
}

/// Application-side sink for the Photos import workflow. It admits durable payloads and owns the
/// source-load side effect; it does not own transfer progress or provider errors.
@MainActor
protocol PhotosImportDestination: AnyObject {
    /// Package mode hashes while staging on the package-I/O lane; the Photos payload must not be
    /// walked a second time on the main actor merely to prepare a legacy cache key.
    var packageImportDoesNotNeedDigest: Bool { get }
    func preparePhotosImport(totalCount: Int)
    func insertPhotosImport(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) -> PhotosImportInsertionOutcome
    func recordPhotosImportFailureDestination(name: String, ordinal: Int?, reason: String)
    func finishPhotosImportDestination(summary: ImportOutcomeSummary)
}

extension PhotosImportDestination {
    var packageImportDoesNotNeedDigest: Bool { false }
}

/// Optional asynchronous destination hook used by package mode. The compatibility destination
/// remains synchronous for the legacy managed-folder path and for small deterministic tests.
@MainActor
protocol AsyncPhotosImportDestination: AnyObject {
    func insertPhotosImportAsync(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int
    ) async -> PhotosImportInsertionOutcome
}

enum PhotosImportInsertionOutcome: Equatable, Sendable {
    case inserted(String)
    case duplicate(String)
    case failed(String)
}

/// Coordinates Photos provider interaction and the streamed durable import boundary. The view only
/// creates selections, supplies a provider, and forwards cancellation; all asynchronous item
/// iteration, hashing, progress, and failure handling lives here.
///
/// Migrated to Observation (KRMA-521): progress publishes through this object's own boundary.
/// Views observe the coordinator directly through `@Bindable` so import progress never passes
/// through AppViewModel's former root notification fan-in.
@MainActor
@Observable
final class PhotosImportCoordinator {
    @concurrent private static func contentDigest(of data: Data) async -> String {
        PhotoAssetID.contentDigest(data)
    }

    private(set) var progress: PhotosImportProgress?
    private(set) var failures: [PhotosImportFailure] = []
    private(set) var wasCancelled = false

    weak var destination: (any PhotosImportDestination)?
    private var task: Task<Void, Never>?
    private var operationID = UUID()
    @ObservationIgnored private var activeTransferID: UUID?
    var onStatus: ((String) -> Void)?
    var onProgress: ((PhotosImportProgress?) -> Void)?

    init(destination: (any PhotosImportDestination)? = nil) {
        self.destination = destination
    }

    func start(
        selections: [PhotosImportSelection],
        provider: any PhotosImportProviding
    ) {
        task?.cancel()
        let currentOperationID = UUID()
        operationID = currentOperationID
        activeTransferID = nil
        failures = []
        wasCancelled = false

        let selections = PhotosImportNaming.resolve(selections, provider: provider)
        begin(totalCount: selections.count)

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var wasCancelled = false

            for selection in selections {
                guard self.isCurrent(currentOperationID) else { return }
                if Task.isCancelled {
                    wasCancelled = true
                    break
                }

                let name = selection.name ?? "Photo \(selection.ordinal + 1)"
                self.updatePhase(.transferring, name: name)

                var transferInterval = KromoraSignpostInterval(
                    .photoTransfer,
                    context: KromoraTraceContext(
                        sourceFingerprint: selection.localIdentifier ?? "ordinal:\(selection.ordinal)",
                        quality: "photosImport"
                    )
                )

                let transferID = UUID()
                self.activeTransferID = transferID
                do {
                    let data = try await provider.transferData(for: selection) { [weak self] fraction in
                        self?.updateTransfer(
                            fraction, operationID: currentOperationID, transferID: transferID
                        )
                    }
                    self.endTransfer(transferID)
                    guard let data else {
                        transferInterval.end()
                        guard self.isCurrent(currentOperationID), !Task.isCancelled else {
                            wasCancelled = true
                            break
                        }
                        self.recordFailure(
                            name: name, ordinal: selection.ordinal,
                            reason: "Photos returned no transferable data.", outcome: .skipped
                        )
                        continue
                    }
                    transferInterval.end()

                    guard self.isCurrent(currentOperationID), !Task.isCancelled else {
                        wasCancelled = true
                        break
                    }

                    if let reason = OriginalFileTypeCheck.mismatchReason(name: name, data: data) {
                        self.recordFailure(
                            name: name, ordinal: selection.ordinal, reason: reason, outcome: .skipped
                        )
                        continue
                    }

                    // Legacy folder imports share this digest with source/thumbnail identity.
                    // Package imports compute their digest in the detached package staging pass.
                    let contentDigest: String?
                    if self.destination?.packageImportDoesNotNeedDigest == true {
                        contentDigest = nil
                    } else {
                        contentDigest = await Self.contentDigest(of: data)
                    }

                    guard self.isCurrent(currentOperationID), !Task.isCancelled else {
                        wasCancelled = true
                        break
                    }

                    await self.appendAsync(
                        ImageCollection.PhotoImportItem(
                            name: name,
                            data: data,
                            localIdentifier: selection.localIdentifier,
                            contentDigest: contentDigest,
                            calculateContentDigest: contentDigest != nil
                        ),
                        ordinal: selection.ordinal,
                        operationID: currentOperationID
                    )
                } catch is CancellationError {
                    self.endTransfer(transferID)
                    transferInterval.end()
                    wasCancelled = true
                    break
                } catch {
                    self.endTransfer(transferID)
                    transferInterval.end()
                    guard self.isCurrent(currentOperationID), !Task.isCancelled else {
                        wasCancelled = true
                        break
                    }
                    self.recordFailure(
                        name: name,
                        ordinal: selection.ordinal,
                        reason: error.localizedDescription
                    )
                }
            }

            provider.discardRetainedTransfers(keeping: [])
            guard self.isCurrent(currentOperationID) else { return }
            wasCancelled = wasCancelled || Task.isCancelled
            self.finish(cancelled: wasCancelled, operationID: currentOperationID)
            guard self.isCurrent(currentOperationID) else { return }
            self.wasCancelled = wasCancelled
            self.task = nil
        }
    }

    func begin(totalCount: Int) {
        destination?.preparePhotosImport(totalCount: totalCount)
        progress = PhotosImportProgress(
            total: max(0, totalCount), processed: 0, imported: 0, duplicates: 0, skipped: 0,
            failed: 0,
            currentName: nil, phase: .transferring
        )
        onProgress?(progress)
        if let progress { onStatus?("Importing Photos 0/\(progress.total)…") }
    }

    func updatePhase(_ phase: PhotosImportProgress.Phase, name: String) {
        guard var progress else { return }
        progress.phase = phase
        progress.currentName = name
        progress.transferFraction = nil
        self.progress = progress
        onProgress?(progress)
        onStatus?("\(phase.label) \(name)  \(progress.processed)/\(progress.total)…")
    }

    /// Records the current item's transfer fraction. Late or out-of-order updates (from a finished,
    /// cancelled, or superseded item) are ignored and the value never moves backwards.
    func updateTransfer(_ fraction: Double, operationID: UUID, transferID: UUID) {
        guard isCurrent(operationID), activeTransferID == transferID else { return }
        guard var progress, progress.phase == .transferring, !Task.isCancelled else { return }
        let clamped = min(1, max(0, fraction))
        guard clamped > (progress.transferFraction ?? -1) else { return }
        progress.transferFraction = clamped
        self.progress = progress
        onProgress?(progress)
        let percent = Int((clamped * 100).rounded(.down))
        onStatus?(
            "Transferring \(progress.currentName ?? "")  \(percent)%  "
                + "\(progress.processed)/\(progress.total)…"
        )
    }

    private func endTransfer(_ transferID: UUID) {
        if activeTransferID == transferID { activeTransferID = nil }
    }

    func append(_ item: ImageCollection.PhotoImportItem, ordinal: Int) {
        append(outcome: destination?.insertPhotosImport(item, ordinal: ordinal), item: item, ordinal: ordinal)
    }

    private func append(outcome: PhotosImportInsertionOutcome?, item: ImageCollection.PhotoImportItem, ordinal: Int) {
        guard var progress else { return }
        updatePhase(.inserting, name: item.name)
        let outcome = outcome ?? .failed("The import destination is no longer available.")
        progress = self.progress ?? progress
        progress.processed += 1
        switch outcome {
        case .inserted:
            progress.imported += 1
        case .duplicate:
            progress.duplicates += 1
        case .failed(let reason):
            progress.failed += 1
            failures.append(.init(ordinal: ordinal, name: item.name, reason: reason))
            destination?.recordPhotosImportFailureDestination(
                name: item.name, ordinal: ordinal, reason: reason
            )
        }
        progress.currentName = item.name
        progress.phase = .transferring
        progress.transferFraction = nil
        self.progress = progress
        onProgress?(progress)
        let label: String
        switch outcome {
        case .inserted: label = "Imported"
        case .duplicate: label = "Duplicate"
        case .failed: label = "Failed"
        }
        onStatus?("\(label) \(progress.processed)/\(progress.total)  \(item.name)…")
    }

    private func appendAsync(
        _ item: ImageCollection.PhotoImportItem, ordinal: Int, operationID: UUID
    ) async {
        let outcome: PhotosImportInsertionOutcome?
        if let destination = destination as? any AsyncPhotosImportDestination {
            outcome = await destination.insertPhotosImportAsync(item, ordinal: ordinal)
        } else {
            outcome = destination?.insertPhotosImport(item, ordinal: ordinal)
        }
        guard isCurrent(operationID), !Task.isCancelled else { return }
        append(outcome: outcome, item: item, ordinal: ordinal)
    }

    func recordFailure(
        name: String, ordinal: Int? = nil, reason: String,
        outcome: PhotosImportFailureOutcome = .failed
    ) {
        guard var progress else { return }
        failures.append(PhotosImportFailure(ordinal: ordinal ?? progress.processed, name: name, reason: reason))
        destination?.recordPhotosImportFailureDestination(
            name: name, ordinal: ordinal, reason: reason
        )
        progress.processed += 1
        switch outcome {
        case .skipped: progress.skipped += 1
        case .failed: progress.failed += 1
        }
        progress.currentName = name
        progress.phase = .transferring
        progress.transferFraction = nil
        self.progress = progress
        onProgress?(progress)
        onStatus?(
            "\(outcome == .skipped ? "Skipped" : "Failed") \(name)  "
                + "\(progress.processed)/\(progress.total)…"
        )
    }

    func recordSkipped(name: String, ordinal: Int? = nil, reason: String) {
        recordFailure(name: name, ordinal: ordinal, reason: reason, outcome: .skipped)
    }

    func finish(cancelled: Bool, operationID: UUID? = nil) {
        if let operationID, !isCurrent(operationID) { return }
        guard let progress else {
            destination?.finishPhotosImportDestination(
                summary: ImportOutcomeSummary(total: 0, cancelled: cancelled)
            )
            return
        }
        let summary = ImportOutcomeSummary(
            total: progress.total,
            imported: progress.imported,
            duplicates: progress.duplicates,
            skipped: progress.skipped,
            failed: progress.failed,
            failureReasons: failures.map { "\($0.name): \($0.reason)" },
            cancelled: cancelled
        )
        destination?.finishPhotosImportDestination(summary: summary)
        if let operationID, !isCurrent(operationID) { return }
        onStatus?(summary.status(prefix: "Photos import"))
        self.progress = nil
        onProgress?(nil)
    }

    func cancel() {
        activeTransferID = nil
        task?.cancel()
    }

    func shutdown() async {
        operationID = UUID()
        let current = task
        current?.cancel()
        if let current { await current.value }
        task = nil
        destination = nil
        progress = nil
        onProgress?(nil)
    }

    private func isCurrent(_ id: UUID) -> Bool {
        operationID == id
    }

}

enum PhotosImportFailureOutcome: Equatable {
    case skipped
    case failed
}
