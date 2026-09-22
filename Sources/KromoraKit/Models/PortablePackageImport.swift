import Foundation
import os.lock

struct PortablePackageImportSource: Equatable, Sendable {
    let url: URL
    let name: String
    let inlineData: Data?
    let precomputedContentHash: String?

    init(url: URL, name: String? = nil) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        inlineData = nil
        precomputedContentHash = nil
    }

    init(data: Data, name: String, contentHash: String? = nil) {
        // The URL is a descriptive compatibility value only; inline payloads never touch it.
        self.url = URL(fileURLWithPath: name)
        self.name = name
        inlineData = data
        precomputedContentHash = contentHash
    }
}

enum PortablePackageDuplicatePolicy: Sendable, Equatable {
    case skip
    case importAnyway
}

struct PortablePackageImportOptions: Sendable {
    var duplicatePolicy: PortablePackageDuplicatePolicy
    var chunkSize: Int
    var copyMode: PortablePackageFileCopyMode

    init(
        duplicatePolicy: PortablePackageDuplicatePolicy = .skip,
        chunkSize: Int = 1 << 20,
        copyMode: PortablePackageFileCopyMode = .automatic
    ) {
        self.duplicatePolicy = duplicatePolicy
        self.chunkSize = max(1, chunkSize)
        self.copyMode = copyMode
    }
}

struct PortablePackageImportProgress: Equatable, Sendable {
    enum Phase: String, Sendable {
        case preparing
        case staging
        case committing
        case finished
    }

    let total: Int
    var processed: Int
    var imported: Int
    var duplicates: Int
    var failed: Int
    var bytesRead: UInt64
    let totalBytes: UInt64?
    var currentName: String?
    var phase: Phase

    var fraction: Double {
        guard total > 0 else { return 1 }
        return min(1, Double(processed) / Double(total))
    }
}

struct PortablePackageImportedAsset: Equatable, Sendable {
    let source: PortablePackageImportSource
    let assetID: PortablePhotoAssetID
    let contentHash: String
    let byteCount: UInt64
    let usedClonefile: Bool
}

struct PortablePackageDuplicate: Equatable, Sendable {
    let source: PortablePackageImportSource
    let contentHash: String
    let existingAssetID: PortablePhotoAssetID
    let importedAssetID: PortablePhotoAssetID?
}

struct PortablePackageImportFailure: Equatable, Sendable {
    let source: PortablePackageImportSource
    let reason: String
}

struct PortablePackageImportResult: Equatable, Sendable {
    let imported: [PortablePackageImportedAsset]
    let duplicates: [PortablePackageDuplicate]
    let failures: [PortablePackageImportFailure]
    let cancelled: Bool
    let indexDelta: LibraryIndexDelta

    init(
        imported: [PortablePackageImportedAsset],
        duplicates: [PortablePackageDuplicate],
        failures: [PortablePackageImportFailure],
        cancelled: Bool,
        indexDelta: LibraryIndexDelta = .empty
    ) {
        self.imported = imported
        self.duplicates = duplicates
        self.failures = failures
        self.cancelled = cancelled
        self.indexDelta = indexDelta
    }
}

enum PortablePackageImportWorkerError: Error, Equatable, CustomStringConvertible {
    case schedulerUnavailable
    case notAdmitted

    var description: String {
        switch self {
        case .schedulerUnavailable: return "Package import scheduling is unavailable"
        case .notAdmitted: return "Package import was not admitted to the I/O queue"
        }
    }
}

/// A lock-backed cancellation seam shared by the main actor and the detached package worker.
final class PortablePackageImportCancellation: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: false)

    var isCancelled: Bool {
        value.withLock { $0 }
    }

    func cancel() {
        value.withLock { $0 = true }
    }
}

/// A one-shot result handoff. The detached worker must be allowed to finish its transaction
/// rollback before the caller proceeds, so cancellation is cooperative rather than a detached
/// fire-and-forget task.
final class PortablePackageImportResultBox: Sendable {
    private struct State: Sendable {
        var outcome: Result<PortablePackageImportResult, Error>?
        var waiters: [CheckedContinuation<PortablePackageImportResult, Error>]
    }

    private let state = OSAllocatedUnfairLock(
        initialState: State(outcome: nil, waiters: [])
    )

    func wait() async throws -> PortablePackageImportResult {
        try await withCheckedThrowingContinuation { continuation in
            let outcome = state.withLock { state -> Result<PortablePackageImportResult, Error>? in
                if let outcome = state.outcome { return outcome }
                state.waiters.append(continuation)
                return nil
            }
            if let outcome {
                continuation.resume(with: outcome)
            }
        }
    }

    func finish(_ result: Result<PortablePackageImportResult, Error>) {
        let waiters = state.withLock { state -> [CheckedContinuation<PortablePackageImportResult, Error>] in
            guard state.outcome == nil else { return [] }
            state.outcome = result
            let waiters = state.waiters
            state.waiters.removeAll()
            return waiters
        }
        waiters.forEach { $0.resume(with: result) }
    }

    func valueIfFinished() -> PortablePackageImportResult? {
        guard case .success(let result)? = state.withLock({ $0.outcome }) else { return nil }
        return result
    }

    func outcomeIfFinished() -> Result<PortablePackageImportResult, Error>? {
        state.withLock { $0.outcome }
    }
}

final class PortablePackageImportProgressSink: Sendable {
    private let state = OSAllocatedUnfairLock<
        AsyncStream<PortablePackageImportProgress>.Continuation?
    >(initialState: nil)

    func install(_ continuation: AsyncStream<PortablePackageImportProgress>.Continuation) {
        state.withLock { $0 = continuation }
    }

    func yield(_ value: PortablePackageImportProgress) {
        _ = state.withLock { $0?.yield(value) }
    }

    func finish() {
        state.withLock { $0?.finish() }
    }
}

/// Main-actor-facing handle returned when an import is admitted to the package-I/O lane.
/// Progress is streamed independently of the final result so folder and removable-media UI can
/// remain responsive while a large source is copied or hashed.
@MainActor
final class PortablePackageImportHandle {
    let progress: AsyncStream<PortablePackageImportProgress>
    private let resultBox: PortablePackageImportResultBox
    private let cancellation: PortablePackageImportCancellation
    private let cancelAction: () -> Void

    init(
        progress: AsyncStream<PortablePackageImportProgress>,
        resultBox: PortablePackageImportResultBox,
        cancellation: PortablePackageImportCancellation,
        cancelAction: @escaping () -> Void
    ) {
        self.progress = progress
        self.resultBox = resultBox
        self.cancellation = cancellation
        self.cancelAction = cancelAction
    }

    func cancel() {
        cancellation.cancel()
        cancelAction()
    }

    func value() async throws -> PortablePackageImportResult {
        try await resultBox.wait()
    }

    func finish(_ result: Result<PortablePackageImportResult, Error>) {
        resultBox.finish(result)
    }

    func resultIfFinished() -> PortablePackageImportResult? {
        resultBox.valueIfFinished()
    }
}

/// Duplicate detection state that can be reused across streamed single-source imports.
///
/// A Photos import commits one package transaction per item so a failed transfer or write does not
/// discard earlier successes. Keeping the catalog alive across those transactions avoids rereading
/// every membership shard and asset record for each item in the batch.
final class PortablePackageImportCatalog {
    var shards: [String: PortablePackageMembershipShard]
    var existingHashes: [String: PortablePhotoAssetID]

    init(package: PortableLibraryPackage) throws {
        var shards: [String: PortablePackageMembershipShard] = [:]
        var existingHashes: [String: PortablePhotoAssetID] = [:]
        for shardName in PortableLibraryPackage.allShards {
            let shard = try package.readMembershipShard(shardName)
            shards[shardName] = shard
            for entry in shard.entries where !entry.isTombstone {
                let record = try package.readAssetRecord(for: entry.assetID)
                existingHashes[record.identity.sourceFingerprint.contentHash] = entry.assetID
            }
        }
        self.shards = shards
        self.existingHashes = existingHashes
    }
}

/// Copies originals into a portable package without taking ownership of the source URLs.
///
/// Each source gets its own package transaction. That makes progressive publication possible while
/// ensuring cancellation or an item-local write failure can only discard that source's staging
/// directory. The source is opened by the transaction exactly once; duplicate detection happens
/// after that pass from the resulting SHA-256.
struct PortablePackageImporter: Sendable {
    let package: PortableLibraryPackage
    let lease: PortablePackageLease

    init(package: PortableLibraryPackage, lease: PortablePackageLease) {
        self.package = package
        self.lease = lease
    }

    init(at packageRoot: URL, lease: PortablePackageLease) throws {
        self.init(package: try PortableLibraryPackage.open(at: packageRoot), lease: lease)
    }

    /// Runs synchronously so callers can choose the worker queue/actor. The cancellation and
    /// progress closures are value-only seams, which also make fault-injection tests deterministic.
    func `import`(
        sources: [PortablePackageImportSource],
        options: PortablePackageImportOptions = .init(),
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortablePackageImportProgress) -> Void = { _ in },
        sourceReadObserver: @Sendable (PortablePackageImportSource) -> Void = { _ in },
        faultInjector: PortablePackageFaultInjector? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> PortablePackageImportResult {
        let catalog = try PortablePackageImportCatalog(package: package)
        return try self.`import`(
            sources: sources,
            options: options,
            isCancelled: isCancelled,
            progress: progress,
            sourceReadObserver: sourceReadObserver,
            faultInjector: faultInjector,
            catalog: catalog,
            now: now
        )
    }

    func `import`(
        sources: [PortablePackageImportSource],
        options: PortablePackageImportOptions = .init(),
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortablePackageImportProgress) -> Void = { _ in },
        sourceReadObserver: @Sendable (PortablePackageImportSource) -> Void = { _ in },
        faultInjector: PortablePackageFaultInjector? = nil,
        catalog: PortablePackageImportCatalog,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> PortablePackageImportResult {
        var progressValue = PortablePackageImportProgress(
            total: sources.count,
            processed: 0,
            imported: 0,
            duplicates: 0,
            failed: 0,
            bytesRead: 0,
            totalBytes: Self.totalBytes(for: sources),
            currentName: nil,
            phase: .preparing
        )
        progress(progressValue)

        var imported: [PortablePackageImportedAsset] = []
        var duplicates: [PortablePackageDuplicate] = []
        var failures: [PortablePackageImportFailure] = []
        var indexUpserts: [LibraryIndexEntry] = []
        var cancelled = false

        var hashesSeenThisImport: [String: PortablePhotoAssetID] = [:]

        for source in sources {
            if isCancelled() {
                cancelled = true
                break
            }

            progressValue.currentName = source.name
            progressValue.phase = .staging
            progress(progressValue)

            let assetID = PortablePhotoAssetID()
            let shardName = PortableLibraryPackage.shard(for: assetID)
            let filename = Self.safeFilename(source.name)
            let sourcePath = "Assets/\(shardName)/\(assetID.raw)/Original/\(filename)"
            let recordPath = "Assets/\(shardName)/\(assetID.raw)/asset.json"
            var transaction: PortablePackageTransaction
            do {
                // A batch can outlive one lease duration. Refresh immediately before each
                // transaction so a later item does not inherit the first item's expiry window.
                try lease.renew(now: now())
                transaction = try package.beginTransaction(
                    lease: lease, now: now(), faultInjector: faultInjector
                )
            } catch {
                if error is CancellationError || isCancelled() {
                    cancelled = true
                    break
                }
                // Lease loss is session-fatal. Returning it as an item-local failure would make
                // a batch look successful while silently leaving later edits unwritable.
                if error is PortablePackageLeaseError { throw error }
                failures.append(.init(source: source, reason: error.localizedDescription))
                progressValue.processed += 1
                progressValue.failed += 1
                progress(progressValue)
                continue
            }

            do {
                let staged: PortablePackageStagedFile
                if let inlineData = source.inlineData {
                    staged = try transaction.stage(
                        data: inlineData,
                        at: sourcePath,
                        chunkSize: options.chunkSize,
                        isCancelled: isCancelled,
                        checksum: source.precomputedContentHash
                    )
                } else {
                    staged = try transaction.stage(
                        fileAt: source.url,
                        to: sourcePath,
                        chunkSize: options.chunkSize,
                        copyMode: options.copyMode,
                        isCancelled: isCancelled,
                        sourceReadObserver: { sourceReadObserver(source) }
                    )
                }
                progressValue.bytesRead += staged.byteCount

                let duplicateAssetID = catalog.existingHashes[staged.checksum]
                    ?? hashesSeenThisImport[staged.checksum]
                if let duplicateAssetID {
                    let importAnyway = options.duplicatePolicy == .importAnyway
                    duplicates.append(.init(
                        source: source,
                        contentHash: staged.checksum,
                        existingAssetID: duplicateAssetID,
                        importedAssetID: importAnyway ? assetID : nil
                    ))
                    progressValue.duplicates += 1
                    if !importAnyway {
                        try abort(&transaction)
                        progressValue.processed += 1
                        progress(progressValue)
                        continue
                    }
                }

                if isCancelled() { throw CancellationError() }
                let identity = PortablePhotoIdentity(
                    assetID: assetID,
                    sourceFingerprint: PortablePhotoSourceFingerprint(
                        contentHash: staged.checksum,
                        decoderVersion: "import-v1"
                    )
                )
                let record = PortablePackageAssetRecord(
                    identity: identity,
                    source: .embedded(relativePath: sourcePath)
                )
                try transaction.stage(data: try Self.encode(record), at: recordPath)

                var shard = try Self.requireShard(shardName, from: catalog.shards)
                shard.entries.append(.init(
                    assetID: assetID,
                    recordPath: recordPath,
                    summary: .init(displayName: source.name)
                ))
                try transaction.stage(
                    data: try package.encodedMembershipShard(shard),
                    at: "Catalog/Membership/\(shardName).json"
                )

                progressValue.phase = .committing
                progress(progressValue)
                try transaction.commit(now: now(), isCancelled: isCancelled)

                catalog.shards[shardName] = shard
                catalog.existingHashes[staged.checksum] = assetID
                hashesSeenThisImport[staged.checksum] = assetID
                indexUpserts.append(.init(
                    assetID: assetID, recordPath: recordPath, summary: .init(displayName: source.name)
                ))
                imported.append(.init(
                    source: source,
                    assetID: assetID,
                    contentHash: staged.checksum,
                    byteCount: staged.byteCount,
                    usedClonefile: staged.usedClonefile
                ))
                progressValue.imported += 1
                progressValue.processed += 1
                progress(progressValue)
            } catch {
                try abort(&transaction)
                if error is CancellationError || isCancelled() {
                    cancelled = true
                    break
                }
                if error is PortablePackageLeaseError { throw error }
                failures.append(.init(source: source, reason: error.localizedDescription))
                progressValue.processed += 1
                progressValue.failed += 1
                progress(progressValue)
                continue
            }
        }

        progressValue.currentName = nil
        progressValue.phase = .finished
        progress(progressValue)
        return PortablePackageImportResult(
            imported: imported,
            duplicates: duplicates,
            failures: failures,
            cancelled: cancelled,
            indexDelta: .init(upserts: indexUpserts)
        )
    }

    func importAsync(
        sources: [PortablePackageImportSource],
        options: PortablePackageImportOptions = .init(),
        progress: @Sendable @escaping (PortablePackageImportProgress) -> Void = { _ in },
        faultInjector: PortablePackageFaultInjector? = nil
    ) async throws -> PortablePackageImportResult {
        try `import`(
            sources: sources,
            options: options,
            isCancelled: { Task.isCancelled },
            progress: progress,
            faultInjector: faultInjector
        )
    }

    func `import`(
        sources: [PortablePackageImportSource],
        options: PortablePackageImportOptions = .init(),
        progress: @Sendable @escaping (PortablePackageImportProgress) -> Void = { _ in },
        faultInjector: PortablePackageFaultInjector? = nil
    ) async throws -> PortablePackageImportResult {
        try await importAsync(
            sources: sources, options: options, progress: progress, faultInjector: faultInjector
        )
    }

    private static func totalBytes(for sources: [PortablePackageImportSource]) -> UInt64? {
        var total: UInt64 = 0
        for source in sources {
            if let inlineData = source.inlineData {
                total += UInt64(inlineData.count)
            } else {
                guard let size = try? source.url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size >= 0 else { return nil }
                total += UInt64(size)
            }
        }
        return total
    }

    private static func safeFilename(_ name: String) -> String {
        PortableLibraryPackage.safeFilename(name)
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func requireShard(
        _ name: String, from shards: [String: PortablePackageMembershipShard]
    ) throws -> PortablePackageMembershipShard {
        guard let shard = shards[name] else {
            throw PortablePackageError.missingShard(name)
        }
        return shard
    }

    private func abort(_ transaction: inout PortablePackageTransaction) throws {
        do {
            try transaction.abort()
        } catch {
            let abortError = error
            do {
                _ = try PortablePackageTransaction.recover(at: package.rootURL)
            } catch {
                throw abortError
            }
        }
    }
}

extension PortableLibraryPackage {
    func importSources(
        _ sources: [PortablePackageImportSource],
        lease: PortablePackageLease,
        options: PortablePackageImportOptions = .init(),
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortablePackageImportProgress) -> Void = { _ in },
        sourceReadObserver: @Sendable (PortablePackageImportSource) -> Void = { _ in },
        faultInjector: PortablePackageFaultInjector? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> PortablePackageImportResult {
        try PortablePackageImporter(package: self, lease: lease).`import`(
            sources: sources,
            options: options,
            isCancelled: isCancelled,
            progress: progress,
            sourceReadObserver: sourceReadObserver,
            faultInjector: faultInjector,
            now: now
        )
    }

    func importSources(
        _ sources: [PortablePackageImportSource],
        lease: PortablePackageLease,
        options: PortablePackageImportOptions = .init(),
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortablePackageImportProgress) -> Void = { _ in },
        sourceReadObserver: @Sendable (PortablePackageImportSource) -> Void = { _ in },
        faultInjector: PortablePackageFaultInjector? = nil,
        catalog: PortablePackageImportCatalog,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> PortablePackageImportResult {
        try PortablePackageImporter(package: self, lease: lease).`import`(
            sources: sources,
            options: options,
            isCancelled: isCancelled,
            progress: progress,
            sourceReadObserver: sourceReadObserver,
            faultInjector: faultInjector,
            catalog: catalog,
            now: now
        )
    }
}
