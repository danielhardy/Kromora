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

    func with(geometry: PhotoPixelDimensions?) -> Self {
        Self(
            contentHash: contentHash,
            sourceRevision: sourceRevision,
            decoderVersion: decoderVersion,
            geometry: geometry
        )
    }

    /// Compare a migrated legacy key with a render-boundary identity. Legacy cache keys did not
    /// carry decoded geometry, so an absent geometry is compatible while two known geometries
    /// must still agree.
    func matches(_ other: Self) -> Bool {
        contentHash == other.contentHash
            && sourceRevision == other.sourceRevision
            && (decoderVersion == other.decoderVersion
                || decoderVersion == "legacy-v1"
                || other.decoderVersion == "legacy-v1")
            && (geometry == nil || other.geometry == nil || geometry == other.geometry)
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
/// Keeping the UUID and source fingerprint together gives render, cache, and persistence code one
/// value to pass across those boundaries.
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

    func with(geometry: PhotoPixelDimensions?) -> Self {
        Self(
            assetID: assetID,
            sourceFingerprint: sourceFingerprint.with(geometry: geometry)
        )
    }

    /// Normalize a legacy cache caller without allowing its filesystem-derived spelling into a
    /// new cache key. This bridge is intentionally deterministic so an old in-memory caller can
    /// still remove or find the same entry after the cache schema changes. New code should pass a
    /// real portable identity instead.
    static func compatibility(
        assetID: PhotoAssetID,
        sourceFingerprint: PhotoSourceFingerprint
    ) -> Self {
        Self(
            assetID: PortablePhotoAssetID.compatibility(from: assetID),
            sourceFingerprint: PortablePhotoSourceFingerprint.compatibility(from: sourceFingerprint)
        )
    }
}

extension PortablePhotoAssetID {
    static func compatibility(from legacy: PhotoAssetID) -> Self {
        if let rawUUID = legacy.raw.split(separator: ":", maxSplits: 1).last,
            legacy.raw.hasPrefix("portable:"),
            let uuid = UUID(uuidString: String(rawUUID))
        {
            return Self(uuid: uuid)
        }
        return Self(uuid: UUID.deterministic(from: Data(("asset:" + legacy.raw).utf8)))
    }

    /// Stable bridge for a legacy source record that has no persisted UUID yet. The bridge is
    /// deliberately based on the immutable source fingerprint, never on the URL or filesystem
    /// metadata. New package records should allocate and persist a random UUID instead; this
    /// compatibility path exists only so a folder-backed record can be reopened after relocation
    /// before the package catalog has taken ownership of its UUID.
    static func compatibility(from fingerprint: PortablePhotoSourceFingerprint) -> Self {
        Self(uuid: UUID.deterministic(from: Data(("source:" + fingerprint.cacheKey).utf8)))
    }
}

extension PortablePhotoSourceFingerprint {
    static func compatibility(from legacy: PhotoSourceFingerprint) -> Self {
        let legacyKey = legacy.cacheKey
        return Self(
            contentHash: legacy.sampleDigest
                ?? Self.contentHash(of: Data(("fingerprint:" + legacyKey).utf8)),
            decoderVersion: "legacy-v1"
        )
    }
}

private extension UUID {
    static func deterministic(from data: Data) -> UUID {
        let digest = SHA256.hash(data: data)
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
