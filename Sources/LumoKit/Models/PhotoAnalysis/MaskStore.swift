import CryptoKit
import Foundation

/// Durable, actor-isolated storage for mask pixels. The directory is injectable so tests and
/// previews can use a temporary location; the production default lives beside Lumo's other
/// Application Support data. Each quality is a separate file by construction.
actor MaskStore {
    private struct PersistedMask: Codable, Sendable {
        let key: MaskCacheKey
        let mask: NormalizedMask
    }

    private let directory: URL

    init(directory: URL = MaskStore.defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns an exact-quality reference. A lower-quality mask is never substituted implicitly.
    func mask(for key: MaskCacheKey, quality: MaskQuality) -> RegionMaskReference? {
        let exactKey = key.with(quality: quality)
        guard let persisted = load(for: exactKey) else { return nil }
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
        let persisted = PersistedMask(key: exactKey, mask: pixels)
        let data = try JSONEncoder().encode(persisted)
        try Task.checkCancellation()
        try data.write(to: fileURL(for: exactKey), options: .atomic)
        return RegionMaskReference(cacheKey: exactKey, size: pixels.size, quality: quality)
    }

    func pixels(for reference: RegionMaskReference) -> NormalizedMask? {
        load(for: reference.cacheKey)?.mask
    }

    private func load(for key: MaskCacheKey) -> PersistedMask? {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let persisted = try? JSONDecoder().decode(PersistedMask.self, from: data),
              persisted.key == key else { return nil }
        return persisted
    }

    private func fileURL(for key: MaskCacheKey) -> URL {
        directory.appendingPathComponent(Self.filename(for: key), isDirectory: false)
    }

    private static func filename(for key: MaskCacheKey) -> String {
        let identity = [key.assetID.raw, key.sourceFingerprint.cacheKey,
                        String(describing: key.kind), key.quality.rawValue, key.providerVersion]
            .joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "mask-\(digest).json"
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Lumo/Masks", isDirectory: true)
    }
}
