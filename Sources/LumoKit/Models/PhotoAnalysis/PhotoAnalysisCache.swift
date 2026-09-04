import CryptoKit
import Foundation

/// The identity of one persisted source analysis.
///
/// Creative edits are intentionally absent. Analysis describes the decoded/oriented source image,
/// so changing Light, Color, a LUT, or any other EditDocument field must not create a new entry or
/// cause Auto to analyze its own output.
struct AnalysisCacheKey: Sendable, Codable, Hashable, Equatable {
    let assetID: PhotoAssetID
    let sourceFingerprint: PhotoSourceFingerprint
    let analysisVersion: AnalysisVersion
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

    private func fileURL(for key: AnalysisCacheKey) -> URL {
        directory.appendingPathComponent(Self.filename(for: key), isDirectory: false)
    }

    private static func filename(for key: AnalysisCacheKey) -> String {
        let identity = "\(key.assetID.raw)|\(key.sourceFingerprint.cacheKey)|\(key.analysisVersion.rawValue)"
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "analysis-\(digest).json"
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Lumo/PhotoAnalysis", isDirectory: true)
    }
}
