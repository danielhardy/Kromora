import Foundation
import XCTest

@testable import LumoKit

final class AutoLightEngineTests: XCTestCase {
    func testAllEvaluatorsProduceBoundedProposals() {
        let analysis = makeAnalysis(
            tone: tone(mean: 0.32, p25: 0.12, p50: 0.30, p75: 0.58, p95: 0.92)
        )

        let proposals = AutoLightEngine.proposals(analysis: analysis)

        XCTAssertEqual(Set(proposals.map(\.parameter)), Set(AutoLightParameter.allCases))
        for proposal in proposals {
            XCTAssertTrue(proposal.preferred.isFinite)
            XCTAssertTrue(proposal.minimum.isFinite)
            XCTAssertTrue(proposal.maximum.isFinite)
            XCTAssertTrue(proposal.minimum <= proposal.maximum)
            XCTAssertTrue((0...1).contains(proposal.confidence))
        }
    }

    func testBacklitAnalysisLiftsShadowsAndProtectsHighlights() {
        let subject = region(kind: .person, mean: 0.20, coverage: 0.25, confidence: 0.95)
        let face = region(kind: .face, mean: 0.24, coverage: 0.04, confidence: 0.95)
        let background = region(kind: .background, mean: 0.90, coverage: 0.75, confidence: 0.95)
        let analysis = makeAnalysis(
            tone: tone(mean: 0.52, p25: 0.16, p50: 0.50, p75: 0.82, p95: 0.98),
            regions: [subject, face, background],
            relationships: RegionRelationships(
                subjectToBackgroundLuminanceDelta: -0.70,
                subjectContrast: 0.70
            ),
            primary: subject
        )

        let result = AutoLightEngine.evaluate(analysis: analysis)

        XCTAssertGreaterThan(result.light.shadows, 0)
        XCTAssertLessThan(result.light.highlights, 0)
        XCTAssertEqual(result.algorithmVersion, AutoLightConfiguration.currentVersion)
        XCTAssertFalse(result.rationale.shadows.explanation.isEmpty)
    }

    func testTonalIntentKeepsHighAndLowKeyNearTheirOriginalKey() {
        let highSubject = region(kind: .subject, mean: 0.82, coverage: 0.35, confidence: 0.9)
        let high = makeAnalysis(
            tone: tone(mean: 0.80, p25: 0.66, p50: 0.81, p75: 0.91, p95: 0.96),
            regions: [highSubject], primary: highSubject
        )
        let lowSubject = region(kind: .subject, mean: 0.36, coverage: 0.2, confidence: 0.9)
        let low = makeAnalysis(
            tone: tone(mean: 0.20, p25: 0.05, p50: 0.18, p75: 0.35, p95: 0.60),
            regions: [lowSubject],
            relationships: RegionRelationships(subjectContrast: 0.32),
            primary: lowSubject
        )

        let highResult = AutoLightEngine.evaluate(analysis: high)
        let lowResult = AutoLightEngine.evaluate(analysis: low)

        XCTAssertLessThan(abs(highResult.light.exposure), 0.5)
        XCTAssertLessThan(abs(lowResult.light.exposure), 0.5)
        XCTAssertGreaterThan(highResult.rationale.exposure.confidence, 0)
        XCTAssertGreaterThan(lowResult.rationale.exposure.confidence, 0)
    }

    func testAlreadyGoodImageProducesNearZeroExposureAndContrast() {
        let subject = region(kind: .subject, mean: 0.48, coverage: 0.3, confidence: 0.9)
        let analysis = makeAnalysis(
            tone: tone(mean: 0.48, p05: 0.08, p25: 0.12, p50: 0.48, p75: 0.84, p95: 0.88),
            regions: [subject], primary: subject
        )

        let result = AutoLightEngine.evaluate(analysis: analysis)

        XCTAssertLessThan(abs(result.light.exposure), 0.05)
        XCTAssertLessThan(abs(result.light.contrast), 6)
    }

    private func makeAnalysis(
        tone: ToneStatistics,
        regions: [AnalyzedRegion] = [],
        relationships: RegionRelationships = .unavailable,
        primary: AnalyzedRegion? = nil
    ) -> PhotoAnalysis {
        let selection = primary.map {
            PrimarySubjectSelection(primaryRegionID: $0.id, confidence: $0.confidence)
        } ?? .none
        return PhotoAnalysis(
            globalTone: tone,
            colorStatistics: .neutral,
            regions: regions,
            primarySubject: selection,
            relationships: relationships,
            quality: AnalysisQuality(globalToneAvailable: true, overallConfidence: 1)
        )
    }

    private func region(
        kind: RegionKind,
        mean: Float,
        coverage: Float,
        confidence: Float
    ) -> AnalyzedRegion {
        let data = Data("auto-light".utf8)
        let key = MaskCacheKey(
            assetID: PhotoAssetID.data(data),
            sourceFingerprint: PhotoSourceFingerprint.data(data),
            kind: kind
        )
        return AnalyzedRegion(
            id: UUID(), kind: kind,
            mask: RegionMaskReference(cacheKey: key, size: PixelDimensions(width: 1, height: 1)),
            bounds: NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.5),
            confidence: confidence, importance: confidence * coverage,
            tone: tone(mean: mean, p25: mean, p50: mean, p75: mean, p95: mean),
            color: .neutral, coverage: coverage
        )
    }

    private func tone(
        mean: Float, p05: Float = 0, p25: Float, p50: Float, p75: Float, p95: Float
    ) -> ToneStatistics {
        ToneStatistics(
            variant: .perceptual, minimum: p05, maximum: p95, mean: mean,
            p05: p05, p25: p25, p50: p50, p75: p75, p95: p95
        )
    }
}
