import CryptoKit
import Darwin
import Foundation

/// The points at which a package commit can be interrupted in tests or by a process crash.
enum PortablePackageTransactionBoundary: String, CaseIterable, Codable, Sendable {
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
        }
    }
}

/// A deterministic, test-only fault injector. Production callers use the default instance.
final class PortablePackageFaultInjector: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [PortablePackageTransactionBoundary: Int]

    init(failingAt boundary: PortablePackageTransactionBoundary, times: Int = 1) {
        remaining = [boundary: max(times, 0)]
    }

    init(failingAt boundaries: Set<PortablePackageTransactionBoundary>) {
        remaining = Dictionary(uniqueKeysWithValues: boundaries.map { ($0, 1) })
    }

    func check(_ boundary: PortablePackageTransactionBoundary) throws {
        let shouldFail = lock.withLock {
            guard let count = remaining[boundary], count > 0 else { return false }
            remaining[boundary] = count - 1
            return true
        }
        if shouldFail { throw PortablePackageTransactionError.injectedFailure(boundary) }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

struct PortablePackageLeaseInfo: Codable, Equatable, Sendable {
    let ownerID: UUID
    let deviceName: String
    let processID: Int32
    let acquiredAt: Date
    var heartbeatAt: Date
    var expiresAt: Date
}

enum PortablePackageLeaseError: Error, Equatable, CustomStringConvertible {
    case contended(PortablePackageLeaseInfo)
    case expired(PortablePackageLeaseInfo)
    case notOwner
    case missing
    case invalid
    case injectedFailure(PortablePackageTransactionBoundary)

    var description: String {
        switch self {
        case .contended(let info):
            return "Package is already being written by \(info.deviceName) (pid \(info.processID))"
        case .expired: return "The package writer lease has expired"
        case .notOwner: return "This session does not own the package writer lease"
        case .missing: return "The package writer lease is missing"
        case .invalid: return "The package writer lease is invalid"
        case .injectedFailure(let boundary): return "Injected lease failure at \(boundary.rawValue)"
        }
    }
}

/// An explicit single-writer lease stored beside the package manifest.
///
/// Acquisition uses O_EXCL, so two processes cannot both become the owner. Expired leases are
/// reported rather than silently broken; callers must explicitly call `breakExpired` after any
/// transaction recovery and, normally, user confirmation.
final class PortablePackageLease: @unchecked Sendable {
    static let defaultDuration: TimeInterval = 180

    let packageRoot: URL
    let ownerID: UUID
    private(set) var info: PortablePackageLeaseInfo
    private let duration: TimeInterval
    private var released = false

    private init(packageRoot: URL, info: PortablePackageLeaseInfo, duration: TimeInterval) {
        self.packageRoot = packageRoot
        ownerID = info.ownerID
        self.info = info
        self.duration = duration
    }

    deinit {
        try? release()
    }

    static func acquire(
        at packageRoot: URL,
        ownerID: UUID = UUID(),
        deviceName: String = Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        now: Date = Date(),
        duration: TimeInterval = PortablePackageLease.defaultDuration
    ) throws -> Self {
        let fm = FileManager.default
        try fm.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        let lockURL = packageRoot.appendingPathComponent("manifest.lock")
        let info = PortablePackageLeaseInfo(
            ownerID: ownerID, deviceName: deviceName, processID: processID,
            acquiredAt: now, heartbeatAt: now, expiresAt: now.addingTimeInterval(duration)
        )
        let data = try Self.encode(info)
        let descriptor = open(lockURL.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            if errno != EEXIST { throw PortablePackageLeaseError.invalid }
            guard let existing = try? Self.readInfo(at: lockURL) else {
                throw PortablePackageLeaseError.invalid
            }
            if existing.expiresAt > now { throw PortablePackageLeaseError.contended(existing) }
            throw PortablePackageLeaseError.expired(existing)
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

    static func breakExpired(at packageRoot: URL, now: Date = Date()) throws {
        let fm = FileManager.default
        let lockURL = packageRoot.appendingPathComponent("manifest.lock")
        guard fm.fileExists(atPath: lockURL.path) else { throw PortablePackageLeaseError.missing }
        let existing = try readInfo(at: lockURL)
        guard existing.expiresAt <= now else { throw PortablePackageLeaseError.contended(existing) }
        let quarantine = packageRoot.appendingPathComponent(
            "manifest.lock.expired-\(UUID().uuidString)")
        try fm.moveItem(at: lockURL, to: quarantine)
        try? fm.removeItem(at: quarantine)
    }

    var isExpired: Bool { isExpired(at: Date()) }

    func isExpired(at date: Date) -> Bool { info.expiresAt <= date }

    func renew(
        now: Date = Date(),
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws {
        try faultInjector?.check(.leaseRenewal)
        try assertOwnership(at: now)
        info.heartbeatAt = now
        info.expiresAt = now.addingTimeInterval(duration)
        let data = try Self.encode(info)
        guard FileManager.default.fileExists(atPath: lockURL.path) else {
            throw PortablePackageLeaseError.missing
        }
        try writeDurably(data, to: lockURL)
    }

    func assertOwnership(
        at date: Date = Date(),
        faultInjector: PortablePackageFaultInjector? = nil
    ) throws {
        try faultInjector?.check(.leaseLoss)
        guard !released else { throw PortablePackageLeaseError.notOwner }
        guard let current = try? Self.readInfo(at: lockURL) else {
            throw PortablePackageLeaseError.missing
        }
        guard current.ownerID == ownerID else { throw PortablePackageLeaseError.notOwner }
        guard current.expiresAt > date else { throw PortablePackageLeaseError.expired(current) }
    }

    func release() throws {
        guard !released else { return }
        guard let current = try? Self.readInfo(at: lockURL) else {
            released = true
            return
        }
        guard current.ownerID == ownerID else { throw PortablePackageLeaseError.notOwner }
        try FileManager.default.removeItem(at: lockURL)
        released = true
    }

    private var lockURL: URL { packageRoot.appendingPathComponent("manifest.lock") }

    private static func readInfo(at url: URL) throws -> PortablePackageLeaseInfo {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PortablePackageLeaseInfo.self, from: Data(contentsOf: url))
    }

    private static func encode(_ info: PortablePackageLeaseInfo) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(info)
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
    }

    let relativePath: String
    let stagingPath: String
    var backupPath: String?
    let byteCount: UInt64
    let stagedChecksum: String
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
    var state: State
}

struct PortablePackageRecoveryReport: Equatable, Sendable {
    let recoveredTransactionIDs: [UUID]
    let removedOrphanedStagingDirectories: [String]
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
        let recoveryURL = packageRoot.appendingPathComponent("Recovery", isDirectory: true)
        let transactionsURL = recoveryURL.appendingPathComponent("Transactions", isDirectory: true)
        let stagingURL = recoveryURL.appendingPathComponent(
            "Staging/\(transactionID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: transactionsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
        let journal = PortablePackageTransactionJournal(
            transactionID: transactionID, packageID: packageID, createdAt: now,
            stagingDirectory: "Recovery/Staging/\(transactionID.uuidString)", files: [],
            state: .prepared
        )
        let journalURL = transactionsURL.appendingPathComponent("\(transactionID.uuidString).json")
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

    mutating func stage(data: Data, at relativePath: String) throws {
        try validateRelativePath(relativePath)
        guard !journal.files.contains(where: { $0.relativePath == relativePath }) else {
            throw PortablePackageTransactionError.duplicateStagedPath(relativePath)
        }
        let stagingPath = "\(journal.stagingDirectory)/\(relativePath)"
        let destination = packageRoot.appendingPathComponent(stagingPath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: [])
        let checksum = Self.sha256(data)
        let file = PortablePackageTransactionFile(
            relativePath: relativePath, stagingPath: stagingPath, backupPath: nil,
            byteCount: UInt64(data.count), stagedChecksum: checksum, publicationState: .staged
        )
        journal.files.append(file)
        try persistJournal()
        try faultInjector?.check(.stage)
    }

    /// Streams a source file once into same-volume staging while computing its expected checksum.
    mutating func stage(fileAt sourceURL: URL, to relativePath: String, chunkSize: Int = 1 << 20)
        throws
    {
        try validateRelativePath(relativePath)
        guard !journal.files.contains(where: { $0.relativePath == relativePath }) else {
            throw PortablePackageTransactionError.duplicateStagedPath(relativePath)
        }
        let stagingPath = "\(journal.stagingDirectory)/\(relativePath)"
        let destination = packageRoot.appendingPathComponent(stagingPath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: Self.createEmptyFile(at: destination))
        var hasher = SHA256()
        var byteCount: UInt64 = 0
        do {
            while true {
                let chunk = try input.read(upToCount: chunkSize) ?? Data()
                if chunk.isEmpty { break }
                try output.write(contentsOf: chunk)
                hasher.update(data: chunk)
                byteCount += UInt64(chunk.count)
            }
            try output.synchronize()
            try fullSync(output.fileDescriptor)
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
        try persistJournal()
        try faultInjector?.check(.stage)
    }

    mutating func commit(now: Date = Date()) throws {
        guard journal.state != .committed else {
            throw PortablePackageTransactionError.transactionAlreadyCommitted
        }
        try lease.assertOwnership(at: now, faultInjector: faultInjector)
        journal.state = .flushing
        try persistJournal()
        for file in journal.files {
            let url = packageRoot.appendingPathComponent(file.stagingPath)
            let handle = try FileHandle(forWritingTo: url)
            try handle.synchronize()
            try fullSync(handle.fileDescriptor)
            try handle.close()
            try faultInjector?.check(.flush)
        }

        journal.state = .checksumming
        try persistJournal()
        for file in journal.files {
            let url = packageRoot.appendingPathComponent(file.stagingPath)
            let data = try Data(contentsOf: url)
            let actual = Self.sha256(data)
            guard UInt64(data.count) == file.byteCount else {
                throw PortablePackageTransactionError.stagedFileChanged(path: file.relativePath)
            }
            guard actual == file.stagedChecksum else {
                throw PortablePackageTransactionError.checksumMismatch(
                    path: file.relativePath, expected: file.stagedChecksum, actual: actual
                )
            }
            try faultInjector?.check(.checksum)
        }

        journal.files = journal.files.map { file in
            var prepared = file
            let target = packageRoot.appendingPathComponent(file.relativePath)
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
        journal.state = .publishing
        try persistJournal()

        let ordered = journal.files.sorted {
            Self.publishRank($0.relativePath) < Self.publishRank($1.relativePath)
        }
        for item in ordered {
            try lease.assertOwnership(at: now, faultInjector: faultInjector)
            guard
                let currentIndex = journal.files.firstIndex(where: {
                    $0.relativePath == item.relativePath
                })
            else {
                throw PortablePackageTransactionError.journalCorrupt(item.relativePath)
            }
            journal.files[currentIndex].publicationState = .started
            try persistJournal()
            let target = packageRoot.appendingPathComponent(item.relativePath)
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
            }
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let staged = packageRoot.appendingPathComponent(item.stagingPath)
            try FileManager.default.moveItem(at: staged, to: target)
            try fullSyncDirectory(target.deletingLastPathComponent())
            journal.files[currentIndex].publicationState = .published
            try persistJournal()
            try faultInjector?.check(.publish)
        }
        journal.state = .committed
        try persistJournal()
        cleanupCommittedArtifacts()
    }

    /// Replays all uncommitted journals by restoring previous files and removing staging. A
    /// committed journal is only cleanup work, so recovery remains safe after a post-commit crash.
    @discardableResult
    static func recover(at packageRoot: URL) throws -> PortablePackageRecoveryReport {
        let fm = FileManager.default
        let transactionsURL = packageRoot.appendingPathComponent("Recovery/Transactions")
        let stagingRoot = packageRoot.appendingPathComponent("Recovery/Staging")
        var recovered: [UUID] = []
        if fm.fileExists(atPath: transactionsURL.path) {
            let urls = try fm.contentsOfDirectory(
                at: transactionsURL, includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "json" }
            for url in urls {
                let journal: PortablePackageTransactionJournal
                do {
                    journal = try decodeJournal(from: Data(contentsOf: url))
                } catch {
                    throw PortablePackageTransactionError.journalCorrupt(url.lastPathComponent)
                }
                if journal.state != .committed {
                    try rollback(journal, packageRoot: packageRoot)
                    recovered.append(journal.transactionID)
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try writeDurably(encoder.encode(journal), to: journalURL)
    }

    private func cleanupCommittedArtifacts() {
        try? FileManager.default.removeItem(at: stagingURL)
        try? FileManager.default.removeItem(at: journalURL)
    }

    private static func rollback(_ journal: PortablePackageTransactionJournal, packageRoot: URL)
        throws
    {
        let fm = FileManager.default
        for file in journal.files.reversed() {
            let target = packageRoot.appendingPathComponent(file.relativePath)
            let staged = packageRoot.appendingPathComponent(file.stagingPath)
            if let backupPath = file.backupPath {
                let backup = URL(fileURLWithPath: backupPath)
                if fm.fileExists(atPath: backup.path) {
                    if fm.fileExists(atPath: target.path) { try? fm.removeItem(at: target) }
                    try fm.createDirectory(
                        at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: backup, to: target)
                    try fullSyncDirectory(target.deletingLastPathComponent())
                } else if file.publicationState == .published, fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
            } else if file.publicationState == .published
                || (file.publicationState == .started && !fm.fileExists(atPath: staged.path)),
                fm.fileExists(atPath: target.path)
            {
                try fm.removeItem(at: target)
            }
            if !fm.fileExists(atPath: staged.path) { continue }
        }
    }

    private static func decodeJournal(from data: Data) throws -> PortablePackageTransactionJournal {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PortablePackageTransactionJournal.self, from: data)
    }

    private static func validateRelativePath(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
            throw PortablePackageTransactionError.invalidRelativePath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(".."), !components.contains(""), !path.hasPrefix("Recovery/")
        else {
            throw PortablePackageTransactionError.invalidRelativePath(path)
        }
    }

    private func validateRelativePath(_ path: String) throws { try Self.validateRelativePath(path) }

    private static func publishRank(_ path: String) -> Int {
        if path.hasSuffix("/asset.json") { return 2 }
        if path == "manifest.json" { return 3 }
        return 1
    }

    private static func sha256(_ data: Data) -> String { SHA256.hash(data: data).hexString }

    private static func createEmptyFile(at url: URL) throws -> URL {
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    private static func relativePath(from root: URL, to url: URL) -> String {
        let rootPath =
            root.standardizedFileURL.path.hasSuffix("/")
            ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        return String(url.standardizedFileURL.path.dropFirst(rootPath.count))
    }
}

extension SHA256.Digest {
    fileprivate var hexString: String { map { String(format: "%02x", $0) }.joined() }
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

private func fullSync(_ descriptor: Int32) throws {
    #if os(macOS)
        if fcntl(descriptor, F_FULLFSYNC) != 0 { throw CocoaError(.fileWriteUnknown) }
    #else
        if fsync(descriptor) != 0 { throw CocoaError(.fileWriteUnknown) }
    #endif
}

private func fullSyncDirectory(_ url: URL) throws {
    let descriptor = open(url.path, O_RDONLY)
    guard descriptor >= 0 else { return }
    defer { close(descriptor) }
    _ = fsync(descriptor)
}
