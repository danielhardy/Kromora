import CryptoKit
import Foundation
import ImageIO

/// The storage boundary that produced a validation finding.
enum PortableLibraryValidationComponent: String, Codable, CaseIterable, Sendable {
    case manifest
    case membershipShard
    case assetRecord
    case original
    case editRevision
    case editSidecar
    case embeddedLook
    case derived
    case thumbnail
    case preview
    case localIndex
    case mask
    case analysis
}

enum PortableLibraryValidationIssueKind: String, Codable, Sendable {
    case missing
    case unreadable
    case corrupt
    case checksumMismatch
    case stale
    case orphaned
}

/// One non-fatal finding from a package scrub. Findings are accumulated so a maintenance or UI
/// caller can show all data-loss risks and all cache gaps in one pass.
struct PortableLibraryValidationIssue: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let component: PortableLibraryValidationComponent
    let kind: PortableLibraryValidationIssueKind
    /// Package components use package-relative paths. External projection/cache components use
    /// their absolute URL path because they do not belong to the package namespace.
    let path: String
    let message: String
    let expectedChecksum: String?
    let actualChecksum: String?

    init(
        component: PortableLibraryValidationComponent,
        kind: PortableLibraryValidationIssueKind,
        path: String,
        message: String,
        expectedChecksum: String? = nil,
        actualChecksum: String? = nil
    ) {
        self.component = component
        self.kind = kind
        self.path = path
        self.message = message
        self.expectedChecksum = expectedChecksum
        self.actualChecksum = actualChecksum
        id = [component.rawValue, kind.rawValue, path, message].joined(separator: "|")
    }
}

/// A checksum observed while scrubbing a regular file. The validator does not persist a checksum
/// index or rewrite the package; these values make the verification performed by the pass explicit
/// to backup, restore, diagnostics, and tests.
struct PortableLibraryValidationCheckedFile: Codable, Equatable, Sendable {
    let component: PortableLibraryValidationComponent
    let path: String
    let byteCount: UInt64
    let checksum: String
}

struct PortableLibraryValidationProgress: Equatable, Sendable {
    enum Phase: String, Sendable {
        case manifest
        case canonical
        case rebuildable
        case finished
    }

    let phase: Phase
    let path: String?
    let completed: Int
    let total: Int
}

/// The result of a read-only package validation/scrub.
struct PortableLibraryValidationReport: Codable, Equatable, Sendable {
    let packageURL: URL
    let libraryID: UUID?
    let checkedFiles: [PortableLibraryValidationCheckedFile]
    let criticalFailures: [PortableLibraryValidationIssue]
    let rebuildableGaps: [PortableLibraryValidationIssue]

    var isValid: Bool { criticalFailures.isEmpty }
    /// Short aliases make the two intentional buckets easy to consume at call sites.
    var critical: [PortableLibraryValidationIssue] { criticalFailures }
    var rebuildable: [PortableLibraryValidationIssue] { rebuildableGaps }
}

/// Locations and policy for the rebuildable half of a scrub.
///
/// The package owns `Derived/`; the local index and device-local masks/analysis caches live outside
/// it, so their locations are explicit inputs. Leaving an external location nil means that this
/// pass does not invent a cache location or create one as a side effect.
struct PortableLibraryValidationOptions: Equatable, Sendable {
    var chunkSize: Int
    var localIndexURL: URL?
    var masksDirectoryURL: URL?
    var analysisDirectoryURL: URL?
    var expectedRebuildablePaths: [String]
    var inspectRebuildable: Bool

    init(
        chunkSize: Int = 1 << 20,
        localIndexURL: URL? = nil,
        masksDirectoryURL: URL? = nil,
        analysisDirectoryURL: URL? = nil,
        expectedRebuildablePaths: [String] = [],
        inspectRebuildable: Bool = true
    ) {
        self.chunkSize = max(1, chunkSize)
        self.localIndexURL = localIndexURL
        self.masksDirectoryURL = masksDirectoryURL
        self.analysisDirectoryURL = analysisDirectoryURL
        self.expectedRebuildablePaths = expectedRebuildablePaths
        self.inspectRebuildable = inspectRebuildable
    }

    /// Useful to backup and restore, whose integrity gate is intentionally canonical-only.
    static let criticalOnly = Self(inspectRebuildable: false)
}

/// Explicit, non-mutating validation of a portable library package.
///
/// A malformed canonical component never aborts the rest of the scrub. It becomes a critical
/// finding and validation continues with the remaining shards and records. Rebuildable artifacts
/// are reported separately and can never make `isValid` false.
struct PortableLibraryValidation {
    private struct MutableReport {
        var libraryID: UUID?
        var checkedFiles: [PortableLibraryValidationCheckedFile] = []
        var critical: [PortableLibraryValidationIssue] = []
        var rebuildable: [PortableLibraryValidationIssue] = []
    }

    private struct DecodedManifest {
        let manifest: PortablePackageManifest
        let data: Data
    }

    private struct DecodedShard {
        let shard: PortablePackageMembershipShard
        let data: Data
    }

    /// Scrub a package at a URL. Errors from individual files are represented in the report;
    /// `CancellationError` is the only operational error intentionally propagated.
    @discardableResult
    static func run(
        at packageURL: URL,
        options: PortableLibraryValidationOptions = .init(),
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortableLibraryValidationProgress) -> Void = { _ in }
    ) throws -> PortableLibraryValidationReport {
        let root = packageURL.standardizedFileURL
        var result = MutableReport()
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            result.critical.append(issue(
                .manifest, .missing, "manifest.json", "package root is missing"
            ))
            return report(root: root, result: result)
        }

        let manifestURL = root.appendingPathComponent("manifest.json")
        progress(.init(phase: .manifest, path: "manifest.json", completed: 0, total: 1))
        var package: PortableLibraryPackage?
        if let decoded = tryDecodeManifest(at: manifestURL) {
            result.libraryID = decoded.manifest.libraryID
            recordChecksum(
                component: .manifest, path: "manifest.json", data: decoded.data, into: &result
            )
            do {
                package = try PortableLibraryPackage.openForQuery(at: root)
            } catch {
                result.critical.append(issue(
                    .manifest, .corrupt, "manifest.json", String(describing: error)
                ))
            }
        } else {
            result.critical.append(issue(
                .manifest, .corrupt, "manifest.json", "manifest is missing, unreadable, or malformed"
            ))
        }
        try checkCancellation(isCancelled)

        let canonicalTotal = PortableLibraryPackage.allShards.count
        progress(.init(phase: .canonical, path: nil, completed: 0, total: canonicalTotal))
        var liveAssetIDs = Set<PortablePhotoAssetID>()
        var visitedRecordPaths = Set<String>()
        for (offset, shardName) in PortableLibraryPackage.allShards.enumerated() {
            try checkCancellation(isCancelled)
            let shardPath = "Catalog/Membership/\(shardName).json"
            guard let decoded = tryDecodeShard(at: root.appendingPathComponent(shardPath), expected: shardName) else {
                result.critical.append(issue(
                    .membershipShard, .missing, shardPath, "membership shard is missing, unreadable, or malformed"
                ))
                progress(.init(phase: .canonical, path: shardPath, completed: offset + 1, total: canonicalTotal))
                continue
            }
            recordChecksum(component: .membershipShard, path: shardPath, data: decoded.data, into: &result)
            let shard = decoded.shard
            var ids = Set<PortablePhotoAssetID>()
            if shard.shard != shardName {
                result.critical.append(issue(
                    .membershipShard, .corrupt, shardPath, "shard header does not match its path"
                ))
            }
            for entry in shard.entries {
                try checkCancellation(isCancelled)
                let recordPath = entry.recordPath
                guard ids.insert(entry.assetID).inserted else {
                    result.critical.append(issue(
                        .membershipShard, .corrupt, shardPath, "duplicate asset \(entry.assetID.raw)"
                    ))
                    continue
                }
                guard liveAssetIDs.insert(entry.assetID).inserted else {
                    result.critical.append(issue(
                        .membershipShard, .corrupt, shardPath, "asset appears in more than one membership shard"
                    ))
                    continue
                }
                guard recordPath == "Assets/\(shardName)/\(entry.assetID.raw)/asset.json" else {
                    result.critical.append(issue(
                        .membershipShard, .corrupt, shardPath, "record path does not match asset \(entry.assetID.raw)"
                    ))
                    continue
                }
                visitedRecordPaths.insert(recordPath)
                guard !entry.isTombstone else { continue }
                try validateAsset(
                    entry: entry, package: package, root: root, result: &result,
                    options: options, isCancelled: isCancelled
                )
            }
            progress(.init(phase: .canonical, path: shardPath, completed: offset + 1, total: canonicalTotal))
        }

        // Scan records not reachable from membership as well. An orphaned canonical record is a
        // data-integrity finding, not a rebuildable cache miss, and this also catches a record
        // placed in the wrong shard directory.
        try scanOrphanedRecords(
            under: root, referenced: visitedRecordPaths, result: &result,
            options: options, isCancelled: isCancelled
        )
        try scanLooks(
            under: root, result: &result, options: options, isCancelled: isCancelled
        )

        if options.inspectRebuildable {
            let expected = Set(options.expectedRebuildablePaths)
            try scanDerived(
                under: root, expected: expected, result: &result,
                options: options, isCancelled: isCancelled
            )
            try scanIndex(
                options.localIndexURL, package: package, root: root, result: &result,
                isCancelled: isCancelled
            )
            try scanCache(
                options.masksDirectoryURL, component: .mask, result: &result,
                isCancelled: isCancelled
            )
            try scanCache(
                options.analysisDirectoryURL, component: .analysis, result: &result,
                isCancelled: isCancelled
            )
        }
        progress(.init(phase: .finished, path: nil, completed: 1, total: 1))
        return report(root: root, result: result)
    }

    /// Validate an already-open package while still rereading the manifest and canonical files
    /// from disk. This is the reusable seam used by backup/restore callers.
    static func run(
        package: PortableLibraryPackage,
        options: PortableLibraryValidationOptions = .init(),
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortableLibraryValidationProgress) -> Void = { _ in }
    ) throws -> PortableLibraryValidationReport {
        try run(at: package.rootURL, options: options, isCancelled: isCancelled, progress: progress)
    }

    static func validate(
        at packageURL: URL,
        options: PortableLibraryValidationOptions = .init()
    ) throws -> PortableLibraryValidationReport {
        try run(at: packageURL, options: options)
    }

    private static func validateAsset(
        entry: PortablePackageMembershipEntry,
        package: PortableLibraryPackage?,
        root: URL,
        result: inout MutableReport,
        options: PortableLibraryValidationOptions,
        isCancelled: @Sendable () -> Bool
    ) throws {
        let recordURL = root.appendingPathComponent(entry.recordPath)
        guard let data = try? Data(contentsOf: recordURL) else {
            result.critical.append(issue(.assetRecord, .missing, entry.recordPath, "asset record is unreadable or missing"))
            return
        }
        recordChecksum(component: .assetRecord, path: entry.recordPath, data: data, into: &result)
        let record: PortablePackageAssetRecord
        do {
            if let package {
                record = try package.readAssetRecord(for: entry.assetID)
            } else {
                record = try decodePackageJSON(PortablePackageAssetRecord.self, from: data)
                guard record.identity.assetID == entry.assetID else {
                    throw PortablePackageError.recordPathMismatch(entry.recordPath)
                }
            }
        } catch {
            result.critical.append(issue(.assetRecord, .corrupt, entry.recordPath, String(describing: error)))
            return
        }

        let source = record.source
        if source.storage == .embedded, let relativePath = source.relativePath {
            try validateOriginal(
                at: root.appendingPathComponent(relativePath), relativePath: relativePath,
                expectedHash: record.identity.sourceFingerprint.contentHash,
                result: &result, options: options, isCancelled: isCancelled
            )
        }

        guard record.currentRevision == record.editHistory.currentRevision else {
            result.critical.append(issue(
                .assetRecord, .corrupt, entry.recordPath, "current revision pointers disagree"
            ))
            return
        }
        for pointer in record.editHistory.edits {
            try validateEdit(
                pointer: pointer, assetID: entry.assetID, package: package, root: root,
                result: &result, options: options, isCancelled: isCancelled
            )
        }
    }

    private static func validateOriginal(
        at url: URL,
        relativePath: String,
        expectedHash: String,
        result: inout MutableReport,
        options: PortableLibraryValidationOptions,
        isCancelled: @Sendable () -> Bool
    ) throws {
        guard regularFileExists(at: url) else {
            result.critical.append(issue(.original, .missing, relativePath, "embedded original is missing"))
            return
        }
        do {
            let digest = try hashFile(at: url, chunkSize: options.chunkSize, isCancelled: isCancelled)
            result.checkedFiles.append(.init(
                component: .original, path: relativePath,
                byteCount: digest.byteCount, checksum: digest.checksum
            ))
            if digest.checksum != expectedHash {
                result.critical.append(issue(
                    .original, .checksumMismatch, relativePath, "embedded original checksum does not match asset identity",
                    expectedChecksum: expectedHash, actualChecksum: digest.checksum
                ))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            result.critical.append(issue(.original, .unreadable, relativePath, String(describing: error)))
        }
    }

    private static func validateEdit(
        pointer: PortablePackageEditPointer,
        assetID: PortablePhotoAssetID,
        package: PortableLibraryPackage?,
        root: URL,
        result: inout MutableReport,
        options: PortableLibraryValidationOptions,
        isCancelled: @Sendable () -> Bool
    ) throws {
        let nativeURL = root.appendingPathComponent(pointer.relativePath)
        guard let nativeData = try? Data(contentsOf: nativeURL) else {
            result.critical.append(issue(.editRevision, .missing, pointer.relativePath, "native edit revision is missing"))
            return
        }
        recordChecksum(component: .editRevision, path: pointer.relativePath, data: nativeData, into: &result)
        do {
            if let package {
                _ = try package.readEditRevision(for: assetID, revision: pointer.revision)
            } else {
                let revision = try decodePackageJSON(PortablePackageEditRevision.self, from: nativeData)
                guard revision.assetID == assetID, revision.revision == pointer.revision else {
                    throw PortablePackageError.invalidEditRevision(pointer.relativePath)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            result.critical.append(issue(.editRevision, .corrupt, pointer.relativePath, String(describing: error)))
            return
        }

        guard let xmpPath = pointer.xmpRelativePath else {
            result.critical.append(issue(.editSidecar, .missing, pointer.relativePath, "edit revision has no XMP sidecar pointer"))
            return
        }
        let xmpURL = root.appendingPathComponent(xmpPath)
        guard let xmpData = try? Data(contentsOf: xmpURL) else {
            result.critical.append(issue(.editSidecar, .missing, xmpPath, "edit XMP sidecar is missing"))
            return
        }
        recordChecksum(component: .editSidecar, path: xmpPath, data: xmpData, into: &result)
        do {
            if let package {
                _ = try package.readEditSidecar(for: assetID, revision: pointer.revision)
            } else {
                let xmp = try PortablePackageXMPCodec.decode(xmpData)
                guard xmp.assetID == assetID, xmp.revision == pointer.revision else {
                    throw PortablePackageError.malformedXMP("XMP identity does not match pointer")
                }
            }
        } catch {
            result.critical.append(issue(.editSidecar, .corrupt, xmpPath, String(describing: error)))
            return
        }

        // Native revisions are the place where embedded Look references are carried. Re-read the
        // value so a malformed XMP does not hide a separate Look checksum finding.
        if let package, let revision = try? package.readEditRevision(for: assetID, revision: pointer.revision) {
            for reference in revision.lookReferences {
                try validateLook(reference, root: root, result: &result, options: options, isCancelled: isCancelled)
            }
        }
    }

    private static func validateLook(
        _ reference: PortablePackageLookReference,
        root: URL,
        result: inout MutableReport,
        options: PortableLibraryValidationOptions,
        isCancelled: @Sendable () -> Bool
    ) throws {
        let url = root.appendingPathComponent(reference.relativePath)
        guard regularFileExists(at: url) else {
            result.critical.append(issue(.embeddedLook, .missing, reference.relativePath, "embedded Look blob is missing"))
            return
        }
        do {
            let digest = try hashFile(at: url, chunkSize: options.chunkSize, isCancelled: isCancelled)
            result.checkedFiles.append(.init(
                component: .embeddedLook, path: reference.relativePath,
                byteCount: digest.byteCount, checksum: digest.checksum
            ))
            if digest.byteCount != reference.byteCount || digest.checksum != reference.contentHash {
                result.critical.append(issue(
                    .embeddedLook, .checksumMismatch, reference.relativePath, "embedded Look checksum or byte count does not match reference",
                    expectedChecksum: reference.contentHash, actualChecksum: digest.checksum
                ))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            result.critical.append(issue(.embeddedLook, .unreadable, reference.relativePath, String(describing: error)))
        }
    }

    private static func scanOrphanedRecords(
        under root: URL,
        referenced: Set<String>,
        result: inout MutableReport,
        options: PortableLibraryValidationOptions,
        isCancelled: @Sendable () -> Bool
    ) throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root.appendingPathComponent("Assets"),
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let url as URL in enumerator {
            try checkCancellation(isCancelled)
            let relative = relativePath(from: root, to: url)
            guard relative.hasSuffix("/asset.json") else { continue }
            guard regularFileExists(at: url) else {
                result.critical.append(issue(.assetRecord, .unreadable, relative, "asset record is not a regular file"))
                continue
            }
            guard !referenced.contains(relative) else { continue }
            guard let data = try? Data(contentsOf: url) else {
                result.critical.append(issue(.assetRecord, .unreadable, relative, "orphaned asset record is unreadable"))
                continue
            }
            recordChecksum(component: .assetRecord, path: relative, data: data, into: &result)
            do {
                _ = try decodePackageJSON(PortablePackageAssetRecord.self, from: data)
                result.critical.append(issue(.assetRecord, .orphaned, relative, "asset record is not reachable from membership"))
            } catch {
                result.critical.append(issue(.assetRecord, .corrupt, relative, String(describing: error)))
            }
        }
    }

    private static func scanLooks(
        under root: URL,
        result: inout MutableReport,
        options: PortableLibraryValidationOptions,
        isCancelled: @Sendable () -> Bool
    ) throws {
        let looksURL = root.appendingPathComponent("Looks")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: looksURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else { return }
        let alreadyChecked = Set(result.checkedFiles.map(\.path))
        for file in files where file.pathExtension.lowercased() == "cube" {
            try checkCancellation(isCancelled)
            let path = relativePath(from: root, to: file)
            guard !alreadyChecked.contains(path) else { continue }
            guard regularFileExists(at: file), let data = try? Data(contentsOf: file), !data.isEmpty else {
                result.critical.append(issue(.embeddedLook, .missing, path, "embedded Look blob is missing or unreadable"))
                continue
            }
            let actual = SHA256.hash(data: data).portableHexString
            recordChecksum(component: .embeddedLook, path: path, data: data, into: &result)
            let expected = file.deletingPathExtension().lastPathComponent.lowercased()
            if expected.count != 64 || expected != actual {
                result.critical.append(issue(
                    .embeddedLook, .checksumMismatch, path, "content-addressed Look filename does not match its bytes",
                    expectedChecksum: expected, actualChecksum: actual
                ))
            }
        }
    }

    private static func scanDerived(
        under root: URL,
        expected: Set<String>,
        result: inout MutableReport,
        options: PortableLibraryValidationOptions,
        isCancelled: @Sendable () -> Bool
    ) throws {
        let derivedURL = root.appendingPathComponent("Derived")
        guard FileManager.default.fileExists(atPath: derivedURL.path) else {
            result.rebuildable.append(issue(.derived, .missing, "Derived", "derived cache directory is missing"))
            appendMissingExpected(expected, under: root, result: &result)
            return
        }
        guard let enumerator = FileManager.default.enumerator(
            at: derivedURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let url as URL in enumerator {
            try checkCancellation(isCancelled)
            let path = relativePath(from: root, to: url)
            guard regularFileExists(at: url) else {
                result.rebuildable.append(issue(.derived, .unreadable, path, "derived entry is not a regular file"))
                continue
            }
            let component: PortableLibraryValidationComponent = path.contains("/Thumbnails/") || path.hasSuffix(".pack") ? .thumbnail : .preview
            guard let data = try? Data(contentsOf: url), !data.isEmpty else {
                result.rebuildable.append(issue(component, .corrupt, path, "derived artifact is empty or unreadable"))
                continue
            }
            recordChecksum(component: component, path: path, data: data, into: &result)
            if component == .preview,
               (path.lowercased().hasSuffix(".jpg") || path.lowercased().hasSuffix(".jpeg")),
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               CGImageSourceCreateImageAtIndex(source, 0, nil) == nil {
                result.rebuildable.append(issue(.preview, .corrupt, path, "preview is not a decodable image"))
            }
        }
        appendMissingExpected(expected, under: root, result: &result)
    }

    private static func appendMissingExpected(
        _ expected: Set<String>, under root: URL, result: inout MutableReport
    ) {
        for path in expected.sorted() where !regularFileExists(at: root.appendingPathComponent(path)) {
            let component: PortableLibraryValidationComponent = path.contains("Thumbnail") || path.hasSuffix(".pack") ? .thumbnail : .preview
            result.rebuildable.append(issue(component, .missing, path, "expected rebuildable artifact is missing"))
        }
    }

    private static func scanIndex(
        _ indexURL: URL?,
        package: PortableLibraryPackage?,
        root: URL,
        result: inout MutableReport,
        isCancelled: @Sendable () -> Bool
    ) throws {
        guard let indexURL else { return }
        let path = indexURL.path
        guard regularFileExists(at: indexURL) else {
            result.rebuildable.append(issue(.localIndex, .missing, path, "local index is missing"))
            return
        }
        guard let data = try? Data(contentsOf: indexURL) else {
            result.rebuildable.append(issue(.localIndex, .unreadable, path, "local index is unreadable"))
            return
        }
        recordChecksum(component: .localIndex, path: path, data: data, into: &result)
        guard let package else {
            result.rebuildable.append(issue(.localIndex, .stale, path, "package manifest is unavailable for index validation"))
            return
        }
        do {
            try checkCancellation(isCancelled)
            let loaded = try LibraryIndexProjection.load(from: indexURL)
            let expected = try LibraryIndexProjection(package: package)
            guard loaded == expected else {
                result.rebuildable.append(issue(.localIndex, .stale, path, "local index does not match membership shards"))
                return
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            result.rebuildable.append(issue(.localIndex, .corrupt, path, String(describing: error)))
        }
        _ = root
    }

    private static func scanCache(
        _ directoryURL: URL?,
        component: PortableLibraryValidationComponent,
        result: inout MutableReport,
        isCancelled: @Sendable () -> Bool
    ) throws {
        guard let directoryURL else { return }
        let path = directoryURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            result.rebuildable.append(issue(component, .missing, path, "cache directory is missing"))
            return
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ) else {
            result.rebuildable.append(issue(component, .unreadable, path, "cache directory is unreadable"))
            return
        }
        var metadataPaths = Set<String>()
        for file in files where file.pathExtension.lowercased() == "json" {
            try checkCancellation(isCancelled)
            let filePath = file.path
            metadataPaths.insert(file.deletingPathExtension().path)
            guard let data = try? Data(contentsOf: file), !data.isEmpty else {
                result.rebuildable.append(issue(component, .corrupt, filePath, "cache entry is empty or unreadable"))
                continue
            }
            if component == .mask {
                validateMaskJSON(data, at: file, result: &result)
            } else {
                validateAnalysisJSON(data, at: file, result: &result)
            }
            recordChecksum(component: component, path: filePath, data: data, into: &result)
        }
        if component == .mask {
            for file in files where file.pathExtension.lowercased() == "bin" {
                if !metadataPaths.contains(file.deletingPathExtension().path) {
                    result.rebuildable.append(issue(component, .orphaned, file.path, "mask pixel sidecar has no metadata"))
                }
            }
        }
    }

    private static func validateMaskJSON(
        _ data: Data, at url: URL, result: inout MutableReport
    ) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mask = object["mask"] as? [String: Any],
              let size = mask["size"] as? [String: Any],
              let width = size["width"] as? Int, let height = size["height"] as? Int,
              width > 0, height > 0 else {
            result.rebuildable.append(issue(.mask, .corrupt, url.path, "mask metadata is malformed"))
            return
        }
        if mask["values"] == nil {
            let expected = width.multipliedReportingOverflow(by: height)
            let bytes = expected.overflow
                ? (partialValue: 0, overflow: true)
                : expected.partialValue.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
            let bin = url.deletingPathExtension().appendingPathExtension("bin")
            let attributes = try? FileManager.default.attributesOfItem(atPath: bin.path)
            let validSidecar = !expected.overflow && !bytes.overflow
                && (attributes?[.size] as? NSNumber)?.intValue == bytes.partialValue
            if !validSidecar {
                result.rebuildable.append(issue(.mask, .missing, bin.path, "mask pixel sidecar is missing or truncated"))
            }
        }
    }

    private static func validateAnalysisJSON(
        _ data: Data, at url: URL, result: inout MutableReport
    ) {
        struct PersistedAnalysis: Codable { let key: AnalysisCacheKey; let analysis: PhotoAnalysis }
        do {
            let persisted = try JSONDecoder().decode(PersistedAnalysis.self, from: data)
            guard persisted.analysis.version == persisted.key.analysisVersion else {
                result.rebuildable.append(issue(.analysis, .stale, url.path, "analysis version does not match its cache key"))
                return
            }
        } catch {
            result.rebuildable.append(issue(.analysis, .corrupt, url.path, "analysis cache entry is malformed"))
        }
    }

    private static func tryDecodeManifest(at url: URL) -> DecodedManifest? {
        guard let data = try? Data(contentsOf: url),
              let manifest = try? decodePackageJSON(PortablePackageManifest.self, from: data) else { return nil }
        return .init(manifest: manifest, data: data)
    }

    private static func tryDecodeShard(at url: URL, expected: String) -> DecodedShard? {
        guard let data = try? Data(contentsOf: url),
              let shard = try? decodePackageJSON(PortablePackageMembershipShard.self, from: data),
              shard.shard == expected else { return nil }
        return .init(shard: shard, data: data)
    }

    private static func decodePackageJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    private static func recordChecksum(
        component: PortableLibraryValidationComponent,
        path: String,
        data: Data,
        into result: inout MutableReport
    ) {
        result.checkedFiles.append(.init(
            component: component, path: path, byteCount: UInt64(data.count),
            checksum: SHA256.hash(data: data).portableHexString
        ))
    }

    private static func hashFile(
        at url: URL, chunkSize: Int, isCancelled: @Sendable () -> Bool
    ) throws -> (byteCount: UInt64, checksum: String) {
        let input = try FileHandle(forReadingFrom: url)
        var hasher = SHA256()
        var count: UInt64 = 0
        do {
            while true {
                try checkCancellation(isCancelled)
                let data = try input.read(upToCount: max(1, chunkSize)) ?? Data()
                if data.isEmpty { break }
                hasher.update(data: data)
                count += UInt64(data.count)
            }
            try input.close()
        } catch {
            try? input.close()
            throw error
        }
        return (count, hasher.finalize().portableHexString)
    }

    private static func checkCancellation(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() || Task.isCancelled { throw CancellationError() }
    }

    private static func issue(
        _ component: PortableLibraryValidationComponent,
        _ kind: PortableLibraryValidationIssueKind,
        _ path: String,
        _ message: String,
        expectedChecksum: String? = nil,
        actualChecksum: String? = nil
    ) -> PortableLibraryValidationIssue {
        .init(component: component, kind: kind, path: path, message: message,
              expectedChecksum: expectedChecksum, actualChecksum: actualChecksum)
    }

    private static func report(root: URL, result: MutableReport) -> PortableLibraryValidationReport {
        .init(
            packageURL: root, libraryID: result.libraryID,
            checkedFiles: result.checkedFiles,
            criticalFailures: result.critical,
            rebuildableGaps: result.rebuildable
        )
    }

    private static func regularFileExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }
        return (try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile) == true
            && (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
    }

    private static func relativePath(from root: URL, to url: URL) -> String {
        let rootPath = root.standardizedFileURL.path.hasSuffix("/")
            ? root.standardizedFileURL.path
            : root.standardizedFileURL.path + "/"
        return String(url.standardizedFileURL.path.dropFirst(rootPath.count))
    }
}

extension PortableLibraryPackage {
    @discardableResult
    func validate(
        options: PortableLibraryValidationOptions = .init(),
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortableLibraryValidationProgress) -> Void = { _ in }
    ) throws -> PortableLibraryValidationReport {
        try PortableLibraryValidation.run(
            package: self, options: options, isCancelled: isCancelled, progress: progress
        )
    }

    @discardableResult
    func scrub(
        options: PortableLibraryValidationOptions = .init(),
        isCancelled: @Sendable () -> Bool = { false },
        progress: @Sendable (PortableLibraryValidationProgress) -> Void = { _ in }
    ) throws -> PortableLibraryValidationReport {
        try validate(options: options, isCancelled: isCancelled, progress: progress)
    }
}

private extension SHA256.Digest {
    var portableHexString: String { map { String(format: "%02x", $0) }.joined() }
}
