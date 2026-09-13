import Foundation

struct PortablePackageImportSource: Equatable, Sendable {
    let url: URL
    let name: String

    init(url: URL, name: String? = nil) {
        self.url = url
        self.name = name ?? url.lastPathComponent
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
        sourceReadObserver: @Sendable (PortablePackageImportSource) -> Void = { _ in }
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
        var cancelled = false

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
                transaction = try package.beginTransaction(lease: lease)
            } catch {
                if error is CancellationError || isCancelled() {
                    cancelled = true
                    break
                }
                failures.append(.init(source: source, reason: error.localizedDescription))
                progressValue.processed += 1
                progressValue.failed += 1
                progress(progressValue)
                continue
            }

            do {
                let staged = try transaction.stage(
                    fileAt: source.url,
                    to: sourcePath,
                    chunkSize: options.chunkSize,
                    copyMode: options.copyMode,
                    isCancelled: isCancelled,
                    sourceReadObserver: { sourceReadObserver(source) }
                )
                progressValue.bytesRead += staged.byteCount

                let duplicateAssetID = existingHashes[staged.checksum]
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

                var shard = try Self.requireShard(shardName, from: shards)
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
                try transaction.commit(now: Date(), isCancelled: isCancelled)

                shards[shardName] = shard
                hashesSeenThisImport[staged.checksum] = assetID
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
            imported: imported, duplicates: duplicates, failures: failures, cancelled: cancelled)
    }

    func importAsync(
        sources: [PortablePackageImportSource],
        options: PortablePackageImportOptions = .init(),
        progress: @Sendable @escaping (PortablePackageImportProgress) -> Void = { _ in }
    ) async throws -> PortablePackageImportResult {
        try `import`(
            sources: sources,
            options: options,
            isCancelled: { Task.isCancelled },
            progress: progress
        )
    }

    func `import`(
        sources: [PortablePackageImportSource],
        options: PortablePackageImportOptions = .init(),
        progress: @Sendable @escaping (PortablePackageImportProgress) -> Void = { _ in }
    ) async throws -> PortablePackageImportResult {
        try await importAsync(sources: sources, options: options, progress: progress)
    }

    private static func totalBytes(for sources: [PortablePackageImportSource]) -> UInt64? {
        var total: UInt64 = 0
        for source in sources {
            guard let size = try? source.url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size >= 0 else { return nil }
            total += UInt64(size)
        }
        return total
    }

    private static func safeFilename(_ name: String) -> String {
        let lastPathComponent = URL(fileURLWithPath: name).lastPathComponent
        let candidate = lastPathComponent.isEmpty ? "original" : lastPathComponent
        return candidate.replacingOccurrences(of: "/", with: "_")
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
        sourceReadObserver: @Sendable (PortablePackageImportSource) -> Void = { _ in }
    ) throws -> PortablePackageImportResult {
        try PortablePackageImporter(package: self, lease: lease).`import`(
            sources: sources,
            options: options,
            isCancelled: isCancelled,
            progress: progress,
            sourceReadObserver: sourceReadObserver
        )
    }
}
