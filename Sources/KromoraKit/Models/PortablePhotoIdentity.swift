import CryptoKit
import Foundation

/// The durable identity of an asset in the portable library model.
///
/// The UUID is intentionally opaque: it is allocated by the library and is not derived from a
/// URL, filesystem metadata, or the asset's bytes. A moved asset therefore keeps the same identity
/// because its record keeps the same UUID. Content integrity and source replacement detection live
/// in `PortablePhotoSourceFingerprint`.
struct PortablePhotoAssetID: Codable, Hashable, Sendable, Equatable, CustomStringConvertible {
    let uuid: UUID

    init(uuid: UUID = UUID()) {
        self.uuid = uuid
    }

    var raw: String { uuid.uuidString.lowercased() }

    var description: String { raw }
}

/// The immutable source identity used beside a portable asset UUID.
///
/// This type deliberately contains no URL, path, inode/device identifier, timestamp, or other
/// filesystem-derived value. The caller reads and hashes a source at the import/render boundary,
/// then persists only these value fields. Geometry is optional because it may not be known until a
/// decoder has inspected the source.
struct PortablePhotoSourceFingerprint: Codable, Hashable, Sendable, Equatable {
    let contentHash: String
    let sourceRevision: UInt64
    let decoderVersion: String
    let geometry: PhotoPixelDimensions?

    init(
        contentHash: String,
        sourceRevision: UInt64 = 0,
        decoderVersion: String,
        geometry: PhotoPixelDimensions? = nil
    ) {
        self.contentHash = contentHash
        self.sourceRevision = sourceRevision
        self.decoderVersion = decoderVersion
        self.geometry = geometry
    }

    /// Build a fingerprint from bytes that are already available to the caller.
    static func data(
        _ data: Data,
        sourceRevision: UInt64 = 0,
        decoderVersion: String,
        geometry: PhotoPixelDimensions? = nil
    ) -> Self {
        Self(
            contentHash: Self.contentHash(of: data),
            sourceRevision: sourceRevision,
            decoderVersion: decoderVersion,
            geometry: geometry
        )
    }

    /// Read and hash a file without retaining its URL in the identity value.
    ///
    /// This is an import/render-boundary helper. The URL is only an input used to obtain immutable
    /// bytes; it is never copied into the returned fingerprint.
    static func file(
        at url: URL,
        sourceRevision: UInt64 = 0,
        decoderVersion: String,
        geometry: PhotoPixelDimensions? = nil
    ) throws -> Self {
        Self(
            contentHash: Self.contentHash(of: try Data(contentsOf: url)),
            sourceRevision: sourceRevision,
            decoderVersion: decoderVersion,
            geometry: geometry
        )
    }

    /// A delimiter-safe printable representation for future cache-key consumers.
    ///
    /// Only the portable fields participate. In particular, this must remain identical when the
    /// same asset is opened from a different path or filesystem.
    var cacheKey: String {
        let geometryKey = geometry.map { "\($0.width)x\($0.height)" } ?? "none"
        return [
            "sha256=\(contentHash)",
            "revision=\(sourceRevision)",
            "decoder=\(Self.escape(decoderVersion))",
            "geometry=\(geometryKey)",
        ].joined(separator: "|")
    }

    static func contentHash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "|", with: "%7C")
            .replacingOccurrences(of: "=", with: "%3D")
    }
}

/// The complete portable source identity used by future render, cache, and persistence consumers.
///
/// Keeping the UUID and source fingerprint together gives migration code one value to pass across
/// those boundaries while allowing this ticket to remain additive. No consumer uses this type yet.
struct PortablePhotoIdentity: Codable, Hashable, Sendable, Equatable {
    let assetID: PortablePhotoAssetID
    let sourceFingerprint: PortablePhotoSourceFingerprint

    init(
        assetID: PortablePhotoAssetID,
        sourceFingerprint: PortablePhotoSourceFingerprint
    ) {
        self.assetID = assetID
        self.sourceFingerprint = sourceFingerprint
    }

    var cacheKey: String {
        "asset=\(assetID.raw)|\(sourceFingerprint.cacheKey)"
    }

    /// Canonical bytes are useful for relocation tests and future content-addressed indexes.
    /// Identity is still the opaque UUID; this is only a deterministic serialization of the value.
    var canonicalData: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

// These aliases make the intent explicit at migration call sites while retaining one canonical
// implementation. The existing PhotoAssetID/PhotoSourceFingerprint types remain legacy-compatible
// until the cache and persistence tickets switch their consumers.
typealias OpaquePhotoAssetID = PortablePhotoAssetID
typealias OpaquePhotoSourceFingerprint = PortablePhotoSourceFingerprint
typealias OpaquePhotoIdentity = PortablePhotoIdentity
