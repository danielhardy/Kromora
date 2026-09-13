import Darwin
import Foundation

/// Controls a restore without changing the active package until all restore gates have passed.
struct PortableLibraryRestoreOptions: Equatable, Sendable {
    var chunkSize: Int
    var copyMode: PortablePackageFileCopyMode
    var cleanProfileURL: URL?
    var faultInjector: PortablePackageFaultInjector?

    init(
        chunkSize: Int = 1 << 20,
        copyMode: PortablePackageFileCopyMode = .automatic,
        cleanProfileURL: URL? = nil,
        faultInjector: PortablePackageFaultInjector? = nil
    ) {
        self.chunkSize = max(1, chunkSize)
        self.copyMode = copyMode
        self.cleanProfileURL = cleanProfileURL
        self.faultInjector = faultInjector
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.chunkSize == rhs.chunkSize
            && lhs.copyMode == rhs.copyMode
            && lhs.cleanProfileURL == rhs.cleanProfileURL
    }
}

struct PortableLibraryRestoreProgress: Equatable, Sendable {
    enum Phase: String, Sendable {
        case validatingBackup
        case staging
        case validatingCandidate
        case rebuildingIndex
        case publishing
        case finished
    }

    let phase: Phase
    let relativePath: String?
    let completedFiles: Int
    let totalFiles: Int
    let copiedBytes: UInt64
    let totalBytes: UInt64
}

struct PortableLibraryRestoreResult: Equatable, Sendable {
    let activePackageURL: URL
    let sourceLibraryID: UUID
    let assetCount: Int
    let editRevisionCount: Int
    let indexEntryCount: Int
}

enum PortableLibraryRestoreError: Error, Equatable, CustomStringConvertible {
    case invalidSource(String)
    case activePackageIsNotPackage(String)
    case backupValidationFailed(String)
    case candidateValidationFailed(String)
    case cleanProfileValidationFailed(String)
    case invalidProfile(String)
    case cannotPublish(String)

    var description: String {
        switch self {
        case .invalidSource(let message): return "Invalid restore source: \(message)"
        case .activePackageIsNotPackage(let message):
            return "The active library cannot be restored because it is invalid: \(message)"
        case .backupValidationFailed(let message):
            return "Restore source validation failed: \(message)"
        case .candidateValidationFailed(let message):
            return "Restore candidate validation failed: \(message)"
        case .cleanProfileValidationFailed(let message):
            return "Clean-profile restore validation failed: \(message)"
        case .invalidProfile(let message): return "Invalid clean restore profile: \(message)"
        case .cannotPublish(let message): return "Restore could not replace the active library: \(message)"
        }
    }
}

/// Restores a verified package copy into an active library directory.
///
/// The source is validated first. The source is then copied into a sibling staging directory and
/// validated there, including a fresh index rebuild from membership shards and every edit's native
/// plus XMP representation. Only after those checks succeed is the old active directory renamed
/// aside and the candidate renamed into its place. Cancellation and all ordinary validation errors
/// happen before that final publication boundary.
struct PortableLibraryRestore {
    private static let stagingSuffix = ".kromora-restore-staging"
    private static let previousSuffix = ".kromora-restore-previous"
    private static let indexName = "LibraryIndex.json"

    @discardableResult
    static func run(
        from backupURL: URL,
        replacing activePackageURL: URL,
        options: PortableLibraryRestoreOptions = .init(),
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortableLibraryRestoreProgress) -> Void = { _ in }
    ) throws -> PortableLibraryRestoreResult {
        let backup = backupURL.standardizedFileURL
        let active = activePackageURL.standardizedFileURL
        try validatePaths(backup: backup, active: active)
        try checkCancellation(isCancelled)

        progress(.init(
            phase: .validatingBackup, relativePath: nil, completedFiles: 0,
            totalFiles: 0, copiedBytes: 0, totalBytes: 0
        ))
        do {
            try PortableLibraryBackup.validateVerifiedBackup(at: backup)
        } catch {
            throw PortableLibraryRestoreError.backupValidationFailed(String(describing: error))
        }

        let sourcePackage: PortableLibraryPackage
        do {
            sourcePackage = try PortableLibraryPackage.open(at: backup)
            try PortableLibraryBackup.validateCanonicalReferences(in: sourcePackage)
        } catch {
            throw PortableLibraryRestoreError.backupValidationFailed(String(describing: error))
        }

        var isActiveDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: active.path, isDirectory: &isActiveDirectory),
              isActiveDirectory.boolValue else {
            throw PortableLibraryRestoreError.activePackageIsNotPackage("the package directory is missing")
        }

        let activeLease: PortablePackageLease
        do {
            activeLease = try PortablePackageLease.acquire(at: active)
            _ = try PortablePackageTransaction.recover(at: active)
            _ = try PortableLibraryPackage.open(at: active)
        } catch {
            throw PortableLibraryRestoreError.activePackageIsNotPackage(String(describing: error))
        }
        defer { try? activeLease.release() }

        let staging = stagingURL(for: active)
        let previous = previousURL(for: active)
        try? FileManager.default.removeItem(at: staging)
        try? FileManager.default.removeItem(at: previous)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        var published = false
        defer {
            if !published { try? FileManager.default.removeItem(at: staging) }
        }

        do {
            let files = try sourceFiles(at: backup)
            let totalBytes = files.reduce(UInt64(0)) { $0 + $1.byteCount }
            var copiedBytes: UInt64 = 0
            for (index, file) in files.enumerated() {
                try checkCancellation(isCancelled)
                let destination = staging.appendingPathComponent(file.relativePath)
                try copy(
                    from: backup.appendingPathComponent(file.relativePath), to: destination,
                    chunkSize: options.chunkSize, copyMode: options.copyMode,
                    isCancelled: isCancelled, faultInjector: options.faultInjector
                )
                copiedBytes += file.byteCount
                progress(.init(
                    phase: .staging, relativePath: file.relativePath,
                    completedFiles: index + 1, totalFiles: files.count,
                    copiedBytes: copiedBytes, totalBytes: totalBytes
                ))
                // A large restore may outlive the default writer lease. Renew after each file so
                // another writer cannot acquire the active package while the candidate is staged.
                try activeLease.renew()
            }

            progress(.init(
                phase: .validatingCandidate, relativePath: nil,
                completedFiles: files.count, totalFiles: files.count,
                copiedBytes: copiedBytes, totalBytes: totalBytes
            ))
            try checkCancellation(isCancelled)
            do {
                try PortableLibraryBackup.validateVerifiedBackup(at: staging)
                let candidate = try PortableLibraryPackage.open(at: staging)
                try PortableLibraryBackup.validateCanonicalReferences(in: candidate)

                progress(.init(
                    phase: .rebuildingIndex, relativePath: nil,
                    completedFiles: files.count, totalFiles: files.count,
                    copiedBytes: copiedBytes, totalBytes: totalBytes
                ))
                let profile = try cleanProfileURL(
                    options.cleanProfileURL, active: active, backup: backup, staging: staging
                )
                let profileWasSupplied = options.cleanProfileURL != nil
                defer {
                    if !profileWasSupplied { try? FileManager.default.removeItem(at: profile) }
                }
                let indexURL = profile.appendingPathComponent(indexName)
                try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
                // This is the same shard-only rebuild path used after a missing or corrupt local
                // index. The profile starts empty and contains no prior application cache.
                let projection = try LibraryIndexProjection(package: candidate)
                try projection.write(to: indexURL)

                let editResult = try validateEdits(in: candidate)
                let assetCount = projection.entries.count
                guard assetCount == editResult.assetCount else {
                    throw PortableLibraryRestoreError.cleanProfileValidationFailed(
                        "rebuilt index contains \(assetCount) assets, expected \(editResult.assetCount)"
                    )
                }
                try checkCancellation(isCancelled)
                try activeLease.assertOwnership()
                try activeLease.renew()
                try options.faultInjector?.check(.publish)

                let candidateLease: PortablePackageLease
                do {
                    candidateLease = try PortablePackageLease.acquire(at: staging)
                } catch {
                    throw PortableLibraryRestoreError.cannotPublish(String(describing: error))
                }

                progress(.init(
                    phase: .publishing, relativePath: nil,
                    completedFiles: files.count, totalFiles: files.count,
                    copiedBytes: copiedBytes, totalBytes: totalBytes
                ))
                do {
                    try publish(staging: staging, active: active, previous: previous)
                } catch {
                    try? candidateLease.release()
                    throw error
                }
                published = true
                // The candidate's lock file moved with the directory rename above; release it at
                // its new location (see `release(movedTo:)`) rather than the now-nonexistent
                // staging path, or the newly active package is left permanently leased.
                try? candidateLease.release(movedTo: active)
                try? FileManager.default.removeItem(at: previous)
                progress(.init(
                    phase: .finished, relativePath: nil,
                    completedFiles: files.count, totalFiles: files.count,
                    copiedBytes: copiedBytes, totalBytes: totalBytes
                ))
                return PortableLibraryRestoreResult(
                    activePackageURL: active,
                    sourceLibraryID: candidate.manifest.libraryID,
                    assetCount: assetCount,
                    editRevisionCount: editResult.editRevisionCount,
                    indexEntryCount: projection.entries.count
                )
            } catch let error as PortableLibraryRestoreError {
                throw error
            } catch {
                throw PortableLibraryRestoreError.candidateValidationFailed(String(describing: error))
            }
        } catch let error as PortableLibraryRestoreError {
            throw error
        } catch {
            throw error
        }
    }

    @discardableResult
    static func run(
        from backupURL: URL,
        replacing activePackageURL: URL,
        options: PortableLibraryRestoreOptions = .init(),
        progress: @escaping @Sendable (PortableLibraryRestoreProgress) -> Void = { _ in }
    ) async throws -> PortableLibraryRestoreResult {
        try Task.checkCancellation()
        return try run(
            from: backupURL, replacing: activePackageURL, options: options,
            isCancelled: { Task.isCancelled }, progress: progress
        )
    }

    static func stagingURL(for activePackageURL: URL) -> URL {
        activePackageURL.deletingLastPathComponent()
            .appendingPathComponent(".\(activePackageURL.lastPathComponent)\(stagingSuffix)")
    }

    private struct SourceFile {
        let relativePath: String
        let byteCount: UInt64
    }

    private struct EditValidationResult {
        let assetCount: Int
        let editRevisionCount: Int
    }

    private static func validatePaths(backup: URL, active: URL) throws {
        guard backup != active else {
            throw PortableLibraryRestoreError.invalidSource("backup and active package are the same directory")
        }
        guard !active.path.hasPrefix(backup.path + "/") else {
            throw PortableLibraryRestoreError.invalidSource("active package is inside the backup")
        }
        guard !backup.path.hasPrefix(active.path + "/") else {
            throw PortableLibraryRestoreError.invalidSource("backup is inside the active package")
        }
    }

    private static func sourceFiles(at root: URL) throws -> [SourceFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        ) else {
            throw PortableLibraryRestoreError.invalidSource("backup cannot be enumerated")
        }
        var files: [SourceFile] = []
        for case let url as URL in enumerator {
            let relative = relativePath(from: root, to: url)
            if relative == "manifest.lock" { continue }
            let values = try url.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isSymbolicLink != true else {
                throw PortableLibraryRestoreError.invalidSource("backup contains a symbolic link at \(relative)")
            }
            guard values.isRegularFile == true else { continue }
            files.append(.init(relativePath: relative, byteCount: UInt64(values.fileSize ?? 0)))
        }
        return files.sorted { $0.relativePath < $1.relativePath }
    }

    private static func copy(
        from source: URL,
        to destination: URL,
        chunkSize: Int,
        copyMode: PortablePackageFileCopyMode,
        isCancelled: @Sendable () -> Bool,
        faultInjector: PortablePackageFaultInjector?
    ) throws {
        try faultInjector?.check(.diskFull)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)

        #if os(macOS)
        if copyMode == .automatic,
           clonefile(source.path, destination.path, 0) == 0 {
            try faultInjector?.check(.stage)
            return
        }
        #endif

        let input = try FileHandle(forReadingFrom: source)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        do {
            while true {
                try checkCancellation(isCancelled)
                let data = try input.read(upToCount: max(1, chunkSize)) ?? Data()
                if data.isEmpty { break }
                try output.write(contentsOf: data)
            }
            try output.synchronize()
            try input.close()
            try output.close()
            try faultInjector?.check(.stage)
        } catch {
            try? input.close()
            try? output.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func validateEdits(in package: PortableLibraryPackage) throws -> EditValidationResult {
        var assets = 0
        var revisions = 0
        for shardName in PortableLibraryPackage.allShards {
            let shard = try package.readMembershipShard(shardName)
            for entry in shard.entries where !entry.isTombstone {
                assets += 1
                let record = try package.readAssetRecord(for: entry.assetID)
                guard record.currentRevision == record.editHistory.currentRevision else {
                    throw PortablePackageError.invalidEditRevision(
                        "current revision pointers disagree for \(entry.assetID.raw)"
                    )
                }
                for pointer in record.editHistory.edits {
                    let sidecar = try package.readEditSidecar(
                        for: entry.assetID, revision: pointer.revision
                    )
                    guard sidecar.native.revision == pointer.revision,
                          sidecar.native.document == sidecar.xmp.document else {
                        throw PortablePackageError.invalidEditRevision(pointer.relativePath)
                    }
                    revisions += 1
                }
            }
        }
        return .init(assetCount: assets, editRevisionCount: revisions)
    }

    private static func cleanProfileURL(
        _ supplied: URL?, active: URL, backup: URL, staging: URL
    ) throws -> URL {
        let profile = (supplied ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("KromoraRestore-\(UUID().uuidString)", isDirectory: true))
            .standardizedFileURL
        let paths = [active, backup, staging].map(\.path)
        guard !paths.contains(where: { profile.path == $0 || profile.path.hasPrefix($0 + "/") }) else {
            throw PortableLibraryRestoreError.invalidProfile("profile must not be inside a package")
        }
        return profile
    }

    private static func publish(staging: URL, active: URL, previous: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: previous)
        guard rename(active.path, previous.path) == 0 else {
            throw PortableLibraryRestoreError.cannotPublish("could not stage the active package")
        }
        guard rename(staging.path, active.path) == 0 else {
            _ = rename(previous.path, active.path)
            throw PortableLibraryRestoreError.cannotPublish("could not publish the validated candidate")
        }
        let parent = active.deletingLastPathComponent()
        let descriptor = open(parent.path, O_RDONLY)
        if descriptor >= 0 {
            _ = fsync(descriptor)
            close(descriptor)
        }
    }

    private static func previousURL(for active: URL) -> URL {
        active.deletingLastPathComponent()
            .appendingPathComponent(".\(active.lastPathComponent)\(previousSuffix)")
    }

    private static func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return String(url.standardizedFileURL.path.dropFirst(rootPath.count))
    }

    private static func checkCancellation(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() || Task.isCancelled { throw CancellationError() }
    }
}

extension PortableLibraryPackage {
    @discardableResult
    func restore(
        from backupURL: URL,
        options: PortableLibraryRestoreOptions = .init(),
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortableLibraryRestoreProgress) -> Void = { _ in }
    ) throws -> PortableLibraryRestoreResult {
        try PortableLibraryRestore.run(
            from: backupURL, replacing: rootURL, options: options,
            isCancelled: isCancelled, progress: progress
        )
    }

    @discardableResult
    func restore(
        from backupURL: URL,
        options: PortableLibraryRestoreOptions = .init(),
        progress: @escaping @Sendable (PortableLibraryRestoreProgress) -> Void = { _ in }
    ) async throws -> PortableLibraryRestoreResult {
        try await PortableLibraryRestore.run(
            from: backupURL, replacing: rootURL, options: options, progress: progress
        )
    }
}
