import CryptoKit
import Foundation

/// The identity of one persisted source analysis.
///
/// Creative edits are intentionally absent. Analysis describes the decoded/oriented source image,
/// so changing Light, Color, a LUT, or any other EditDocument field must not create a new entry or
/// cause Auto to analyze its own output.
struct AnalysisCacheKey: Sendable, Codable, Hashable, Equatable {
    /// The only identity written to a new analysis entry. Legacy projections below exist for
    /// source-compatible callers and are excluded from equality, hashing, and encoding.
    let identity: PortablePhotoIdentity
    let analysisVersion: AnalysisVersion

    private var legacyAssetID: PhotoAssetID?
    private var legacySourceFingerprint: PhotoSourceFingerprint?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity && lhs.analysisVersion == rhs.analysisVersion
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
        hasher.combine(analysisVersion)
    }

    var assetID: PhotoAssetID {
        legacyAssetID ?? PhotoAssetID(rawValue: "portable:\(identity.assetID.raw)")
    }

    var sourceFingerprint: PhotoSourceFingerprint {
        legacySourceFingerprint ?? PhotoSourceFingerprint.data(
            Data(identity.sourceFingerprint.contentHash.utf8),
            digest: identity.sourceFingerprint.contentHash
        )
    }

    private enum CodingKeys: String, CodingKey {
        case identity, assetID, sourceFingerprint, analysisVersion
    }

    init(
        identity: PortablePhotoIdentity,
        analysisVersion: AnalysisVersion
    ) {
        self.identity = identity
        self.analysisVersion = analysisVersion
        self.legacyAssetID = nil
        self.legacySourceFingerprint = nil
    }

    init(
        assetID: PhotoAssetID,
        sourceFingerprint: PhotoSourceFingerprint,
        analysisVersion: AnalysisVersion
    ) {
        self.identity = PortablePhotoIdentity.compatibility(
            assetID: assetID, sourceFingerprint: sourceFingerprint
        )
        self.analysisVersion = analysisVersion
        self.legacyAssetID = assetID
        self.legacySourceFingerprint = sourceFingerprint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let identity = try container.decodeIfPresent(
            PortablePhotoIdentity.self, forKey: .identity
        ) {
            self.identity = identity
            self.legacyAssetID = nil
            self.legacySourceFingerprint = nil
        } else {
            let assetID = try container.decode(PhotoAssetID.self, forKey: .assetID)
            let sourceFingerprint = try container.decode(
                PhotoSourceFingerprint.self, forKey: .sourceFingerprint
            )
            self.identity = PortablePhotoIdentity.compatibility(
                assetID: assetID, sourceFingerprint: sourceFingerprint
            )
            self.legacyAssetID = nil
            self.legacySourceFingerprint = nil
        }
        self.analysisVersion = try container.decode(AnalysisVersion.self, forKey: .analysisVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(identity, forKey: .identity)
        try container.encode(analysisVersion, forKey: .analysisVersion)
    }
}

enum PhotoAnalysisCacheError: Error, Sendable, Equatable {
    case versionMismatch(expected: AnalysisVersion, actual: AnalysisVersion)
}

/// A stored analysis with the stage coverage it was computed with. `coverage` is `nil` for an entry
/// written before coverage was recorded; the coordinator treats that as a miss.
struct PhotoAnalysisCacheEntry: Sendable, Equatable {
    let analysis: PhotoAnalysis
    let coverage: PhotoAnalysisCoverage?
}

/// Small, disposable storage for scalar `PhotoAnalysis` values.
///
/// Mask pixels remain owned by `MaskStore`; this cache only stores the inexpensive facts and
/// references needed to rebuild an analysis result. Each key gets its own atomically replaced JSON
/// file inside a per-asset directory, so a failed or cancelled write cannot leave a partially
/// written entry, and removing an asset (or a batch) is a directory delete with no scan or decode.
/// `trim(budget:)` enforces byte and age caps and drops entries of any other analysis version.
actor PhotoAnalysisCache {
    private struct PersistedAnalysis: Codable, Sendable, Equatable {
        let key: AnalysisCacheKey
        let analysis: PhotoAnalysis
        /// Absent in entries written before stage coverage was persisted.
        let coverage: PhotoAnalysisCoverage?
    }

    /// A stored analysis is scalar facts plus region references; anything larger is corrupt.
    private static let maxEntryBytes: Int64 = 4 << 20

    private let directory: URL
    private let now: @Sendable () -> Date
    private var bytesStoredSinceTrim: Int64 = 0
    /// Entry documents decoded, so tests can assert that deletion never decodes.
    private(set) var decodeCount = 0

    init(
        directory: URL = PhotoAnalysisCache.defaultDirectory(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.now = now
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Reads an exact key. A missing, malformed, or stale entry is a cache miss rather than a
    /// failure of photo analysis.
    func analysis(for key: AnalysisCacheKey) throws -> PhotoAnalysis? {
        try entry(for: key)?.analysis
    }

    /// Like `analysis(for:)`, with the stage coverage the entry was stored with.
    func entry(for key: AnalysisCacheKey) throws -> PhotoAnalysisCacheEntry? {
        try Task.checkCancellation()
        let url = fileURL(for: key)
        guard let data = DiskCacheIO.boundedData(at: url, maxBytes: Self.maxEntryBytes) else {
            return nil
        }
        try Task.checkCancellation()
        decodeCount += 1
        guard let persisted = try? JSONDecoder().decode(PersistedAnalysis.self, from: data),
              persisted.key == key,
              persisted.analysis.version == key.analysisVersion else {
            return nil
        }
        DiskCacheIO.touch(url, now: now())
        return PhotoAnalysisCacheEntry(analysis: persisted.analysis, coverage: persisted.coverage)
    }

    /// Stores one analysis using an atomic replacement. Cancellation is checked before the file
    /// operation so a cancelled write cannot replace a previously valid entry.
    func store(
        _ analysis: PhotoAnalysis, coverage: PhotoAnalysisCoverage? = nil, for key: AnalysisCacheKey
    ) throws {
        try Task.checkCancellation()
        guard analysis.version == key.analysisVersion else {
            throw PhotoAnalysisCacheError.versionMismatch(
                expected: key.analysisVersion, actual: analysis.version
            )
        }
        let data = try JSONEncoder().encode(PersistedAnalysis(key: key, analysis: analysis, coverage: coverage))
        try Task.checkCancellation()
        try FileManager.default.createDirectory(
            at: assetDirectory(for: key.identity.assetID), withIntermediateDirectories: true
        )
        try DiskCacheIO.writeAtomically(data, to: fileURL(for: key))
        bytesStoredSinceTrim += Int64(data.count)
    }

    /// Remove all analysis entries for an asset. Cache cleanup is keyed by the asset rather than
    /// by the current source fingerprint because a source may have been edited or relinked since
    /// an older analysis was written.
    func remove(for assetID: PhotoAssetID) throws {
        try remove(for: PortablePhotoAssetID.compatibility(from: assetID))
    }

    func remove(for assetID: PortablePhotoAssetID) throws {
        try remove(for: [assetID])
    }

    /// Batch form of `remove(for:)`: one directory delete per asset, independent of cache size.
    func remove(for assetIDs: [PortablePhotoAssetID]) throws {
        for assetID in assetIDs {
            try Task.checkCancellation()
            do {
                try FileManager.default.removeItem(at: assetDirectory(for: assetID))
            } catch CocoaError.fileNoSuchFile {
                continue
            }
        }
    }

    /// True once enough has been written since the last trim that a background pass is worthwhile.
    func isTrimDue(budget: DiskCacheBudget = .analysis) -> Bool {
        bytesStoredSinceTrim > budget.maxBytes / 8
    }

    /// Enforces `budget` and drops entries written by any other `AnalysisVersion`.
    @discardableResult
    func trim(budget: DiskCacheBudget = .analysis) async throws -> DiskCacheTrimReport {
        bytesStoredSinceTrim = 0
        return try await DiskCacheTrimmer.trim(
            root: directory,
            configuration: .init(
                prefix: "analysis", requiredExtensions: ["json"], budget: budget,
                liveVersion: Self.versionTag(.current)
            ),
            now: now()
        )
    }

    private func assetDirectory(for assetID: PortablePhotoAssetID) -> URL {
        DiskCacheIO.assetDirectory(in: directory, for: assetID)
    }

    private func fileURL(for key: AnalysisCacheKey) -> URL {
        assetDirectory(for: key.identity.assetID)
            .appendingPathComponent(Self.filename(for: key), isDirectory: false)
    }

    private static func versionTag(_ version: AnalysisVersion) -> String {
        "v\(version.rawValue)"
    }

    static func entryName(for key: AnalysisCacheKey) -> DiskCacheEntryName {
        let identity = "\(key.identity.cacheKey)|\(key.analysisVersion.rawValue)"
        return DiskCacheEntryName(
            prefix: "analysis", group: "a", version: versionTag(key.analysisVersion),
            digest: SHA256.hash(data: Data(identity.utf8)).hexString
        )
    }

    private static func filename(for key: AnalysisCacheKey) -> String {
        entryName(for: key).filename(extension: "json")
    }

    private static func defaultDirectory() -> URL {
        KromoraStorage.cacheDirectory(named: "PhotoAnalysis")
    }
}
