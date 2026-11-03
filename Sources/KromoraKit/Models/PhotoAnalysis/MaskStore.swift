import CryptoKit
import Foundation

/// Actor-isolated storage for rebuildable mask pixels. The directory is injectable so tests and
/// previews can use a temporary location; the production default lives in Kromora's disposable
/// cache boundary. Each quality is a separate file by construction.
///
/// Entries live in one directory per asset, so removing an asset (or a whole batch) is one
/// directory delete per asset with no scan and no decoding. Pixel payloads are a raw native-endian
/// Float32 sidecar next to a small JSON metadata file. Retention is enforced by `trim(budget:)`:
/// byte and age caps, superseded provider/source variants, and interrupted two-file writes.
/// Nothing in this directory is canonical; every entry can be regenerated from the source.
///
/// An earlier revision stored a flat directory and, before that, inlined the floats in the JSON
/// (a ~500MB document for a 60MP mask). Those files are no longer read: `trim` reclaims them
/// without opening them.
actor MaskStore {
    private struct PersistedMask: Codable, Sendable {
        let key: MaskCacheKey
        let mask: PersistedPixels
    }

    private struct PersistedPixels: Codable, Sendable {
        let size: PixelDimensions
    }

    /// Current metadata is a few hundred bytes. Anything near this size is corrupt or legacy and
    /// is treated as a miss without being read.
    private static let maxMetadataBytes: Int64 = 64 << 10
    /// 256 mega-pixels (1 GiB of Float32), well above any supported source.
    private static let maxPixelCount = 1 << 28

    private let directory: URL
    private let now: @Sendable () -> Date
    private var bytesStoredSinceTrim: Int64 = 0
    /// Metadata documents decoded, so tests can assert that deletion never decodes.
    private(set) var metadataDecodeCount = 0

    init(
        directory: URL = MaskStore.defaultDirectory(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.now = now
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Returns an exact-quality reference. A lower-quality mask is never substituted implicitly.
    /// Existence only needs the metadata file (plus the sidecar for current files), never the
    /// pixels, so gating lookups stay cheap even for full-resolution entries.
    func mask(for key: MaskCacheKey, quality: MaskQuality) -> RegionMaskReference? {
        let exactKey = key.with(quality: quality)
        guard let persisted = loadMetadata(for: exactKey),
              persisted.key == exactKey,
              sidecarHasExpectedSize(for: exactKey, dimensions: persisted.mask.size) else {
            return nil
        }
        DiskCacheIO.touch(fileURL(for: exactKey), now: now())
        return RegionMaskReference(cacheKey: persisted.key, size: persisted.mask.size, quality: quality)
    }

    @discardableResult
    func store(
        _ pixels: NormalizedMask,
        for key: MaskCacheKey,
        quality: MaskQuality
    ) throws -> RegionMaskReference {
        try Task.checkCancellation()
        let exactKey = key.with(quality: quality)
        try FileManager.default.createDirectory(
            at: assetDirectory(for: exactKey.identity.assetID), withIntermediateDirectories: true
        )
        // Sidecar first: a reader only trusts the metadata when the pixels are already there,
        // so an interrupted write degrades to a cache miss rather than a corrupt entry.
        try pixels.values.withUnsafeBytes { buffer in
            try DiskCacheIO.writeAtomically(buffer, to: binURL(for: exactKey))
        }
        try Task.checkCancellation()
        let persisted = PersistedMask(key: exactKey, mask: PersistedPixels(size: pixels.size))
        let data = try JSONEncoder().encode(persisted)
        try Task.checkCancellation()
        try DiskCacheIO.writeAtomically(data, to: fileURL(for: exactKey))
        bytesStoredSinceTrim += Int64(pixels.values.count * MemoryLayout<Float>.size + data.count)
        return RegionMaskReference(cacheKey: exactKey, size: pixels.size, quality: quality)
    }

    func pixels(for reference: RegionMaskReference) -> NormalizedMask? {
        guard let persisted = loadMetadata(for: reference.cacheKey),
              persisted.key == reference.cacheKey,
              let count = Self.pixelCount(of: persisted.mask.size),
              let floats = DiskCacheIO.floats(at: binURL(for: reference.cacheKey), count: count)
        else { return nil }
        DiskCacheIO.touch(fileURL(for: reference.cacheKey), now: now())
        return try? NormalizedMask(size: persisted.mask.size, values: floats)
    }

    /// Remove every quality/provider variant belonging to an asset, including its binary sidecar.
    /// One directory delete per asset; no entry is opened.
    func remove(for assetID: PhotoAssetID) throws {
        try remove(for: PortablePhotoAssetID.compatibility(from: assetID))
    }

    func remove(for assetID: PortablePhotoAssetID) throws {
        try remove(for: [assetID])
    }

    /// Batch form of `remove(for:)`. Cost is proportional to the number of assets removed, not to
    /// the size of the cache.
    func remove(for assetIDs: [PortablePhotoAssetID]) throws {
        for assetID in assetIDs {
            try Task.checkCancellation()
            let url = assetDirectory(for: assetID)
            do {
                try FileManager.default.removeItem(at: url)
            } catch CocoaError.fileNoSuchFile {
                continue
            }
        }
    }

    /// True once enough has been written since the last trim that a background pass is worthwhile.
    func isTrimDue(budget: DiskCacheBudget = .masks) -> Bool {
        bytesStoredSinceTrim > budget.maxBytes / 8
    }

    /// Enforces `budget` over the whole directory in one traversal. Safe to run at low priority:
    /// it yields between asset directories and checks cancellation.
    @discardableResult
    func trim(budget: DiskCacheBudget = .masks) async throws -> DiskCacheTrimReport {
        bytesStoredSinceTrim = 0
        return try await DiskCacheTrimmer.trim(
            root: directory,
            configuration: .init(prefix: "mask", requiredExtensions: ["json", "bin"], budget: budget),
            now: now()
        )
    }

    private func loadMetadata(for key: MaskCacheKey) -> PersistedMask? {
        guard let data = DiskCacheIO.boundedData(
            at: fileURL(for: key), maxBytes: Self.maxMetadataBytes
        ) else { return nil }
        metadataDecodeCount += 1
        guard let persisted = try? JSONDecoder().decode(PersistedMask.self, from: data),
              persisted.key == key else { return nil }
        return persisted
    }

    private func assetDirectory(for assetID: PortablePhotoAssetID) -> URL {
        DiskCacheIO.assetDirectory(in: directory, for: assetID)
    }

    private func fileURL(for key: MaskCacheKey) -> URL {
        assetDirectory(for: key.identity.assetID)
            .appendingPathComponent(Self.filename(for: key), isDirectory: false)
    }

    private func binURL(for key: MaskCacheKey) -> URL {
        assetDirectory(for: key.identity.assetID)
            .appendingPathComponent(Self.filename(for: key, extension: "bin"), isDirectory: false)
    }

    /// Validate only the file metadata. This keeps existence/gating lookups from faulting a
    /// full-resolution sidecar into memory while still rejecting interrupted or truncated writes.
    private func sidecarHasExpectedSize(for key: MaskCacheKey, dimensions: PixelDimensions) -> Bool {
        guard let count = Self.pixelCount(of: dimensions) else { return false }
        return DiskCacheIO.fileSize(at: binURL(for: key))
            == Int64(count * MemoryLayout<Float>.size)
    }

    /// The pixel count for sane dimensions, or nil for zero, negative, overflowing, or absurd ones.
    private static func pixelCount(of dimensions: PixelDimensions) -> Int? {
        guard dimensions.width > 0, dimensions.height > 0 else { return nil }
        let (count, overflow) = dimensions.width.multipliedReportingOverflow(by: dimensions.height)
        return overflow || count > maxPixelCount ? nil : count
    }

    /// `mask-<kind+quality>-<provider>-<digest>`: the group (kind and quality) and provider
    /// version are readable from the name, so trim can find superseded variants without opening
    /// files.
    static func entryName(for key: MaskCacheKey) -> DiskCacheEntryName {
        let identity = [key.identity.cacheKey, String(describing: key.kind),
                        key.quality.rawValue, key.providerVersion]
            .joined(separator: "\u{1f}")
        return DiskCacheEntryName(
            prefix: "mask",
            group: DiskCacheEntryName.tag(String(describing: key.kind), key.quality.rawValue),
            version: DiskCacheEntryName.tag(key.providerVersion),
            digest: SHA256.hash(data: Data(identity.utf8)).hexString
        )
    }

    private static func filename(for key: MaskCacheKey, extension ext: String = "json") -> String {
        entryName(for: key).filename(extension: ext)
    }

    private static func defaultDirectory() -> URL {
        KromoraStorage.cacheDirectory(named: "Masks")
    }
}
