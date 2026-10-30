import CryptoKit
import Darwin
import Foundation
import os.lock

/// The points at which a package commit can be interrupted in tests or by a process crash.
enum PortablePackageTransactionBoundary: String, CaseIterable, Codable, Sendable {
    /// Simulates an exhausted destination volume before a staged file is written.
    case diskFull
    case stage
    case flush
    case checksum
    case publish
    case leaseRenewal
    case leaseLoss
}

enum PortablePackageTransactionError: Error, Equatable, CustomStringConvertible {
    case invalidRelativePath(String)
    case duplicateStagedPath(String)
    case transactionAlreadyCommitted
    case transactionNotCommitted
    case checksumMismatch(path: String, expected: String, actual: String)
    case stagedFileChanged(path: String)
    case injectedFailure(PortablePackageTransactionBoundary)
    case leaseRequired
    case leaseLost
    case journalCorrupt(String)
    case cannotPublishDirectory(String)
    case sourceIsNotARegularFile(String)
    case moveSourceMissing(String)
    case moveDestinationExists(String)
    case invalidRemovalPath(String)
    case unsafeJournal(String)

    var description: String {
        switch self {
        case .invalidRelativePath(let path):
            return "Unsafe package-relative transaction path '\(path)'"
        case .duplicateStagedPath(let path): return "A transaction already stages '\(path)'"
        case .transactionAlreadyCommitted: return "The package transaction is already committed"
        case .transactionNotCommitted: return "The package transaction has not committed"
        case .checksumMismatch(let path, let expected, let actual):
            return "Checksum mismatch for '\(path)': expected \(expected), got \(actual)"
        case .stagedFileChanged(let path):
            return "Staged file '\(path)' changed while it was being committed"
        case .injectedFailure(let boundary):
            return "Injected package transaction failure at \(boundary.rawValue)"
        case .leaseRequired: return "A valid package writer lease is required"
        case .leaseLost: return "The package writer lease was lost"
        case .journalCorrupt(let message): return "Corrupt package transaction journal: \(message)"
        case .cannotPublishDirectory(let path):
            return "Cannot atomically publish directory '\(path)'"
        case .sourceIsNotARegularFile(let path):
            return "Import source is not a regular file: '\(path)'"
        case .moveSourceMissing(let path): return "Transaction move source is missing: '\(path)'"
        case .moveDestinationExists(let path):
            return "Transaction move destination already exists: '\(path)'"
        case .invalidRemovalPath(let path):
            return "Only quarantined package paths may be permanently removed: '\(path)'"
        case .unsafeJournal(let reason):
            return "Refusing to recover package transaction journal; no files were changed: \(reason)"
        }
    }
}

/// A deterministic, test-only fault injector. Production callers use the default instance.
final class PortablePackageFaultInjector: Sendable {
    private let remaining: OSAllocatedUnfairLock<[PortablePackageTransactionBoundary: Int]>

    init(failingAt boundary: PortablePackageTransactionBoundary, times: Int = 1) {
        remaining = OSAllocatedUnfairLock(initialState: [boundary: max(times, 0)])
    }

    init(failingAt boundaries: Set<PortablePackageTransactionBoundary>) {
        remaining = OSAllocatedUnfairLock(
            initialState: Dictionary(uniqueKeysWithValues: boundaries.map { ($0, 1) }))
    }

    func check(_ boundary: PortablePackageTransactionBoundary) throws {
        let shouldFail = remaining.withLock { remaining -> Bool in
            guard let count = remaining[boundary], count > 0 else { return false }
            remaining[boundary] = count - 1
            return true
        }
        if shouldFail { throw PortablePackageTransactionError.injectedFailure(boundary) }
    }
}

struct PortablePackageLeaseInfo: Codable, Equatable, Sendable {
    let ownerID: UUID
    let deviceName: String
    let processID: Int32
    /// Opaque machine identity. Optional so lock files written by older versions remain readable.
    let hostID: String?
    /// Process start time protects against a different process reusing `processID`.
    let processStartedAt: String?
    let acquiredAt: Date
    var heartbeatAt: Date
    var expiresAt: Date

    enum LocalWriterState: Equatable {
        case dead
        case live
        case remoteOrUnknown
    }

    /// A PID is meaningful only on the host that issued it. Compare the process start timestamp
    /// too, since the kernel may have reused a terminated writer's PID.
    var localWriterState: LocalWriterState {
        guard let hostID, hostID == Self.currentHostID(), let processStartedAt else {
            return .remoteOrUnknown
        }
        guard let currentStart = Self.processStartTime(processID) else {
            return errno == ESRCH ? .dead : .remoteOrUnknown
        }
        return currentStart == processStartedAt ? .live : .dead
    }

    private static func currentHostID() -> String? {
        var bytes = [CChar](repeating: 0, count: 128)
        var length = bytes.count
        let result = bytes.withUnsafeMutableBufferPointer { buffer in
            sysctlbyname("kern.uuid", buffer.baseAddress, &length, nil, 0)
        }
        guard result == 0 else { return nil }
        let utf8 = bytes.prefix(length).prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: utf8, as: UTF8.self)
    }

    private static func processStartTime(_ pid: Int32) -> String? {
        var info = proc_bsdinfo()
        errno = 0
        let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info,
                                 infoSize)
        guard count == infoSize else { return nil }
        return "\(info.pbi_start_tvsec):\(info.pbi_start_tvusec)"
    }

    static var currentProcessIdentity: (hostID: String?, startedAt: String?) {
        (currentHostID(), processStartTime(ProcessInfo.processInfo.processIdentifier))
    }
}

enum PortablePackageLeaseError: Error, Equatable, LocalizedError, CustomStringConvertible {
    case contended(PortablePackageLeaseInfo)
    case expired(PortablePackageLeaseInfo)
    /// The lock was acquired by this process/session, but ownership could not be retained.
    /// This is intentionally distinct from `expired`, which describes a stale previous session
    /// during acquisition and is the only state eligible for explicit recovery.
    case lostDuringSession
    case notOwner
    case missing
    case invalid
    case injectedFailure(PortablePackageTransactionBoundary)

    var description: String {
        switch self {
        case .contended(let info):
            switch info.localWriterState {
            case .remoteOrUnknown:
                return "Kromora cannot verify whether the package writer on \(info.deviceName) (pid \(info.processID)) has stopped. Check that device before taking over, or wait for its lease to expire."
            case .live, .dead:
                return "Package is already being written by \(info.deviceName) (pid \(info.processID))"
            }
        case .expired(let info):
            return "The previous session on \(info.deviceName) (pid \(info.processID)) did not close cleanly, so the package writer lease has expired"
        case .lostDuringSession:
            return "The package writer lease was lost during this editing session. Writes are paused; keep unsaved edits and reopen the library to continue."
        case .notOwner: return "This session does not own the package writer lease"
        case .missing: return "The package writer lease is missing"
        case .invalid: return "The package writer lease is invalid"
        case .injectedFailure(let boundary): return "Injected lease failure at \(boundary.rawValue)"
        }
    }

    var errorDescription: String? { description }
}

/// An explicit single-writer lease stored beside the package manifest.
///
/// Acquisition uses O_EXCL, so two processes cannot both become the owner. Expired leases are
/// reported rather than silently broken; callers must explicitly call `breakExpired` or
/// `recoverExpiredWriter` and, normally, user confirmation.
final class PortablePackageLease: Sendable {
    static let defaultDuration: TimeInterval = 180

    private struct State: Sendable {
        var info: PortablePackageLeaseInfo
        var released = false
        var lostDuringSession = false
    }

    let packageRoot: URL
    let ownerID: UUID
    private let duration: TimeInterval
    private let state: OSAllocatedUnfairLock<State>
    /// Serializes this lease's own fence holds (renew, release) so two threads sharing the lease
    /// never contend with each other for the package fence and mistake it for a takeover.
    private let fenceGate = NSLock()
    private let writerMutationQueue = DispatchQueue(
        label: "com.kromora.package-writer-mutation", qos: .utility
    )

    var info: PortablePackageLeaseInfo { state.withLock { $0.info } }

    /// Serializes same-session package mutations that must read a current value and publish a
    /// related transaction without a concurrent edit slipping between those steps.
    ///
    /// The body performs whole package transactions (journal, `F_FULLFSYNC`, renames); capture
    /// metadata repair also reads every embedded original needing repair in a shard before its
    /// commit. Holds can last from tens of milliseconds to seconds. That rules out `os_unfair_lock`,
    /// which is meant for tiny critical sections. A serial queue is used instead: waiters block in
    /// the kernel without spinning, and synchronous dispatch propagates a waiting caller's QoS to
    /// the work already holding the queue rather than inverting behind a utility-QoS holder.
    ///
    /// Callers, all reached from the package-I/O worker, `EditDocumentStore`, or detached
    /// maintenance tasks when a scheduler exists (always, in production): `commitEditRevision`,
    /// `selectEditRevision`, `replaceSourceFingerprint`, the presented-aspect-ratio and
    /// capture-metadata shard repairs, virtual copy, removal, and library-state writes. The main
    /// actor reaches this lock only through the scheduler-less inline fallbacks of
    /// `PortableLibrarySession` (tests) and its synchronous `updateLibraryState`,
    /// `removeFromLibrary` and `replaceSourceFingerprint`, which production does not call.
    /// `body` must not re-enter this method on the same lease; that would deadlock.
    func withWriterMutationLock<T: Sendable>(
        _ body: @Sendable () throws -> T
    ) rethrows -> T {
        try writerMutationQueue.sync(execute: body)
    }

    private init(packageRoot: URL, info: PortablePackageLeaseInfo, duration: TimeInterval) {
        self.packageRoot = packageRoot
        ownerID = info.ownerID
        self.duration = duration
        state = OSAllocatedUnfairLock(initialState: State(info: info))
    }

    deinit {
        try? release()
    }

    /// Raised internally when a non-blocking fence attempt finds another party inside the fence.
    private struct FenceBusy: Error {}

    /// The continuous ownership fence: an advisory `flock` on the package directory.
    ///
    /// Acquisition (when it must create the lock), renewal, release, `breakExpired`,
    /// `recoverDeadWriter` and `recoverExpiredWriter` each run their whole check-then-mutate
    /// sequence inside it, so none can interleave with another. The kernel scopes the lock to the
    /// open file description, so separate lease callers in one process and separate processes are
    /// serialized alike, and it is released if the holder dies. `blocking` callers wait their turn;
    /// the rest throw `FenceBusy` immediately.
    private static func withFence<T>(
        at packageRoot: URL, blocking: Bool, _ body: () throws -> T
    ) throws -> T {
        let descriptor = open(packageRoot.path, O_RDONLY | O_DIRECTORY)
        guard descriptor >= 0 else { throw PortablePackageLeaseError.invalid }
        defer { close(descriptor) }
        while flock(descriptor, blocking ? LOCK_EX : LOCK_EX | LOCK_NB) != 0 {
            if errno == EINTR { continue }
            throw errno == EWOULDBLOCK ? FenceBusy() : PortablePackageLeaseError.invalid
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }

    /// Maps a busy fence to the lease error that describes whoever holds the lock right now.
    private static func contention(at packageRoot: URL) -> PortablePackageLeaseError {
        guard let holder = existingInfo(at: packageRoot) else { return .invalid }
        return .contended(holder)
    }

    private static func makeInfo(
        ownerID: UUID, deviceName: String, processID: Int32, writerHostID: String?,
        processStartedAt: String?, now: Date, duration: TimeInterval
    ) -> PortablePackageLeaseInfo {
        let currentIdentity = PortablePackageLeaseInfo.currentProcessIdentity
        return PortablePackageLeaseInfo(
            ownerID: ownerID, deviceName: deviceName, processID: processID,
            hostID: writerHostID ?? currentIdentity.hostID,
            processStartedAt: processStartedAt ?? (processID == ProcessInfo.processInfo.processIdentifier
                ? currentIdentity.startedAt : nil),
            acquiredAt: now, heartbeatAt: now, expiresAt: now.addingTimeInterval(duration)
        )
    }

    static func acquire(
        at packageRoot: URL,
        ownerID: UUID = UUID(),
        deviceName: String = DeviceName.current(),
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        writerHostID: String? = nil,
        processStartedAt: String? = nil,
        now: Date = Date(),
        duration: TimeInterval = PortablePackageLease.defaultDuration
    ) throws -> Self {
        let fm = FileManager.default
        try fm.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        let lockURL = packageRoot.appendingPathComponent("manifest.lock")
        let info = makeInfo(
            ownerID: ownerID, deviceName: deviceName, processID: processID,
            writerHostID: writerHostID, processStartedAt: processStartedAt, now: now,
            duration: duration)
        let data = try Self.encode(info)

        func rejection(for existing: PortablePackageLeaseInfo) -> PortablePackageLeaseError {
            existing.expiresAt > now ? .contended(existing) : .expired(existing)
        }
        // An existing lock is never replaced by acquisition, so reporting it needs no fence.
        // Recovery keeps a lock file in place for its whole run, which is what keeps an ordinary
        // writer from starting while an interrupted journal is pending.
        if fm.fileExists(atPath: lockURL.path) {
            guard let existing = try? Self.readInfo(at: lockURL) else {
                throw PortablePackageLeaseError.invalid
            }
            throw rejection(for: existing)
        }
        return try withFence(at: packageRoot, blocking: true) {
            let descriptor = open(lockURL.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else {
                if errno != EEXIST { throw PortablePackageLeaseError.invalid }
                guard let existing = try? Self.readInfo(at: lockURL) else {
                    throw PortablePackageLeaseError.invalid
                }
                throw rejection(for: existing)
            }
            do {
                try Self.write(data, to: descriptor)
                try fullSyncDirectory(packageRoot)
            } catch {
                try? fm.removeItem(at: lockURL)
                throw error
            }
            return Self(packageRoot: packageRoot, info: info, duration: duration)
        }
    }

    static func breakExpired(at packageRoot: URL, now: Date = Date()) throws {
        let fm = FileManager.default
        let lockURL = packageRoot.appendingPathComponent("manifest.lock")
        do {
            try withFence(at: packageRoot, blocking: false) {
                guard fm.fileExists(atPath: lockURL.path) else { throw PortablePackageLeaseError.missing }
                let existing = try readInfo(at: lockURL)
                guard existing.expiresAt <= now else { throw PortablePackageLeaseError.contended(existing) }
                let quarantine = packageRoot.appendingPathComponent(
                    "manifest.lock.expired-\(UUID().uuidString)")
                try fm.moveItem(at: lockURL, to: quarantine)
                try? fm.removeItem(at: quarantine)
            }
        } catch is FenceBusy {
            throw contention(at: packageRoot)
        }
    }

    /// Takes exclusive ownership of an expired writer lock, then rolls back its interrupted
    /// transactions. A writer process still alive on this Mac remains contended even after expiry.
    ///
    /// The whole sequence runs inside the ownership fence, so renewal, release, ordinary
    /// acquisition and other recoverers cannot interleave with it; a renewal already past its
    /// ownership check holds the fence and makes recovery back off with contention instead.
    /// Nothing is mutated until the lock, re-read under the fence, is expired and not owned by a
    /// live local process; a rejected takeover leaves the lock, journal and staging untouched.
    /// The lock file is never absent: it is atomically replaced by this process's recovery lease
    /// for the duration of the rollback, so an opener sees contention rather than starting a
    /// transaction that recovery would roll back, and a former owner's `assertOwnership` fails
    /// instead of publishing. If the rollback fails, the original expired lock is restored so the
    /// next opener still sees the journal and recovers it.
    ///
    /// `afterClaim` is a test seam that runs after the takeover and before the rollback.
    static func recoverExpiredWriter(
        at packageRoot: URL,
        now: Date = Date(),
        afterClaim: @Sendable () throws -> Void = {}
    ) throws {
        let fm = FileManager.default
        let lockURL = packageRoot.appendingPathComponent("manifest.lock")
        do {
            try withFence(at: packageRoot, blocking: false) {
                guard fm.fileExists(atPath: lockURL.path) else { throw PortablePackageLeaseError.missing }
                let originalData: Data
                let claimed: PortablePackageLeaseInfo
                do {
                    originalData = try Data(contentsOf: lockURL)
                    claimed = try PackageJSONCoder.decode(PortablePackageLeaseInfo.self, from: originalData)
                } catch {
                    throw PortablePackageLeaseError.invalid
                }
                guard claimed.expiresAt <= now, claimed.localWriterState != .live else {
                    throw PortablePackageLeaseError.contended(claimed)
                }
                let recoveryInfo = makeInfo(
                    ownerID: UUID(), deviceName: DeviceName.current(),
                    processID: ProcessInfo.processInfo.processIdentifier, writerHostID: nil,
                    processStartedAt: nil, now: now, duration: defaultDuration)
                try writeDurably(try encode(recoveryInfo), to: lockURL)
                do {
                    try afterClaim()
                    _ = try PortablePackageTransaction.recover(at: packageRoot)
                } catch {
                    try? writeDurably(originalData, to: lockURL)
                    throw error
                }
                try fm.removeItem(at: lockURL)
            }
        } catch is FenceBusy {
            throw contention(at: packageRoot)
        }
    }

    /// Rolls back transactions from a conclusively dead same-host writer, even when its lease
    /// timestamp is still in the future. The lock remains present during rollback, so ordinary
    /// acquisition continues to report contention until recovery has finished.
    static func recoverDeadWriter(at packageRoot: URL) throws {
        let lockURL = packageRoot.appendingPathComponent("manifest.lock")
        do {
            try withFence(at: packageRoot, blocking: false) {
                guard let initial = try? readInfo(at: lockURL), initial.localWriterState == .dead else {
                    throw PortablePackageLeaseError.invalid
                }
                _ = try PortablePackageTransaction.recover(at: packageRoot)
                guard let current = try? readInfo(at: lockURL),
                      current.ownerID == initial.ownerID,
                      current.localWriterState == .dead
                else { throw PortablePackageLeaseError.contended(initial) }
                let quarantine = packageRoot.appendingPathComponent(
                    "manifest.lock.recovered-\(UUID().uuidString)")
                try FileManager.default.moveItem(at: lockURL, to: quarantine)
                try? FileManager.default.removeItem(at: quarantine)
            }
        } catch is FenceBusy {
            throw contention(at: packageRoot)
        }
    }

    var isExpired: Bool { isExpired(at: Date()) }

    func isExpired(at date: Date) -> Bool { info.expiresAt <= date }

    /// Renews the lease. The ownership check and the lock publication run inside one hold of the
    /// ownership fence, so recovery cannot install its lease between them and have it overwritten.
    /// A renewal that finds the fence held by recovery or another takeover fails rather than waits.
    /// `afterOwnershipCheck` is a test seam that runs between validation and publication.
    func renew(
        now: Date = Date(),
        faultInjector: PortablePackageFaultInjector? = nil,
        afterOwnershipCheck: @Sendable () throws -> Void = {}
    ) throws {
        try faultInjector?.check(.leaseRenewal)
        try fenceGate.withLock {
            do {
                try Self.withFence(at: packageRoot, blocking: false) {
                    try assertOwnership(at: now)
                    try afterOwnershipCheck()
                    let data = try state.withLock { state -> Data in
                        state.info.heartbeatAt = now
                        state.info.expiresAt = now.addingTimeInterval(duration)
                        return try Self.encode(state.info)
                    }
                    guard FileManager.default.fileExists(atPath: lockURL.path) else {
                        throw PortablePackageLeaseError.missing
                    }
                    try writeDurably(data, to: lockURL)
                }
            } catch is FenceBusy {
                throw Self.contention(at: packageRoot)
            }
        }
    }

    /// Runs `body` with ownership validated and the package fence held throughout, so expired
    /// recovery cannot take over between the check and the mutations in `body`. A transaction that
    /// obtains the fence first makes recovery back off with contention; one that finds recovery
    /// already finished fails the ownership check and mutates nothing. Waiting is bounded by the
    /// duration of one recovery or one publication step. `afterOwnershipCheck` is a test seam.
    func withOwnershipFence<T>(
        at date: Date,
        faultInjector: PortablePackageFaultInjector? = nil,
        afterOwnershipCheck: @Sendable () throws -> Void = {},
        _ body: () throws -> T
    ) throws -> T {
        try fenceGate.withLock {
            try Self.withFence(at: packageRoot, blocking: true) {
                try assertOwnership(at: date, faultInjector: faultInjector)
                try afterOwnershipCheck()
                return try body()
            }
        }
    }

    func assertOwnership(
        at date: Date = Date(),
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws {
        try faultInjector?.check(.leaseLoss)
        guard !state.withLock({ $0.released }) else { throw PortablePackageLeaseError.notOwner }
        guard !state.withLock({ $0.lostDuringSession }) else {
            throw PortablePackageLeaseError.lostDuringSession
        }
        guard let current = try? Self.readInfo(at: lockURL) else {
            state.withLock { $0.lostDuringSession = true }
            throw PortablePackageLeaseError.lostDuringSession
        }
        guard current.ownerID == ownerID else {
            state.withLock { $0.lostDuringSession = true }
            throw PortablePackageLeaseError.lostDuringSession
        }
        guard current.expiresAt > date else {
            state.withLock { $0.lostDuringSession = true }
            // Preserve the useful expiry detail for the first low-level probe. Subsequent
            // assertions from this acquired lease return the session-loss state.
            throw PortablePackageLeaseError.expired(current)
        }
    }

    func release() throws {
        try release(at: lockURL)
    }

    /// Releases a lease whose lock file was relocated by an atomic directory rename after this
    /// lease was acquired — e.g. restore renaming a validated staging directory into place as the
    /// new active package. The ownership token is unchanged; only the on-disk path moved, so
    /// releasing via the original `packageRoot` would silently no-op against a path that no longer
    /// exists and leak the lock at its new location.
    func release(movedTo newRoot: URL) throws {
        try release(at: newRoot.appendingPathComponent("manifest.lock"))
    }

    private func release(at lockURL: URL) throws {
        try fenceGate.withLock {
            guard !state.withLock({ $0.released }) else { return }
            let root = lockURL.deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: root.path) else {
                state.withLock { $0.released = true }
                return
            }
            try Self.withFence(at: root, blocking: true) {
                guard let current = try? Self.readInfo(at: lockURL) else {
                    state.withLock { $0.released = true }
                    return
                }
                guard current.ownerID == ownerID else { throw PortablePackageLeaseError.notOwner }
                try FileManager.default.removeItem(at: lockURL)
                state.withLock { $0.released = true }
            }
        }
    }

    private var lockURL: URL { packageRoot.appendingPathComponent("manifest.lock") }

    /// The writer recorded in the package's lock file, or `nil` when there is no readable lock.
    /// Reading never acquires, renews, or breaks the lease.
    static func existingInfo(at packageRoot: URL) -> PortablePackageLeaseInfo? {
        try? readInfo(at: packageRoot.appendingPathComponent("manifest.lock"))
    }

    private static func readInfo(at url: URL) throws -> PortablePackageLeaseInfo {
        return try PackageJSONCoder.decode(
            PortablePackageLeaseInfo.self, from: Data(contentsOf: url)
        )
    }

    private static func encode(_ info: PortablePackageLeaseInfo) throws -> Data {
        return try PackageJSONCoder.encode(info)
    }

    private static func write(_ data: Data, to descriptor: Int32) throws {
        defer { close(descriptor) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try fullSync(descriptor)
    }
}

struct PortablePackageTransactionFile: Codable, Equatable, Sendable {
    enum PublicationState: String, Codable, Sendable {
        case staged
        case started
        case published
        /// Rollback chose to restore the backup and is about to (or did) move it back. A backup
        /// that is gone while this state is recorded was consumed by that restore, so the target
        /// is the restored original and must never be deleted as a published replacement.
        case restoring
        /// Rollback finished with this file. Later retries skip it.
        case restored
    }

    let relativePath: String
    let stagingPath: String
    var backupPath: String?
    let byteCount: UInt64
    let stagedChecksum: String
    var publicationState: PublicationState
}

struct PortablePackageTransactionMove: Codable, Equatable, Sendable {
    enum PublicationState: String, Codable, Sendable {
        case staged
        case started
        case published
    }

    let sourcePath: String
    let targetPath: String
    var publicationState: PublicationState
}

struct PortablePackageTransactionRemoval: Codable, Equatable, Sendable {
    enum PublicationState: String, Codable, Sendable {
        case staged
        case started
        case published
    }

    let relativePath: String
    var backupPath: String?
    var publicationState: PublicationState
}

struct PortablePackageTransactionJournal: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case prepared
        case flushing
        case checksumming
        case publishing
        case committed
    }

    let transactionID: UUID
    let packageID: UUID?
    let createdAt: Date
    let stagingDirectory: String
    var files: [PortablePackageTransactionFile]
    var moves: [PortablePackageTransactionMove]
    var removals: [PortablePackageTransactionRemoval]
    var state: State

    init(
        transactionID: UUID,
        packageID: UUID?,
        createdAt: Date,
        stagingDirectory: String,
        files: [PortablePackageTransactionFile],
        moves: [PortablePackageTransactionMove] = [],
        removals: [PortablePackageTransactionRemoval] = [],
        state: State
    ) {
        self.transactionID = transactionID
        self.packageID = packageID
        self.createdAt = createdAt
        self.stagingDirectory = stagingDirectory
        self.files = files
        self.moves = moves
        self.removals = removals
        self.state = state
    }

    enum CodingKeys: String, CodingKey {
        case transactionID, packageID, createdAt, stagingDirectory, files, moves, removals, state
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        transactionID = try c.decode(UUID.self, forKey: .transactionID)
        packageID = try c.decodeIfPresent(UUID.self, forKey: .packageID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        stagingDirectory = try c.decode(String.self, forKey: .stagingDirectory)
        files = try c.decode([PortablePackageTransactionFile].self, forKey: .files)
        // These fields were added for package-native quarantine/reclaim. Missing means an older
        // file-only transaction journal, which remains fully recoverable.
        moves = try c.decodeIfPresent([PortablePackageTransactionMove].self, forKey: .moves) ?? []
        removals = try c.decodeIfPresent([PortablePackageTransactionRemoval].self, forKey: .removals) ?? []
        state = try c.decode(State.self, forKey: .state)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(transactionID, forKey: .transactionID)
        try c.encodeIfPresent(packageID, forKey: .packageID)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(stagingDirectory, forKey: .stagingDirectory)
        try c.encode(files, forKey: .files)
        try c.encode(moves, forKey: .moves)
        try c.encode(removals, forKey: .removals)
        try c.encode(state, forKey: .state)
    }
}

/// Test seam: the points inside rollback where recovery can be interrupted.
enum PortablePackageRollbackEntry: Equatable, Sendable {
    case file
    case move
    case removal
}

enum PortablePackageRollbackDirectory: Equatable, Sendable {
    case from
    case to
}

enum PortablePackageRollbackPoint: Equatable, Sendable {
    case beforeJournalCleanup(transactionID: UUID)
    case beforeRestoringMarker(path: String)
    case afterRestoringMarker(path: String)
    case beforeRestoreTargetRemoval(path: String)
    case afterRestoreTargetRemoval(path: String)
    case beforeRestoreMove(entry: PortablePackageRollbackEntry, path: String)
    case afterRestoreMove(entry: PortablePackageRollbackEntry, path: String)
    case beforeRestoreDirectorySync(
        entry: PortablePackageRollbackEntry, directory: PortablePackageRollbackDirectory,
        path: String)
    case afterRestoreDirectorySync(
        entry: PortablePackageRollbackEntry, directory: PortablePackageRollbackDirectory,
        path: String)
    case beforeRestoredMarker(path: String)
    case afterRestoredMarker(path: String)
}

typealias PortablePackageRollbackHook = @Sendable (PortablePackageRollbackPoint) throws -> Void

struct PortablePackageRecoveryReport: Equatable, Sendable {
    let recoveredTransactionIDs: [UUID]
    let removedOrphanedStagingDirectories: [String]
}

struct PortablePackageStagedFile: Equatable, Sendable {
    let byteCount: UInt64
    let checksum: String
    let usedClonefile: Bool
}

enum PortablePackageFileCopyMode: Sendable, Equatable {
    case automatic
    case streamed
}

extension PortableLibraryPackage {
    func beginTransaction(
        lease: PortablePackageLease,
        transactionID: UUID = UUID(),
        now: Date = Date(),
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws -> PortablePackageTransaction {
        try PortablePackageTransaction.begin(
            package: self, lease: lease, transactionID: transactionID,
            now: now, faultInjector: faultInjector
        )
    }
}

/// Coordinates one crash-safe package mutation. All paths are relative to the package root and
/// all staging/backup paths are created below `Recovery`, guaranteeing same-volume publication.
struct PortablePackageTransaction {
    let packageRoot: URL
    let transactionID: UUID
    private let journalURL: URL
    private let stagingURL: URL
    private let lease: PortablePackageLease
    private let faultInjector: PortablePackageFaultInjector?
    private var journal: PortablePackageTransactionJournal

    static func begin(
        at packageRoot: URL,
        packageID: UUID? = nil,
        lease: PortablePackageLease,
        transactionID: UUID = UUID(),
        now: Date = Date(),
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws -> Self {
        guard lease.packageRoot.standardizedFileURL == packageRoot.standardizedFileURL else {
            throw PortablePackageTransactionError.leaseRequired
        }
        // Fault injection starts at the first transaction boundary after the journal exists;
        // beginning a transaction itself must always be able to validate the existing lease.
        try lease.assertOwnership(at: now)
        _ = try PackagePath("Recovery").url(in: packageRoot)
        let transactionsURL = try PackagePath("Recovery/Transactions").url(in: packageRoot)
        let stagingURL = try PackagePath(
            "Recovery/Staging/\(transactionID.uuidString)"
        ).url(in: packageRoot)
        try FileManager.default.createDirectory(
            at: transactionsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        let journal = PortablePackageTransactionJournal(
            transactionID: transactionID, packageID: packageID, createdAt: now,
            stagingDirectory: "Recovery/Staging/\(transactionID.uuidString)", files: [],
            state: .prepared
        )
        let journalURL = try PackagePath(
            "Recovery/Transactions/\(transactionID.uuidString).json"
        ).url(in: packageRoot)
        let transaction = Self(
            packageRoot: packageRoot, transactionID: transactionID, journalURL: journalURL,
            stagingURL: stagingURL, lease: lease, faultInjector: faultInjector, journal: journal
        )
        try transaction.persistJournal()
        return transaction
    }

    /// Convenience entry point for callers that already opened the Phase 2.1 package format.
    static func begin(
        package: PortableLibraryPackage,
        lease: PortablePackageLease,
        transactionID: UUID = UUID(),
        now: Date = Date(),
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws -> Self {
        try begin(
            at: package.rootURL, packageID: package.manifest.libraryID, lease: lease,
            transactionID: transactionID, now: now, faultInjector: faultInjector
        )
    }

    /// URL of a staged file, for capturing metadata that must follow the file through its
    /// same-volume publication rename.
    func stagedURL(for relativePath: String) throws -> URL {
        try validateRelativePath(relativePath)
        guard let file = journal.files.first(where: { $0.relativePath == relativePath }) else {
            throw PortablePackageTransactionError.invalidRelativePath(relativePath)
        }
        return try PackagePath(file.stagingPath).url(in: packageRoot)
    }

    @discardableResult
    mutating func stage(
        data: Data,
        at relativePath: String,
        chunkSize: Int = .max,
        isCancelled: @Sendable () -> Bool = { false },
        checksum: String? = nil
    ) throws -> PortablePackageStagedFile {
        try validateRelativePath(relativePath)
        guard !journal.files.contains(where: { $0.relativePath == relativePath }) else {
            throw PortablePackageTransactionError.duplicateStagedPath(relativePath)
        }
        try faultInjector?.check(.diskFull)
        let stagingPath = "\(journal.stagingDirectory)/\(relativePath)"
        let destination = try packageURL(for: stagingPath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let output = try FileHandle(forWritingTo: destinationURLCreatingIfNeeded(destination))
        var hasher = SHA256()
        var offset = 0
        let step = max(1, min(chunkSize, data.count == 0 ? 1 : data.count))
        do {
            while offset < data.count {
                if isCancelled() { throw CancellationError() }
                let end = min(data.count, offset + step)
                let chunk = data[offset..<end]
                try output.write(contentsOf: chunk)
                if checksum == nil { hasher.update(data: chunk) }
                offset = end
            }
            if isCancelled() { throw CancellationError() }
            try output.close()
        } catch {
            try? output.close()
            throw error
        }
        let stagedChecksum = checksum ?? hasher.finalize().hexString
        let file = PortablePackageTransactionFile(
            relativePath: relativePath, stagingPath: stagingPath, backupPath: nil,
            byteCount: UInt64(data.count), stagedChecksum: stagedChecksum, publicationState: .staged
        )
        journal.files.append(file)
        try faultInjector?.check(.stage)
        return PortablePackageStagedFile(
            byteCount: UInt64(data.count), checksum: stagedChecksum, usedClonefile: false
        )
    }

    private func destinationURLCreatingIfNeeded(_ url: URL) throws -> URL {
        if !FileManager.default.createFile(atPath: url.path, contents: nil) {
            // NSURLErrorKey must be a URL. A path String makes Foundation's Cocoa error
            // formatter call URLByDeletingLastPathComponent on a non-URL and abort.
            throw CocoaError(.fileWriteUnknown, userInfo: [NSURLErrorKey: url])
        }
        return url
    }

    /// Journals a same-volume move. Unlike a copy, this preserves the package's single original
    /// and can be reversed by recovery if publication stops between the two directory entries.
    mutating func stageMove(from sourcePath: String, to targetPath: String) throws {
        try validateMovePath(sourcePath)
        try validateMovePath(targetPath)
        guard !journal.moves.contains(where: {
            $0.sourcePath == sourcePath || $0.targetPath == targetPath
                || $0.sourcePath == targetPath || $0.targetPath == sourcePath
        }) else {
            throw PortablePackageTransactionError.duplicateStagedPath(targetPath)
        }
        let source = try packageURL(for: sourcePath)
        let target = try packageURL(for: targetPath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw PortablePackageTransactionError.moveSourceMissing(sourcePath)
        }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw PortablePackageTransactionError.moveDestinationExists(targetPath)
        }
        journal.moves.append(.init(
            sourcePath: sourcePath, targetPath: targetPath, publicationState: .staged
        ))
        try persistJournal()
        try faultInjector?.check(.stage)
    }

    /// Stages the only destructive primitive exposed by the transaction layer. The quarantined
    /// directory is first moved into journal staging; commit cleanup is what finally destroys it.
    mutating func stageRemoval(at relativePath: String) throws {
        guard relativePath.hasPrefix("Recovery/Quarantine/") else {
            throw PortablePackageTransactionError.invalidRemovalPath(relativePath)
        }
        try validateMovePath(relativePath)
        guard !journal.removals.contains(where: { $0.relativePath == relativePath }) else {
            throw PortablePackageTransactionError.duplicateStagedPath(relativePath)
        }
        let source = try packageURL(for: relativePath)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw PortablePackageTransactionError.moveSourceMissing(relativePath)
        }
        journal.removals.append(.init(
            relativePath: relativePath, backupPath: nil, publicationState: .staged
        ))
        try persistJournal()
        try faultInjector?.check(.stage)
    }

    /// Streams a source file once into same-volume staging while computing its expected checksum.
    /// Staging is disposable: the durable begin journal owns its entire directory. Commit persists
    /// the complete file list and flushes/checksums every file before the first publication rename.
    /// The non-escaping byte observer runs synchronously on the caller's worker.
    @discardableResult
    mutating func stage(
        fileAt sourceURL: URL,
        to relativePath: String,
        chunkSize: Int = 1 << 20,
        copyMode: PortablePackageFileCopyMode = .automatic,
        isCancelled: @Sendable () -> Bool = { false },
        sourceReadObserver: @Sendable () -> Void = {},
        timingObserver: (@Sendable (PortablePackageImportPhase, Duration) -> Void)? = nil,
        bytesReadObserver: (UInt64) -> Void = { _ in }
    ) throws -> PortablePackageStagedFile {
        try validateRelativePath(relativePath)
        let chunkSize = max(1, chunkSize)
        guard !journal.files.contains(where: { $0.relativePath == relativePath }) else {
            throw PortablePackageTransactionError.duplicateStagedPath(relativePath)
        }
        let stagingPath = "\(journal.stagingDirectory)/\(relativePath)"
        let destination = try packageURL(for: stagingPath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try faultInjector?.check(.diskFull)

        guard Self.isRegularFile(at: sourceURL) else {
            throw PortablePackageTransactionError.sourceIsNotARegularFile(sourceURL.path)
        }

        // clonefile does not read the source data. It creates a CoW destination directory entry,
        // after which the source is opened exactly once below for the digest. On other volumes or
        // filesystems the fallback reads source -> staged output in one bounded pass.
        if copyMode == .automatic,
           Self.canClonefile(source: sourceURL, destination: destination),
           clonefile(sourceURL.path, destination.path, 0) == 0 {
            sourceReadObserver()
            let digest = try Self.hashFile(
                at: sourceURL, chunkSize: chunkSize, isCancelled: isCancelled)
            let file = PortablePackageTransactionFile(
                relativePath: relativePath, stagingPath: stagingPath, backupPath: nil,
                byteCount: digest.byteCount, stagedChecksum: digest.checksum,
                publicationState: .staged
            )
            journal.files.append(file)
            try faultInjector?.check(.stage)
            return PortablePackageStagedFile(
                byteCount: digest.byteCount, checksum: digest.checksum, usedClonefile: true)
        }

        sourceReadObserver()
        let input = try FileHandle(forReadingFrom: sourceURL)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        var hasher = SHA256()
        var byteCount: UInt64 = 0
        do {
            while true {
                if isCancelled() { throw CancellationError() }
                // `read(upToCount:)` returns autoreleased storage. This loop runs inside one
                // worker job for the whole batch, so without a pool per chunk every chunk of
                // every file stays live until the job returns (KRMA-1139).
                let finished = try autoreleasepool {
                    let chunk = try PortablePackageImportPhase.measure(.read, observer: timingObserver) {
                        try input.read(upToCount: chunkSize) ?? Data()
                    }
                    if chunk.isEmpty { return true }
                    try PortablePackageImportPhase.measure(.write, observer: timingObserver) {
                        try output.write(contentsOf: chunk)
                    }
                    PortablePackageImportPhase.measure(.hash, observer: timingObserver) {
                        hasher.update(data: chunk)
                    }
                    byteCount += UInt64(chunk.count)
                    return false
                }
                if finished { break }
                bytesReadObserver(byteCount)
            }
            try input.close()
            try output.close()
        } catch {
            try? input.close()
            try? output.close()
            throw error
        }
        let file = PortablePackageTransactionFile(
            relativePath: relativePath, stagingPath: stagingPath, backupPath: nil,
            byteCount: byteCount, stagedChecksum: hasher.finalize().hexString,
            publicationState: .staged
        )
        journal.files.append(file)
        try faultInjector?.check(.stage)
        return PortablePackageStagedFile(
            byteCount: byteCount, checksum: file.stagedChecksum, usedClonefile: false)
    }

    mutating func abort(now: Date = Date(), rollbackHook: PortablePackageRollbackHook? = nil) throws {
        guard journal.state != .committed else {
            throw PortablePackageTransactionError.transactionAlreadyCommitted
        }
        // Cleanup after a failed commit is still a package mutation. Recovery may have taken
        // over and already replayed this transaction, so serialize the rollback and verify that
        // this lease still owns the lock before applying the cached journal a second time.
        try lease.withOwnershipFence(at: now) {
            try Self.rollback(
                journal, packageRoot: packageRoot, journalURL: journalURL, hook: rollbackHook)
            cleanupCommittedArtifacts()
        }
    }

    /// Retries journal recovery after an abort I/O error without racing an expired takeover.
    func recoverWhileOwner(now: Date = Date(), rollbackHook: PortablePackageRollbackHook? = nil) throws {
        try lease.withOwnershipFence(at: now) {
            _ = try Self.recover(at: packageRoot, rollbackHook: rollbackHook)
        }
    }

    /// Every journal write and publication move below runs inside `lease.withOwnershipFence`, so
    /// expired recovery either waits for the step to finish (and then contends) or has already
    /// taken over, in which case the ownership check fails before this writer touches the package.
    /// `afterOwnershipCheck` is a test seam that runs inside each fenced step after validation.
    mutating func commit(
        now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false },
        afterOwnershipCheck: @Sendable () throws -> Void = {}
    ) throws {
        guard journal.state != .committed else {
            throw PortablePackageTransactionError.transactionAlreadyCommitted
        }
        if isCancelled() { throw CancellationError() }
        try lease.withOwnershipFence(
            at: now, faultInjector: faultInjector, afterOwnershipCheck: afterOwnershipCheck
        ) {
            journal.state = .flushing
            try persistJournal()
        }
        for file in journal.files {
            if isCancelled() { throw CancellationError() }
            let url = try packageURL(for: file.stagingPath)
            let handle = try FileHandle(forWritingTo: url)
            try handle.synchronize()
            try fullSync(handle.fileDescriptor)
            try handle.close()
            try faultInjector?.check(.flush)
        }

        journal.state = .checksumming
        for file in journal.files {
            if isCancelled() { throw CancellationError() }
            let url = try packageURL(for: file.stagingPath)
            let digest = try Self.hashFile(
                at: url, chunkSize: 1 << 20, isCancelled: isCancelled)
            let actual = digest.checksum
            guard digest.byteCount == file.byteCount else {
                throw PortablePackageTransactionError.stagedFileChanged(path: file.relativePath)
            }
            guard actual == file.stagedChecksum else {
                throw PortablePackageTransactionError.checksumMismatch(
                    path: file.relativePath, expected: file.stagedChecksum, actual: actual
                )
            }
            try faultInjector?.check(.checksum)
        }

        journal.files = try journal.files.map { file in
            var prepared = file
            let target = try packageURL(for: file.relativePath)
            if FileManager.default.fileExists(atPath: target.path) {
                var backup = stagingURL.appendingPathComponent(
                    "Backups/\(journal.files.firstIndex(of: file) ?? 0)/\(target.lastPathComponent)"
                )
                backup = backup.standardizedFileURL
                prepared.backupPath =
                    packageRoot.standardizedFileURL
                    .appendingPathComponent(Self.relativePath(from: packageRoot, to: backup)).path
            }
            return prepared
        }
        journal.removals = journal.removals.enumerated().map { index, removal in
            var prepared = removal
            prepared.backupPath = packageRoot.standardizedFileURL
                .appendingPathComponent(Self.relativePath(
                    from: packageRoot,
                    to: stagingURL.appendingPathComponent("Backups/Removals/\(index)")
                )).path
            return prepared
        }
        try lease.withOwnershipFence(at: now, afterOwnershipCheck: afterOwnershipCheck) {
            journal.state = .publishing
            try persistJournal()
        }

        for index in journal.removals.indices {
            if isCancelled() { throw CancellationError() }
            try lease.withOwnershipFence(
                at: now, faultInjector: faultInjector, afterOwnershipCheck: afterOwnershipCheck
            ) {
            journal.removals[index].publicationState = .started
            try persistJournal()
            let target = try packageURL(for: journal.removals[index].relativePath)
            let backup = URL(fileURLWithPath: journal.removals[index].backupPath!)
            try FileManager.default.createDirectory(
                at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.fileExists(atPath: target.path) else {
                throw PortablePackageTransactionError.moveSourceMissing(
                    journal.removals[index].relativePath)
            }
            try FileManager.default.moveItem(at: target, to: backup)
            try fullSyncDirectory(target.deletingLastPathComponent())
            try fullSyncDirectory(backup.deletingLastPathComponent())
            journal.removals[index].publicationState = .published
            try persistJournal()
            }
            try faultInjector?.check(.publish)
        }

        for index in journal.moves.indices {
            if isCancelled() { throw CancellationError() }
            try lease.withOwnershipFence(
                at: now, faultInjector: faultInjector, afterOwnershipCheck: afterOwnershipCheck
            ) {
            journal.moves[index].publicationState = .started
            try persistJournal()
            let source = try packageURL(for: journal.moves[index].sourcePath)
            let target = try packageURL(for: journal.moves[index].targetPath)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw PortablePackageTransactionError.moveSourceMissing(
                    journal.moves[index].sourcePath)
            }
            guard !FileManager.default.fileExists(atPath: target.path) else {
                throw PortablePackageTransactionError.moveDestinationExists(
                    journal.moves[index].targetPath)
            }
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: source, to: target)
            try fullSyncDirectory(source.deletingLastPathComponent())
            try fullSyncDirectory(target.deletingLastPathComponent())
            journal.moves[index].publicationState = .published
            try persistJournal()
            }
            try faultInjector?.check(.publish)
        }

        let ordered = journal.files.sorted {
            Self.publishRank($0.relativePath) < Self.publishRank($1.relativePath)
        }
        for item in ordered {
            if isCancelled() { throw CancellationError() }
            let currentIndex = try lease.withOwnershipFence(
                at: now, faultInjector: faultInjector, afterOwnershipCheck: afterOwnershipCheck
            ) { () throws -> Int in
            guard
                let currentIndex = journal.files.firstIndex(where: {
                    $0.relativePath == item.relativePath
                })
            else {
                throw PortablePackageTransactionError.journalCorrupt(item.relativePath)
            }
            journal.files[currentIndex].publicationState = .started
            try persistJournal()
            let target = try packageURL(for: item.relativePath)
            if let backupPath = journal.files[currentIndex].backupPath {
                let backup = URL(fileURLWithPath: backupPath)
                try FileManager.default.createDirectory(
                    at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.moveItem(at: target, to: backup)
                    try fullSyncDirectory(target.deletingLastPathComponent())
                }
            } else if FileManager.default.fileExists(atPath: target.path) {
                var directory = ObjCBool(false)
                FileManager.default.fileExists(atPath: target.path, isDirectory: &directory)
                if directory.boolValue {
                    throw PortablePackageTransactionError.cannotPublishDirectory(item.relativePath)
                }
                // A prior journalled move may have created this target after backup planning
                // (for example, the moved quarantine directory still contains asset.json). Move
                // it into the transaction backup before publishing the replacement.
                let backup = stagingURL.appendingPathComponent(
                    "Backups/Dynamic/\(currentIndex)/\(target.lastPathComponent)")
                try FileManager.default.createDirectory(
                    at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: target, to: backup)
                journal.files[currentIndex].backupPath = packageRoot.standardizedFileURL
                    .appendingPathComponent(Self.relativePath(from: packageRoot, to: backup)).path
                try fullSyncDirectory(target.deletingLastPathComponent())
                try persistJournal()
            }
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let staged = try packageURL(for: item.stagingPath)
            try FileManager.default.moveItem(at: staged, to: target)
            try fullSyncDirectory(target.deletingLastPathComponent())
            journal.files[currentIndex].publicationState = .published
            try persistJournal()
            return currentIndex
            }
            _ = currentIndex
            try faultInjector?.check(.publish)
        }
        try lease.withOwnershipFence(at: now, afterOwnershipCheck: afterOwnershipCheck) {
            journal.state = .committed
            try persistJournal()
        }
        cleanupCommittedArtifacts()
    }

    /// Replays all uncommitted journals by restoring previous files and removing staging. A
    /// committed journal is only cleanup work, so recovery remains safe after a post-commit crash.
    @discardableResult
    static func recover(
        at packageRoot: URL, rollbackHook: PortablePackageRollbackHook? = nil
    ) throws -> PortablePackageRecoveryReport {
        let fm = FileManager.default
        try validateRecoveryRoots(packageRoot: packageRoot)
        let transactionsURL = try packageURL("Recovery/Transactions", in: packageRoot)
        let stagingRoot = try packageURL("Recovery/Staging", in: packageRoot)
        var recovered: [UUID] = []
        if fm.fileExists(atPath: transactionsURL.path) {
            let urls = try fm.contentsOfDirectory(
                at: transactionsURL, includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "json" }
            // Decode and validate every journal before the first replay or cleanup, so a malformed
            // journal cannot be reached after other journals have already been applied.
            var journals: [(url: URL, journal: PortablePackageTransactionJournal)] = []
            for url in urls {
                try requireNotSymbolicLink(
                    "Recovery/Transactions/\(url.lastPathComponent)", packageRoot: packageRoot)
                let journal: PortablePackageTransactionJournal
                do {
                    journal = try decodeJournal(from: Data(contentsOf: url))
                } catch {
                    throw PortablePackageTransactionError.journalCorrupt(url.lastPathComponent)
                }
                try validate(journal, fileName: url.lastPathComponent, packageRoot: packageRoot)
                journals.append((url, journal))
            }
            for (url, journal) in journals {
                if journal.state != .committed {
                    try rollback(
                        journal, packageRoot: packageRoot, journalURL: url, hook: rollbackHook)
                    recovered.append(journal.transactionID)
                    try rollbackHook?(.beforeJournalCleanup(transactionID: journal.transactionID))
                }
                try? fm.removeItem(at: packageRoot.appendingPathComponent(journal.stagingDirectory))
                try? fm.removeItem(at: url)
            }
        }
        var orphaned: [String] = []
        if fm.fileExists(atPath: stagingRoot.path) {
            let referenced = Set(recovered.map { $0.uuidString })
            let stagingDirectories = try fm.contentsOfDirectory(
                at: stagingRoot, includingPropertiesForKeys: nil)
            for directory in stagingDirectories
            where !referenced.contains(directory.lastPathComponent) {
                orphaned.append(directory.lastPathComponent)
                try? fm.removeItem(at: directory)
            }
        }
        return PortablePackageRecoveryReport(
            recoveredTransactionIDs: recovered.sorted { $0.uuidString < $1.uuidString },
            removedOrphanedStagingDirectories: orphaned.sorted()
        )
    }

    private func persistJournal() throws {
        try writeDurably(PackageJSONCoder.encode(journal), to: journalURL)
    }

    private func cleanupCommittedArtifacts() {
        try? FileManager.default.removeItem(at: stagingURL)
        try? FileManager.default.removeItem(at: journalURL)
    }

    /// Rolls back an uncommitted journal. Every step is safe to repeat after an interruption: a
    /// replaced file records `restoring` before its backup moves back, so a retry that finds the
    /// backup gone and the target present knows the target is the restored original. Progress is
    /// persisted to `journalURL`; the journal is kept until the caller removes it after success.
    private static func rollback(
        _ original: PortablePackageTransactionJournal, packageRoot: URL, journalURL: URL,
        hook: PortablePackageRollbackHook?
    ) throws {
        let fm = FileManager.default
        var journal = original
        for index in journal.files.indices.reversed() {
            let file = journal.files[index]
            if file.publicationState == .restored { continue }
            let target = try packageURL(file.relativePath, in: packageRoot)
            let staged = try packageURL(file.stagingPath, in: packageRoot)
            if let backup = try backupURL(file.backupPath, journal: journal, packageRoot: packageRoot) {
                if fm.fileExists(atPath: backup.path) {
                    try hook?(.beforeRestoringMarker(path: file.relativePath))
                    journal.files[index].publicationState = .restoring
                    try writeDurably(PackageJSONCoder.encode(journal), to: journalURL)
                    try hook?(.afterRestoringMarker(path: file.relativePath))
                    if fm.fileExists(atPath: target.path) {
                        try hook?(.beforeRestoreTargetRemoval(path: file.relativePath))
                        try fm.removeItem(at: target)
                        try hook?(.afterRestoreTargetRemoval(path: file.relativePath))
                    }
                    try fm.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try hook?(.beforeRestoreMove(entry: .file, path: file.relativePath))
                    try fm.moveItem(at: backup, to: target)
                    try hook?(.afterRestoreMove(entry: .file, path: file.relativePath))
                    try syncRollbackRenameDirectories(
                        from: backup, to: target, entry: .file, path: file.relativePath, hook: hook)
                    try hook?(.beforeRestoredMarker(path: file.relativePath))
                    journal.files[index].publicationState = .restored
                    try writeDurably(PackageJSONCoder.encode(journal), to: journalURL)
                    try hook?(.afterRestoredMarker(path: file.relativePath))
                } else if file.publicationState == .restoring
                    || file.publicationState == .published
                {
                    guard fm.fileExists(atPath: target.path) else {
                        throw PortablePackageTransactionError.journalCorrupt(
                            "restored file '\(file.relativePath)' and its backup are both missing")
                    }
                    // A restoring marker with a consumed backup identifies an interrupted restore.
                    // Older journals have no marker, and identical old/new bytes are ambiguous;
                    // preserve the target rather than risk deleting the last committed file.
                    try syncRollbackRenameDirectories(
                        from: backup, to: target, entry: .file, path: file.relativePath, hook: hook)
                    try hook?(.beforeRestoredMarker(path: file.relativePath))
                    journal.files[index].publicationState = .restored
                    try writeDurably(PackageJSONCoder.encode(journal), to: journalURL)
                    try hook?(.afterRestoredMarker(path: file.relativePath))
                } else if file.publicationState == .started, !fm.fileExists(atPath: target.path)
                {
                    // The journal says publication started, but neither the staged file, target,
                    // nor its expected backup remains. Retain the journal for diagnosis/retry.
                    throw PortablePackageTransactionError.journalCorrupt(
                        "published file '\(file.relativePath)' and its backup are both missing")
                }
            } else if file.publicationState == .published
                || (file.publicationState == .started && !fm.fileExists(atPath: staged.path))
            {
                if fm.fileExists(atPath: target.path) {
                    try hook?(.beforeRestoreTargetRemoval(path: file.relativePath))
                    try fm.removeItem(at: target)
                    try hook?(.afterRestoreTargetRemoval(path: file.relativePath))
                }
                try syncRollbackDirectory(
                    target.deletingLastPathComponent(), entry: .file, directory: .to,
                    path: file.relativePath, hook: hook)
                try hook?(.beforeRestoredMarker(path: file.relativePath))
                journal.files[index].publicationState = .restored
                try writeDurably(PackageJSONCoder.encode(journal), to: journalURL)
                try hook?(.afterRestoredMarker(path: file.relativePath))
            }
        }
        for removal in journal.removals.reversed() {
            guard let backup = try backupURL(removal.backupPath, journal: journal, packageRoot: packageRoot)
            else { continue }
            let target = try packageURL(removal.relativePath, in: packageRoot)
            if fm.fileExists(atPath: backup.path) {
                if fm.fileExists(atPath: target.path) {
                    try hook?(.beforeRestoreTargetRemoval(path: removal.relativePath))
                    try fm.removeItem(at: target)
                    try hook?(.afterRestoreTargetRemoval(path: removal.relativePath))
                }
                try fm.createDirectory(
                    at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try hook?(.beforeRestoreMove(entry: .removal, path: removal.relativePath))
                try fm.moveItem(at: backup, to: target)
                try hook?(.afterRestoreMove(entry: .removal, path: removal.relativePath))
                try syncRollbackRenameDirectories(
                    from: backup, to: target, entry: .removal,
                    path: removal.relativePath, hook: hook)
            } else if removal.publicationState != .staged {
                guard fm.fileExists(atPath: target.path) else {
                    throw PortablePackageTransactionError.journalCorrupt(
                        "removed path '\(removal.relativePath)' and its backup are both missing")
                }
                // A retry after the backup rename sees the source restored and backup absent.
                // Sync both entries again before recovery is allowed to discard the journal.
                try syncRollbackRenameDirectories(
                    from: backup, to: target, entry: .removal,
                    path: removal.relativePath, hook: hook)
            }
        }
        for move in journal.moves.reversed() {
            let source = try packageURL(move.sourcePath, in: packageRoot)
            let target = try packageURL(move.targetPath, in: packageRoot)
            // If the process stopped after rename but before the journal state was flushed, the
            // filesystem is the source of truth: target exists and source does not.
            if move.publicationState != .staged,
                fm.fileExists(atPath: target.path), !fm.fileExists(atPath: source.path)
            {
                try fm.createDirectory(
                    at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
                try hook?(.beforeRestoreMove(entry: .move, path: move.sourcePath))
                try fm.moveItem(at: target, to: source)
                try hook?(.afterRestoreMove(entry: .move, path: move.sourcePath))
                try syncRollbackRenameDirectories(
                    from: target, to: source, entry: .move, path: move.sourcePath, hook: hook)
            } else if move.publicationState != .staged,
                fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path)
            {
                // A prior attempt already renamed the target back. Re-sync both directory entries
                // so a failed durability call cannot be mistaken for a completed rollback.
                try syncRollbackRenameDirectories(
                    from: target, to: source, entry: .move, path: move.sourcePath, hook: hook)
            } else if move.publicationState != .staged,
                !fm.fileExists(atPath: source.path), !fm.fileExists(atPath: target.path)
            {
                throw PortablePackageTransactionError.journalCorrupt(
                    "moved path '\(move.sourcePath)' and its target are both missing")
            }
        }
    }

    private static func syncRollbackRenameDirectories(
        from: URL, to: URL, entry: PortablePackageRollbackEntry, path: String,
        hook: PortablePackageRollbackHook?
    ) throws {
        try syncRollbackDirectory(
            to.deletingLastPathComponent(), entry: entry, directory: .to, path: path, hook: hook)
        try syncRollbackDirectory(
            from.deletingLastPathComponent(), entry: entry, directory: .from, path: path, hook: hook)
    }

    private static func syncRollbackDirectory(
        _ directoryURL: URL, entry: PortablePackageRollbackEntry,
        directory: PortablePackageRollbackDirectory, path: String,
        hook: PortablePackageRollbackHook?
    ) throws {
        try hook?(.beforeRestoreDirectorySync(entry: entry, directory: directory, path: path))
        try fullSyncDirectory(directoryURL)
        try hook?(.afterRestoreDirectorySync(entry: entry, directory: directory, path: path))
    }

    /// Resolves a journalled backup location. The current writer records some backups as absolute
    /// paths under the package root, so those remain valid; every backup must still sit below its
    /// own transaction's `Backups` directory.
    private static func backupURL(
        _ backupPath: String?, journal: PortablePackageTransactionJournal, packageRoot: URL
    ) throws -> URL? {
        guard let backupPath else { return nil }
        var relative = backupPath
        if backupPath.hasPrefix("/") {
            let roots = [
                packageRoot.standardizedFileURL.path,
                packageRoot.resolvingSymlinksInPath().standardizedFileURL.path,
            ]
            guard let prefix = roots.first(where: { backupPath.hasPrefix($0 + "/") }) else {
                throw PortablePackageTransactionError.unsafeJournal(
                    "backup path '\(backupPath)' is outside the package")
            }
            relative = String(backupPath.dropFirst(prefix.count + 1))
        }
        guard relative.hasPrefix("\(journal.stagingDirectory)/Backups/") else {
            throw PortablePackageTransactionError.unsafeJournal(
                "backup path '\(backupPath)' is outside the transaction's backup directory")
        }
        return try transactionStorageURL(relative, journal: journal, packageRoot: packageRoot)
    }

    /// Staged content and backups must resolve inside the transaction directory itself. Package
    /// containment alone is not enough: an in-package symlink could otherwise redirect a backup
    /// into canonical library data while still resolving below the package root.
    private static func transactionStorageURL(
        _ relativePath: String, journal: PortablePackageTransactionJournal, packageRoot: URL
    ) throws -> URL {
        let transactionRoot = try packageURL(journal.stagingDirectory, in: packageRoot)
        let candidate = try packageURL(relativePath, in: packageRoot)
        let resolvedRoot = transactionRoot.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let prefix = resolvedRoot.path.hasSuffix("/")
            ? resolvedRoot.path : resolvedRoot.path + "/"
        guard resolvedCandidate.path.hasPrefix(prefix) else {
            throw PortablePackageTransactionError.unsafeJournal(
                "path '\(relativePath)' does not resolve inside its transaction directory")
        }
        return candidate
    }

    private static func isQuarantinePath(_ path: String) -> Bool {
        path.hasPrefix("Recovery/Quarantine/")
    }

    private static func isForbiddenRecoveryPath(_ path: String) -> Bool {
        path == "Recovery" || (path.hasPrefix("Recovery/") && !isQuarantinePath(path))
    }

    private static func requireNotSymbolicLink(_ relativePath: String, packageRoot: URL) throws {
        let url = try packageURL(relativePath, in: packageRoot)
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
            throw PortablePackageTransactionError.unsafeJournal(
                "'\(relativePath)' is a symbolic link")
        }
    }

    private static func validateRecoveryRoots(packageRoot: URL) throws {
        for path in ["Recovery", "Recovery/Transactions", "Recovery/Staging"] {
            try requireNotSymbolicLink(path, packageRoot: packageRoot)
        }
    }

    /// Checks every path a journal can direct recovery to touch, before recovery touches any.
    private static func validate(
        _ journal: PortablePackageTransactionJournal, fileName: String, packageRoot: URL
    ) throws {
        func unsafe(_ reason: String) -> PortablePackageTransactionError {
            .unsafeJournal("\(fileName): \(reason)")
        }
        let id = journal.transactionID.uuidString
        guard fileName == "\(id).json" else { throw unsafe("file name does not match transaction \(id)") }
        let expectedStaging = "Recovery/Staging/\(id)"
        guard journal.stagingDirectory == expectedStaging else {
            throw unsafe("staging directory '\(journal.stagingDirectory)' is not '\(expectedStaging)'")
        }
        try requireNotSymbolicLink(expectedStaging, packageRoot: packageRoot)
        if let packageID = journal.packageID {
            let manifest: PortablePackageManifest
            do {
                let data = try Data(contentsOf: packageRoot.appendingPathComponent("manifest.json"))
                manifest = try PackageJSONCoder.decode(PortablePackageManifest.self, from: data)
            } catch {
                throw unsafe("cannot verify journal package identity from manifest.json")
            }
            guard manifest.libraryID == packageID else {
                throw unsafe("journal belongs to a different package")
            }
        }
        func requireCanonicalOrQuarantine(_ path: String) throws {
            guard !Self.isForbiddenRecoveryPath(path) else {
                throw unsafe("path '\(path)' targets recovery storage")
            }
            _ = try packageURL(path, in: packageRoot)
        }
        for file in journal.files {
            try requireCanonicalOrQuarantine(file.relativePath)
            let expectedFileStaging = "\(expectedStaging)/\(file.relativePath)"
            guard file.stagingPath == expectedFileStaging else {
                throw unsafe("staged path '\(file.stagingPath)' does not match its package path")
            }
            _ = try transactionStorageURL(
                file.stagingPath, journal: journal, packageRoot: packageRoot)
            _ = try backupURL(file.backupPath, journal: journal, packageRoot: packageRoot)
        }
        for move in journal.moves {
            for path in [move.sourcePath, move.targetPath] {
                guard !Self.isForbiddenRecoveryPath(path) else {
                    throw unsafe("move path '\(path)' targets recovery storage")
                }
                _ = try packageURL(path, in: packageRoot)
            }
        }
        for removal in journal.removals {
            guard Self.isQuarantinePath(removal.relativePath) else {
                throw unsafe("removal path '\(removal.relativePath)' is outside quarantine")
            }
            _ = try packageURL(removal.relativePath, in: packageRoot)
            _ = try backupURL(removal.backupPath, journal: journal, packageRoot: packageRoot)
        }
    }

    private static func decodeJournal(from data: Data) throws -> PortablePackageTransactionJournal {
        try PackageJSONCoder.decode(PortablePackageTransactionJournal.self, from: data)
    }

    private func packageURL(for path: String) throws -> URL {
        try Self.packageURL(path, in: packageRoot)
    }

    private static func packageURL(_ path: String, in root: URL) throws -> URL {
        do {
            return try PackagePath(path).url(in: root)
        } catch {
            throw PortablePackageTransactionError.invalidRelativePath(path)
        }
    }

    private func validateRelativePath(_ path: String) throws {
        guard !Self.isForbiddenRecoveryPath(path) else {
            throw PortablePackageTransactionError.invalidRelativePath(path)
        }
        _ = try packageURL(for: path)
    }

    private func validateMovePath(_ path: String) throws {
        guard !Self.isForbiddenRecoveryPath(path) else {
            throw PortablePackageTransactionError.invalidRelativePath(path)
        }
        _ = try packageURL(for: path)
    }

    private static func publishRank(_ path: String) -> Int {
        if path.hasSuffix("/asset.json") { return 2 }
        if path == "Derived/Thumbnails/index.json" { return 3 }
        if path == "manifest.json" { return 3 }
        return 1
    }

    private static func isRegularFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    private static func hashFile(
        at url: URL, chunkSize: Int, isCancelled: @Sendable () -> Bool
    ) throws -> (byteCount: UInt64, checksum: String) {
        let input = try FileHandle(forReadingFrom: url)
        var hasher = SHA256()
        var byteCount: UInt64 = 0
        do {
            while true {
                if isCancelled() { throw CancellationError() }
                // Per-chunk pool for the same reason as `stage(fileAt:)`.
                let finished = try autoreleasepool {
                    let chunk = try input.read(upToCount: chunkSize) ?? Data()
                    if chunk.isEmpty { return true }
                    hasher.update(data: chunk)
                    byteCount += UInt64(chunk.count)
                    return false
                }
                if finished { break }
            }
            try input.close()
        } catch {
            try? input.close()
            throw error
        }
        return (byteCount, hasher.finalize().hexString)
    }

    private static func canClonefile(source: URL, destination: URL) -> Bool {
        guard let sourceVolume = volumeIdentifier(for: source),
              let destinationVolume = volumeIdentifier(for: destination.deletingLastPathComponent())
        else { return false }
        return sourceVolume == destinationVolume
    }

    private static func volumeIdentifier(for url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.volumeIdentifierKey])
        return values?.volumeIdentifier.map { String(describing: $0) }
    }

    private static func relativePath(from root: URL, to url: URL) -> String {
        let rootPath =
            root.standardizedFileURL.path.hasSuffix("/")
            ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        return String(url.standardizedFileURL.path.dropFirst(rootPath.count))
    }
}
private func writeDurably(_ data: Data, to url: URL) throws {
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
        ".\(url.lastPathComponent).tmp-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: temporary.path, contents: nil)
    let descriptor = open(temporary.path, O_WRONLY | O_TRUNC)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
    var descriptorOpen = true
    do {
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try fullSync(descriptor)
        close(descriptor)
        descriptorOpen = false
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(
                url, withItemAt: temporary, backupItemName: nil, options: .usingNewMetadataOnly
            )
        } else {
            try FileManager.default.moveItem(at: temporary, to: url)
        }
        try fullSyncDirectory(url.deletingLastPathComponent())
    } catch {
        if descriptorOpen { close(descriptor) }
        try? FileManager.default.removeItem(at: temporary)
        throw error
    }
}

func fullSync(_ descriptor: Int32) throws {
    if fcntl(descriptor, F_FULLFSYNC) != 0 { throw CocoaError(.fileWriteUnknown) }
}

/// Flushes a directory's entries to stable storage with the same primitive as `fullSync`.
/// Throws when the directory cannot be opened or the sync fails: a rename or unlink that
/// was not made durable must not be reported as committed. `sync` is a test seam for
/// forcing a sync failure, which APFS will not produce on demand.
func fullSyncDirectory(_ url: URL, sync: (Int32) throws -> Void = fullSync) throws {
    let descriptor = open(url.path, O_RDONLY)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
    defer { close(descriptor) }
    try sync(descriptor)
}
