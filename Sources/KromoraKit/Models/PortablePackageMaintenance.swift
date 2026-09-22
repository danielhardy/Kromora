import Foundation

/// The retention policy for immutable edit sidecars.
///
/// The newest revisions and explicitly protected revisions are always retained. A revision is
/// only removed when its pointer is removed from the asset record in the same transaction as its
/// sidecars, so a reader can never observe a dangling retained pointer.
struct PortablePackageMaintenancePolicy: Sendable, Equatable {
    var maximumEditRevisions: Int
    var protectedRevisions: [String: Set<UInt64>]

    init(
        maximumEditRevisions: Int = 20,
        protectedRevisions: [String: Set<UInt64>] = [:]
    ) {
        self.maximumEditRevisions = max(1, maximumEditRevisions)
        self.protectedRevisions = protectedRevisions
    }

    static let `default` = Self()

    func isProtected(_ revision: UInt64, for assetID: PortablePhotoAssetID) -> Bool {
        protectedRevisions[assetID.raw]?.contains(revision) == true
    }
}

struct PortablePackageMaintenanceOptions: Sendable, Equatable {
    var policy: PortablePackageMaintenancePolicy
    var faultInjector: PortablePackageFaultInjector?

    init(
        policy: PortablePackageMaintenancePolicy = .default,
        faultInjector: PortablePackageFaultInjector? = nil
    ) {
        self.policy = policy
        self.faultInjector = faultInjector
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.policy == rhs.policy
    }
}

enum PortablePackageMaintenanceError: Error, Equatable, Sendable, CustomStringConvertible {
    case schedulerRejected

    var description: String {
        switch self {
        case .schedulerRejected:
            return "Portable package maintenance was rejected because the package-I/O scheduler is full"
        }
    }
}

struct PortablePackageRevisionCompactionResult: Equatable, Sendable {
    let assetsScanned: Int
    let revisionsBefore: Int
    let revisionsAfter: Int
    let revisionsRemoved: Int
}

struct PortablePackageThumbnailCompactionResult: Equatable, Sendable {
    let bytesBefore: UInt64
    let bytesAfter: UInt64
    let indexedEntriesBefore: Int
    let indexedEntriesAfter: Int
    let staleEntriesRemoved: Int
}

struct PortablePackageMaintenanceResult: Equatable, Sendable {
    let revisions: PortablePackageRevisionCompactionResult
    let thumbnails: PortablePackageThumbnailCompactionResult
}

/// A rebuildable packed-thumbnail store owned by a portable package's Derived directory.
///
/// The index is the only source of live offsets. Appending a replacement leaves the previous
/// bytes in place; compaction copies only values that the current index can still read and then
/// publishes the new packs and index through the package transaction.
final class PortablePackagePackedThumbnailStore {

    struct Record: Sendable {
        let key: String
        let data: Data
    }

    enum LookupResult: Equatable, Sendable {
        case found(Data)
        case missing
        case stale
    }

    struct ScanResult: Equatable, Sendable {
        let indexedEntries: Int
        let validEntries: Int
        let staleEntries: Int
    }

    struct CompactionResult: Equatable, Sendable {
        let bytesBefore: UInt64
        let bytesAfter: UInt64
        let indexedEntriesBefore: Int
        let indexedEntriesAfter: Int
        let staleEntriesRemoved: Int
    }

    private struct Entry: Codable, Equatable, Sendable {
        let key: String
        let shard: Int
        var offset: UInt64
        var length: UInt64
    }

    private struct IndexFile: Codable, Sendable {
        let schemaVersion: Int
        let entries: [Entry]
    }

    private struct CompactionPlan: Sendable {
        let entries: [String: Entry]
        let packData: [Int: Data]
        let indexedEntriesBefore: Int
        let staleEntriesRemoved: Int
        let bytesBefore: UInt64
    }

    private static let schemaVersion = 1
    private let fileManager = FileManager.default
    private let rootURL: URL
    private let indexURL: URL
    private var entries: [String: Entry]

    init(at rootURL: URL) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.indexURL = self.rootURL.appendingPathComponent("index.json")
        try fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: indexURL.path) {
            let index = try JSONDecoder().decode(IndexFile.self, from: Data(contentsOf: indexURL))
            guard index.schemaVersion == Self.schemaVersion else {
                throw PortablePackageError.invalidRelativePath("unsupported thumbnail index schema")
            }
            entries = Dictionary(uniqueKeysWithValues: index.entries.map { ($0.key, $0) })
        } else {
            entries = [:]
        }
    }

    var liveEntryCount: Int { entries.count }

    var physicalByteCount: UInt64 {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        return urls.reduce(into: UInt64(0)) { total, url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return
            }
            total += UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    func append(_ record: Record) throws {
        try append(records: [record])
    }

    func append(records: [Record]) throws {
        for record in records {
            let shard = Self.shard(for: record.key)
            let packURL = packURL(for: shard)
            if !fileManager.fileExists(atPath: packURL.path) {
                try Data().write(to: packURL)
            }
            let handle = try FileHandle(forWritingTo: packURL)
            defer { try? handle.close() }
            let offset = try handle.seekToEnd()
            try handle.write(contentsOf: record.data)
            entries[record.key] = Entry(
                key: record.key, shard: shard, offset: offset, length: UInt64(record.data.count)
            )
        }
        try saveIndex()
    }

    func remove(keys: [String]) throws {
        for key in keys { entries.removeValue(forKey: key) }
        try saveIndex()
    }

    func lookup(_ key: String) throws -> LookupResult {
        guard let entry = entries[key] else { return .missing }
        guard entry.shard == Self.shard(for: key),
              let size = try? packSize(for: entry.shard),
              entry.offset <= size,
              entry.length <= size - entry.offset,
              let length = Int(exactly: entry.length) else {
            return .stale
        }
        do {
            let handle = try FileHandle(forReadingFrom: packURL(for: entry.shard))
            defer { try? handle.close() }
            try handle.seek(toOffset: entry.offset)
            guard let data = try handle.read(upToCount: length), data.count == length else {
                return .stale
            }
            return .found(data)
        } catch {
            return .stale
        }
    }

    func coldScan() throws -> ScanResult {
        var stale = 0
        for entry in entries.values {
            guard let size = try? packSize(for: entry.shard),
                  entry.offset <= size,
                  entry.length <= size - entry.offset else {
                stale += 1
                continue
            }
        }
        return .init(
            indexedEntries: entries.count,
            validEntries: entries.count - stale,
            staleEntries: stale
        )
    }

    /// Rewrites live values in shard order. The result is not published until the package
    /// transaction commits, so cancellation or an injected interruption leaves the old index and
    /// packs readable. Obsolete empty packs are removed only after the new index is committed.
    func compact(
        package: PortableLibraryPackage,
        lease: PortablePackageLease,
        now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false },
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws -> CompactionResult {
        let plan = try makeCompactionPlan(isCancelled: isCancelled)
        var transaction = try package.beginTransaction(
            lease: lease, now: now, faultInjector: faultInjector
        )
        do {
            for shard in plan.packData.keys.sorted() {
                try checkCancellation(isCancelled)
                try transaction.stage(
                    data: plan.packData[shard]!, at: packRelativePath(for: shard)
                )
            }
            try checkCancellation(isCancelled)
            try transaction.stage(data: try encodedIndex(plan.entries), at: indexRelativePath)
            try transaction.commit(now: now, isCancelled: isCancelled)
        } catch {
            try? transaction.abort()
            throw error
        }

        // These files contain no values referenced by the newly committed index. Removing them
        // after commit is safe even if the process stops between removals; the next pass retries.
        let liveShards = Set(plan.packData.keys)
        for shard in 0..<256 where !liveShards.contains(shard) {
            let url = packURL(for: shard)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
        entries = plan.entries
        return CompactionResult(
            bytesBefore: plan.bytesBefore,
            bytesAfter: physicalByteCount,
            indexedEntriesBefore: plan.indexedEntriesBefore,
            indexedEntriesAfter: plan.entries.count,
            staleEntriesRemoved: plan.staleEntriesRemoved
        )
    }

    private func makeCompactionPlan(
        isCancelled: @Sendable () -> Bool
    ) throws -> CompactionPlan {
        var compactedEntries: [String: Entry] = [:]
        var packData: [Int: Data] = [:]
        var staleEntries = 0
        for entry in entries.values.sorted(by: { $0.key < $1.key }) {
            try checkCancellation(isCancelled)
            guard case .found(let data) = try lookup(entry.key) else {
                staleEntries += 1
                continue
            }
            let offset = UInt64(packData[entry.shard]?.count ?? 0)
            packData[entry.shard, default: Data()].append(data)
            compactedEntries[entry.key] = Entry(
                key: entry.key, shard: entry.shard, offset: offset, length: UInt64(data.count)
            )
        }
        return CompactionPlan(
            entries: compactedEntries,
            packData: packData,
            indexedEntriesBefore: entries.count,
            staleEntriesRemoved: staleEntries,
            bytesBefore: physicalByteCount
        )
    }

    private func saveIndex() throws {
        let index = IndexFile(
            schemaVersion: Self.schemaVersion,
            entries: entries.values.sorted { $0.key < $1.key }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    private func encodedIndex(_ values: [String: Entry]) throws -> Data {
        let index = IndexFile(
            schemaVersion: Self.schemaVersion,
            entries: values.values.sorted { $0.key < $1.key }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(index)
    }

    private func packSize(for shard: Int) throws -> UInt64 {
        let values = try packURL(for: shard).resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }

    private func packURL(for shard: Int) -> URL {
        rootURL.appendingPathComponent(String(format: "%02x.pack", shard))
    }

    private func packRelativePath(for shard: Int) -> String {
        "Derived/Thumbnails/" + String(format: "%02x.pack", shard)
    }

    private let indexRelativePath = "Derived/Thumbnails/index.json"

    private static func shard(for key: String) -> Int {
        let bytes = Array(key.utf8)
        if bytes.count >= 2,
           let first = hexValue(bytes[0]), let second = hexValue(bytes[1]) {
            return first * 16 + second
        }
        var hash: UInt8 = 216
        for byte in bytes { hash = hash &* 31 &+ byte }
        return Int(hash)
    }

    private static func hexValue(_ byte: UInt8) -> Int? {
        switch byte {
        case 48...57: return Int(byte - 48)
        case 65...70: return Int(byte - 55)
        case 97...102: return Int(byte - 87)
        default: return nil
        }
    }

    private func checkCancellation(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() { throw CancellationError() }
    }
}

/// Coordinates rebuildable package maintenance. The coordinator itself is main-actor isolated,
/// while every filesystem pass is admitted to ImageWorkScheduler's detached package-I/O lane.
@MainActor
final class PortablePackageMaintenance {
    typealias Completion = @MainActor @Sendable (Result<PortablePackageMaintenanceResult, Error>) -> Void

    private let scheduler: ImageWorkScheduler
    private var retryCounts: [ImageWorkScheduler.JobID: Int] = [:]
    private var retryTasks: [ImageWorkScheduler.JobID: Task<Void, Never>] = [:]
    private var isShuttingDown = false
    private(set) var failureLog: [String] = []

    init(scheduler: ImageWorkScheduler) {
        self.scheduler = scheduler
    }

    @discardableResult
    func enqueue(
        packageURL: URL,
        options: PortablePackageMaintenanceOptions = .init(),
        lease: PortablePackageLease? = nil,
        id: ImageWorkScheduler.JobID = .init("portable-package-maintenance"),
        retryLimit: Int = 3,
        completion: @escaping Completion = { _ in }
    ) -> Bool {
        guard !isShuttingDown else { return false }
        let root = packageURL.standardizedFileURL
        let limit = max(0, retryLimit)
        retryTasks[id]?.cancel()
        retryTasks.removeValue(forKey: id)
        retryCounts[id] = 0
        return enqueueAttempt(
            packageURL: root, options: options, lease: lease, id: id, retryLimit: limit,
            completion: completion
        )
    }

    /// Stops delayed scheduler-rejection retries before the owning application tears down its
    /// shared scheduler. A cancelled admitted job is also prevented from creating a new retry.
    func shutdown() {
        isShuttingDown = true
        for task in retryTasks.values { task.cancel() }
        retryTasks.removeAll()
        retryCounts.removeAll()
    }

    @discardableResult
    private func enqueueAttempt(
        packageURL root: URL,
        options: PortablePackageMaintenanceOptions,
        lease: PortablePackageLease?,
        id: ImageWorkScheduler.JobID,
        retryLimit: Int,
        completion: @escaping Completion
    ) -> Bool {
        guard !isShuttingDown else { return false }
        let admitted = scheduler.enqueuePackageIO(
            id: id, lane: .maintenance,
            onTerminal: { [weak self] outcome in
                guard let self else { return }
                if outcome == .rejected {
                    let failure = PortablePackageMaintenanceError.schedulerRejected
                    self.failureLog.append(String(describing: failure))
                    self.scheduleRetry(
                        packageURL: root, options: options, lease: lease, id: id, retryLimit: retryLimit,
                        completion: completion
                    )
                    completion(.failure(failure))
                    return
                }
                guard outcome == .completed || outcome == .cancelled else { return }
                // The detached operation reports its result before the scheduler terminal event.
                // A failed pass is operationally non-critical and is retried through this same
                // lane, with the scheduler remaining free to admit editor work first.
                let failure: Error?
                if let reported = Self.pendingFailures.removeValue(forKey: id) {
                    failure = reported
                } else if outcome == .cancelled {
                    failure = CancellationError()
                } else {
                    failure = nil
                }
                guard let failure else {
                    self.retryCounts.removeValue(forKey: id)
                    return
                }
                self.failureLog.append(String(describing: failure))
                self.scheduleRetry(
                    packageURL: root, options: options, lease: lease, id: id, retryLimit: retryLimit,
                    completion: completion
                )
                completion(.failure(failure))
            },
            operation: { [root, options, lease] in
                do {
                    let result = try Self.run(at: root, options: options, lease: lease)
                    await MainActor.run { completion(.success(result)) }
                } catch {
                    await MainActor.run { Self.pendingFailures[id] = error }
                }
            }
        )
        return admitted
    }

    private func scheduleRetry(
        packageURL root: URL,
        options: PortablePackageMaintenanceOptions,
        lease: PortablePackageLease?,
        id: ImageWorkScheduler.JobID,
        retryLimit: Int,
        completion: @escaping Completion
    ) {
        let attempt = retryCounts[id, default: 0]
        guard attempt < retryLimit, !isShuttingDown else {
            retryCounts.removeValue(forKey: id)
            return
        }
        retryCounts[id] = attempt + 1

        // A rejection means another package-I/O job is occupying the admission window. Let the
        // scheduler drain before trying again; immediate recursion would exhaust retryLimit while
        // the queue is still full and would turn contention into a permanent no-op.
        retryTasks[id]?.cancel()
        retryTasks[id] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return
            }
            guard let self, !self.isShuttingDown else { return }
            self.retryTasks.removeValue(forKey: id)
            _ = self.enqueueAttempt(
                packageURL: root, options: options, lease: lease, id: id, retryLimit: retryLimit,
                completion: completion
            )
        }
    }

    private static var pendingFailures: [ImageWorkScheduler.JobID: Error] = [:]

    /// Runs one maintenance attempt synchronously. Callers normally use `enqueue`; this seam is
    /// also useful to command-line maintenance and deterministic fault-injection tests.
    @discardableResult
    nonisolated static func run(
        at packageURL: URL,
        options: PortablePackageMaintenanceOptions = .init(),
        now: Date = Date(),
        lease: PortablePackageLease? = nil,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> PortablePackageMaintenanceResult {
        try checkCancellation(isCancelled)
        let root = packageURL.standardizedFileURL
        let activeLease = try lease ?? PortablePackageLease.acquire(at: root)
        let ownsLease = lease == nil
        defer {
            if ownsLease { try? activeLease.release() }
        }
        _ = try PortablePackageTransaction.recover(at: root)
        try sweepOrphanedMaintenanceQuarantine(
            at: root, lease: activeLease, now: now, faultInjector: options.faultInjector,
            isCancelled: isCancelled
        )
        let package = try PortableLibraryPackage.open(at: root)
        let revisions = try compactRevisions(
            in: package, lease: activeLease, policy: options.policy,
            now: now, isCancelled: isCancelled, faultInjector: options.faultInjector
        )
        try checkCancellation(isCancelled)
        let thumbnailStore = try PortablePackagePackedThumbnailStore(
            at: root.appendingPathComponent("Derived/Thumbnails", isDirectory: true)
        )
        let thumbnailResult = try thumbnailStore.compact(
            package: package, lease: activeLease, now: now,
            isCancelled: isCancelled, faultInjector: options.faultInjector
        )
        return PortablePackageMaintenanceResult(
            revisions: revisions,
            thumbnails: .init(
                bytesBefore: thumbnailResult.bytesBefore,
                bytesAfter: thumbnailResult.bytesAfter,
                indexedEntriesBefore: thumbnailResult.indexedEntriesBefore,
                indexedEntriesAfter: thumbnailResult.indexedEntriesAfter,
                staleEntriesRemoved: thumbnailResult.staleEntriesRemoved
            )
        )
    }

    /// Removes quarantine directories left by a process that stopped after the revision move
    /// committed but before its journaled cleanup transaction completed. This runs before the
    /// current pass creates a fresh UUID, so an interrupted run cannot accumulate one directory
    /// per launch forever.
    private nonisolated static func sweepOrphanedMaintenanceQuarantine(
        at root: URL,
        lease: PortablePackageLease,
        now: Date,
        faultInjector: PortablePackageFaultInjector?,
        isCancelled: @Sendable () -> Bool
    ) throws {
        let maintenanceRoot = root.appendingPathComponent(
            "Recovery/Quarantine/Maintenance", isDirectory: true
        )
        guard FileManager.default.fileExists(atPath: maintenanceRoot.path) else { return }
        let directories = try FileManager.default.contentsOfDirectory(
            at: maintenanceRoot, includingPropertiesForKeys: [.isDirectoryKey]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard !directories.isEmpty else { return }

        var transaction = try PortablePackageTransaction.begin(
            at: root, lease: lease, now: now, faultInjector: faultInjector
        )
        do {
            for directory in directories {
                try checkCancellation(isCancelled)
                try transaction.stageRemoval(
                    at: "Recovery/Quarantine/Maintenance/\(directory.lastPathComponent)"
                )
            }
            try transaction.commit(now: now, isCancelled: isCancelled)
        } catch {
            try? transaction.abort()
            throw error
        }
    }

    private nonisolated static func compactRevisions(
        in package: PortableLibraryPackage,
        lease: PortablePackageLease,
        policy: PortablePackageMaintenancePolicy,
        now: Date,
        isCancelled: @Sendable () -> Bool,
        faultInjector: PortablePackageFaultInjector?
    ) throws -> PortablePackageRevisionCompactionResult {
        var assetsScanned = 0
        var before = 0
        var after = 0
        var removed = 0

        for shard in PortableLibraryPackage.allShards {
            try checkCancellation(isCancelled)
            let membership = try package.readMembershipShard(shard)
            for entry in membership.entries where !entry.isTombstone {
                try checkCancellation(isCancelled)
                let record = try package.readAssetRecord(for: entry.assetID)
                let pointers = record.editHistory.edits
                assetsScanned += 1
                before += pointers.count
                let protected = Set(pointers.map(\.revision).filter {
                    $0 == record.editHistory.currentRevision
                        || policy.isProtected($0, for: entry.assetID)
                })
                let newest = Set(
                    pointers.sorted { $0.revision > $1.revision }
                        .prefix(policy.maximumEditRevisions).map(\.revision)
                )
                let retained = protected.union(newest)
                let stale = pointers.filter { !retained.contains($0.revision) }
                guard !stale.isEmpty else {
                    after += pointers.count
                    continue
                }

                let quarantinePrefix = "Recovery/Quarantine/Maintenance/\(UUID().uuidString)"
                var updated = record
                updated.editHistory.edits = pointers.filter { retained.contains($0.revision) }
                var transaction = try package.beginTransaction(
                    lease: lease, now: now, faultInjector: faultInjector
                )
                do {
                    for pointer in stale {
                        try transaction.stageMove(
                            from: pointer.relativePath,
                            to: "\(quarantinePrefix)/\(pointer.revision).json"
                        )
                        if let xmp = pointer.xmpRelativePath {
                            try transaction.stageMove(
                                from: xmp,
                                to: "\(quarantinePrefix)/\(pointer.revision).xmp"
                            )
                        }
                    }
                    try transaction.stage(
                        data: try package.encodedAssetRecord(updated),
                        at: "Assets/\(shard)/\(entry.assetID.raw)/asset.json"
                    )
                    try transaction.commit(now: now, isCancelled: isCancelled)
                } catch {
                    try? transaction.abort()
                    throw error
                }
                // The quarantine directory only exists on disk once the move above has published,
                // so its permanent removal is staged as its own follow-up transaction — the same
                // journaled `stageRemoval` primitive `PortablePackageTrash.reclaimSpace` uses. That
                // keeps cleanup crash-safe and idempotent instead of a best-effort delete that could
                // leak an orphaned quarantine directory if the process stops right after `commit`.
                var removalTransaction = try package.beginTransaction(
                    lease: lease, now: now, faultInjector: faultInjector
                )
                do {
                    try removalTransaction.stageRemoval(at: quarantinePrefix)
                    try removalTransaction.commit(now: now, isCancelled: isCancelled)
                } catch {
                    try? removalTransaction.abort()
                    throw error
                }
                after += updated.editHistory.edits.count
                removed += stale.count
            }
        }
        return .init(
            assetsScanned: assetsScanned, revisionsBefore: before,
            revisionsAfter: after, revisionsRemoved: removed
        )
    }

    private nonisolated static func checkCancellation(
        _ isCancelled: @Sendable () -> Bool
    ) throws {
        if isCancelled() { throw CancellationError() }
    }
}
