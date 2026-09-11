import Foundation

/// Pure coordinated Auto enhancement policy (KRMA-345).
///
/// This is the production content-aware Auto engine's proposal step. It is a pure deterministic
/// function: frozen analysis facts plus the current document in, one editable document change
/// out. No actor, no renderer, no Vision, no UI. Every number derives from the same rendered
/// samples measured in KRMA-343 (`CurrentEditMeasurement`) and the scene/confidence evidence
/// from KRMA-344 (`SceneCharacteristics`, `AutoSignalConfidence`); this file owns no second
/// analysis or mask subsystem.
///
/// Coordination order (exposure first, then tone placement):
///
/// 1. Exposure establishes global placement from the perceptual median with tonal-key brakes
///    and a backlit-subject lift (same tuning as `AutoLightEngine`).
/// 2. Highlights/shadows/whites/blacks/contrast are derived from the tone facts and then
///    shrunk toward zero in proportion to `|exposure|` — exposure already moved the whole
///    frame, so the tails only correct the residual. Highlights keep an extra protection term
///    when a positive exposure pushes bright pixels toward clipping.
/// 3. White balance, color, and dehaze are gated independently below and never fight the tone
///    placement: WB only shifts the neutral axis, vibrance/saturation only touch colorfulness,
///    dehaze only answers fog evidence.
///
/// Preservation: the proposed document starts as a copy of the current document and only
/// Auto-owned fields move — the six Light sliders, vibrance/saturation, dehaze, and white
/// balance through the existing RAW/standard mapping. Curves, mixer, grading, Looks/LUTs,
/// crop/rotation, other adjustment nodes, grain/vignette/texture/clarity, RAW detail knobs,
/// and every local mask layer are preserved byte-for-byte. The master curve is additionally
/// never synthesized in v1: it moves only from identity, and v1 leaves even identity alone,
/// reserving curve work for Auto-owned state in a later ticket.
///
/// White-balance direction (pinned, do not "fix" without updating the tests):
/// `CIRAWFilter.neutralTemperature` runs the photographic way round (raising warms), while the
/// standard-image `temperatureTint` node runs inverted about D65 (raising cools — see
/// `AdjustmentControl.sliderMapped`). A warm cast therefore *lowers* the RAW temperature and
/// *raises* the standard temperature. Tint runs the same way on both paths (+ is magenta).
enum AutoEnhancementPolicy {
    /// Bumped when the exposure objective changes so a prior near-no-op Auto result is not
    /// treated as current by the repeat-run fingerprint.
    static let algorithmVersion = 2

    static func propose(
        facts: AutoEnhancementFacts,
        current: EditDocument,
        sourceKind: AutoSourceKind
    ) -> AutoEnhancementProposal {
        let tone = facts.tonePerceptual
        let scene = facts.scene
        let confidence = facts.signalConfidence

        var changes: [AutoControlChange] = []
        var working = current

        // MARK: Tone (exposure first, then residual tails)

        // Without measurable tone there is nothing to place: skip the whole tone section
        // rather than applying a full-strength correction at zero confidence.
        let toneConfidence = combinedConfidence(
            confidence.globalTone, confidence.scene, method: .tone
        )
        if confidence.globalTone >= 0.2 {
        let neutralTarget = AutoExposureObjective.targetMedian(tone: tone, scene: scene)
        let exposureTarget = AutoExposureObjective.desiredExposure(
            tone: tone,
            scene: scene,
            headroom: facts.highlightHeadroom
        )
        let exposureChange = restrainedDelta(
            target: exposureTarget,
            current: current.light.exposure,
            range: LightAdjustments.exposureRange,
            noOpThreshold: 0.05,
            userEditScale: 0.5
        )
        let exposure = current.light.exposure + exposureChange
        if abs(exposureChange) >= 0.05 {
            working.light.exposure = bounded(
                exposure, LightAdjustments.exposureRange
            )
            let underexposure = AutoExposureObjective.robustUnderexposureEvidence(tone: tone)
            let evidence = "p05=\(format(tone.p05)) p10=\(format(tone.p10)) "
                + "p50=\(format(tone.p50)) p75=\(format(tone.p75)) "
                + "p95=\(format(tone.p95)) spread=\(format(tone.p95 - tone.p05)) "
                + "underExposure=\(format(Float(underexposure))) "
                + "highKey=\(format(scene.highKeyLikelihood)) "
                + "lowKey=\(format(scene.lowKeyLikelihood))"
            changes.append(AutoControlChange(
                control: .exposure,
                previous: current.light.exposure,
                proposed: working.light.exposure,
                confidence: toneConfidence,
                reason: "Robust neutral median target (\(format(Float(neutralTarget)))) with scene-key restraint when supported.",
                evidence: evidence
            ))
        }

        // The coordination factor: exposure already moved the frame, so tails correct only the
        // residual. At |E| = 1.6 EV the tails keep 60% of their independent strength.
        let residualScale = max(0.6, 1 - abs(exposure) * 0.25)

        func toneChange(
            _ control: AutoPolicyControl,
            independent: Double,
            currentValue: Double,
            range: ClosedRange<Double>,
            reason: String,
            evidence: String
        ) {
            let coordinated = independent * Double(residualScale)
            let delta = restrainedDelta(
                target: coordinated,
                current: currentValue,
                range: range,
                noOpThreshold: 1.0,
                userEditScale: 0.5
            )
            guard abs(delta) >= 1.0 else { return }
            let proposed = bounded(currentValue + delta, range)
            setLight(control, to: proposed, in: &working.light)
            changes.append(AutoControlChange(
                control: control,
                previous: currentValue,
                proposed: proposed,
                confidence: toneConfidence,
                reason: reason,
                evidence: evidence
            ))
        }

        let tails = TailPlacement.evaluate(tone: tone, scene: scene, exposure: exposure)
        toneChange(
            .highlights, independent: tails.highlights,
            currentValue: current.light.highlights,
            range: LightAdjustments.highlightsRange,
            reason: "Protects bright tails after exposure placement; no second exposure correction.",
            evidence: "tone.p95=\(format(tone.p95)) clip=\(format(tone.highlightClippingFraction))"
        )
        toneChange(
            .shadows, independent: tails.shadows,
            currentValue: current.light.shadows,
            range: LightAdjustments.shadowsRange,
            reason: "Opens dark subject tones left over after exposure placement.",
            evidence: "tone.p10=\(format(tone.p10))"
        )
        toneChange(
            .whites, independent: tails.whites,
            currentValue: current.light.whites,
            range: LightAdjustments.whitesRange,
            reason: "Sets the white point from the exposure-compensated upper percentile.",
            evidence: "tone.p95=\(format(tone.p95))"
        )
        toneChange(
            .blacks, independent: tails.blacks,
            currentValue: current.light.blacks,
            range: LightAdjustments.blacksRange,
            reason: "Sets the black point while respecting low-key intent.",
            evidence: "tone.p05=\(format(tone.p05))"
        )
        toneChange(
            .contrast, independent: tails.contrast,
            currentValue: current.light.contrast,
            range: LightAdjustments.contrastRange,
            reason: "Responds to residual dynamic range without re-placing exposure.",
            evidence: "spread=\(format(tone.p95 - tone.p05))"
        )
        } // confidence.globalTone >= 0.2; WB/color/detail gate independently below

        // MARK: White balance (neutral evidence or estimator agreement, never a guess)

        if let wb = WhiteBalancePlacement.evaluate(
            facts: facts, current: current, sourceKind: sourceKind
        ) {
            switch sourceKind {
            case .raw:
                if let temp = wb.temperature {
                    working.rawDevelop.neutralTemperature = temp
                    changes.append(AutoControlChange(
                        control: .temperature, previous: current.rawDevelop.neutralTemperature ?? wb.baseTemperature,
                        proposed: temp, confidence: wb.confidence,
                        reason: wb.reason, evidence: wb.evidence
                    ))
                }
                if let tint = wb.tint {
                    working.rawDevelop.neutralTint = tint
                    changes.append(AutoControlChange(
                        control: .tint, previous: current.rawDevelop.neutralTint ?? wb.baseTint,
                        proposed: tint, confidence: wb.confidence,
                        reason: wb.reason, evidence: wb.evidence
                    ))
                }
            case .standard:
                var nodes = current.adjustments
                if let temp = wb.temperature {
                    nodes = AdjustmentControl.temperature.setting(temp, in: nodes)
                    changes.append(AutoControlChange(
                        control: .temperature,
                        previous: AdjustmentControl.temperature.value(in: current.adjustments),
                        proposed: temp, confidence: wb.confidence,
                        reason: wb.reason, evidence: wb.evidence
                    ))
                }
                if let tint = wb.tint {
                    nodes = AdjustmentControl.tint.setting(tint, in: nodes)
                    changes.append(AutoControlChange(
                        control: .tint,
                        previous: AdjustmentControl.tint.value(in: current.adjustments),
                        proposed: tint, confidence: wb.confidence,
                        reason: wb.reason, evidence: wb.evidence
                    ))
                }
                working.adjustments = nodes
            }
        }

        // MARK: Color (restrained; skipped when evidence is unreliable)

        if let color = ColorPlacement.evaluate(facts: facts, current: current) {
            if let vibrance = color.vibrance {
                working.color.vibrance = vibrance
                changes.append(AutoControlChange(
                    control: .vibrance, previous: current.color.vibrance,
                    proposed: vibrance, confidence: color.confidence,
                    reason: color.reason, evidence: color.evidence
                ))
            }
            if let saturation = color.saturation {
                working.color.saturation = saturation
                changes.append(AutoControlChange(
                    control: .saturation, previous: current.color.saturation,
                    proposed: saturation, confidence: color.confidence,
                    reason: color.reason, evidence: color.evidence
                ))
            }
        }

        // MARK: Detail (fog dehaze only; every other detail knob is out of scope)

        if let dehaze = DetailPlacement.evaluate(facts: facts, current: current) {
            working.effects.dehaze = dehaze.value
            changes.append(AutoControlChange(
                control: .dehaze, previous: current.effects.dehaze,
                proposed: dehaze.value, confidence: dehaze.confidence,
                reason: dehaze.reason, evidence: dehaze.evidence
            ))
        }

        // The master curve is never synthesized in v1, even from identity. Recording the
        // decision keeps the rationale auditable when Auto-owned curve state arrives.
        let overall = changes.isEmpty
            ? confidence.overall
            : changes.map(\.confidence).reduce(0, +) / Float(changes.count)

        return AutoEnhancementProposal(
            algorithmVersion: algorithmVersion,
            document: working,
            changes: changes,
            confidence: overall,
            evidence: AutoEvidenceUsed(
                toneMedian: tone.p50,
                highlightClipping: tone.highlightClippingFraction,
                shadowClipping: tone.shadowClippingFraction,
                neutralConfidence: bestNeutralConfidence(facts.color),
                recommendsNeutralCorrection: facts.color.recommendsNeutralCorrection,
                hueMixed: facts.color.isMixed,
                overallSignalConfidence: confidence.overall
            ),
            requestedMasks: MaskAdvisory.requestedMasks(scene: scene),
            avoidedMasks: MaskAdvisory.avoidedMasks(),
            notes: curveNote(current: current)
        )
    }

    // MARK: - Helpers

    private enum ConfidenceMethod { case tone, color }

    private static func combinedConfidence(
        _ toneOrColor: Float, _ scene: Float, method: ConfidenceMethod
    ) -> Float {
        unit(0.6 * toneOrColor + 0.4 * scene)
    }

    /// Bounded refinement toward `target` that respects existing user edits: a control already
    /// moved past half its range is left alone; any other non-neutral control moves at half
    /// strength toward the target.
    static func restrainedDelta(
        target: Double,
        current: Double,
        range: ClosedRange<Double>,
        noOpThreshold: Double,
        userEditScale: Double
    ) -> Double {
        let clampedTarget = bounded(target, range)
        var delta = clampedTarget - current
        if abs(delta) < noOpThreshold { return 0 }
        let halfRange = (range.upperBound - range.lowerBound) / 2
        if halfRange > 0, abs(current) > halfRange * 0.5 { return 0 }
        if current != 0 { delta *= userEditScale }
        guard delta.isFinite else { return 0 }
        return delta
    }

    private static func setLight(
        _ control: AutoPolicyControl, to value: Double, in light: inout LightAdjustments
    ) {
        switch control {
        case .highlights: light.highlights = value
        case .shadows: light.shadows = value
        case .whites: light.whites = value
        case .blacks: light.blacks = value
        case .contrast: light.contrast = value
        default: break
        }
    }

    private static func bestNeutralConfidence(_ color: PixelCorrelatedColor) -> Float {
        color.neutralCandidates.map(\.confidence).max() ?? 0
    }

    private static func curveNote(current: EditDocument) -> String {
        current.light.toneCurve.isIdentity
            ? "Master curve left neutral; v1 never synthesizes a curve."
            : "User-owned master curve preserved byte-for-byte."
    }

    private static func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
}

// MARK: - Input facts

/// Which white-balance mapping the proposal must use. RAW edits set
/// `rawDevelop.neutralTemperature/Tint` (photographic direction); standard images set the
/// post-render `temperatureTint` node (inverted about D65).
enum AutoSourceKind: String, Codable, Sendable, Equatable, CaseIterable {
    case raw
    case standard
}

/// The frozen facts one proposal is derived from. Assembled by the caller from a
/// `CurrentEditMeasurement` (tone, color, headroom, detail availability), the scene analysis
/// for that measurement, and the per-signal confidence — plus the as-shot white balance when
/// the source is RAW and the decoder reported one. Facts only; no slider values.
struct AutoEnhancementFacts: Codable, Sendable, Equatable {
    var tonePerceptual: ToneStatistics
    var color: PixelCorrelatedColor
    var scene: SceneCharacteristics
    var signalConfidence: AutoSignalConfidence
    var highlightHeadroom: HighlightHeadroom
    var detailAvailable: Bool
    var asShotTemperature: Double?
    var asShotTint: Double?

    init(
        tonePerceptual: ToneStatistics = ToneStatistics(variant: .perceptual),
        color: PixelCorrelatedColor = PixelCorrelatedColor(),
        scene: SceneCharacteristics = SceneCharacteristics(),
        signalConfidence: AutoSignalConfidence = AutoSignalConfidence(),
        highlightHeadroom: HighlightHeadroom = HighlightHeadroom(),
        detailAvailable: Bool = false,
        asShotTemperature: Double? = nil,
        asShotTint: Double? = nil
    ) {
        self.tonePerceptual = tonePerceptual
        self.color = color
        self.scene = scene
        self.signalConfidence = signalConfidence
        self.highlightHeadroom = highlightHeadroom
        self.detailAvailable = detailAvailable
        self.asShotTemperature = asShotTemperature
        self.asShotTint = asShotTint
    }

    /// Bridge from a current-render measurement plus its scene interpretation.
    init(
        measurement: CurrentEditMeasurement,
        scene: SceneCharacteristics,
        signalConfidence: AutoSignalConfidence,
        asShotTemperature: Double? = nil,
        asShotTint: Double? = nil
    ) {
        self.tonePerceptual = measurement.globalTone.perceptual
        self.color = measurement.color
        self.scene = scene
        self.signalConfidence = signalConfidence
        self.highlightHeadroom = measurement.highlightHeadroom
        self.detailAvailable = measurement.detail.available
        self.asShotTemperature = asShotTemperature
        self.asShotTint = asShotTint
    }
}

// MARK: - Proposal types

/// Every control the v1 policy may move. Detail knobs beyond dehaze, mixer/grading channels,
/// crop/rotation, and mask geometry are deliberately absent: the policy cannot represent a
/// change it is not allowed to make.
enum AutoPolicyControl: String, Codable, Sendable, Equatable, CaseIterable {
    case exposure
    case contrast
    case highlights
    case shadows
    case whites
    case blacks
    case temperature
    case tint
    case vibrance
    case saturation
    case dehaze
}

/// One moved control: what it was, what Auto proposes, how confident, and why. `previous` and
/// `proposed` are control-native values (EV, -100…100 sliders, Kelvin, tint units).
struct AutoControlChange: Codable, Sendable, Equatable {
    let control: AutoPolicyControl
    let previous: Double
    let proposed: Double
    let confidence: Float
    let reason: String
    let evidence: String

    init(
        control: AutoPolicyControl,
        previous: Double,
        proposed: Double,
        confidence: Float,
        reason: String,
        evidence: String
    ) {
        self.control = control
        self.previous = previous.isFinite ? previous : 0
        self.proposed = proposed.isFinite ? proposed : 0
        self.confidence = Self.unit(confidence)
        self.reason = reason
        self.evidence = evidence
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// The measurable evidence one proposal rested on. Persisted with the result so a later review
/// can tell "confident daylight correction" from "weak-evidence restraint" without pixels.
struct AutoEvidenceUsed: Codable, Sendable, Equatable {
    let toneMedian: Float
    let highlightClipping: Float
    let shadowClipping: Float
    let neutralConfidence: Float
    let recommendsNeutralCorrection: Bool
    let hueMixed: Bool
    let overallSignalConfidence: Float
}

/// One reviewable Auto result: the full proposed document plus exactly what changed and why.
/// An empty `changes` is a deliberate no-op (balanced image, weak evidence, or fully
/// user-owned controls) — the document then equals the input.
struct AutoEnhancementProposal: Codable, Sendable, Equatable {
    let algorithmVersion: Int
    let document: EditDocument
    let changes: [AutoPolicyControl: AutoControlChange]
    let confidence: Float
    let evidence: AutoEvidenceUsed
    let requestedMasks: [RegionKind]
    let avoidedMasks: [RegionKind]
    let notes: String

    init(
        algorithmVersion: Int = AutoEnhancementPolicy.algorithmVersion,
        document: EditDocument,
        changes: [AutoControlChange],
        confidence: Float,
        evidence: AutoEvidenceUsed,
        requestedMasks: [RegionKind] = [],
        avoidedMasks: [RegionKind] = [],
        notes: String = ""
    ) {
        self.algorithmVersion = algorithmVersion
        self.document = document
        var mapped: [AutoPolicyControl: AutoControlChange] = [:]
        for change in changes { mapped[change.control] = change }
        self.changes = mapped
        self.confidence = Self.unit(confidence)
        self.evidence = evidence
        self.requestedMasks = requestedMasks
        self.avoidedMasks = avoidedMasks
        self.notes = notes
    }

    var isNoOp: Bool { changes.isEmpty }

    var changedControls: [AutoPolicyControl] {
        changes.keys.sorted { $0.rawValue < $1.rawValue }
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

// MARK: - Placement stages

/// Shared neutral-exposure objective used by both proposal generation and renderer-backed
/// candidate scoring. It is deliberately facts-only: no fixed per-image boost and no CSS or
/// synthetic preview is involved.
///
/// The neutral target is a perceptual median of 0.48 for ordinary photographic frames. A key
/// scene (high-key, low-key, or night) pulls that target back toward the measured median, but
/// only while the robust distribution is consistent with intent. A low p50 by itself is not
/// enough to override the key brake: the p10/p75/p95 spread must also show usable scene
/// structure. This is what lets a materially underexposed mountain frame lift while a genuinely
/// low-key frame stays low-key.
enum AutoExposureObjective {
    static let neutralMedian = 0.48
    static let ordinaryCorrectionCapEV = 1.25
    static let structurallyUnderexposedCorrectionCapEV = 1.75
    /// A small but non-zero evidence gate avoids letting a barely dark frame inherit a key-scene
    /// brake while keeping a measured, broad distribution eligible for the stronger search bound.
    static let structuralEvidenceGate = 0.05

    static func targetMedian(tone: ToneStatistics, scene: SceneCharacteristics) -> Double {
        let intent = Double(max(
            scene.highKeyLikelihood,
            max(scene.lowKeyLikelihood, scene.nightLikelihood)
        ))
        let underexposure = robustUnderexposureEvidence(tone: tone)
        // Keep a clearly intentional key unchanged when the distribution is not materially
        // contradictory. Once the evidence crosses the structural-underexposure gate, use the
        // neutral target fully; a fractional key brake is exactly the near-no-op failure this
        // objective is meant to avoid.
        let intentWeight = underexposure >= structuralEvidenceGate
            ? 0
            : intent
        let target = neutralMedian * (1 - intentWeight)
            + Double(tone.p50) * intentWeight
        return bounded(target, 0.18...0.82)
    }

    static func desiredExposure(
        tone: ToneStatistics,
        scene: SceneCharacteristics,
        headroom: HighlightHeadroom
    ) -> Double {
        let floored = max(Double(tone.p50), 0.03)
        let target = targetMedian(tone: tone, scene: scene)
        var desired = log2(target / floored)
        desired += Double(scene.backlightingLikelihood)
            * Double(scene.subjectProminence) * 0.20

        // A clipped frame has no display headroom for a lift. RAW recovery support is allowed to
        // preserve a little more of a positive lift because the renderer can recover highlights
        // before the preview/export tone path clips them.
        let recoveryAllowance = headroom.rawRecoveryLikely ? 0.12 : 0
        if desired > 0, tone.highlightClippingFraction > 0.01 {
            desired *= max(0.3, 1 - Double(tone.highlightClippingFraction) * 4)
        }
        let cap = robustUnderexposureEvidence(tone: tone) >= structuralEvidenceGate
            ? structurallyUnderexposedCorrectionCapEV + recoveryAllowance
            : ordinaryCorrectionCapEV
        guard desired.isFinite else { return 0 }
        return min(max(desired, -ordinaryCorrectionCapEV), cap)
    }

    /// Confidence that a dark median is a placement defect rather than a tonal-key choice.
    /// The three terms are intentionally robust quantiles, not a mean or a fixed exposure delta:
    /// mid-tone deficit (p50), retained upper structure (p95), and usable spread (p95−p05).
    /// Shadow clipping is a supporting signal, never a requirement, because a developed RAW can
    /// report a dark p10 before the display histogram reaches zero.
    static func robustUnderexposureEvidence(tone: ToneStatistics) -> Double {
        let midDeficit = smooth(1 - tone.p50, start: 0.45, full: 0.80)
        let upperStructure = smooth(tone.p95, start: 0.38, full: 0.68)
        let spread = smooth(tone.p95 - tone.p05, start: 0.30, full: 0.60)
        let shadowClipping = min(max(Double(tone.shadowClippingFraction) * 8, 0), 1)
        let structure = max(upperStructure * spread, shadowClipping * 0.75)
        return bounded(midDeficit * structure, 0...1)
    }

    private static func smooth(_ value: Float, start: Float, full: Float) -> Double {
        guard full > start else { return value >= full ? 1 : 0 }
        let t = min(max((value - start) / (full - start), 0), 1)
        return Double(t * t * (3 - 2 * t))
    }

    private static func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// Tail controls derived from the tone facts for an exposure that is already decided.
private enum TailPlacement {
    struct Tails { var highlights = 0.0; var shadows = 0.0; var whites = 0.0; var blacks = 0.0; var contrast = 0.0 }

    static func evaluate(
        tone: ToneStatistics, scene: SceneCharacteristics, exposure: Double
    ) -> Tails {
        var tails = Tails()
        let smooth: (Float, Float, Float) -> Double = { value, start, full in
            guard full > start else { return value >= full ? 1 : 0 }
            let t = min(max((value - start) / (full - start), 0), 1)
            return Double(t * t * (3 - 2 * t))
        }
        let unit: (Float) -> Double = { v in Double(min(max(v.isFinite ? v : 0, 0), 1)) }

        let tail = smooth(tone.p95, 0.72, 0.94)
        let clipping = unit(tone.highlightClippingFraction * 3)
        let backlight = Double(scene.backlightingLikelihood) * 0.35
        let highKeyBrake = 1 - Double(scene.highKeyLikelihood) * 0.75
        tails.highlights = -(tail * 14 + clipping * 24 + backlight * 14) * highKeyBrake
        // A positive exposure already pushes highlights; protect what it endangered.
        if exposure > 0 { tails.highlights -= exposure * 5 }

        let lift = smooth(1 - tone.p10, 0.55, 0.90) * 10
        let backlightLift = Double(scene.backlightingLikelihood) * 20
        tails.shadows = (lift + backlightLift) * (1 - Double(scene.lowKeyLikelihood) * 0.85)

        tails.whites = ((0.86 - Double(tone.p95)) * 62 - unit(tone.highlightClippingFraction * 2) * 18)
            * (1 - Double(scene.lowKeyLikelihood) * 0.80)
        tails.blacks = (0.12 - Double(tone.p05)) * 48
            * (1 - Double(scene.lowKeyLikelihood) * 0.8)
            * (1 - Double(scene.highKeyLikelihood) * 0.80)
        tails.contrast = (0.78 - Double(tone.p95 - tone.p05)) * 46
            * (1 - Double(scene.backlightingLikelihood) * 0.35)

        tails.highlights = bounded(tails.highlights, -38...8)
        tails.shadows = bounded(tails.shadows, -8...38)
        tails.whites = bounded(tails.whites, -22...18)
        tails.blacks = bounded(tails.blacks, -18...22)
        tails.contrast = bounded(tails.contrast, -30...42)
        return tails
    }

    private static func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// White balance through the existing RAW/standard mapping. Changes require either a confident
/// non-mixed neutral candidate or agreement between the independent mean and median cast
/// estimators — plus a veto when warm/mixed illumination or monochrome makes a "correction"
/// more likely to erase intent than to fix a cast.
private enum WhiteBalancePlacement {
    struct Decision {
        let temperature: Double?
        let tint: Double?
        let baseTemperature: Double
        let baseTint: Double
        let confidence: Float
        let reason: String
        let evidence: String
    }

    static let rawTemperatureRange = 2000.0...50000.0
    static let standardTemperatureRange = 2000.0...11000.0
    static let tintRange = -150.0...150.0

    static func evaluate(
        facts: AutoEnhancementFacts, current: EditDocument, sourceKind: AutoSourceKind
    ) -> Decision? {
        let color = facts.color
        let scene = facts.scene
        let confidence = facts.signalConfidence

        // Vetoes: a correction here would erase intent, not fix a cast.
        if color.isMixed { return nil }
        if scene.monochromeLikelihood > 0.6 { return nil }
        if scene.mixedLightLikelihood > 0.5 { return nil }
        if confidence.colorNeutral < 0.4 { return nil }
        if confidence.scene < 0.25 { return nil }

        let bestNeutral = color.neutralCandidates.map(\.confidence).max() ?? 0
        let hasCredibleNeutral = color.recommendsNeutralCorrection && bestNeutral >= 0.5

        // Two independent estimators: global mean cast vs global median cast. Agreement means
        // both see the same direction, so one outlier region cannot invent a white balance.
        let meanWarm = Double(color.meanRGB.x - color.meanRGB.z)
        let medianWarm = Double(color.medianRGB.x - color.medianRGB.z)
        let meanGreen = Double(color.meanRGB.y - (color.meanRGB.x + color.meanRGB.z) / 2)
        let medianGreen = Double(color.medianRGB.y - (color.medianRGB.x + color.medianRGB.z) / 2)
        let warmAgrees = meanWarm * medianWarm > 0
            && abs(meanWarm) > 0.02 && abs(medianWarm) > 0.015
        let tintAgrees = meanGreen * medianGreen > 0
            && abs(meanGreen) > 0.015 && abs(medianGreen) > 0.01
        let estimatorsAgree = warmAgrees && (tintAgrees || (abs(meanGreen) < 0.02 && abs(medianGreen) < 0.02))

        guard hasCredibleNeutral || estimatorsAgree else { return nil }

        // Warm illumination is preserved when neutral evidence is weak.
        if scene.sunsetWarmLikelihood > 0.5, bestNeutral < 0.7 { return nil }

        let cast = hasCredibleNeutral ? meanWarm : (meanWarm + medianWarm) / 2
        let green = hasCredibleNeutral ? meanGreen : (meanGreen + medianGreen) / 2
        if abs(cast) < 0.02, abs(green) < 0.015 { return nil }

        // RAW runs photographic (raising warms); the standard node is inverted about D65.
        let rawTempDelta = bounded(-cast * 6000, -2500...2500)
        let standardTempDelta = bounded(cast * 6000, -1500...1500)
        let tintDelta = bounded(green * 300, -30...30)

        let wbConfidence = unit(min(bestNeutral > 0 ? bestNeutral : 0.6, min(confidence.colorNeutral, confidence.scene)))
        let reason = hasCredibleNeutral
            ? "Neutral-region cast correction; warm illumination preserved when evidence is weak."
            : "Independent mean/median estimators agree on the cast direction."
        let evidence = "warm=\(format(Float(cast))) green=\(format(Float(green))) neutral=\(format(bestNeutral))"

        switch sourceKind {
        case .raw:
            let baseTemp = current.rawDevelop.neutralTemperature ?? facts.asShotTemperature
            let baseTint = current.rawDevelop.neutralTint ?? facts.asShotTint ?? 0
            // Without a base temperature there is no absolute Kelvin to propose; a delta
            // against an unknown as-shot value would be a guess, so WB stays untouched.
            guard let baseTemp else { return nil }
            var temperature: Double?
            var tint: Double?
            if abs(rawTempDelta) >= 50 {
                temperature = bounded(baseTemp + rawTempDelta, rawTemperatureRange)
            }
            if abs(tintDelta) >= 2 {
                tint = bounded(baseTint + tintDelta, tintRange)
            }
            guard temperature != nil || tint != nil else { return nil }
            return Decision(
                temperature: temperature, tint: tint,
                baseTemperature: baseTemp, baseTint: baseTint,
                confidence: wbConfidence, reason: reason, evidence: evidence
            )
        case .standard:
            let baseTemp = AdjustmentControl.temperature.value(in: current.adjustments)
            let baseTint = AdjustmentControl.tint.value(in: current.adjustments)
            var temperature: Double?
            var tint: Double?
            if abs(standardTempDelta) >= 50 {
                temperature = bounded(baseTemp + standardTempDelta, standardTemperatureRange)
            }
            if abs(tintDelta) >= 2 {
                tint = bounded(baseTint + tintDelta, tintRange)
            }
            guard temperature != nil || tint != nil else { return nil }
            return Decision(
                temperature: temperature, tint: tint,
                baseTemperature: baseTemp, baseTint: baseTint,
                confidence: wbConfidence, reason: reason, evidence: evidence
            )
        }
    }

    private static func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
}

/// Vibrance/saturation stay restrained and are skipped when color evidence is unreliable.
private enum ColorPlacement {
    struct Decision {
        let vibrance: Double?
        let saturation: Double?
        let confidence: Float
        let reason: String
        let evidence: String
    }

    static func evaluate(facts: AutoEnhancementFacts, current: EditDocument) -> Decision? {
        let color = facts.color
        let scene = facts.scene
        let confidence = facts.signalConfidence
        if color.isMixed { return nil }
        if scene.monochromeLikelihood > 0.5 { return nil }
        if scene.sunsetWarmLikelihood > 0.6 { return nil }
        if scene.nightLikelihood > 0.6 { return nil }
        if confidence.colorNeutral < 0.4 { return nil }

        let spread = Double(color.saturationP95 - color.saturationMedian)
        var vibrance: Double?
        var saturation: Double?
        var reasons: [String] = []

        let clipping = max(color.channelClipping.red, max(color.channelClipping.green, color.channelClipping.blue))
        if clipping > 0.01 || color.saturationP95 > 0.9 {
            let target = bounded(
                current.color.saturation - Double(clipping * 200 + max(0, color.saturationP95 - 0.9) * 100),
                ColorAdjustments.saturationRange
            )
            if current.color.saturation - target >= 2 {
                saturation = target
                reasons.append("restrains clipped/over-saturated color")
            }
        } else if color.colorfulness < 0.35, spread < 0.5, confidence.colorNeutral >= 0.6 {
            let target = bounded(
                current.color.vibrance + Double((0.5 - spread) * 24),
                0...18
            )
            if target - current.color.vibrance >= 2, current.color.vibrance < 18 {
                vibrance = min(target, 18)
                reasons.append("lifts muted color within a restrained envelope")
            }
        }
        guard vibrance != nil || saturation != nil else { return nil }
        return Decision(
            vibrance: vibrance, saturation: saturation,
            confidence: unit(min(confidence.colorNeutral, confidence.scene)),
            reason: reasons.joined(separator: "; ") + ".",
            evidence: "satP95=\(format(color.saturationP95)) colorful=\(format(color.colorfulness))"
        )
    }

    private static func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
}

/// Detail in v1 is fog dehaze only. RAW sharpening/NR knobs, texture, and clarity are never
/// touched: without decoder capability facts (a later ticket's scope) any value would be a
/// guess, and the unsupported-detail test pins that restraint.
private enum DetailPlacement {
    struct Decision {
        let value: Double
        let confidence: Float
        let reason: String
        let evidence: String
    }

    static func evaluate(facts: AutoEnhancementFacts, current: EditDocument) -> Decision? {
        let fog = facts.scene.fogLikelihood
        guard fog > 0.55 else { return nil }
        guard facts.signalConfidence.scene >= 0.3 else { return nil }
        let target = min(max(current.effects.dehaze + Double(fog) * 15, -100), 25)
        guard target - current.effects.dehaze >= 2 else { return nil }
        return Decision(
            value: target,
            confidence: min(max(fog, 0), 1) * facts.signalConfidence.scene,
            reason: "Fog evidence supports a restrained dehaze lift.",
            evidence: "fog=\(String(format: "%.2f", fog))"
        )
    }
}

/// Mask advisory for the later regional-correction ticket. V1 creates no layers (explicit
/// non-goal); it only records which masks a regional step should consider or must avoid.
private enum MaskAdvisory {
    static func requestedMasks(scene: SceneCharacteristics) -> [RegionKind] {
        if scene.backlightingLikelihood > 0.5, scene.subjectProminence > 0.4 {
            return [.subject]
        }
        return []
    }

    static func avoidedMasks() -> [RegionKind] {
        // People masks are never invented by global policy; a regional step must earn them.
        // Instance kinds share the face/person signal (see `isFaceKind`), so naming the
        // families here covers them without enumerating indices.
        [.face, .person]
    }
}
