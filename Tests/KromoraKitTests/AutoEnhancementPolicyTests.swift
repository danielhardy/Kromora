import Foundation
import XCTest

@testable import KromoraKit

/// Pure unit tests for the coordinated `AutoEnhancementPolicy` (KRMA-345).
///
/// All assertions use ranges/invariants, never exact floating-point equality: the policy is
/// deterministic (same facts twice give the same proposal), but its tuning constants are free
/// to move with a version bump.
final class AutoEnhancementPolicyTests: XCTestCase {
    // MARK: - Helpers

    private func facts(
        median: Float = 0.48,
        p05: Float = 0.08,
        p10: Float = 0.16,
        p25: Float = 0.30,
        p50: Float? = nil,
        p75: Float = 0.68,
        p90: Float = 0.85,
        p95: Float = 0.90,
        highlightClipping: Float = 0,
        shadowClipping: Float = 0,
        meanRGB: SIMD3<Float> = SIMD3(0.48, 0.48, 0.48),
        medianRGB: SIMD3<Float>? = nil,
        saturationMedian: Float = 0.15,
        saturationP95: Float = 0.5,
        colorfulness: Float = 0.3,
        neutrality: Float = 0.5,
        mixed: Bool = false,
        neutralCandidates: [NeutralCandidate] = [],
        scene: SceneCharacteristics = SceneCharacteristics(),
        sceneConfidence: Float = 0.9,
        colorNeutral: Float = 0.8,
        detailAvailable: Bool = false,
        asShotTemperature: Double? = nil,
        asShotTint: Double? = nil
    ) -> AutoEnhancementFacts {
        let tone = ToneStatistics(
            variant: .perceptual, minimum: p05, maximum: p95, mean: median,
            p05: p05, p10: p10, p25: p25, p50: p50 ?? median, p75: p75,
            p90: p90, p95: p95,
            shadowClippingFraction: shadowClipping,
            highlightClippingFraction: highlightClipping
        )
        let color = PixelCorrelatedColor(
            meanRGB: meanRGB,
            medianRGB: medianRGB ?? meanRGB,
            saturationMedian: saturationMedian,
            saturationP95: saturationP95,
            estimatedNeutrality: neutrality,
            colorfulness: colorfulness,
            isMixed: mixed,
            neutralCandidates: neutralCandidates
        )
        return AutoEnhancementFacts(
            tonePerceptual: tone,
            color: color,
            scene: scene,
            signalConfidence: AutoSignalConfidence(
                globalTone: 1, colorNeutral: colorNeutral, scene: sceneConfidence,
                subjectRegions: 0.5, overall: 0.8
            ),
            detailAvailable: detailAvailable,
            asShotTemperature: asShotTemperature,
            asShotTint: asShotTint
        )
    }

    private func neutralCandidate(confidence: Float) -> NeutralCandidate {
        NeutralCandidate(
            column: 1, row: 1,
            bounds: NormalizedRect(x: 1 / 3, y: 1 / 3, width: 1 / 3, height: 1 / 3),
            coverage: 0.2, meanChroma: 0.02, meanLuma: 0.5,
            confidence: confidence, recommendsCorrection: confidence >= 0.5
        )
    }

    private func warmCastFacts(
        strength: Float = 0.08,
        neutralConfidence: Float = 0.8,
        scene: SceneCharacteristics = SceneCharacteristics(),
        asShot: Double? = 5500
    ) -> AutoEnhancementFacts {
        facts(
            meanRGB: SIMD3(0.55, 0.47, 0.55 - strength),
            medianRGB: SIMD3(0.54, 0.47, 0.54 - strength),
            neutralCandidates: [neutralCandidate(confidence: neutralConfidence)],
            scene: scene,
            asShotTemperature: asShot
        )
    }

    // MARK: - Purity and shape

    func testProposalIsDeterministicAndPure() {
        let input = warmCastFacts()
        let first = AutoEnhancementPolicy.propose(
            facts: input, current: EditDocument(), sourceKind: .standard
        )
        let second = AutoEnhancementPolicy.propose(
            facts: input, current: EditDocument(), sourceKind: .standard
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.algorithmVersion, AutoEnhancementPolicy.algorithmVersion)
    }

    func testBalancedImageStaysCloseToUnchanged() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(), current: EditDocument(), sourceKind: .standard
        )
        // Corpus-aligned golden bounds for a daylight frame: a balanced image earns only a
        // small refinement, never a large correction (cf. AutoLightEngineTests golden ranges).
        for change in proposal.changes.values {
            switch change.control {
            case .exposure: XCTAssertLessThan(abs(change.proposed), 0.3)
            case .contrast, .highlights, .shadows, .whites, .blacks:
                XCTAssertLessThan(abs(change.proposed), 16)
            case .temperature: XCTAssertLessThan(abs(change.proposed - 6500), 400)
            case .tint, .vibrance, .saturation, .dehaze:
                XCTAssertLessThan(abs(change.proposed), 12)
            }
        }
    }

    func testZeroConfidenceFactsYieldNoOp() {
        // Graceful degradation: with no usable signals the policy records evidence and
        // changes nothing. Strict repeat-invocation no-op lives in the coordinator (KRMA-349).
        var input = facts()
        input.signalConfidence = AutoSignalConfidence(
            globalTone: 0, colorNeutral: 0, scene: 0,
            subjectRegions: 0, overall: 0
        )
        let proposal = AutoEnhancementPolicy.propose(
            facts: input, current: EditDocument(), sourceKind: .standard
        )
        XCTAssertTrue(proposal.isNoOp)
        XCTAssertEqual(proposal.document, EditDocument())
    }

    // MARK: - Exposure-first coordination

    func testUnderexposedFrameLiftsExposureWithRestrainedTails() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(median: 0.22, p05: 0.01, p10: 0.04, p25: 0.10, p50: 0.22, p75: 0.38, p90: 0.55, p95: 0.62),
            current: EditDocument(), sourceKind: .standard
        )
        let exposure = proposal.changes[.exposure]?.proposed ?? 0
        XCTAssertGreaterThan(exposure, 0.5)
        XCTAssertLessThanOrEqual(
            exposure, AutoExposureObjective.structurallyUnderexposedCorrectionCapEV
        )
        // Tails correct the residual, never the full independent defect: bounded well inside
        // the model ranges even for a two-stop error.
        XCTAssertLessThan(abs(proposal.changes[.shadows]?.proposed ?? 0), 20)
        XCTAssertLessThan(abs(proposal.changes[.whites]?.proposed ?? 0), 18)
        XCTAssertLessThan(abs(proposal.changes[.blacks]?.proposed ?? 0), 18)
    }

    func testStructuredUnderexposureOverridesLowKeyBrake() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(
                median: 0.20, p05: 0.01, p10: 0.04, p25: 0.10,
                p75: 0.36, p90: 0.52, p95: 0.60,
                scene: SceneCharacteristics(lowKeyLikelihood: 0.9)
            ),
            current: EditDocument(), sourceKind: .standard
        )
        XCTAssertGreaterThan(
            proposal.changes[.exposure]?.proposed ?? 0, 0.8,
            "broad tonal structure contradicts a low-key classification"
        )
        XCTAssertLessThanOrEqual(
            proposal.changes[.exposure]?.proposed ?? 0,
            AutoExposureObjective.structurallyUnderexposedCorrectionCapEV
        )
    }

    func testRAWUsesTheSameNeutralObjectiveAndBoundedLift() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(
                median: 0.14, p05: 0.005, p10: 0.02, p25: 0.07,
                p75: 0.30, p90: 0.50, p95: 0.64,
                asShotTemperature: 5200
            ),
            current: EditDocument(), sourceKind: .raw
        )
        let exposure = proposal.changes[.exposure]?.proposed ?? 0
        XCTAssertGreaterThan(exposure, 1.0)
        XCTAssertLessThanOrEqual(
            exposure, AutoExposureObjective.structurallyUnderexposedCorrectionCapEV
        )
    }

    func testClippedHighlightsRecoverWithoutExposureLift() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(
                median: 0.60, p75: 0.80, p90: 0.95, p95: 1.0,
                highlightClipping: 0.08
            ),
            current: EditDocument(), sourceKind: .standard
        )
        let highlights = proposal.changes[.highlights]?.proposed ?? 0
        XCTAssertLessThanOrEqual(highlights, -18)
        XCTAssertGreaterThanOrEqual(highlights, -38)
        XCTAssertLessThanOrEqual(proposal.changes[.exposure]?.proposed ?? 0, 0.3)
    }

    func testUserEditedControlsAreRestrainedNotOverwritten() {
        var edited = EditDocument()
        edited.light.exposure = 1.0
        edited.light.shadows = 20
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(median: 0.22, p05: 0.01, p10: 0.04, p25: 0.10, p50: 0.22, p75: 0.38, p90: 0.55, p95: 0.62),
            current: edited, sourceKind: .standard
        )
        // Existing user edits move at most half strength toward the new target.
        let exposure = proposal.changes[.exposure]?.proposed ?? edited.light.exposure
        XCTAssertLessThanOrEqual(abs(exposure - 1.0), 0.65)
        // A control past half its model range is left alone entirely.
        var extreme = EditDocument()
        extreme.light.shadows = 80
        let restrained = AutoEnhancementPolicy.propose(
            facts: facts(median: 0.22, p05: 0.01, p10: 0.04, p25: 0.10, p50: 0.22, p75: 0.38, p90: 0.55, p95: 0.62),
            current: extreme, sourceKind: .standard
        )
        XCTAssertNil(restrained.changes[.shadows])
        XCTAssertEqual(restrained.document.light.shadows, 80)
    }

    // MARK: - White balance direction and gating

    func testWarmCastMovesStandardAndRAWTemperaturesInOppositeDirections() {
        let standard = AutoEnhancementPolicy.propose(
            facts: warmCastFacts(), current: EditDocument(), sourceKind: .standard
        )
        let raw = AutoEnhancementPolicy.propose(
            facts: warmCastFacts(), current: EditDocument(), sourceKind: .raw
        )
        let standardTemp = standard.changes[.temperature]?.proposed
        let rawTemp = raw.changes[.temperature]?.proposed
        XCTAssertNotNil(standardTemp)
        XCTAssertNotNil(rawTemp)
        // A warm cast needs cooling: the standard node is inverted (raising cools) while the
        // RAW knob is photographic (lowering cools).
        XCTAssertGreaterThan(standardTemp!, 6500)
        XCTAssertLessThan(rawTemp!, 5500)
        // Tint runs the same way on both paths.
        XCTAssertEqual(
            (standard.changes[.tint]?.proposed ?? 0).sign,
            (raw.changes[.tint]?.proposed ?? 0).sign
        )
    }

    func testEstimatorAgreementWithoutNeutralCandidateStillCorrects() {
        // No neutral region, but mean and median independently see the same warm cast.
        let input = facts(
            meanRGB: SIMD3(0.56, 0.47, 0.44),
            medianRGB: SIMD3(0.55, 0.47, 0.45),
            neutralCandidates: []
        )
        let proposal = AutoEnhancementPolicy.propose(
            facts: input, current: EditDocument(), sourceKind: .standard
        )
        XCTAssertNotNil(proposal.changes[.temperature])
    }

    func testDisagreeingEstimatorsWithoutNeutralEvidenceSkipWB() {
        let input = facts(
            meanRGB: SIMD3(0.56, 0.47, 0.44),
            medianRGB: SIMD3(0.44, 0.47, 0.56),
            neutralCandidates: []
        )
        let proposal = AutoEnhancementPolicy.propose(
            facts: input, current: EditDocument(), sourceKind: .standard
        )
        XCTAssertNil(proposal.changes[.temperature])
        XCTAssertNil(proposal.changes[.tint])
    }

    func testWeakNeutralPreservesSunsetWarmth() {
        let sunset = SceneCharacteristics(sunsetWarmLikelihood: 0.8)
        let proposal = AutoEnhancementPolicy.propose(
            facts: warmCastFacts(neutralConfidence: 0.55, scene: sunset),
            current: EditDocument(), sourceKind: .standard
        )
        XCTAssertNil(proposal.changes[.temperature])
        XCTAssertNil(proposal.changes[.tint])
    }

    func testMixedLightSkipsWhiteBalance() {
        let mixedScene = SceneCharacteristics(mixedLightLikelihood: 0.8)
        let proposal = AutoEnhancementPolicy.propose(
            facts: warmCastFacts(scene: mixedScene),
            current: EditDocument(), sourceKind: .standard
        )
        XCTAssertNil(proposal.changes[.temperature])
        XCTAssertNil(proposal.changes[.tint])
    }

    func testRAWWithoutBaseTemperatureSkipsWB() {
        // No current value and no as-shot value: any Kelvin would be a guess.
        let proposal = AutoEnhancementPolicy.propose(
            facts: warmCastFacts(asShot: nil),
            current: EditDocument(), sourceKind: .raw
        )
        XCTAssertNil(proposal.changes[.temperature])
    }

    // MARK: - Intent preservation

    func testTonalAndSceneIntentIsPreserved() {
        let intents: [(String, SceneCharacteristics)] = [
            ("highKey", SceneCharacteristics(highKeyLikelihood: 0.9)),
            ("lowKey", SceneCharacteristics(lowKeyLikelihood: 0.9)),
            ("sunset", SceneCharacteristics(sunsetWarmLikelihood: 0.85)),
            ("monochrome", SceneCharacteristics(monochromeLikelihood: 0.9)),
            ("fog", SceneCharacteristics(fogLikelihood: 0.4)),
            ("snow", SceneCharacteristics(snowLikelihood: 0.85)),
            ("night", SceneCharacteristics(nightLikelihood: 0.85)),
        ]
        for (name, scene) in intents {
            let proposal = AutoEnhancementPolicy.propose(
                facts: facts(median: 0.48, scene: scene),
                current: EditDocument(), sourceKind: .standard
            )
            XCTAssertLessThan(
                abs(proposal.changes[.exposure]?.proposed ?? 0), 0.6,
                "\(name) intent must restrain exposure"
            )
            XCTAssertNil(proposal.changes[.temperature], "\(name) must not force white balance")
            XCTAssertNil(proposal.changes[.tint], "\(name) must not force white balance")
        }
    }

    func testMonochromeSkipsColorMoves() {
        let mono = SceneCharacteristics(monochromeLikelihood: 0.9)
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(median: 0.40, colorfulness: 0.05, neutrality: 0.95, scene: mono),
            current: EditDocument(), sourceKind: .standard
        )
        XCTAssertNil(proposal.changes[.vibrance])
        XCTAssertNil(proposal.changes[.saturation])
    }

    func testBacklitSubjectAdvisesSubjectMaskWithoutLiftingBackgroundAlone() {
        let backlit = SceneCharacteristics(
            subjectProminence: 0.8, backlightingLikelihood: 0.8
        )
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(median: 0.42, p50: 0.40, scene: backlit),
            current: EditDocument(), sourceKind: .standard
        )
        XCTAssertEqual(proposal.requestedMasks, [.subject])
        XCTAssertTrue(proposal.avoidedMasks.contains(.face))
        XCTAssertTrue(proposal.avoidedMasks.contains(.person))
        // No local layers are created by the proposal step.
        XCTAssertTrue(proposal.document.localAdjustments.isEmpty)
    }

    // MARK: - Detail restraint and preservation

    func testUnsupportedDetailLeavesDetailKnobsUntouched() {
        var current = EditDocument()
        current.rawDevelop.sharpnessAmount = nil
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(detailAvailable: false),
            current: current, sourceKind: .raw
        )
        XCTAssertNil(proposal.document.rawDevelop.sharpnessAmount)
        XCTAssertNil(proposal.document.rawDevelop.detailAmount)
        XCTAssertNil(proposal.document.rawDevelop.luminanceNoiseReductionAmount)
        XCTAssertNil(proposal.document.rawDevelop.colorNoiseReductionAmount)
        XCTAssertEqual(proposal.document.effects.texture, 0)
        XCTAssertEqual(proposal.document.effects.clarity, 0)
        XCTAssertNil(proposal.changes[.dehaze])
    }

    func testFogEvidenceAllowsRestrainedDehaze() {
        let foggy = SceneCharacteristics(fogLikelihood: 0.8)
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(median: 0.55, scene: foggy),
            current: EditDocument(), sourceKind: .standard
        )
        let dehaze = proposal.changes[.dehaze]?.proposed ?? 0
        XCTAssertGreaterThan(dehaze, 0)
        XCTAssertLessThanOrEqual(dehaze, 25)
    }

    func testUserOwnedStateIsPreservedByteForByte() {
        var current = EditDocument()
        current.light.toneCurve = LightToneCurve(points: [
            LightCurvePoint(input: 0, output: 0),
            LightCurvePoint(input: 0.5, output: 0.6),
            LightCurvePoint(input: 1, output: 1),
        ])
        current.color.mixer = ColorMixerAdjustments(
            red: ColorMixerChannel(hue: 10, saturation: 5, luminance: -5)
        )
        current.color.grading = ColorGradingAdjustments(
            shadows: ColorGradingWheel(hue: 30, saturation: 20)
        )
        current.lut = LUTSettings(lutID: LUTID(raw: "keeper"), intensity: 0.8)
        current.crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            aspectRatio: .square
        )
        current.rotation = .clockwise90
        current.adjustments = [.vibrance(amount: 0.2)]
        current.effects.vignette = VignetteAdjustments(amount: 0.5)

        let proposal = AutoEnhancementPolicy.propose(
            facts: warmCastFacts(), current: current, sourceKind: .standard
        )
        XCTAssertEqual(proposal.document.light.toneCurve, current.light.toneCurve)
        XCTAssertEqual(proposal.document.color.mixer, current.color.mixer)
        XCTAssertEqual(proposal.document.color.grading, current.color.grading)
        XCTAssertEqual(proposal.document.lut, current.lut)
        XCTAssertEqual(proposal.document.crop, current.crop)
        XCTAssertEqual(proposal.document.rotation, current.rotation)
        XCTAssertEqual(proposal.document.effects.vignette, current.effects.vignette)
        XCTAssertTrue(proposal.document.adjustments.contains(.vibrance(amount: 0.2)))
        XCTAssertTrue(proposal.document.localAdjustments.isEmpty)
    }

    func testIdentityCurveIsNeverSynthesized() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(median: 0.25, p05: 0.02, p10: 0.05, p25: 0.12, p50: 0.25, p75: 0.45, p90: 0.65, p95: 0.75),
            current: EditDocument(), sourceKind: .standard
        )
        XCTAssertTrue(proposal.document.light.toneCurve.isIdentity)
    }

    // MARK: - Change records

    func testChangesRecordPreviousProposedConfidenceAndBounds() {
        let proposal = AutoEnhancementPolicy.propose(
            facts: facts(median: 0.22, p05: 0.01, p10: 0.04, p25: 0.10, p50: 0.22, p75: 0.38, p90: 0.55, p95: 0.62),
            current: EditDocument(), sourceKind: .standard
        )
        XCTAssertFalse(proposal.changes.isEmpty)
        for change in proposal.changes.values {
            XCTAssertFalse(change.reason.isEmpty)
            XCTAssertFalse(change.evidence.isEmpty)
            XCTAssertTrue((0...1).contains(change.confidence))
            XCTAssertTrue(change.previous.isFinite)
            XCTAssertTrue(change.proposed.isFinite)
            let range = rangeFor(change.control)
            XCTAssertGreaterThanOrEqual(change.proposed, range.lowerBound)
            XCTAssertLessThanOrEqual(change.proposed, range.upperBound)
        }
    }

    private func rangeFor(_ control: AutoPolicyControl) -> ClosedRange<Double> {
        switch control {
        case .exposure: return LightAdjustments.exposureRange
        case .contrast: return LightAdjustments.contrastRange
        case .highlights: return LightAdjustments.highlightsRange
        case .shadows: return LightAdjustments.shadowsRange
        case .whites: return LightAdjustments.whitesRange
        case .blacks: return LightAdjustments.blacksRange
        case .temperature: return AdjustmentControl.temperature.range
        case .tint: return AdjustmentControl.tint.range
        case .vibrance: return ColorAdjustments.vibranceRange
        case .saturation: return ColorAdjustments.saturationRange
        case .dehaze: return EffectsAdjustments.dehazeRange
        }
    }
}
