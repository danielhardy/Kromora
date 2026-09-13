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

/// Small, durable storage for scalar `PhotoAnalysis` values.
///
/// Mask pixels remain owned by `MaskStore`; this cache only stores the inexpensive facts and
/// references needed to rebuild an analysis result. Each key gets its own atomically replaced JSON
/// file, so a failed or cancelled write cannot leave a partially written entry behind.
actor PhotoAnalysisCache {
    private struct PersistedAnalysis: Codable, Sendable, Equatable {
        let key: AnalysisCacheKey
        let analysis: PhotoAnalysis
    }

    private let directory: URL

    init(directory: URL = PhotoAnalysisCache.defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Reads an exact key. A missing, malformed, or stale entry is a cache miss rather than a
    /// failure of photo analysis.
    func analysis(for key: AnalysisCacheKey) throws -> PhotoAnalysis? {
        try Task.checkCancellation()
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        try Task.checkCancellation()
        guard let persisted = try? JSONDecoder().decode(PersistedAnalysis.self, from: data),
              persisted.key == key,
              persisted.analysis.version == key.analysisVersion else {
            return nil
        }
        return persisted.analysis
    }

    /// Stores one analysis using an atomic replacement. Cancellation is checked before the file
    /// operation so a cancelled write cannot replace a previously valid entry.
    func store(_ analysis: PhotoAnalysis, for key: AnalysisCacheKey) throws {
        try Task.checkCancellation()
        guard analysis.version == key.analysisVersion else {
            throw PhotoAnalysisCacheError.versionMismatch(
                expected: key.analysisVersion, actual: analysis.version
            )
        }
        let data = try JSONEncoder().encode(PersistedAnalysis(key: key, analysis: analysis))
        try Task.checkCancellation()
        try data.write(to: fileURL(for: key), options: .atomic)
    }

    /// Remove all analysis entries for an asset. Cache cleanup is keyed by the asset rather than
    /// by the current source fingerprint because a source may have been edited or relinked since
    /// an older analysis was written.
    func remove(for assetID: PhotoAssetID) throws {
        try Task.checkCancellation()
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        for url in files where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let persisted = try? JSONDecoder().decode(PersistedAnalysis.self, from: data),
                  (persisted.key.assetID == assetID
                    || persisted.key.identity.assetID
                        == PortablePhotoAssetID.compatibility(from: assetID)) else { continue }
            try Task.checkCancellation()
            try FileManager.default.removeItem(at: url)
        }
    }

    func remove(for assetID: PortablePhotoAssetID) throws {
        try Task.checkCancellation()
        let files = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        for url in files where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let persisted = try? JSONDecoder().decode(PersistedAnalysis.self, from: data),
                  persisted.key.identity.assetID == assetID else { continue }
            try Task.checkCancellation()
            try FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for key: AnalysisCacheKey) -> URL {
        directory.appendingPathComponent(Self.filename(for: key), isDirectory: false)
    }

    private static func filename(for key: AnalysisCacheKey) -> String {
        let identity = "\(key.identity.cacheKey)|\(key.analysisVersion.rawValue)"
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "analysis-\(digest).json"
    }

    private static func defaultDirectory() -> URL {
        KromoraStorage.applicationSupportRoot()
            .appendingPathComponent("PhotoAnalysis", isDirectory: true)
    }
}
