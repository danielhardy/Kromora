import CryptoKit
import Foundation

/// Durable, actor-isolated storage for mask pixels. The directory is injectable so tests and
/// previews can use a temporary location; the production default lives beside Kromora's other
/// Application Support data. Each quality is a separate file by construction.
///
/// Pixel payloads live in a binary sidecar (raw native-endian Float32) next to a small JSON
/// metadata file. An earlier revision JSON-encoded the floats inline, which turned a full-
/// resolution refinement (60M values for a 60MP source) into a ~500MB JSON document: encoding
/// and decoding that stalled the main render for minutes, presenting as a permanent spinner on
/// any photo with a semantic layer. Files written by that revision still load: an inline
/// `values` array is honored when present, and only new writes use the sidecar.
actor MaskStore {
    private struct PersistedMask: Codable, Sendable {
        let key: MaskCacheKey
        let mask: PersistedPixels
    }

    private struct PersistedPixels: Codable, Sendable {
        let size: PixelDimensions
        /// Inline payload written by the pre-sidecar revision. Nil for current files, whose
        /// pixels live in the adjacent `.bin` file.
        let values: [Float]?

        private enum CodingKeys: String, CodingKey {
            case size
            case values
        }

        init(size: PixelDimensions, values: [Float]?) {
            self.size = size
            self.values = values
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            size = try container.decode(PixelDimensions.self, forKey: .size)
            values = try container.decodeIfPresent([Float].self, forKey: .values)
        }

        /// Current metadata must never contain a text-encoded pixel payload. Keeping this custom
        /// encoder next to the legacy decoder makes that invariant structural rather than relying
        /// on every caller to pass `nil` for `values`.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(size, forKey: .size)
        }
    }

    private let directory: URL

    init(directory: URL = MaskStore.defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns an exact-quality reference. A lower-quality mask is never substituted implicitly.
    /// Existence only needs the metadata file (plus the sidecar for current files), never the
    /// pixels, so gating lookups stay cheap even for full-resolution entries.
    func mask(for key: MaskCacheKey, quality: MaskQuality) -> RegionMaskReference? {
        let exactKey = key.with(quality: quality)
        guard let persisted = loadMetadata(for: exactKey),
              persisted.key == exactKey else { return nil }
        if persisted.mask.values == nil {
            guard sidecarHasExpectedSize(for: exactKey, dimensions: persisted.mask.size) else {
                return nil
            }
        }
        return RegionMaskReference(cacheKey: persisted.key, size: persisted.mask.size, quality: quality)
    }

    /// Finds the least expensive cached quality that satisfies the requested minimum.
    func bestAvailable(for key: MaskCacheKey, minimumQuality: MaskQuality) -> RegionMaskReference? {
        for quality in MaskQuality.allCases where quality >= minimumQuality {
            if let reference = mask(for: key, quality: quality) { return reference }
        }
        return nil
    }

    @discardableResult
    func store(
        _ pixels: NormalizedMask,
        for key: MaskCacheKey,
        quality: MaskQuality
    ) throws -> RegionMaskReference {
        try Task.checkCancellation()
        let exactKey = key.with(quality: quality)
        // Sidecar first: a reader only trusts the metadata when the pixels are already there,
        // so an interrupted write degrades to a cache miss rather than a corrupt entry.
        try pixels.values.withUnsafeBytes { buffer in
            try Data(buffer).write(to: binURL(for: exactKey), options: .atomic)
        }
        try Task.checkCancellation()
        let persisted = PersistedMask(
            key: exactKey,
            mask: PersistedPixels(size: pixels.size, values: nil)
        )
        let data = try JSONEncoder().encode(persisted)
        try Task.checkCancellation()
        try data.write(to: fileURL(for: exactKey), options: .atomic)
        return RegionMaskReference(cacheKey: exactKey, size: pixels.size, quality: quality)
    }

    func pixels(for reference: RegionMaskReference) -> NormalizedMask? {
        guard let persisted = load(for: reference.cacheKey),
              persisted.key == reference.cacheKey else { return nil }
        if let values = persisted.mask.values {
            return try? NormalizedMask(size: persisted.mask.size, values: values)
        }
        guard let data = try? Data(contentsOf: binURL(for: reference.cacheKey)) else {
            return nil
        }
        guard let floats = Self.decode(data, for: persisted.mask.size) else { return nil }
        return try? NormalizedMask(size: persisted.mask.size, values: floats)
    }

    /// Remove every quality/provider variant belonging to an asset, including its binary sidecar.
    /// A missing or malformed cache entry is harmless and is left for the normal cache hygiene
    /// path; valid entries are removed atomically one file at a time.
    func remove(for assetID: PhotoAssetID) throws {
        try Task.checkCancellation()
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        for url in files where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let persisted = try? JSONDecoder().decode(PersistedMask.self, from: data),
                  persisted.key.identity.assetID
                    == PortablePhotoAssetID.compatibility(from: assetID) else { continue }
            try Task.checkCancellation()
            try FileManager.default.removeItem(at: url)
            let sidecar = url.deletingPathExtension().appendingPathExtension("bin")
            try? FileManager.default.removeItem(at: sidecar)
        }
    }

    private func load(for key: MaskCacheKey) -> PersistedMask? {
        loadMetadata(for: key)
    }

    private func loadMetadata(for key: MaskCacheKey) -> PersistedMask? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let persisted = try? JSONDecoder().decode(PersistedMask.self, from: data),
              persisted.key == key else { return nil }
        return persisted
    }

    private func fileURL(for key: MaskCacheKey) -> URL {
        directory.appendingPathComponent(Self.filename(for: key), isDirectory: false)
    }

    private func binURL(for key: MaskCacheKey) -> URL {
        directory.appendingPathComponent(Self.filename(for: key, extension: "bin"), isDirectory: false)
    }

    /// Validate only the file metadata. This keeps existence/gating lookups from faulting a
    /// full-resolution sidecar into memory while still rejecting interrupted or truncated writes.
    private func sidecarHasExpectedSize(for key: MaskCacheKey, dimensions: PixelDimensions) -> Bool {
        guard dimensions.width > 0, dimensions.height > 0 else { return false }
        let countResult = dimensions.width.multipliedReportingOverflow(by: dimensions.height)
        guard !countResult.overflow else { return false }
        let byteCountResult = countResult.partialValue.multipliedReportingOverflow(
            by: MemoryLayout<Float>.size
        )
        guard !byteCountResult.overflow,
              let attributes = try? FileManager.default.attributesOfItem(atPath: binURL(for: key).path),
              let fileSize = attributes[.size] as? NSNumber else {
            return false
        }
        return fileSize.intValue == byteCountResult.partialValue
    }

    private static func decode(_ data: Data, for dimensions: PixelDimensions) -> [Float]? {
        guard dimensions.width > 0, dimensions.height > 0 else { return nil }
        let countResult = dimensions.width.multipliedReportingOverflow(by: dimensions.height)
        guard !countResult.overflow else { return nil }
        let byteCountResult = countResult.partialValue.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
        guard !byteCountResult.overflow, data.count == byteCountResult.partialValue else { return nil }

        // Copy bytes into an owned Float array instead of binding Data's storage. Data does not
        // promise Float alignment, and the exact-size check above rejects partial sidecars.
        var values = [Float](repeating: 0, count: countResult.partialValue)
        _ = values.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination)
        }
        return values
    }

    /// Internal so the legacy-compatibility test can place a pre-sidecar file at its real location.
    static func filenameForTesting(for key: MaskCacheKey) -> String { filename(for: key) }

    private static func filename(for key: MaskCacheKey, extension ext: String = "json") -> String {
        let identity = [key.identity.cacheKey, String(describing: key.kind),
                        key.quality.rawValue, key.providerVersion]
            .joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "mask-\(digest).\(ext)"
    }

    private static func defaultDirectory() -> URL {
        KromoraStorage.applicationSupportRoot()
            .appendingPathComponent("Masks", isDirectory: true)
    }
}
