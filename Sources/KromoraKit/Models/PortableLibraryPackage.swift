import Foundation

/// The package-level manifest for a portable Kromora library.
///
/// This is deliberately a value type. The package format is not the application's catalog and this
/// layer is not referenced by any view or view model. Later package phases can use these values as
/// their storage contract without making this format the canonical source of library state yet.
struct PortablePackageManifest: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1
    static let currentShardCount = 256
    static let currentShardPrefixLength = 2

    var formatVersion: Int
    var libraryID: UUID
    var createdAt: Date
    var createdBy: String
    var writerVersion: String
    var minimumReaderVersion: String
    var membershipShardCount: Int
    var membershipShardPrefixLength: Int
    var featureFlags: [String: Bool]
    var recoveryFormatVersion: Int

    /// Raw top-level members written by a newer producer. They are not interpreted, but they are
    /// retained verbatim when this manifest is rewritten.
    var unknownJSONFields: [String: Data] = [:]

    init(
        formatVersion: Int = Self.currentFormatVersion,
        libraryID: UUID = UUID(),
        createdAt: Date = Date(),
        createdBy: String = "Kromora",
        writerVersion: String = "1.0",
        minimumReaderVersion: String = "1.0",
        membershipShardCount: Int = Self.currentShardCount,
        membershipShardPrefixLength: Int = Self.currentShardPrefixLength,
        featureFlags: [String: Bool] = [:],
        recoveryFormatVersion: Int = 1
    ) {
        self.formatVersion = formatVersion
        self.libraryID = libraryID
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.writerVersion = writerVersion
        self.minimumReaderVersion = minimumReaderVersion
        self.membershipShardCount = membershipShardCount
        self.membershipShardPrefixLength = membershipShardPrefixLength
        self.featureFlags = featureFlags
        self.recoveryFormatVersion = recoveryFormatVersion
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case formatVersion, libraryID, createdAt, createdBy, writerVersion, minimumReaderVersion
        case membershipShardCount, membershipShardPrefixLength, featureFlags, recoveryFormatVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        libraryID = try c.decode(UUID.self, forKey: .libraryID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        createdBy = try c.decode(String.self, forKey: .createdBy)
        writerVersion = try c.decode(String.self, forKey: .writerVersion)
        minimumReaderVersion = try c.decode(String.self, forKey: .minimumReaderVersion)
        membershipShardCount = try c.decode(Int.self, forKey: .membershipShardCount)
        membershipShardPrefixLength = try c.decode(Int.self, forKey: .membershipShardPrefixLength)
        featureFlags = try c.decode([String: Bool].self, forKey: .featureFlags)
        recoveryFormatVersion = try c.decode(Int.self, forKey: .recoveryFormatVersion)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(libraryID, forKey: .libraryID)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(createdBy, forKey: .createdBy)
        try c.encode(writerVersion, forKey: .writerVersion)
        try c.encode(minimumReaderVersion, forKey: .minimumReaderVersion)
        try c.encode(membershipShardCount, forKey: .membershipShardCount)
        try c.encode(membershipShardPrefixLength, forKey: .membershipShardPrefixLength)
        try c.encode(featureFlags, forKey: .featureFlags)
        try c.encode(recoveryFormatVersion, forKey: .recoveryFormatVersion)
    }
}

/// The denormalised fields available without opening an asset record.
struct PortablePackageAssetSummary: Codable, Equatable, Hashable, Sendable {
    var captureDate: String?
    var rating: Int?
    var flag: String?
    var label: String?
    var cameraMake: String?
    var cameraModel: String?
    var lens: String?
    var dimensions: PhotoPixelDimensions?
    var aspectRatio: Double?
    var displayName: String
    var assetRevision: UInt64

    init(
        captureDate: String? = nil,
        rating: Int? = nil,
        flag: String? = nil,
        label: String? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lens: String? = nil,
        dimensions: PhotoPixelDimensions? = nil,
        aspectRatio: Double? = nil,
        displayName: String,
        assetRevision: UInt64 = 0
    ) {
        self.captureDate = captureDate
        self.rating = rating
        self.flag = flag
        self.label = label
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lens = lens
        self.dimensions = dimensions
        self.aspectRatio = aspectRatio
        self.displayName = displayName
        self.assetRevision = assetRevision
    }
}

/// One entry in a membership shard. Tombstones remain in the shard so deletion history can be
/// reconciled by the transaction layer that is implemented in the sibling package ticket.
struct PortablePackageMembershipEntry: Codable, Equatable, Sendable {
    let assetID: PortablePhotoAssetID
    let recordPath: String
    var addedRevision: UInt64
    var deletedRevision: UInt64?
    var isTombstone: Bool
    var summary: PortablePackageAssetSummary

    init(
        assetID: PortablePhotoAssetID,
        recordPath: String,
        addedRevision: UInt64 = 0,
        deletedRevision: UInt64? = nil,
        isTombstone: Bool = false,
        summary: PortablePackageAssetSummary
    ) {
        self.assetID = assetID
        self.recordPath = recordPath
        self.addedRevision = addedRevision
        self.deletedRevision = deletedRevision
        self.isTombstone = isTombstone
        self.summary = summary
    }
}

/// A membership shard is selected by the first two lowercase hexadecimal characters of the
/// opaque asset UUID. Empty shards are real files, not an implicit fallback, so a cold open always
/// has a bounded 256-file scan.
struct PortablePackageMembershipShard: Codable, Equatable, Sendable {
    let shard: String
    var entries: [PortablePackageMembershipEntry]
    var unknownJSONFields: [String: Data] = [:]

    init(shard: String, entries: [PortablePackageMembershipEntry] = []) throws {
        guard PortableLibraryPackage.isValidShard(shard) else {
            throw PortablePackageError.invalidShard(shard)
        }
        self.shard = shard
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey, CaseIterable { case shard, entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shard = try c.decode(String.self, forKey: .shard)
        guard PortableLibraryPackage.isValidShard(shard) else {
            throw PortablePackageError.invalidShard(shard)
        }
        entries = try c.decode([PortablePackageMembershipEntry].self, forKey: .entries)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shard, forKey: .shard)
        try c.encode(entries, forKey: .entries)
    }
}

/// A source locator is operational state, not identity. Embedded sources use a package-relative
/// path. Referenced sources reserve a security-scoped bookmark for the future referenced-asset
/// resolver; no product UI exposes that capability in this phase.
struct PortablePackageSourceReference: Codable, Equatable, Sendable {
    enum Storage: String, Codable, Sendable { case embedded, referenced }

    var storage: Storage
    var relativePath: String?
    var securityScopedBookmark: Data?

    static func embedded(relativePath: String) -> Self {
        Self(storage: .embedded, relativePath: relativePath, securityScopedBookmark: nil)
    }

    static func referenced(bookmark: Data? = nil) -> Self {
        Self(storage: .referenced, relativePath: nil, securityScopedBookmark: bookmark)
    }
}

struct PortablePackageEditPointer: Codable, Equatable, Sendable {
    let revision: UInt64
    let relativePath: String
    /// The interoperable metadata half of the revision. This is optional so a reader can still
    /// open records written by the format-only phase before XMP sidecars existed.
    var xmpRelativePath: String?

    init(revision: UInt64, relativePath: String, xmpRelativePath: String? = nil) {
        self.revision = revision
        self.relativePath = relativePath
        self.xmpRelativePath = xmpRelativePath
    }
}

/// Pointers only: edit JSON sidecars are written by the sibling edit-sidecar ticket.
struct PortablePackageEditHistoryPointers: Codable, Equatable, Sendable {
    var currentRevision: UInt64
    var edits: [PortablePackageEditPointer]

    init(currentRevision: UInt64 = 0, edits: [PortablePackageEditPointer] = []) {
        self.currentRevision = currentRevision
        self.edits = edits
    }
}

/// The full durable identity and locators for one asset. The original bytes and edit sidecars are
/// intentionally not embedded in this record; this record only points at them.
struct PortablePackageAssetRecord: Codable, Equatable, Sendable {
    let identity: PortablePhotoIdentity
    var source: PortablePackageSourceReference
    /// A quarantined record remains durable so the package can restore it before reclaim.
    var isRemoved: Bool
    var currentRevision: UInt64
    var editHistory: PortablePackageEditHistoryPointers
    var unknownJSONFields: [String: Data] = [:]

    init(
        identity: PortablePhotoIdentity,
        source: PortablePackageSourceReference,
        isRemoved: Bool = false,
        currentRevision: UInt64 = 0,
        editHistory: PortablePackageEditHistoryPointers = .init()
    ) {
        self.identity = identity
        self.source = source
        self.isRemoved = isRemoved
        self.currentRevision = currentRevision
        self.editHistory = editHistory
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case identity, source, isRemoved, currentRevision, editHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identity = try c.decode(PortablePhotoIdentity.self, forKey: .identity)
        source = try c.decode(PortablePackageSourceReference.self, forKey: .source)
        // Added with package-native trash; old package records are active by default.
        isRemoved = try c.decodeIfPresent(Bool.self, forKey: .isRemoved) ?? false
        currentRevision = try c.decode(UInt64.self, forKey: .currentRevision)
        editHistory = try c.decode(PortablePackageEditHistoryPointers.self, forKey: .editHistory)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(identity, forKey: .identity)
        try c.encode(source, forKey: .source)
        try c.encode(isRemoved, forKey: .isRemoved)
        try c.encode(currentRevision, forKey: .currentRevision)
        try c.encode(editHistory, forKey: .editHistory)
    }
}

enum PortablePackageError: Error, Equatable, CustomStringConvertible {
    case invalidPackageRoot
    case invalidManifest(String)
    case invalidShard(String)
    case missingShard(String)
    case invalidRelativePath(String)
    case assetShardMismatch(asset: String, shard: String)
    case duplicateAsset(String)
    case recordPathMismatch(String)
    case invalidEditRevision(String)
    case malformedXMP(String)
    case immutableRevisionExists(String)
    case invalidLookReference(String)
    case lookChecksumMismatch(expected: String, actual: String)
    case missingLook(String)

    var description: String {
        switch self {
        case .invalidPackageRoot: return "The package root is not a directory"
        case .invalidManifest(let message): return "Invalid package manifest: \(message)"
        case .invalidShard(let shard): return "Invalid membership shard '\(shard)'"
        case .missingShard(let shard): return "Missing membership shard '\(shard)'"
        case .invalidRelativePath(let path): return "Unsafe package-relative path '\(path)'"
        case .assetShardMismatch(let asset, let shard):
            return "Asset \(asset) does not belong to membership shard \(shard)"
        case .duplicateAsset(let asset): return "Membership shard contains duplicate asset \(asset)"
        case .recordPathMismatch(let path): return "Invalid asset record path '\(path)'"
        case .invalidEditRevision(let message): return "Invalid edit revision: \(message)"
        case .malformedXMP(let message): return "Malformed XMP edit sidecar: \(message)"
        case .immutableRevisionExists(let path):
            return "Immutable edit revision already exists at '\(path)'"
        case .invalidLookReference(let message): return "Invalid embedded Look reference: \(message)"
        case .lookChecksumMismatch(let expected, let actual):
            return "Embedded Look checksum mismatch: expected \(expected), got \(actual)"
        case .missingLook(let hash): return "Embedded Look blob is missing: \(hash)"
        }
    }
}

/// Read/write access to the format-only portion of a portable library package.
///
/// This type owns no transaction journal, lease, import pipeline, or UI integration. Writes use
/// Foundation's atomic single-file write as a convenience, but commit ordering and crash recovery
/// belong to the sibling transaction ticket.
struct PortableLibraryPackage {
    let rootURL: URL
    private(set) var manifest: PortablePackageManifest

    static func create(
        at rootURL: URL,
        manifest: PortablePackageManifest = .init()
    ) throws -> Self {
        let fm = FileManager.default
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fm.createDirectory(
            at: try PackagePath("Catalog/Membership").url(in: rootURL),
            withIntermediateDirectories: true
        )
        try fm.createDirectory(
            at: try PackagePath("Assets").url(in: rootURL),
            withIntermediateDirectories: true
        )
        var package = try Self(validatingRoot: rootURL, manifest: manifest)
        try package.validateManifest(manifest)
        package.manifest = manifest
        try package.writeManifest()
        for shard in Self.allShards {
            let shardURL = package.membershipURL(for: shard)
            if !fm.fileExists(atPath: shardURL.path) {
                let empty = try PortablePackageMembershipShard(shard: shard)
                try package.writeJSON(empty, to: shardURL)
            }
        }
        return package
    }

    static func open(at rootURL: URL) throws -> Self {
        let package = try openForQuery(at: rootURL)
        // Membership shards are the eager structural boundary. Asset records remain lazy so a
        // normal open does not turn into a full record scrub; reads validate their own record.
        for shard in Self.allShards {
            _ = try package.readMembershipShard(shard)
        }
        return package
    }

    /// Opens the package boundary needed by the library query path.
    ///
    /// This intentionally reads only `manifest.json`. A warm launch must be able to obtain its
    /// first page from the local index without enumerating package directories, opening asset
    /// records, parsing XMP, or reading originals. Callers that need eager membership validation
    /// should use `open(at:)`; asset records are validated when their records are read.
    static func openForQuery(at rootURL: URL) throws -> Self {
        let manifestURL = try PackagePath("manifest.json").url(in: rootURL)
        let data = try Data(contentsOf: manifestURL)
        let manifest = try PortablePackageJSON.decode(PortablePackageManifest.self, from: data)
        var package = try Self(validatingRoot: rootURL, manifest: manifest)
        var loaded = manifest
        loaded.unknownJSONFields = PortablePackageJSON.unknownFields(in: data, excluding: PortablePackageManifest.knownJSONKeys)
        package.manifest = loaded
        try package.validateManifest(loaded)
        return package
    }

    mutating func rewriteManifest(_ manifest: PortablePackageManifest) throws {
        try validateManifest(manifest)
        self.manifest = manifest
        try writeManifest()
    }

    func readMembershipShard(_ shard: String) throws -> PortablePackageMembershipShard {
        guard Self.isValidShard(shard) else { throw PortablePackageError.invalidShard(shard) }
        let data = try Data(contentsOf: packageURL(for: "Catalog/Membership/\(shard).json"))
        var value = try PortablePackageJSON.decode(PortablePackageMembershipShard.self, from: data)
        guard value.shard == shard else { throw PortablePackageError.invalidShard(value.shard) }
        value.unknownJSONFields = PortablePackageJSON.unknownFields(
            in: data, excluding: PortablePackageMembershipShard.knownJSONKeys
        )
        try validate(value)
        return value
    }

    func writeMembershipShard(_ shard: PortablePackageMembershipShard) throws {
        try validate(shard)
        try writeJSON(shard, to: packageURL(for: "Catalog/Membership/\(shard.shard).json"))
    }

    /// Encodes a shard with the same forward-compatible writer used by direct package writes.
    /// Import uses this value to stage the catalog mutation in the package transaction.
    func encodedMembershipShard(_ shard: PortablePackageMembershipShard) throws -> Data {
        try validate(shard)
        return try PortablePackageJSON.encoded(shard)
    }

    func readAssetRecord(for assetID: PortablePhotoAssetID) throws -> PortablePackageAssetRecord {
        let url = try packageURL(for: "Assets/\(Self.shard(for: assetID))/\(assetID.raw)/asset.json")
        let data = try Data(contentsOf: url)
        var record = try PortablePackageJSON.decode(PortablePackageAssetRecord.self, from: data)
        guard record.identity.assetID == assetID else {
            throw PortablePackageError.recordPathMismatch(url.path)
        }
        record.unknownJSONFields = PortablePackageJSON.unknownFields(
            in: data, excluding: PortablePackageAssetRecord.knownJSONKeys
        )
        try validate(record)
        return record
    }

    func writeAssetRecord(_ record: PortablePackageAssetRecord) throws {
        try validate(record)
        let url = try packageURL(
            for: "Assets/\(Self.shard(for: record.identity.assetID))/\(record.identity.assetID.raw)/asset.json"
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try writeJSON(record, to: url)
    }

    /// Encodes an asset record using the package writer, including any retained future fields.
    /// Transactions use this instead of a second JSON encoder so an edit commit cannot discard
    /// fields written by a newer package producer.
    func encodedAssetRecord(_ record: PortablePackageAssetRecord) throws -> Data {
        try validate(record)
        return try PortablePackageJSON.encoded(record)
    }

    /// Resolve an embedded source only at the render boundary. The returned URL is never part of
    /// the portable identity or the asset record.
    func embeddedSourceURL(for record: PortablePackageAssetRecord) throws -> URL {
        guard record.source.storage == .embedded, let relativePath = record.source.relativePath else {
            throw PortablePackageError.invalidRelativePath(record.source.relativePath ?? "<referenced>")
        }
        return try packageURL(for: relativePath)
    }

    /// The writer's filename rule, shared so the browsing derivation below cannot drift from the
    /// import layout. Internal (not private): PortablePackageImporter stages originals with this
    /// rule and the session derives the same path when a record has not been opened.
    static func safeFilename(_ name: String) -> String {
        let lastPathComponent = URL(fileURLWithPath: name).lastPathComponent
        let candidate = lastPathComponent.isEmpty ? "original" : lastPathComponent
        return candidate.replacingOccurrences(of: "/", with: "_")
    }

    /// Best-effort browsing locator for an embedded original, derived from the index summary
    /// without opening the asset record. This performs no file I/O and never hashes bytes: it is
    /// only the writer-layout join of shard, asset directory, and staged filename. It is not
    /// canonical identity — the record remains authoritative — so open/export/edit paths must use
    /// `verifiedEmbeddedSourceURL(for:displayName:)` (record fallback) or resolve the record.
    func browsingOriginalURL(
        for assetID: PortablePhotoAssetID, displayName: String
    ) throws -> URL {
        let shard = Self.shard(for: assetID)
        let filename = Self.safeFilename(displayName)
        return try packageURL(for: "Assets/\(shard)/\(assetID.raw)/Original/\(filename)")
    }

    /// Canonical source URL for one asset with a cheap fast path: the derived browsing locator
    /// when the file exists, otherwise the record's stored locator. Browsing keeps zero record
    /// reads; opening pays exactly one record read for assets whose layout predates the current
    /// writer or whose original was relocated outside the package transaction layer.
    func verifiedEmbeddedSourceURL(
        for assetID: PortablePhotoAssetID, displayName: String
    ) throws -> URL {
        let derived = try browsingOriginalURL(for: assetID, displayName: displayName)
        if FileManager.default.fileExists(atPath: derived.path) { return derived }
        return try embeddedSourceURL(for: readAssetRecord(for: assetID))
    }

    static let allShards: [String] = (0..<256).map { String(format: "%02x", $0) }

    static func shard(for assetID: PortablePhotoAssetID) -> String {
        String(assetID.raw.prefix(PortablePackageManifest.currentShardPrefixLength)).lowercased()
    }

    static func isValidShard(_ shard: String) -> Bool {
        shard.count == PortablePackageManifest.currentShardPrefixLength
            && shard.unicodeScalars.allSatisfy { "0123456789abcdef".unicodeScalars.contains($0) }
    }

    private init(validatingRoot rootURL: URL, manifest: PortablePackageManifest) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PortablePackageError.invalidPackageRoot
        }
        self.rootURL = rootURL
        self.manifest = manifest
    }

    private func writeManifest() throws {
        try writeJSON(manifest, to: packageURL(for: "manifest.json"))
    }

    // internal (not private): LibraryQueryControllerTests corrupts a specific shard file on disk
    // to exercise the rebuild-failure path.
    func membershipURL(for shard: String) -> URL {
        try! packageURL(for: "Catalog/Membership/\(shard).json")
    }

    func assetRecordURL(for assetID: PortablePhotoAssetID) -> URL {
        try! packageURL(for: "Assets/\(Self.shard(for: assetID))/\(assetID.raw)/asset.json")
    }

    // Internal package-native trash helpers. The active asset directory is moved as one unit so
    // originals and their edit sidecars have one recoverable location.
    func assetDirectoryURL(for assetID: PortablePhotoAssetID) -> URL {
        try! packageURL(for: "Assets/\(Self.shard(for: assetID))/\(assetID.raw)")
    }

    func quarantineDirectoryURL(for assetID: PortablePhotoAssetID) -> URL {
        try! packageURL(for: "Recovery/Quarantine/\(assetID.raw)")
    }

    func readAssetRecord(atRelativePath relativePath: String) throws -> PortablePackageAssetRecord {
        let url = try packageURL(for: relativePath)
        let data = try Data(contentsOf: url)
        var record = try PortablePackageJSON.decode(PortablePackageAssetRecord.self, from: data)
        record.unknownJSONFields = PortablePackageJSON.unknownFields(
            in: data, excluding: PortablePackageAssetRecord.knownJSONKeys
        )
        try validate(record)
        return record
    }

    private func validateManifest(_ manifest: PortablePackageManifest) throws {
        guard manifest.formatVersion > 0 else { throw PortablePackageError.invalidManifest("formatVersion must be positive") }
        guard manifest.membershipShardCount == PortablePackageManifest.currentShardCount,
              manifest.membershipShardPrefixLength == PortablePackageManifest.currentShardPrefixLength else {
            throw PortablePackageError.invalidManifest("this build requires 256 two-character hexadecimal shards")
        }
        guard !manifest.writerVersion.isEmpty, !manifest.minimumReaderVersion.isEmpty else {
            throw PortablePackageError.invalidManifest("compatibility versions must not be empty")
        }
    }

    private func validate(_ shard: PortablePackageMembershipShard) throws {
        var ids = Set<PortablePhotoAssetID>()
        for entry in shard.entries {
            guard Self.shard(for: entry.assetID) == shard.shard else {
                throw PortablePackageError.assetShardMismatch(asset: entry.assetID.raw, shard: shard.shard)
            }
            guard ids.insert(entry.assetID).inserted else {
                throw PortablePackageError.duplicateAsset(entry.assetID.raw)
            }
            let expectedPath = "Assets/\(shard.shard)/\(entry.assetID.raw)/asset.json"
            guard entry.recordPath == expectedPath else {
                throw PortablePackageError.recordPathMismatch(entry.recordPath)
            }
            guard (try? packageURL(for: entry.recordPath)) != nil else {
                throw PortablePackageError.recordPathMismatch(entry.recordPath)
            }
        }
    }

    private func validate(_ record: PortablePackageAssetRecord) throws {
        switch record.source.storage {
        case .embedded:
            guard let path = record.source.relativePath, (try? packageURL(for: path)) != nil else {
                throw PortablePackageError.invalidRelativePath(record.source.relativePath ?? "<missing>")
            }
        case .referenced:
            guard record.source.relativePath == nil else {
                throw PortablePackageError.invalidRelativePath(record.source.relativePath ?? "<referenced>")
            }
        }
        for pointer in record.editHistory.edits where (try? packageURL(for: pointer.relativePath)) == nil {
            throw PortablePackageError.invalidRelativePath(pointer.relativePath)
        }
        for pointer in record.editHistory.edits {
            if let xmpPath = pointer.xmpRelativePath, (try? packageURL(for: xmpPath)) == nil {
                throw PortablePackageError.invalidRelativePath(xmpPath)
            }
        }
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        (try? PackagePath(path)) != nil
    }

    /// Resolves a package-relative path and rejects symlink escapes from the package root.
    func packageURL(for relativePath: String) throws -> URL {
        do {
            return try PackagePath(relativePath).url(in: rootURL)
        } catch {
            throw PortablePackageError.invalidRelativePath(relativePath)
        }
    }

    private func writeJSON<T: PortablePackageJSONRecord>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PortablePackageJSON.write(value, to: url)
    }
}

private protocol PortablePackageJSONRecord: Codable {
    static var knownJSONKeys: Set<String> { get }
    var unknownJSONFields: [String: Data] { get set }
}

private enum PortablePackageJSON {
    static func decode<T: PortablePackageJSONRecord>(_ type: T.Type, from data: Data) throws -> T {
        var value = try PackageJSONCoder.decode(type, from: data)
        value.unknownJSONFields = unknownFields(in: data, excluding: type.knownJSONKeys)
        return value
    }

    static func write<T: PortablePackageJSONRecord>(_ value: T, to url: URL) throws {
        let data = try encoded(value)
        try data.write(to: url, options: .atomic)
    }

    static func encoded<T: PortablePackageJSONRecord>(_ value: T) throws -> Data {
        var data = try PackageJSONCoder.encode(value)
        let unknown = value.unknownJSONFields
        if !unknown.isEmpty {
            guard data.first == 123, data.last == 125 else { throw PortablePackageError.invalidManifest("JSON record is not an object") }
            data.removeLast()
            let members = unknown
                .filter { !T.knownJSONKeys.contains($0.key) }
                .sorted(by: { $0.key < $1.key })
                .map(\.value)
            for member in members {
                if data.count > 1 { data.append(44) }
                data.append(contentsOf: member)
            }
            data.append(125)
        }
        return data
    }

    static func unknownFields(in data: Data, excluding knownKeys: Set<String>) -> [String: Data] {
        guard let members = try? JSONMembers(data: data) else { return [:] }
        return members.fields.reduce(into: [:]) { result, field in
            if !knownKeys.contains(field.key) { result[field.key] = field.rawMember }
        }
    }
}

private extension PortablePackageManifest {
    static var knownJSONKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

private extension PortablePackageMembershipShard {
    static var knownJSONKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

private extension PortablePackageAssetRecord {
    static var knownJSONKeys: Set<String> { Set(CodingKeys.allCases.map(\.stringValue)) }
}

private struct JSONMembers {
    struct Field { let key: String; let rawMember: Data }
    let fields: [Field]

    init(data: Data) throws {
        var parser = JSONMemberParser(data: data)
        fields = try parser.parseObject()
    }
}

private struct JSONMemberParser {
    let bytes: [UInt8]
    var index = 0

    init(data: Data) { bytes = Array(data) }

    mutating func parseObject() throws -> [JSONMembers.Field] {
        skipWhitespace()
        guard consume(123) else { throw ParseError.invalidJSON }
        skipWhitespace()
        if consume(125) { return [] }
        var fields: [JSONMembers.Field] = []
        while true {
            skipWhitespace()
            let memberStart = index
            let keyData = try parseString()
            guard let key = try? JSONDecoder().decode(String.self, from: keyData) else { throw ParseError.invalidJSON }
            skipWhitespace()
            guard consume(58) else { throw ParseError.invalidJSON }
            skipWhitespace()
            _ = try parseValue()
            let memberEnd = index
            fields.append(JSONMembers.Field(key: key, rawMember: Data(bytes[memberStart..<memberEnd])))
            skipWhitespace()
            if consume(125) { return fields }
            guard consume(44) else { throw ParseError.invalidJSON }
        }
    }

    private mutating func parseString() throws -> Data {
        let start = index
        guard consume(34) else { throw ParseError.invalidJSON }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 92 { guard index < bytes.count else { throw ParseError.invalidJSON }; index += 1 }
            else if byte == 34 { return Data(bytes[start..<index]) }
            else if byte < 32 { throw ParseError.invalidJSON }
        }
        throw ParseError.invalidJSON
    }

    private mutating func parseValue() throws -> Void {
        guard index < bytes.count else { throw ParseError.invalidJSON }
        switch bytes[index] {
        case 34: _ = try parseString()
        case 123: _ = try parseObject()
        case 91:
            index += 1
            skipWhitespace()
            if consume(93) { return }
            while true {
                try parseValue()
                skipWhitespace()
                if consume(93) { return }
                guard consume(44) else { throw ParseError.invalidJSON }
                skipWhitespace()
            }
        default:
            let start = index
            while index < bytes.count && ![44, 93, 125].contains(bytes[index]) { index += 1 }
            let token = bytes[start..<index]
            guard !token.allSatisfy({ $0 == 32 || $0 == 9 || $0 == 10 || $0 == 13 }) else {
                throw ParseError.invalidJSON
            }
        }
    }

    private mutating func skipWhitespace() {
        while index < bytes.count && [32, 9, 10, 13].contains(bytes[index]) { index += 1 }
    }

    @discardableResult
    private mutating func consume(_ expected: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == expected else { return false }
        index += 1
        return true
    }

    private enum ParseError: Error { case invalidJSON }
}

extension PortablePackageManifest: PortablePackageJSONRecord {}
extension PortablePackageMembershipShard: PortablePackageJSONRecord {}
extension PortablePackageAssetRecord: PortablePackageJSONRecord {}
