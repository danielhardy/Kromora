import CryptoKit
import Darwin
import Foundation

/// Options for a verified package backup. `Derived/` is deliberately omitted by default: it is a
/// rebuildable cache and must never turn a backup into an integrity failure.
struct PortableLibraryBackupOptions: Equatable, Sendable {
    var chunkSize: Int
    var copyMode: PortablePackageFileCopyMode
    var includeDerived: Bool
    var faultInjector: PortablePackageFaultInjector?

    init(
        chunkSize: Int = 1 << 20,
        copyMode: PortablePackageFileCopyMode = .automatic,
        includeDerived: Bool = false,
        faultInjector: PortablePackageFaultInjector? = nil
    ) {
        self.chunkSize = max(1, chunkSize)
        self.copyMode = copyMode
        self.includeDerived = includeDerived
        self.faultInjector = faultInjector
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chunkSize == rhs.chunkSize
            && lhs.copyMode == rhs.copyMode
            && lhs.includeDerived == rhs.includeDerived
    }
}

struct PortableLibraryBackupProgress: Equatable, Sendable {
    enum Phase: String, Sendable { case snapshot, copying, verifying, publishing }

    let phase: Phase
    let relativePath: String?
    let completedFiles: Int
    let totalFiles: Int
    let copiedBytes: UInt64
    let totalBytes: UInt64
}

struct PortableLibraryBackupResult: Equatable, Sendable {
    let destinationURL: URL
    let sourceLibraryID: UUID
    let snapshotID: UUID
    let copiedFiles: Int
    let reusedFiles: Int
    let verifiedFiles: Int
    let totalFiles: Int
    let copiedBytes: UInt64
    let totalBytes: UInt64
    let resumed: Bool
    let includedDerived: Bool
}

enum PortableLibraryBackupError: Error, Equatable, CustomStringConvertible {
    case invalidDestination(String)
    case sourceIsNotPackage
    case sourceChanged(path: String)
    case missingCanonicalComponent(String)
    case incompleteDestination(String)
    case pendingEditsNotDurable(String)
    case checksumMismatch(path: String, expected: String, actual: String)
    case byteCountMismatch(path: String, expected: UInt64, actual: UInt64)
    case backupMetadataCorrupt(String)

    var description: String {
        switch self {
        case .invalidDestination(let message): return "Invalid backup destination: \(message)"
        case .sourceIsNotPackage: return "The source is not a valid Kromora library package"
        case .sourceChanged(let path): return "Source changed while backing up '\(path)'"
        case .missingCanonicalComponent(let path):
            return "Missing canonical package component '\(path)'"
        case .incompleteDestination(let path):
            return "Backup destination is incomplete: '\(path)'"
        case .pendingEditsNotDurable(let message):
            return "Pending edits could not be flushed before backup: \(message)"
        case .checksumMismatch(let path, let expected, let actual):
            return "Backup checksum mismatch for '\(path)': expected \(expected), got \(actual)"
        case .byteCountMismatch(let path, let expected, let actual):
            return "Backup byte-count mismatch for '\(path)': expected \(expected), got \(actual)"
        case .backupMetadataCorrupt(let message): return "Corrupt backup metadata: \(message)"
        }
    }
}

private struct PortableLibraryBackupFile: Codable, Equatable, Sendable {
    let relativePath: String
    let byteCount: UInt64
    let checksum: String
    let rebuildable: Bool
}

private struct PortableLibraryBackupMetadata: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let sourceLibraryID: UUID
    let snapshotID: UUID
    let createdAt: Date
    let files: [PortableLibraryBackupFile]
    let includesDerived: Bool
}

private struct PortableLibraryBackupProgressState: Codable, Equatable, Sendable {
    let sourceLibraryID: UUID
    let snapshotID: UUID
    let includesDerived: Bool
    var files: [PortableLibraryBackupFile]
}

/// A verified, incremental and resumable backup of a `PortableLibraryPackage`.
///
/// The operation never writes directly to the requested destination. Work is retained in a hidden
/// sibling staging directory so cancellation and ordinary errors can resume. The requested path
/// changes only after every canonical file has been checked, using a same-volume directory rename.
struct PortableLibraryBackup {
    private static let stagingSuffix = ".kromora-backup-staging"
    private static let previousSuffix = ".kromora-backup-previous"
    private static let stateName = "backup-state.json"
    private static let recoveryDirectory = "Recovery/Backup"
    private static let metadataName = "manifest.json"
    private static let completeName = "complete.json"

    /// Flushes the caller's coalesced edit persistence path before taking the package lease.
    @discardableResult
    static func run(
        package: PortableLibraryPackage,
        to destinationURL: URL,
        options: PortableLibraryBackupOptions = .init(),
        flushPendingEdits: (() throws -> Void)? = nil,
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortableLibraryBackupProgress) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> PortableLibraryBackupResult {
        try flushPendingEdits?()

        let sourceRoot = package.rootURL.standardizedFileURL
        let destination = destinationURL.standardizedFileURL
        try validateDestination(destination, sourceRoot: sourceRoot)
        try recoverPriorPublication(at: destination)

        let lease = try PortablePackageLease.acquire(at: sourceRoot)
        defer { try? lease.release() }
        // Establish a fresh heartbeat before recovery/snapshot work. The copy and verification
        // loops renew again at file boundaries, so a large backup cannot leave the package open
        // under an expiring writer lease.
        try lease.renew(now: now())
        // A process can have crashed after publishing some transaction files but before the
        // journal was removed. Recover that transaction while the backup owns the writer lease;
        // otherwise the backup could faithfully copy an in-flight commit.
        _ = try PortablePackageTransaction.recover(at: sourceRoot)
        let sourcePackage: PortableLibraryPackage
        do {
            sourcePackage = try PortableLibraryPackage.open(at: sourceRoot)
        } catch {
            throw PortableLibraryBackupError.sourceIsNotPackage
        }
        try validateCanonicalReferences(in: sourcePackage)

        let staging = stagingURL(for: destination)
        let previous = destination
        let previousMetadata: PortableLibraryBackupMetadata?
        do { previousMetadata = try readMetadata(at: previous) }
        catch { previousMetadata = nil }
        let resumedState = try? readProgressState(at: staging)
        let resumed = resumedState != nil
            && resumedState?.sourceLibraryID == sourcePackage.manifest.libraryID
        // Only inherit a staging snapshot's identity when it belongs to this same source library;
        // a staging directory left over from a different library backed up to the same destination
        // path must start a fresh snapshot rather than borrowing an unrelated one.
        let snapshotID = resumed ? (resumedState?.snapshotID ?? UUID()) : UUID()

        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var state = PortableLibraryBackupProgressState(
            sourceLibraryID: sourcePackage.manifest.libraryID,
            snapshotID: snapshotID,
            includesDerived: options.includeDerived,
            files: resumed && resumedState?.includesDerived == options.includeDerived
                ? resumedState?.files ?? [] : []
        )

        let sourceFiles = try canonicalFiles(
            under: sourceRoot, includeDerived: options.includeDerived
        )
        progress(.init(
            phase: .snapshot, relativePath: nil, completedFiles: 0,
            totalFiles: sourceFiles.count, copiedBytes: 0,
            totalBytes: sourceFiles.reduce(0) { $0 + $1.byteCount }
        ))

        let previousFiles = previousMetadata?.files ?? (try? metadataFiles(at: previous)) ?? []
        let previousByPath = Dictionary(uniqueKeysWithValues: previousFiles.map { ($0.relativePath, $0) })
        var completedFiles = 0
        var copiedFiles = 0
        var reusedFiles = 0
        var copiedBytes: UInt64 = 0
        var totalBytes: UInt64 = 0

        for sourceFile in sourceFiles {
            try checkCancellation(isCancelled)
            try lease.renew(now: now())
            totalBytes += sourceFile.byteCount
            let sourceURL = try safePackageURL(sourceFile.relativePath, under: sourceRoot)
            let digest = try hashFile(at: sourceURL, chunkSize: options.chunkSize, isCancelled: isCancelled)
            let snapshotFile = PortableLibraryBackupFile(
                relativePath: sourceFile.relativePath, byteCount: digest.byteCount,
                checksum: digest.checksum, rebuildable: sourceFile.rebuildable
            )

            let existingState = state.files.first { $0.relativePath == snapshotFile.relativePath }
            let stagingFile = try safePackageURL(snapshotFile.relativePath, under: staging)
            if existingState == snapshotFile,
               regularFileExists(at: stagingFile),
               (try? verify(snapshotFile, at: stagingFile)) != nil
            {
                reusedFiles += 1
            } else if let old = previousByPath[snapshotFile.relativePath], old == snapshotFile,
                      regularFileExists(at: try safePackageURL(snapshotFile.relativePath, under: previous))
            {
                try cloneOrLink(
                    from: try safePackageURL(snapshotFile.relativePath, under: previous), to: stagingFile
                )
                reusedFiles += 1
            } else {
                try copyFile(
                    from: sourceURL, to: stagingFile, expected: snapshotFile,
                    chunkSize: options.chunkSize, copyMode: options.copyMode,
                    isCancelled: isCancelled, faultInjector: options.faultInjector
                )
                copiedFiles += 1
                copiedBytes += snapshotFile.byteCount
            }

            state.files.removeAll { $0.relativePath == snapshotFile.relativePath }
            state.files.append(snapshotFile)
            state.files.sort { $0.relativePath < $1.relativePath }
            try writeJSON(state, to: staging.appendingPathComponent(stateName))
            completedFiles += 1
            progress(.init(
                phase: .copying, relativePath: snapshotFile.relativePath,
                completedFiles: completedFiles, totalFiles: sourceFiles.count,
                copiedBytes: copiedBytes, totalBytes: totalBytes
            ))
        }

        // Remove files left over from an older, larger source snapshot. Only the owned staging
        // directory is touched; a canceled backup remains resumable until this point.
        let expectedPaths = Set(sourceFiles.map(\.relativePath))
        try removeStaleStagingFiles(at: staging, expected: expectedPaths)
        let orderedStateFiles = state.files.filter { expectedPaths.contains($0.relativePath) }
            .sorted { $0.relativePath < $1.relativePath }
        state.files = orderedStateFiles
        try writeJSON(state, to: staging.appendingPathComponent(stateName))

        progress(.init(
            phase: .verifying, relativePath: nil, completedFiles: 0,
            totalFiles: orderedStateFiles.count, copiedBytes: copiedBytes,
            totalBytes: orderedStateFiles.reduce(0) { $0 + $1.byteCount }
        ))
        for (index, file) in orderedStateFiles.enumerated() {
            try checkCancellation(isCancelled)
            let url = try safePackageURL(file.relativePath, under: staging)
            guard regularFileExists(at: url) else {
                if file.rebuildable { continue }
                throw PortableLibraryBackupError.missingCanonicalComponent(file.relativePath)
            }
            try verify(file, at: url)
            try options.faultInjector?.check(.checksum)
            progress(.init(
                phase: .verifying, relativePath: file.relativePath,
                completedFiles: index + 1, totalFiles: orderedStateFiles.count,
                copiedBytes: copiedBytes, totalBytes: orderedStateFiles.reduce(0) { $0 + $1.byteCount }
            ))
        }

        let metadata = PortableLibraryBackupMetadata(
            version: PortableLibraryBackupMetadata.currentVersion,
            sourceLibraryID: sourcePackage.manifest.libraryID, snapshotID: snapshotID,
            createdAt: Date(), files: orderedStateFiles, includesDerived: options.includeDerived
        )
        let backupRecovery = staging.appendingPathComponent(recoveryDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: backupRecovery, withIntermediateDirectories: true)
        try writeJSON(metadata, to: backupRecovery.appendingPathComponent(metadataName))
        try writeJSON(metadata, to: backupRecovery.appendingPathComponent(completeName))
        try syncDirectory(backupRecovery)
        try checkCancellation(isCancelled)
        try lease.renew(now: now())
        try options.faultInjector?.check(.publish)

        progress(.init(
            phase: .publishing, relativePath: nil, completedFiles: orderedStateFiles.count,
            totalFiles: orderedStateFiles.count, copiedBytes: copiedBytes,
            totalBytes: orderedStateFiles.reduce(0) { $0 + $1.byteCount }
        ))
        try publish(staging: staging, at: destination)
        try? FileManager.default.removeItem(at: destination.appendingPathComponent(stateName))

        return PortableLibraryBackupResult(
            destinationURL: destination, sourceLibraryID: sourcePackage.manifest.libraryID,
            snapshotID: snapshotID, copiedFiles: copiedFiles, reusedFiles: reusedFiles,
            verifiedFiles: orderedStateFiles.count, totalFiles: orderedStateFiles.count,
            copiedBytes: copiedBytes,
            totalBytes: orderedStateFiles.reduce(0) { $0 + $1.byteCount }, resumed: resumed,
            includedDerived: options.includeDerived
        )
    }

    /// Async convenience used by UI/application orchestration. The closure should call the same
    /// `EditPersistenceCoordinator.flush()` path used at termination and throw if it cannot flush.
    @discardableResult
    static func run(
        package: PortableLibraryPackage,
        to destinationURL: URL,
        options: PortableLibraryBackupOptions = .init(),
        flushPendingEdits: @escaping @Sendable () async throws -> Void,
        isCancelled: @Sendable @escaping () -> Bool = { false },
        progress: @Sendable @escaping (PortableLibraryBackupProgress) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() }
    ) async throws -> PortableLibraryBackupResult {
        try await flushPendingEdits()
        return try run(
            package: package, to: destinationURL, options: options,
            isCancelled: isCancelled, progress: progress, now: now
        )
    }

    /// Variant for the application's coalesced persistence API. A backup cannot start from a
    /// failed or canceled flush, because that would make its snapshot appear newer than the edit
    /// state the user asked to protect.
    @discardableResult
    static func run(
        package: PortableLibraryPackage,
        to destinationURL: URL,
        options: PortableLibraryBackupOptions = .init(),
        flushPendingEditsResult: @escaping @Sendable () async -> PersistenceFlushResult,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        progress: @escaping @Sendable (PortableLibraryBackupProgress) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() }
    ) async throws -> PortableLibraryBackupResult {
        switch await flushPendingEditsResult() {
        case .success:
            break
        case .failure(let message):
            throw PortableLibraryBackupError.pendingEditsNotDurable(message)
        case .cancelled:
            throw CancellationError()
        }
        return try run(
            package: package, to: destinationURL, options: options,
            isCancelled: isCancelled, progress: progress, now: now
        )
    }

    static func stagingURL(for destinationURL: URL) -> URL {
        destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent)\(stagingSuffix)")
    }

    static func isVerifiedBackup(at destinationURL: URL) -> Bool {
        (try? validateVerifiedBackup(at: destinationURL)) != nil
    }

    /// Throws the first actionable checksum/metadata error instead of collapsing it into the
    /// boolean convenience used by backup callers.
    static func validateVerifiedBackup(at destinationURL: URL) throws {
        let metadata: PortableLibraryBackupMetadata
        do {
            metadata = try readMetadata(at: destinationURL)
        } catch {
            throw PortableLibraryBackupError.backupMetadataCorrupt(
                "missing or unreadable Recovery/Backup/manifest.json"
            )
        }
        guard metadata.version == PortableLibraryBackupMetadata.currentVersion else {
            throw PortableLibraryBackupError.backupMetadataCorrupt(
                "unsupported metadata version \(metadata.version)"
            )
        }
        let marker = destinationURL.appendingPathComponent("\(recoveryDirectory)/\(completeName)")
        let completed: PortableLibraryBackupMetadata
        do {
            completed = try PackageJSONCoder.decode(
                PortableLibraryBackupMetadata.self, from: Data(contentsOf: marker)
            )
        } catch {
            throw PortableLibraryBackupError.backupMetadataCorrupt(
                "missing or unreadable Recovery/Backup/complete.json"
            )
        }
        guard completed == metadata else {
            throw PortableLibraryBackupError.backupMetadataCorrupt(
                "completion marker does not match the backup manifest"
            )
        }
        for file in metadata.files {
            try verify(file, at: try safePackageURL(file.relativePath, under: destinationURL))
        }
    }

    private struct SourceFile {
        let relativePath: String
        let byteCount: UInt64
        let rebuildable: Bool
    }

    private static func canonicalFiles(under root: URL, includeDerived: Bool) throws -> [SourceFile] {
        guard regularFileExists(at: try safePackageURL("manifest.json", under: root)) else {
            throw PortableLibraryBackupError.missingCanonicalComponent("manifest.json")
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { throw PortableLibraryBackupError.sourceIsNotPackage }

        var result: [SourceFile] = []
        for case let url as URL in enumerator {
            let relative = relativePath(from: root, to: url)
            if relative == "manifest.lock" || relative == stateName
                || relative == "Recovery" || relative.hasPrefix("Recovery/") { continue }
            if relative == "Derived" || relative.hasPrefix("Derived/") {
                if !includeDerived { enumerator.skipDescendants(); continue }
            }
            let relativeURL = try safePackageURL(relative, under: root)
            let values = try relativeURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else {
                throw PortableLibraryBackupError.sourceIsNotPackage
            }
            guard values.isRegularFile == true else { continue }
            result.append(SourceFile(
                relativePath: relative, byteCount: UInt64(values.fileSize ?? 0),
                rebuildable: relative == "Derived" || relative.hasPrefix("Derived/")
            ))
        }
        return result.sorted { $0.relativePath < $1.relativePath }
    }

    /// Validates all durable references that are not expressible by a single file checksum.
    /// Restore uses the same gate as backup so a package can never be promoted merely because its
    /// files happen to be present.
    static func validateCanonicalReferences(in package: PortableLibraryPackage) throws {
        let report = try PortableLibraryValidation.run(
            package: package, options: .criticalOnly
        )
        if let failure = report.criticalFailures.first {
            throw PortableLibraryBackupError.missingCanonicalComponent(failure.path)
        }
    }

    private static func validateDestination(_ destination: URL, sourceRoot: URL) throws {
        guard destination != sourceRoot else {
            throw PortableLibraryBackupError.invalidDestination("destination is the source package")
        }
        if destination.path.hasPrefix(sourceRoot.path + "/") {
            throw PortableLibraryBackupError.invalidDestination("destination is inside the source package")
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory),
           !isDirectory.boolValue {
            throw PortableLibraryBackupError.invalidDestination("destination is not a directory")
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
    }

    private static func recoverPriorPublication(at destination: URL) throws {
        let previous = previousURL(for: destination)
        let fm = FileManager.default
        guard fm.fileExists(atPath: previous.path) else { return }
        if !fm.fileExists(atPath: destination.path) {
            if rename(previous.path, destination.path) != 0 {
                throw PortableLibraryBackupError.incompleteDestination(previous.path)
            }
        } else if isVerifiedBackup(at: destination) {
            try? fm.removeItem(at: previous)
        } else {
            // A crash or external tamper may have left an unverified destination beside the
            // last good publication. Restore the good publication before the next incremental
            // attempt; the unverified tree is kept only as a recoverable staging artifact.
            try? fm.removeItem(at: destination)
            guard rename(previous.path, destination.path) == 0 else {
                throw PortableLibraryBackupError.incompleteDestination(previous.path)
            }
        }
    }

    private static func publish(staging: URL, at destination: URL) throws {
        let fm = FileManager.default
        let previous = previousURL(for: destination)
        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: previous)
            guard rename(destination.path, previous.path) == 0 else {
                throw PortableLibraryBackupError.incompleteDestination(destination.path)
            }
        }
        guard rename(staging.path, destination.path) == 0 else {
            if fm.fileExists(atPath: previous.path) { _ = rename(previous.path, destination.path) }
            throw PortableLibraryBackupError.incompleteDestination(staging.path)
        }
        try? fm.removeItem(at: previous)
        try syncDirectory(destination.deletingLastPathComponent())
    }

    private static func previousURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent)\(previousSuffix)")
    }

    private static func readProgressState(at staging: URL) throws -> PortableLibraryBackupProgressState {
        try PackageJSONCoder.decode(
            PortableLibraryBackupProgressState.self,
            from: Data(contentsOf: staging.appendingPathComponent(stateName))
        )
    }

    private static func readMetadata(at package: URL) throws -> PortableLibraryBackupMetadata {
        let url = package.appendingPathComponent("\(recoveryDirectory)/\(metadataName)")
        return try PackageJSONCoder.decode(
            PortableLibraryBackupMetadata.self, from: Data(contentsOf: url)
        )
    }

    private static func metadataFiles(at package: URL) throws -> [PortableLibraryBackupFile] {
        try canonicalFiles(under: package, includeDerived: true).map {
            let digest = try hashFile(at: safePackageURL($0.relativePath, under: package), chunkSize: 1 << 20, isCancelled: { false })
            return PortableLibraryBackupFile(
                relativePath: $0.relativePath, byteCount: digest.byteCount,
                checksum: digest.checksum, rebuildable: $0.rebuildable
            )
        }
    }

    private static func copyFile(
        from source: URL, to destination: URL, expected: PortableLibraryBackupFile,
        chunkSize: Int, copyMode: PortablePackageFileCopyMode,
        isCancelled: @Sendable () -> Bool,
        faultInjector: PortablePackageFaultInjector?
    ) throws {
        try faultInjector?.check(.diskFull)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        // A backup must detect a source mutation between its snapshot hash and the copy. The
        // second digest is cheap compared with silently publishing a mixed package.
        if copyMode == .automatic, canClonefile(source: source, destination: destination),
           clonefile(source.path, destination.path, 0) == 0 {
            try verify(expected, at: destination)
            try faultInjector?.check(.stage)
            return
        }
        let input = try FileHandle(forReadingFrom: source)
        try? FileManager.default.removeItem(at: destination)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        var hasher = SHA256()
        var count: UInt64 = 0
        do {
            while true {
                try checkCancellation(isCancelled)
                let chunk = try input.read(upToCount: max(1, chunkSize)) ?? Data()
                if chunk.isEmpty { break }
                try output.write(contentsOf: chunk)
                hasher.update(data: chunk)
                count += UInt64(chunk.count)
            }
            try output.synchronize()
            try syncFile(output.fileDescriptor)
            try input.close(); try output.close()
        } catch {
            try? input.close(); try? output.close(); try? FileManager.default.removeItem(at: destination)
            throw error
        }
        let actual = hasher.finalize().portableHexString
        guard count == expected.byteCount else {
            throw PortableLibraryBackupError.sourceChanged(path: expected.relativePath)
        }
        guard actual == expected.checksum else {
            throw PortableLibraryBackupError.sourceChanged(path: expected.relativePath)
        }
        try faultInjector?.check(.stage)
    }

    private static func verify(_ expected: PortableLibraryBackupFile, at url: URL) throws {
        guard regularFileExists(at: url) else {
            if expected.rebuildable { return }
            throw PortableLibraryBackupError.missingCanonicalComponent(expected.relativePath)
        }
        let digest = try hashFile(at: url, chunkSize: 1 << 20, isCancelled: { false })
        guard digest.byteCount == expected.byteCount else {
            throw PortableLibraryBackupError.byteCountMismatch(
                path: expected.relativePath, expected: expected.byteCount, actual: digest.byteCount
            )
        }
        guard digest.checksum == expected.checksum else {
            throw PortableLibraryBackupError.checksumMismatch(
                path: expected.relativePath, expected: expected.checksum, actual: digest.checksum
            )
        }
    }

    private static func hashFile(
        at url: URL, chunkSize: Int, isCancelled: @Sendable () -> Bool
    ) throws -> (byteCount: UInt64, checksum: String) {
        let input = try FileHandle(forReadingFrom: url)
        var hasher = SHA256(); var count: UInt64 = 0
        do {
            while true {
                try checkCancellation(isCancelled)
                let data = try input.read(upToCount: max(1, chunkSize)) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data); count += UInt64(data.count)
            }
            try input.close()
        } catch { try? input.close(); throw error }
        return (count, hasher.finalize().portableHexString)
    }

    private static func cloneOrLink(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        if canClonefile(source: source, destination: destination), clonefile(source.path, destination.path, 0) == 0 {
            return
        }
        if link(source.path, destination.path) == 0 { return }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private static func removeStaleStagingFiles(at staging: URL, expected: Set<String>) throws {
        guard let enumerator = FileManager.default.enumerator(at: staging, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            let relative = relativePath(from: staging, to: url)
            if relative == stateName || relative.hasPrefix("Recovery/") { continue }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
               !expected.contains(relative) { urls.append(url) }
        }
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    private static func regularFileExists(at url: URL) -> Bool {
        var directory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && !directory.boolValue
    }

    private static func checkCancellation(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() || Task.isCancelled { throw CancellationError() }
    }

    private static func canClonefile(source: URL, destination: URL) -> Bool {
        #if os(macOS)
            guard let a = try? source.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
                  let b = try? destination.deletingLastPathComponent().resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else { return false }
            return String(describing: a) == String(describing: b)
        #else
            return false
        #endif
    }

    private static func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.path.hasSuffix("/") ? root.standardizedFileURL.path : root.standardizedFileURL.path + "/"
        return String(url.standardizedFileURL.path.dropFirst(rootPath.count))
    }

    private static func safePackageURL(_ relativePath: String, under root: URL) throws -> URL {
        do {
            return try PackagePath(relativePath).url(in: root)
        } catch {
            throw PortableLibraryBackupError.sourceIsNotPackage
        }
    }

    private static func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        _ = fsync(descriptor)
    }

    private static func syncFile(_ descriptor: Int32) throws {
        #if os(macOS)
            if fcntl(descriptor, F_FULLFSYNC) != 0 { throw CocoaError(.fileWriteUnknown) }
        #else
            if fsync(descriptor) != 0 { throw CocoaError(.fileWriteUnknown) }
        #endif
    }

    private static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PackageJSONCoder.encode(value).write(to: url, options: .atomic)
    }
}

extension PortableLibraryPackage {
    @discardableResult
    func backup(
        to destinationURL: URL,
        options: PortableLibraryBackupOptions = .init(),
        flushPendingEdits: (() throws -> Void)? = nil,
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortableLibraryBackupProgress) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> PortableLibraryBackupResult {
        try PortableLibraryBackup.run(
            package: self, to: destinationURL, options: options,
            flushPendingEdits: flushPendingEdits, isCancelled: isCancelled, progress: progress,
            now: now
        )
    }

    @discardableResult
    func backup(
        to destinationURL: URL,
        options: PortableLibraryBackupOptions = .init(),
        flushPendingEdits: @escaping @Sendable () async throws -> Void,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        progress: @escaping @Sendable (PortableLibraryBackupProgress) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() }
    ) async throws -> PortableLibraryBackupResult {
        try await PortableLibraryBackup.run(
            package: self, to: destinationURL, options: options,
            flushPendingEdits: flushPendingEdits, isCancelled: isCancelled, progress: progress,
            now: now
        )
    }

    @discardableResult
    func backup(
        to destinationURL: URL,
        options: PortableLibraryBackupOptions = .init(),
        flushPendingEditsResult: @escaping @Sendable () async -> PersistenceFlushResult,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        progress: @escaping @Sendable (PortableLibraryBackupProgress) -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { Date() }
    ) async throws -> PortableLibraryBackupResult {
        try await PortableLibraryBackup.run(
            package: self, to: destinationURL, options: options,
            flushPendingEditsResult: flushPendingEditsResult,
            isCancelled: isCancelled, progress: progress, now: now
        )
    }
}

private extension SHA256.Digest {
    var portableHexString: String { map { String(format: "%02x", $0) }.joined() }
}
