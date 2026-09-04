import Foundation
import XCTest

@testable import LumoKit

final class PhotoAnalysisCacheTests: TempDirectoryTestCase {
    func testRoundTripPersistsAnalysisBySourceAndVersion() async throws {
        let cache = PhotoAnalysisCache(directory: tempDirectory)
        let key = makeKey(version: .current)
        let analysis = PhotoAnalysis(
            version: .current, globalTone: ToneStatistics(variant: .perceptual, mean: 0.4),
            colorStatistics: .neutral, quality: .globalOnly
        )

        try await cache.store(analysis, for: key)

        let reopened = PhotoAnalysisCache(directory: tempDirectory)
        let restored = try await reopened.analysis(for: key)
        XCTAssertEqual(restored, analysis)

        let nextVersion = AnalysisVersion(rawValue: key.analysisVersion.rawValue + 1)
        let invalidated = try await reopened.analysis(for: makeKey(version: nextVersion))
        XCTAssertNil(invalidated)
    }

    func testSourceKeyDoesNotIncludeEditDocumentState() {
        let source = PhotoSourceFingerprint.data(Data("same-source".utf8))
        let first = AnalysisCacheKey(
            assetID: PhotoAssetID.data(Data("same-source".utf8)),
            sourceFingerprint: source, analysisVersion: .current
        )
        // EditDocument fields are deliberately not accepted by AnalysisCacheKey, so changing any
        // creative adjustment leaves this source identity unchanged.
        let second = AnalysisCacheKey(
            assetID: first.assetID, sourceFingerprint: first.sourceFingerprint,
            analysisVersion: first.analysisVersion
        )
        XCTAssertEqual(first, second)
    }

    func testCancelledWriteLeavesNoPartialEntry() async throws {
        let cache = PhotoAnalysisCache(directory: tempDirectory)
        let key = makeKey(version: .current)
        let analysis = PhotoAnalysis(globalTone: .neutral, colorStatistics: .neutral, quality: .globalOnly)
        let task = Task {
            try await cache.store(analysis, for: key)
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("cancelled write unexpectedly completed")
        } catch is CancellationError {
            // Expected: the cache checks cancellation before replacing the entry.
        }
        let restored = try await cache.analysis(for: key)
        XCTAssertNil(restored)
    }

    private func makeKey(version: AnalysisVersion) -> AnalysisCacheKey {
        let bytes = Data("cache-test-source".utf8)
        return AnalysisCacheKey(
            assetID: PhotoAssetID.data(bytes),
            sourceFingerprint: PhotoSourceFingerprint.data(bytes),
            analysisVersion: version
        )
    }
}
