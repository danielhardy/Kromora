import CryptoKit
import Foundation

/// A durable identity for a photo source.
///
/// File identities prefer the filesystem resource identifier, which survives a move on the same
/// volume. A canonical path is the fallback for URLs that do not currently resolve to a file (and
/// for filesystems that do not provide a resource identifier). Data-only imports use the SHA-256 of
/// their bytes. This is deliberately content-addressed only for data that is already in memory;
/// folder scans use `PhotoSourceFingerprint` rather than reading an entire RAW file.
struct PhotoAssetID: Codable, Hashable, Sendable, Equatable, CustomStringConvertible {
    private let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Stable identity for a file URL. The path fallback keeps this useful for missing/relinking
    /// records and makes two unresolved URLs distinct even when they have the same contents.
    static func file(_ url: URL) -> PhotoAssetID {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let fingerprint = PhotoSourceFingerprint.file(at: canonical)
        return file(canonical, fingerprint: fingerprint)
    }

    /// Identity for a file when its fingerprint has already been read by the caller. Keeping this
    /// seam explicit prevents a source construction from walking the file a second time just to
    /// derive the resource identifier.
    static func file(_ url: URL, fingerprint: PhotoSourceFingerprint) -> PhotoAssetID {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        if let resourceID = fingerprint.resourceIdentifier {
            return PhotoAssetID(rawValue: "file-resource:\(resourceID)")
        }
        return PhotoAssetID(rawValue: "file-path:\(canonical.path)")
    }

    /// Identity for a Photos/local-library identifier supplied by the caller. Unlike a generated
    /// UUID, an Apple Photos local identifier is durable across launches and does not depend on the
    /// imported bytes being delivered in exactly the same representation.
    static func photos(localIdentifier: String) -> PhotoAssetID {
        PhotoAssetID(rawValue: "photos:\(localIdentifier)")
    }

    /// Durable identity for a data-only import. Identical bytes intentionally identify one logical
    /// source; callers with two distinct Photos assets should use `photos(localIdentifier:)`.
    static func data(_ data: Data) -> PhotoAssetID {
        Self.data(dataDigest: contentDigest(data))
    }

    /// Identity for bytes whose digest was already calculated at the import boundary.
    ///
    /// Photos payloads are used by the asset record, thumbnail cache, and render source. Keeping
    /// this initializer separate makes it possible for those consumers to share one full-buffer
    /// digest instead of each walking a large RAW independently.
    static func data(dataDigest: String) -> PhotoAssetID {
        PhotoAssetID(rawValue: "data:\(dataDigest)")
    }

    /// Compatibility identity for a transient import whose provider has no durable identifier.
    /// New data-only imports should use `data(_:)`, as `imported(_:)` is only stable for the life of
    /// the UUID supplied by its caller.
    static func imported(_ id: UUID) -> PhotoAssetID {
        PhotoAssetID(rawValue: "import:\(id.uuidString.lowercased())")
    }

    /// Stable identity for an imported collection item when Photos did not provide its local
    /// identifier. The ordinal distinguishes duplicate bytes within one import while the content
    /// and name let the same import be reopened and find its persisted edits after relaunch.
    static func imported(data: Data, name: String, ordinal: Int) -> PhotoAssetID {
        imported(dataDigest: contentDigest(data), name: name, ordinal: ordinal)
    }

    /// Stable identity for an imported item when the caller already owns the content digest.
    static func imported(dataDigest: String, name: String, ordinal: Int) -> PhotoAssetID {
        let nameHash = contentDigest(Data(name.utf8))
        return PhotoAssetID(rawValue: "import-data:\(dataDigest):\(nameHash):\(ordinal)")
    }

    var raw: String { rawValue }
    var description: String { rawValue }

    static func contentDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// A bounded source signature used in cache keys and source-change detection.
///
/// The filesystem resource identifier catches replacement-by-atomic-write on normal macOS
/// volumes. Size, modification time, and a digest of the first/last 64 KiB cover in-place edits
/// without turning every folder scan into a full RAW-file hash. A caller that needs cryptographic
/// identity for already-available bytes can use `PhotoSourceFingerprint.data(_:)`.
struct PhotoSourceFingerprint: Codable, Hashable, Sendable, Equatable {
    static let sampleSize = 64 * 1024

    let byteCount: Int64?
    let modificationDate: Date?
    let resourceIdentifier: String?
    let sampleDigest: String?

    static func file(at url: URL) -> PhotoSourceFingerprint {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey
        ])
        let resourceIdentifier = values?.fileResourceIdentifier.map(String.init(describing:))
        let byteCount = values?.fileSize.map(Int64.init)
        let modificationDate = values?.contentModificationDate
        let sampleDigest = sampleDigest(at: url, byteCount: byteCount)
        return PhotoSourceFingerprint(
            byteCount: byteCount,
            modificationDate: modificationDate,
            resourceIdentifier: resourceIdentifier,
            sampleDigest: sampleDigest
        )
    }

    static func data(_ data: Data, digest: String? = nil) -> PhotoSourceFingerprint {
        PhotoSourceFingerprint(
            byteCount: Int64(data.count),
            modificationDate: nil,
            resourceIdentifier: nil,
            sampleDigest: digest ?? PhotoAssetID.contentDigest(data)
        )
    }

    /// A stable printable key for caches. It includes every observed component, including missing
    /// values, so an unavailable file never aliases a successfully fingerprinted one.
    var cacheKey: String {
        [
            byteCount.map(String.init) ?? "?",
            modificationDate.map { String(format: "%.6f", $0.timeIntervalSinceReferenceDate) } ?? "?",
            resourceIdentifier ?? "?",
            sampleDigest ?? "?",
        ].joined(separator: ":")
    }

    /// Whether two observations can be treated as the same source after a path change. Resource
    /// identity is strongest; the bounded signature is the fallback for volumes that do not expose
    /// one. This is intentionally a matching hint for relinking, not a claim of full-file equality.
    func matches(_ other: PhotoSourceFingerprint) -> Bool {
        if let resourceIdentifier, let otherResourceIdentifier = other.resourceIdentifier {
            return resourceIdentifier == otherResourceIdentifier
                && byteCount == other.byteCount
                && modificationDate == other.modificationDate
                && sampleDigest == other.sampleDigest
        }
        return byteCount == other.byteCount
            && modificationDate == other.modificationDate
            && sampleDigest == other.sampleDigest
    }

    private static func sampleDigest(at url: URL, byteCount: Int64?) -> String? {
        guard let byteCount, byteCount >= 0,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            let first = try handle.read(upToCount: sampleSize) ?? Data()
            var sample = first
            if byteCount > Int64(sampleSize) {
                try handle.seek(toOffset: UInt64(max(0, byteCount - Int64(sampleSize))))
                sample.append(try handle.read(upToCount: sampleSize) ?? Data())
            }
            return PhotoAssetID.contentDigest(sample)
        } catch {
            return nil
        }
    }
}

/// How a discovered source can be reopened. The bookmark is kept with the source record rather
/// than in mutable library state, because it describes the source itself and enables relinking.
struct PhotoAssetSource: Codable, Hashable, Sendable, Equatable {
    let id: PhotoAssetID
    let url: URL?
    let data: Data?
    let bookmarkData: Data?
    let fingerprint: PhotoSourceFingerprint
    let portableIdentity: PortablePhotoIdentity

    private enum CodingKeys: String, CodingKey {
        case id, url, data, bookmarkData, fingerprint, portableIdentity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(PhotoAssetID.self, forKey: .id)
        self.url = try container.decodeIfPresent(URL.self, forKey: .url)
        self.data = try container.decodeIfPresent(Data.self, forKey: .data)
        self.bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        self.fingerprint = try container.decode(PhotoSourceFingerprint.self, forKey: .fingerprint)
        self.portableIdentity = try container.decodeIfPresent(
            PortablePhotoIdentity.self, forKey: .portableIdentity
        ) ?? PortablePhotoIdentity.compatibility(
            assetID: self.id, sourceFingerprint: self.fingerprint
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(data, forKey: .data)
        try container.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encode(portableIdentity, forKey: .portableIdentity)
    }

    init(
        url: URL,
        bookmarkData: Data? = nil,
        fingerprint: PhotoSourceFingerprint? = nil,
        portableIdentity: PortablePhotoIdentity? = nil
    ) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedFingerprint = fingerprint ?? PhotoSourceFingerprint.file(at: canonical)
        self.id = PhotoAssetID.file(canonical, fingerprint: resolvedFingerprint)
        self.url = canonical
        self.data = nil
        self.bookmarkData = bookmarkData
        self.fingerprint = resolvedFingerprint
        self.portableIdentity = Self.makePortableIdentity(
            at: canonical, assetID: self.id,
            existing: portableIdentity
        )
    }

    /// Build a URL-backed record while retaining an already-transferred payload for the current
    /// import operation. The URL is the durable source; `data` is only a short-lived compatibility
    /// cache for callers that already have the bytes in memory.
    init(
        url: URL,
        id: PhotoAssetID,
        data: Data?,
        bookmarkData: Data? = nil,
        fingerprint: PhotoSourceFingerprint? = nil,
        portableIdentity: PortablePhotoIdentity? = nil
    ) {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        self.id = id
        self.url = canonical
        self.data = data
        self.bookmarkData = bookmarkData
        self.fingerprint = fingerprint ?? PhotoSourceFingerprint.file(at: canonical)
        self.portableIdentity = Self.makePortableIdentity(
            at: canonical, assetID: id, existing: portableIdentity
        )
    }

    /// Browsing projection for a portable asset whose record has not been opened.
    ///
    /// Unlike `init(url:id:data:)`, this performs no file I/O: no resource lookup, no sample
    /// read, and no full-file hash. The caller supplies the derived embedded URL (see
    /// `PortableLibraryPackage.browsingOriginalURL`) and the index summary. The placeholder
    /// fingerprints are deterministic per asset UUID and digest-shaped so a browsing observation
    /// can never alias another asset or a record-resolved observation in `matches(_)`; opening
    /// the asset resolves the record identity and replaces this value before any render, cache,
    /// or edit consumer depends on source bytes.
    init(
        browsingPortableAsset assetID: PortablePhotoAssetID,
        embeddedURL: URL,
        summary: PortablePackageAssetSummary
    ) {
        self.id = PhotoAssetID(rawValue: "portable:\(assetID.raw)")
        self.url = embeddedURL.standardizedFileURL
        self.data = nil
        self.bookmarkData = nil
        let observationDigest = PhotoAssetID.contentDigest(Data(("browsing:" + assetID.raw).utf8))
        self.fingerprint = PhotoSourceFingerprint(
            byteCount: nil,
            modificationDate: nil,
            resourceIdentifier: nil,
            sampleDigest: observationDigest
        )
        self.portableIdentity = PortablePhotoIdentity(
            assetID: assetID,
            sourceFingerprint: PortablePhotoSourceFingerprint(
                contentHash: PortablePhotoSourceFingerprint.contentHash(
                    of: Data(("browsing:" + assetID.raw).utf8)
                ),
                decoderVersion: "browsing-v1",
                geometry: summary.dimensions
            )
        )
    }

    init(
        data: Data,
        id: PhotoAssetID? = nil,
        fingerprint: PhotoSourceFingerprint? = nil,
        portableIdentity: PortablePhotoIdentity? = nil
    ) {
        let dataFingerprint = fingerprint ?? PhotoSourceFingerprint.data(data)
        if let id {
            self.id = id
        } else if let digest = dataFingerprint.sampleDigest {
            self.id = PhotoAssetID.data(dataDigest: digest)
        } else {
            // A caller-provided incomplete fingerprint is unusual, but never turn it into a
            // shared "missing" identity. Fall back to the bytes for a safe durable identity.
            self.id = PhotoAssetID.data(data)
        }
        self.url = nil
        self.data = data
        self.bookmarkData = nil
        self.fingerprint = dataFingerprint
        let portableAssetID = portableIdentity?.assetID
            ?? PortablePhotoAssetID.compatibility(from: self.id)
        let decoderVersion = portableIdentity?.sourceFingerprint.decoderVersion
            ?? "imageio-standard-v1"
        self.portableIdentity = PortablePhotoIdentity(
            assetID: portableAssetID,
            sourceFingerprint: .data(
                data,
                sourceRevision: portableIdentity?.sourceFingerprint.sourceRevision ?? 0,
                decoderVersion: decoderVersion,
                geometry: portableIdentity?.sourceFingerprint.geometry
            )
        )
    }

    /// Mint a security-scoped bookmark when the caller has authority to persist one. Failure is
    /// non-fatal: the path and fingerprint still support the normal in-session workflow.
    static func bookmarkData(for url: URL) -> Data? {
        try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// The source record is an immutable observation. Render-boundary `ImageSource` values refresh
    /// the bytes when they are opened; this record's cache key remains a stable snapshot.
    var cacheIdentity: PortablePhotoIdentity { portableIdentity }

    var cacheKey: String { portableIdentity.cacheKey }

    func matches(_ other: PhotoAssetSource) -> Bool {
        fingerprint.matches(other.fingerprint)
    }

    private static func makePortableIdentity(
        at url: URL, assetID: PhotoAssetID,
        existing: PortablePhotoIdentity?
    ) -> PortablePhotoIdentity {
        let fingerprint = (try? PortablePhotoSourceFingerprint.file(
            at: url,
            sourceRevision: existing?.sourceFingerprint.sourceRevision ?? 0,
            decoderVersion: existing?.sourceFingerprint.decoderVersion
                ?? "imageio-\(url.pathExtension.lowercased())-v1",
            geometry: existing?.sourceFingerprint.geometry
        )) ?? PortablePhotoSourceFingerprint(
            contentHash: PortablePhotoSourceFingerprint.contentHash(
                of: Data(("unavailable:" + PhotoAssetID.file(url).raw).utf8)
            ),
            sourceRevision: existing?.sourceFingerprint.sourceRevision ?? 0,
            decoderVersion: existing?.sourceFingerprint.decoderVersion ?? "legacy-fallback-v1",
            geometry: existing?.sourceFingerprint.geometry
        )
        // A file URL is a referenced source, not a data-only import. Two different files can have
        // identical bytes and still require independent edit documents, so their compatibility
        // identity must follow the file asset identity rather than the content fingerprint. The
        // fingerprint remains content-addressed for cache/source-change purposes; it is not the
        // ownership key for per-photo edits.
        return PortablePhotoIdentity(
            assetID: existing?.assetID
                ?? PortablePhotoAssetID.compatibility(from: assetID),
            sourceFingerprint: fingerprint
        )
    }
}

/// Pixel dimensions are kept as integers so the library model remains Codable and independent of
/// Core Graphics.
struct PhotoPixelDimensions: Codable, Hashable, Sendable, Equatable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// The metadata needed by the library and inspector. `ImageMetadata` remains the display-oriented
/// reader; this record is the stable value snapshot stored with an asset.
struct PhotoAssetMetadata: Codable, Hashable, Sendable, Equatable {
    let dimensions: PhotoPixelDimensions?
    let captureDate: String?
    let cameraMake: String?
    let cameraModel: String?
    let lens: String?

    init(
        dimensions: PhotoPixelDimensions? = nil,
        captureDate: String? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lens: String? = nil
    ) {
        self.dimensions = dimensions
        self.captureDate = captureDate
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lens = lens
    }

    init(imageMetadata: ImageMetadata) {
        let dimensions: PhotoPixelDimensions?
        if let width = imageMetadata.pixelWidth, let height = imageMetadata.pixelHeight {
            dimensions = PhotoPixelDimensions(width: width, height: height)
        } else {
            dimensions = nil
        }
        self.init(
            dimensions: dimensions,
            captureDate: imageMetadata.dateTaken,
            cameraMake: imageMetadata.make,
            cameraModel: imageMetadata.model,
            lens: imageMetadata.lens
        )
    }

    static let empty = PhotoAssetMetadata()

    var camera: String? {
        [cameraMake, cameraModel].compactMap { $0 }.joined(separator: " ").nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum PhotoFlag: String, Codable, Hashable, Sendable, Equatable {
    case none
    case pick
    case reject
}

enum PhotoThumbnailState: String, Codable, Hashable, Sendable, Equatable {
    case notRequested
    case loading
    case ready
    case failed
}

/// Mutable library/culling state is separate from the immutable source and metadata snapshot.
struct PhotoAssetLibraryState: Codable, Hashable, Sendable, Equatable {
    private(set) var rating: Int
    var flag: PhotoFlag
    var thumbnail: PhotoThumbnailState

    init(rating: Int = 0, flag: PhotoFlag = .none, thumbnail: PhotoThumbnailState = .notRequested) {
        self.rating = min(max(rating, 0), 5)
        self.flag = flag
        self.thumbnail = thumbnail
    }

    mutating func setRating(_ rating: Int) {
        self.rating = min(max(rating, 0), 5)
    }
}

/// Stable, value-based record for one library asset. Rendered images and AppKit objects are kept
/// outside this type; it is safe to persist, send across actors, and use as a cache/input record.
struct PhotoAsset: Identifiable, Codable, Hashable, Sendable, Equatable {
    let source: PhotoAssetSource
    let filename: String
    let fileType: String
    private(set) var metadata: PhotoAssetMetadata
    var libraryState: PhotoAssetLibraryState

    var id: PhotoAssetID { source.id }
    var url: URL? { source.url }
    var bookmarkData: Data? { source.bookmarkData }
    var cacheKey: String { source.cacheKey }

    /// The name used by the library and filmstrip, with a deterministic value for malformed or
    /// legacy records that do not carry one.
    var displayName: String {
        let value = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { return value }
        if let url, !url.deletingPathExtension().lastPathComponent.isEmpty {
            return url.deletingPathExtension().lastPathComponent
        }
        return "Untitled"
    }

    // Convenience accessors keep the record pleasant to use from a grid/culling model while the
    // stored representation remains split into immutable source/metadata and mutable library state.
    var dimensions: PhotoPixelDimensions? { metadata.dimensions }
    var captureDate: String? { metadata.captureDate }
    var camera: String? { metadata.camera }
    var lens: String? { metadata.lens }
    var rating: Int {
        get { libraryState.rating }
        set { libraryState.setRating(newValue) }
    }
    var flag: PhotoFlag {
        get { libraryState.flag }
        set { libraryState.flag = newValue }
    }
    var thumbnailState: PhotoThumbnailState {
        get { libraryState.thumbnail }
        set { libraryState.thumbnail = newValue }
    }

    /// Complete the value snapshot after deferred ImageIO discovery has finished.
    mutating func updateMetadata(from imageMetadata: ImageMetadata) {
        metadata = PhotoAssetMetadata(imageMetadata: imageMetadata)
    }

    init(
        source: PhotoAssetSource,
        filename: String,
        fileType: String,
        metadata: PhotoAssetMetadata = .empty,
        libraryState: PhotoAssetLibraryState = PhotoAssetLibraryState()
    ) {
        self.source = source
        self.filename = filename
        self.fileType = fileType.lowercased()
        self.metadata = metadata
        self.libraryState = libraryState
    }

    init(
        url: URL,
        filename: String? = nil,
        metadata: PhotoAssetMetadata = .empty,
        libraryState: PhotoAssetLibraryState = PhotoAssetLibraryState(),
        bookmarkData: Data? = nil
    ) {
        self.init(
            source: PhotoAssetSource(url: url, bookmarkData: bookmarkData),
            filename: filename ?? url.deletingPathExtension().lastPathComponent,
            fileType: url.pathExtension,
            metadata: metadata,
            libraryState: libraryState
        )
    }

    init(
        data: Data,
        filename: String,
        fileType: String? = nil,
        metadata: PhotoAssetMetadata = .empty,
        libraryState: PhotoAssetLibraryState = PhotoAssetLibraryState()
    ) {
        self.init(
            source: PhotoAssetSource(data: data),
            filename: filename,
            fileType: fileType ?? URL(fileURLWithPath: filename).pathExtension,
            metadata: metadata,
            libraryState: libraryState
        )
    }
}

typealias PixelDimensions = PhotoPixelDimensions
