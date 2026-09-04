import Foundation
import XCTest

@testable import LumoKit

final class SceneCharacteristicsAnalyzerTests: XCTestCase {
    func testNormalDaylightIsMidKeyWithoutStrongSceneLikelihood() {
        let subject = region(kind: .subject, mean: 0.52, coverage: 0.24, confidence: 0.85)
        let background = region(kind: .background, mean: 0.48, coverage: 0.76, confidence: 0.9)
        let analysis = makeAnalysis(
            tone: tone(mean: 0.50, p25: 0.28, p50: 0.50, p75: 0.72, p95: 0.90),
            regions: [subject, background],
            relationships: RegionRelationships(
                subjectToGlobalLuminanceDelta: 0.02,
                subjectToBackgroundLuminanceDelta: 0.04,
                subjectContrast: 0.04
            ),
            primary: subject
        )

        let scene = SceneCharacteristicsAnalyzer.analyze(analysis)

        XCTAssertEqual(scene.tonalKey, .mid)
        XCTAssertLessThan(scene.backlightingLikelihood, 0.2)
        XCTAssertLessThan(scene.highKeyLikelihood, 0.4)
        XCTAssertLessThan(scene.lowKeyLikelihood, 0.4)
    }

    func testBacklitSceneIsDetectedFromSubjectBackgroundEvidence() {
        let subject = region(kind: .person, mean: 0.22, coverage: 0.24, confidence: 0.92)
        let face = region(kind: .face, mean: 0.25, coverage: 0.04, confidence: 0.96)
        let background = region(kind: .background, mean: 0.90, coverage: 0.76, confidence: 0.9)
        let analysis = makeAnalysis(
            tone: tone(mean: 0.56, p25: 0.20, p50: 0.52, p75: 0.80, p95: 0.98),
            regions: [subject, face, background],
            relationships: RegionRelationships(
                subjectToGlobalLuminanceDelta: -0.30,
                subjectToBackgroundLuminanceDelta: -0.68,
                faceToBackgroundLuminanceDelta: -0.65,
                subjectContrast: 0.68
            ),
            primary: subject
        )

        let scene = SceneCharacteristicsAnalyzer.analyze(analysis)

        XCTAssertTrue(scene.hasFaces)
        XCTAssertTrue(scene.hasPeople)
        XCTAssertGreaterThan(scene.backlightingLikelihood, 0.35)
        XCTAssertGreaterThan(scene.backlightingLikelihood, scene.highKeyLikelihood)
        XCTAssertGreaterThan(scene.backlightingLikelihood, scene.lowKeyLikelihood)
    }

    func testHighKeySceneIsHighKeyAndLowKeySceneIsLowKey() {
        let highSubject = region(kind: .subject, mean: 0.82, coverage: 0.35, confidence: 0.9)
        let high = makeAnalysis(
            tone: tone(mean: 0.80, p25: 0.66, p50: 0.81, p75: 0.91, p95: 0.96),
            regions: [highSubject],
            relationships: .unavailable,
            primary: highSubject
        )
        let lowSubject = region(kind: .subject, mean: 0.43, coverage: 0.18, confidence: 0.9)
        let lowBackground = region(kind: .background, mean: 0.10, coverage: 0.82, confidence: 0.9)
        let low = makeAnalysis(
            tone: tone(mean: 0.20, p25: 0.05, p50: 0.18, p75: 0.35, p95: 0.60),
            regions: [lowSubject, lowBackground],
            relationships: RegionRelationships(
                subjectToBackgroundLuminanceDelta: 0.33,
                subjectContrast: 0.33
            ),
            primary: lowSubject
        )

        let highScene = SceneCharacteristicsAnalyzer.analyze(high)
        let lowScene = SceneCharacteristicsAnalyzer.analyze(low)

        XCTAssertEqual(highScene.tonalKey, .high)
        XCTAssertGreaterThan(highScene.highKeyLikelihood, highScene.lowKeyLikelihood)
        XCTAssertGreaterThan(highScene.highKeyLikelihood, 0.2)
        XCTAssertEqual(lowScene.tonalKey, .low)
        XCTAssertGreaterThan(lowScene.lowKeyLikelihood, lowScene.highKeyLikelihood)
        XCTAssertGreaterThan(lowScene.lowKeyLikelihood, 0.2)
    }

    func testSceneFactsAreBoundedAndPhotoAnalysisRoundTripsThem() throws {
        let subject = region(kind: .subject, mean: 0.5, coverage: 0.25, confidence: 0.8)
        let analysis = makeAnalysis(
            tone: tone(mean: 0.5, p25: 0.2, p50: 0.5, p75: 0.8, p95: 0.95),
            regions: [subject],
            relationships: .unavailable,
            primary: subject
        )
        let decoded = try JSONDecoder().decode(
            PhotoAnalysis.self,
            from: JSONEncoder().encode(analysis)
        )

        XCTAssertEqual(decoded, analysis)
        for value in [
            analysis.scene.subjectProminence,
            analysis.scene.subjectBackgroundSeparation,
            analysis.scene.dynamicRange,
            analysis.scene.backlightingLikelihood,
            analysis.scene.highKeyLikelihood,
            analysis.scene.lowKeyLikelihood,
        ] {
            XCTAssertTrue((0...1).contains(value))
        }
    }

    private func makeAnalysis(
        tone: ToneStatistics,
        regions: [AnalyzedRegion],
        relationships: RegionRelationships,
        primary: AnalyzedRegion
    ) -> PhotoAnalysis {
        PhotoAnalysis(
            globalTone: tone,
            colorStatistics: .neutral,
            regions: regions,
            primarySubject: PrimarySubjectSelection(
                primaryRegionID: primary.id,
                confidence: primary.confidence
            ),
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
        let key = MaskCacheKey(
            assetID: PhotoAssetID.data(Data("scene".utf8)),
            sourceFingerprint: PhotoSourceFingerprint.data(Data("scene".utf8)),
            kind: kind
        )
        let reference = RegionMaskReference(
            cacheKey: key,
            size: PixelDimensions(width: 1, height: 1)
        )
        return AnalyzedRegion(
            id: UUID(),
            kind: kind,
            mask: reference,
            bounds: NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.5),
            confidence: confidence,
            importance: confidence * coverage,
            tone: tone(mean: mean, p25: mean, p50: mean, p75: mean, p95: mean),
            color: .neutral,
            coverage: coverage
        )
    }

    private func tone(
        mean: Float,
        p25: Float,
        p50: Float,
        p75: Float,
        p95: Float
    ) -> ToneStatistics {
        ToneStatistics(
            variant: .perceptual,
            minimum: p25,
            maximum: p95,
            mean: mean,
            p25: p25,
            p50: p50,
            p75: p75,
            p95: p95
        )
    }
}
