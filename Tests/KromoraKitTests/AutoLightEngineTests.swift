import Foundation
import XCTest

@testable import KromoraKit

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

        XCTAssertGreaterThanOrEqual(result.light.exposure, 0)
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

    func testExposureRationaleIncludesFormattedMedian() {
        let analysis = makeAnalysis(
            tone: tone(mean: 0.32, p25: 0.12, p50: 0.30, p75: 0.58, p95: 0.92)
        )

        let explanation = AutoLightEngine.evaluate(analysis: analysis)
            .rationale.exposure.explanation

        XCTAssertEqual(
            explanation,
            "Median (0.30) EV correction, restrained by tonal-key intent."
        )
    }

    func testCorpusTuningKeepsCategoryAdjustmentsWithinGoldenRanges() {
        let daylight = makeAnalysis(
            tone: tone(mean: 0.50, p05: 0.08, p25: 0.28, p50: 0.50, p75: 0.72, p95: 0.90),
            regions: [region(kind: .subject, mean: 0.52, coverage: 0.24, confidence: 0.92)]
        )
        let highKeySubject = region(kind: .subject, mean: 0.82, coverage: 0.24, confidence: 0.92)
        let highKey = makeAnalysis(
            tone: tone(mean: 0.80, p05: 0.50, p25: 0.66, p50: 0.81, p75: 0.91, p95: 0.96),
            regions: [highKeySubject], primary: highKeySubject
        )
        let lowKeySubject = region(kind: .subject, mean: 0.43, coverage: 0.24, confidence: 0.92)
        let lowKey = makeAnalysis(
            tone: tone(mean: 0.20, p05: 0.01, p25: 0.05, p50: 0.18, p75: 0.35, p95: 0.60),
            regions: [lowKeySubject],
            relationships: RegionRelationships(subjectContrast: 0.33),
            primary: lowKeySubject
        )

        let daylightResult = AutoLightEngine.evaluate(analysis: daylight).light
        let highKeyResult = AutoLightEngine.evaluate(analysis: highKey).light
        let lowKeyResult = AutoLightEngine.evaluate(analysis: lowKey).light

        XCTAssertEqual(AutoLightEngine.evaluate(analysis: daylight).algorithmVersion, 2)
        XCTAssertGreaterThanOrEqual(daylightResult.exposure, -0.2)
        XCTAssertLessThanOrEqual(daylightResult.exposure, 0.2)
        XCTAssertGreaterThanOrEqual(daylightResult.contrast, -4)
        XCTAssertLessThanOrEqual(daylightResult.contrast, 4)
        XCTAssertGreaterThanOrEqual(daylightResult.shadows, 0)
        XCTAssertLessThanOrEqual(daylightResult.shadows, 12)
        XCTAssertGreaterThanOrEqual(daylightResult.highlights, -16)
        XCTAssertLessThanOrEqual(daylightResult.highlights, 0)

        XCTAssertLessThan(abs(highKeyResult.exposure), 0.5)
        XCTAssertGreaterThanOrEqual(highKeyResult.blacks, -12)
        XCTAssertLessThanOrEqual(highKeyResult.blacks, 0)
        XCTAssertGreaterThanOrEqual(highKeyResult.highlights, -12)
        XCTAssertLessThanOrEqual(highKeyResult.highlights, 0)

        XCTAssertLessThan(abs(lowKeyResult.exposure), 0.35)
        XCTAssertGreaterThanOrEqual(lowKeyResult.shadows, 0)
        XCTAssertLessThanOrEqual(lowKeyResult.shadows, 12)
        XCTAssertGreaterThanOrEqual(lowKeyResult.whites, 0)
        XCTAssertLessThanOrEqual(lowKeyResult.whites, 14)
    }

    func testCorpusTuningRetainsClippingProtection() {
        let clippedHighlights = makeAnalysis(
            tone: tone(
                mean: 0.60, p05: 0.12, p25: 0.35, p50: 0.58, p75: 0.76, p95: 1.0,
                highlightClippingFraction: 0.08
            ),
            regions: [region(kind: .subject, mean: 0.55, coverage: 0.24, confidence: 0.92)]
        )
        let clippedShadows = makeAnalysis(
            tone: tone(mean: 0.38, p05: 0, p25: 0.12, p50: 0.36, p75: 0.62, p95: 0.88),
            regions: [region(kind: .subject, mean: 0.42, coverage: 0.24, confidence: 0.92)]
        )

        let highlightResult = AutoLightEngine.evaluate(analysis: clippedHighlights).light
        let shadowResult = AutoLightEngine.evaluate(analysis: clippedShadows).light

        XCTAssertLessThanOrEqual(highlightResult.highlights, -18)
        XCTAssertGreaterThanOrEqual(highlightResult.highlights, -34)
        XCTAssertGreaterThanOrEqual(shadowResult.shadows, 6)
        XCTAssertLessThanOrEqual(shadowResult.shadows, 14)
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
        mean: Float, p05: Float = 0, p25: Float, p50: Float, p75: Float, p95: Float,
        highlightClippingFraction: Float = 0, shadowClippingFraction: Float = 0
    ) -> ToneStatistics {
        ToneStatistics(
            variant: .perceptual, minimum: p05, maximum: p95, mean: mean,
            p05: p05, p25: p25, p50: p50, p75: p75, p95: p95,
            shadowClippingFraction: shadowClippingFraction,
            highlightClippingFraction: highlightClippingFraction
        )
    }
}
