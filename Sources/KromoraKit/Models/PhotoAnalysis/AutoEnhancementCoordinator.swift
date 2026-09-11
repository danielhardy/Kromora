import CoreGraphics
import Foundation

/// Asynchronous bounded Auto candidate coordination and selection (KRMA-347).
///
/// This is delivery-sequence step 4 of the KRMA-341 epic: it turns the native coordinated
/// proposal (KRMA-345) and the Apple-reference proposal (KRMA-346) into one validated editable
/// result through the real renderer. It owns no analysis of its own — every fact it scores
/// against is frozen at run start from the caller's `AutoEnhancementFacts` and regional facts,
/// and candidates never redefine their own evaluation targets.
///
/// Shape of a run:
///
/// 1. Freeze: capture the source/document revision, build `AutoEvaluationTargets` from the
///    frozen facts, and generate the candidate list (pure, deterministic). The unchanged
///    current document is always candidate zero.
/// 2. Render: each candidate's document copy is rendered at a small scale through the
///    injected sampler (`CurrentEditSampling`, implemented by `RenderEngine` in production).
///    At most `maxSmallRenders` (24) small renders and `maxRAWRedevelopments` (4) expensive
///    RAW redevelopments happen; both counters are observable in the result.
/// 3. Score: every rendered candidate is scored against the frozen targets with separate
///    global and important-region terms. Missing regional evidence degrades the score (an
///    explicit penalty) rather than fabricating regional facts.
/// 4. Select: guardrail violations (clipping, color, mask-edge) are rejected even when their
///    aggregate score is better. The best completed acceptable candidate wins; ties prefer
///    the simpler edit, and the unchanged candidate wins when improvement is negligible.
///
/// Concurrency and safety: the coordinator is a `Sendable` struct with no shared mutable
/// state — the policy stays pure, candidates render sequentially (no task or cache leaks by
/// construction), and `Task` cancellation, revision mismatch, render failure, and validation
/// failure all return without applying edits. Navigation is handled through task
/// cancellation: the caller cancels the run's task when the user navigates away.
///
/// What this ticket does NOT own: persisting the result or changing UI state, creating local
/// mask layers (KRMA-348 owns mask creation — candidates only consume proposal metadata),
/// or using any Apple aesthetics score for selection.

// MARK: - Candidate provenance

/// Where one evaluated candidate came from. Persisted in diagnostics so a later review can
/// tell "native policy" from "Apple-informed" from "reduced-strength fallback" without pixels.
enum AutoCandidateProvenance: Codable, Sendable, Equatable {
    /// The current document, unmodified. Always candidate zero; always acceptable.
    case unchanged
    /// The coordinated native policy proposal (KRMA-345) at full strength.
    case native
    /// The Apple-reference fitted proposal (KRMA-346) at full strength.
    case appleReference
    /// A reduced-strength variant of the native proposal, `scale` in (0, 1).
    case reducedNative(scale: Double)
    /// A reduced-strength variant of the Apple-reference proposal, `scale` in (0, 1).
    case reducedApple(scale: Double)

    var displayName: String {
        switch self {
        case .unchanged: return "unchanged"
        case .native: return "native"
        case .appleReference: return "apple-reference"
        case .reducedNative(let scale): return "native-\(Int((scale * 100).rounded()))%"
        case .reducedApple(let scale): return "apple-\(Int((scale * 100).rounded()))%"
        }
    }

    /// True for the full-strength policy/reference proposals (not unchanged, not reduced).
    var isFullStrength: Bool {
        switch self {
        case .native, .appleReference: return true
        case .unchanged, .reducedNative, .reducedApple: return false
        }
    }
}

// MARK: - Candidate

/// One editable candidate: a document copy plus the change map that produced it.
/// Documents are values, so every candidate is an independent copy — the input is never mutated.
struct AutoCandidate: Sendable, Equatable {
    let provenance: AutoCandidateProvenance
    let document: EditDocument
    /// The control changes relative to the run's input document. Empty for `.unchanged`.
    let changes: [AutoPolicyControl: AutoControlChange]
    /// Local-mask layers added relative to the input (v1 proposals add none; counted anyway
    /// so complexity and mask-edge terms stay honest when KRMA-348 starts adding layers).
    let addedMaskCount: Int
    let notes: String

    init(
        provenance: AutoCandidateProvenance,
        document: EditDocument,
        changes: [AutoPolicyControl: AutoControlChange] = [:],
        addedMaskCount: Int = 0,
        notes: String = ""
    ) {
        self.provenance = provenance
        self.document = document
        self.changes = changes
        self.addedMaskCount = max(0, addedMaskCount)
        self.notes = notes
    }

    var changedControlCount: Int { changes.count }
}

// MARK: - Pure candidate generation

/// Pure deterministic candidate generation. No renderer, no actor, no async.
enum AutoCandidateGenerator {
    /// Reduced-strength fallback scale. Half strength is the conventional photographic
    /// "pull it back" step and keeps the candidate count bounded.
    static let reducedScale = 0.5

    /// Build the evaluation list for one run. Order is significant and stable: unchanged
    /// first (index zero wins every tie), then full-strength proposals, then reduced-strength
    /// fallbacks. No-ops (a proposal with no changes) contribute no candidate.
    static func generate(
        current: EditDocument,
        native: AutoEnhancementProposal?,
        apple: AppleReferenceProposal?,
        sourceKind: AutoSourceKind
    ) -> [AutoCandidate] {
        var candidates = [AutoCandidate(provenance: .unchanged, document: current)]
        if let native, !native.isNoOp {
            candidates.append(AutoCandidate(
                provenance: .native, document: native.document,
                changes: native.changes,
                addedMaskCount: maskDelta(from: current, to: native.document),
                notes: native.notes
            ))
            candidates.append(AutoCandidate(
                provenance: .reducedNative(scale: reducedScale),
                document: scaledDocument(
                    current: current, changes: native.changes,
                    sourceKind: sourceKind, scale: reducedScale
                ),
                changes: scaledChanges(native.changes, current: current, scale: reducedScale),
                addedMaskCount: 0,
                notes: "Reduced-strength (\(Int(reducedScale * 100))%) native fallback."
            ))
        }
        if let apple, !apple.isNoOp {
            candidates.append(AutoCandidate(
                provenance: .appleReference, document: apple.document,
                changes: apple.changes,
                addedMaskCount: maskDelta(from: current, to: apple.document),
                notes: apple.notes
            ))
            candidates.append(AutoCandidate(
                provenance: .reducedApple(scale: reducedScale),
                document: scaledDocument(
                    current: current, changes: apple.changes,
                    sourceKind: sourceKind, scale: reducedScale
                ),
                changes: scaledChanges(apple.changes, current: current, scale: reducedScale),
                addedMaskCount: 0,
                notes: "Reduced-strength (\(Int(reducedScale * 100))%) Apple-reference fallback."
            ))
        }
        return candidates
    }

    /// Interpolate every changed control toward the current value by `scale`.
    /// Pure; clamps to the same control ranges the policy and fitter use.
    static func scaledDocument(
        current: EditDocument,
        changes: [AutoPolicyControl: AutoControlChange],
        sourceKind: AutoSourceKind,
        scale: Double
    ) -> EditDocument {
        let clampedScale = min(max(scale.isFinite ? scale : 0, 0), 1)
        var document = current
        for (control, change) in changes {
            let base = currentValue(control, in: current, sourceKind: sourceKind)
            let proposed = base + (change.proposed - base) * clampedScale
            setValue(control, to: proposed, in: &document, sourceKind: sourceKind)
        }
        return document
    }

    /// The change map matching `scaledDocument`, so movement/complexity penalties see the
    /// reduced deltas rather than the full-strength ones.
    static func scaledChanges(
        _ changes: [AutoPolicyControl: AutoControlChange],
        current: EditDocument,
        scale: Double
    ) -> [AutoPolicyControl: AutoControlChange] {
        let clampedScale = min(max(scale.isFinite ? scale : 0, 0), 1)
        var scaled: [AutoPolicyControl: AutoControlChange] = [:]
        for (control, change) in changes {
            scaled[control] = AutoControlChange(
                control: control,
                previous: change.previous,
                proposed: change.previous + (change.proposed - change.previous) * clampedScale,
                confidence: change.confidence,
                reason: change.reason,
                evidence: change.evidence
            )
        }
        return scaled
    }

    private static func maskDelta(from current: EditDocument, to candidate: EditDocument) -> Int {
        max(0, candidate.localAdjustments.count - current.localAdjustments.count)
    }

    private static func currentValue(
        _ control: AutoPolicyControl, in document: EditDocument, sourceKind: AutoSourceKind
    ) -> Double {
        switch control {
        case .exposure: return document.light.exposure
        case .contrast: return document.light.contrast
        case .highlights: return document.light.highlights
        case .shadows: return document.light.shadows
        case .whites: return document.light.whites
        case .blacks: return document.light.blacks
        case .vibrance: return document.color.vibrance
        case .saturation: return document.color.saturation
        case .dehaze: return document.effects.dehaze
        case .temperature:
            switch sourceKind {
            case .raw: return document.rawDevelop.neutralTemperature ?? 6500
            case .standard: return AdjustmentControl.temperature.value(in: document.adjustments)
            }
        case .tint:
            switch sourceKind {
            case .raw: return document.rawDevelop.neutralTint ?? 0
            case .standard: return AdjustmentControl.tint.value(in: document.adjustments)
            }
        }
    }

    private static func setValue(
        _ control: AutoPolicyControl, to value: Double,
        in document: inout EditDocument, sourceKind: AutoSourceKind
    ) {
        switch control {
        case .exposure:
            document.light.exposure = bounded(value, LightAdjustments.exposureRange)
        case .contrast:
            document.light.contrast = bounded(value, LightAdjustments.contrastRange)
        case .highlights:
            document.light.highlights = bounded(value, LightAdjustments.highlightsRange)
        case .shadows:
            document.light.shadows = bounded(value, LightAdjustments.shadowsRange)
        case .whites:
            document.light.whites = bounded(value, LightAdjustments.whitesRange)
        case .blacks:
            document.light.blacks = bounded(value, LightAdjustments.blacksRange)
        case .vibrance:
            document.color.vibrance = bounded(value, ColorAdjustments.vibranceRange)
        case .saturation:
            document.color.saturation = bounded(value, ColorAdjustments.saturationRange)
        case .dehaze:
            document.effects.dehaze = bounded(value, EffectsAdjustments.dehazeRange)
        case .temperature:
            switch sourceKind {
            case .raw:
                document.rawDevelop.neutralTemperature = bounded(value, 2000...50000)
            case .standard:
                document.adjustments = AdjustmentControl.temperature.setting(
                    bounded(value, 2000...11000), in: document.adjustments
                )
            }
        case .tint:
            switch sourceKind {
            case .raw:
                document.rawDevelop.neutralTint = bounded(value, -150...150)
            case .standard:
                document.adjustments = AdjustmentControl.tint.setting(
                    bounded(value, -150...150), in: document.adjustments
                )
            }
        }
    }

    private static func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Frozen evaluation targets

/// One important region to score separately from the global frame. Frozen at run start from
/// the analysis facts — candidates never redefine these.
struct AutoRegionTarget: Codable, Sendable, Equatable {
    let kind: RegionKind
    /// Normalized image-space bounds used to crop the candidate's own render. `nil` means the
    /// region cannot be scored from pixels: its weight goes to zero and the missing-evidence
    /// penalty applies instead of inventing a regional measurement.
    let bounds: NormalizedRect?
    /// Baseline median luma of the region, pulled toward the placement target by intent.
    let targetMedian: Double
    /// Measured support (`confidence * coverage`), used as the scoring weight.
    let importance: Double
    let confidence: Double

    /// True when the region carries enough evidence to score from a pixel crop.
    var isScorable: Bool {
        guard let bounds, bounds.width > 0.01, bounds.height > 0.01 else { return false }
        return importance >= Double(AutoCandidateScoring.minimumRegionImportance)
            && confidence >= Double(AutoCandidateScoring.minimumRegionConfidence)
    }
}

/// Everything one run scores against, frozen before the first candidate renders.
/// Absolute terms anchor to the analysis facts; relative terms (contrast loss, noise
/// amplification) anchor to the unchanged candidate's own render, which is scored first and
/// frozen as the pixel baseline before any other candidate is evaluated.
struct AutoEvaluationTargets: Codable, Sendable, Equatable {
    /// Global placement target from the shared robust neutral-exposure objective. Ordinary frames
    /// target a perceptual median of 0.48; high-key, low-key, and night frames are pulled toward
    /// their measured median unless p10/p50/p75/p95 show a structurally underexposed frame.
    let globalTargetMedian: Double
    /// Baseline global median (the status quo the relative terms compare against).
    let baselineMedian: Double
    /// Baseline highlight clipping of the current render.
    let baselineHighlightClipping: Double
    /// Baseline colorfulness cap: candidates must not exceed the restrained baseline.
    let baselineSaturationP95: Double
    /// Baseline cast magnitude (warm + green) of the current render.
    let baselineCastMagnitude: Double
    /// True when neutral evidence was credible enough to score neutral-color error.
    /// Otherwise the neutral term is zero and the missing-evidence penalty applies.
    let hasNeutralReference: Bool
    /// Up to four important regions, sorted by importance. Fewer when evidence is weak —
    /// never padded with invented regions.
    let regions: [AutoRegionTarget]

    /// Derive frozen targets from the run's facts and regional analysis. Pure.
    static func frozen(
        facts: AutoEnhancementFacts,
        regions: [AnalyzedRegion]
    ) -> AutoEvaluationTargets {
        let scene = facts.scene
        let baselineMedian = Double(facts.tonePerceptual.p50)
        let globalTarget = AutoExposureObjective.targetMedian(
            tone: facts.tonePerceptual, scene: scene
        )

        let meanRGB = facts.color.meanRGB
        let warm = Double(meanRGB.x - meanRGB.z)
        let green = Double(meanRGB.y - (meanRGB.x + meanRGB.z) / 2)
        let castMagnitude = abs(warm) + abs(green)

        let bestNeutral = facts.color.neutralCandidates.map(\.confidence).max() ?? 0
        let hasNeutral = facts.color.recommendsNeutralCorrection && bestNeutral >= 0.5
            && !facts.color.isMixed

        let scored = regions
            .filter {
                Double($0.importance) >= Double(AutoCandidateScoring.minimumRegionImportance)
                    && Double($0.confidence) >= Double(AutoCandidateScoring.minimumRegionConfidence)
            }
            .sorted { $0.importance > $1.importance }
            .prefix(AutoCandidateScoring.maximumScoredRegions)
            .map { region -> AutoRegionTarget in
                return AutoRegionTarget(
                    kind: region.kind,
                    bounds: region.bounds,
                    targetMedian: AutoExposureObjective.targetMedian(
                        tone: region.tone, scene: scene
                    ),
                    importance: Double(region.importance),
                    confidence: Double(region.confidence)
                )
            }

        return AutoEvaluationTargets(
            globalTargetMedian: globalTarget,
            baselineMedian: baselineMedian,
            baselineHighlightClipping: Double(facts.tonePerceptual.highlightClippingFraction),
            baselineSaturationP95: Double(facts.color.saturationP95),
            baselineCastMagnitude: castMagnitude,
            hasNeutralReference: hasNeutral,
            regions: Array(scored)
        )
    }
}

// MARK: - Pure scoring

/// Component costs for one rendered candidate. Lower is better; `total` is the weighted sum
/// the coordinator selects on. `rejected` marks a guardrail violation, which excludes the
/// candidate even when its total beats every other candidate.
struct AutoCandidateScore: Sendable, Equatable {
    /// |global median − frozen target|.
    var globalExposure: Double
    /// Importance-weighted |regional median − regional target| over scorable regions.
    var regionExposure: Double
    /// Highlight clipping above the restrained baseline.
    var clipping: Double
    /// Residual cast where neutral evidence supports scoring it.
    var neutral: Double
    /// Saturation above the restrained baseline cap.
    var saturation: Double
    /// Local contrast lost relative to the unchanged render.
    var contrastLoss: Double
    /// Laplacian noise amplified relative to the unchanged render.
    var noise: Double
    /// Halo-like proxy: a local-contrast spike concentrated where masks changed. A coarse
    /// proxy by design — KRMA-348 owns real mask creation; this term only keeps a candidate
    /// from buying sharpness with ringing.
    var maskEdge: Double
    /// Normalized distance moved from the current edit.
    var movement: Double
    /// Changed-control count plus added-mask count.
    var complexity: Double
    /// Applied when regional or neutral evidence was missing: the score degrades instead of
    /// fabricating the missing measurement.
    var missingEvidencePenalty: Double
    var total: Double
    var rejected: Bool
    var rejectionReasons: [String]

    static let acceptable = AutoCandidateScore(
        globalExposure: 0, regionExposure: 0, clipping: 0, neutral: 0, saturation: 0,
        contrastLoss: 0, noise: 0, maskEdge: 0, movement: 0, complexity: 0,
        missingEvidencePenalty: 0, total: 0, rejected: false, rejectionReasons: []
    )

    init(
        globalExposure: Double = 0, regionExposure: Double = 0, clipping: Double = 0,
        neutral: Double = 0, saturation: Double = 0, contrastLoss: Double = 0,
        noise: Double = 0, maskEdge: Double = 0, movement: Double = 0,
        complexity: Double = 0, missingEvidencePenalty: Double = 0, total: Double = 0,
        rejected: Bool = false, rejectionReasons: [String] = []
    ) {
        self.globalExposure = globalExposure
        self.regionExposure = regionExposure
        self.clipping = clipping
        self.neutral = neutral
        self.saturation = saturation
        self.contrastLoss = contrastLoss
        self.noise = noise
        self.maskEdge = maskEdge
        self.movement = movement
        self.complexity = complexity
        self.missingEvidencePenalty = missingEvidencePenalty
        self.total = total
        self.rejected = rejected
        self.rejectionReasons = rejectionReasons
    }
}

/// Pure deterministic candidate scoring against frozen targets. No renderer, no async.
/// Pixel helpers operate on the candidate's own small render; every number is range-checked
/// so NaN or malformed bytes degrade to a penalized score, never a crash or a free pass.
enum AutoCandidateScoring {
    // MARK: Tuning (documented; ranges asserted by tests, never exact floats)

    /// Regions below this measured support do not earn a scoring slot.
    static let minimumRegionImportance: Float = 0.15
    /// Regions below this confidence do not earn a scoring slot.
    static let minimumRegionConfidence: Float = 0.3
    /// At most this many regions score; the rest are ignored, not approximated.
    static let maximumScoredRegions = 4

    /// Absolute highlight-clipping cap: above this *and* above the baseline, reject.
    static let absoluteClippingCap = 0.03
    /// Relative clipping tolerance before cost and guardrails engage.
    static let clippingTolerance = 0.01
    /// Absolute saturation cap: above this, reject regardless of baseline.
    static let absoluteSaturationCap = 0.97
    /// Absolute neutral-error cap where a reference exists: above this, reject.
    static let absoluteNeutralCap = 0.25
    /// Mask-edge proxy cap when the candidate changed masks: above this, reject.
    static let maskEdgeRejectionCap = 0.10
    /// Absolute Laplacian-noise cap: above this, cost hard without needing a baseline.
    static let absoluteNoiseCap = 0.25

    /// Score one rendered candidate. `baseline` carries the unchanged candidate's pixel facts
    /// (frozen after it renders); `isUnchanged` marks the baseline itself, which is always
    /// acceptable — guardrails judge changes, never the status quo.
    static func score(
        samples: RenderedPixelSamples,
        candidate: AutoCandidate,
        targets: AutoEvaluationTargets,
        baseline: AutoPixelBaseline,
        isUnchanged: Bool
    ) -> AutoCandidateScore {
        guard !samples.isEmpty else {
            var failed = AutoCandidateScore.acceptable
            failed.missingEvidencePenalty = 1
            failed.total = 1
            failed.rejected = !isUnchanged
            if !isUnchanged { failed.rejectionReasons = ["render-unmeasurable"] }
            return failed
        }

        let luma = lumaPlanes(samples)
        let median = percentile(luma.sorted(), 0.5)
        let highlightClip = fractionAbove(luma, 254.0 / 255.0)
        let color = RenderedPixelAnalyzer.correlatedColor(from: samples)
        let contrast = RenderedPixelAnalyzer.localContrast(from: samples).value
        let noise = laplacianNoise(samples)
        let castMagnitude = abs(Double(color.meanRGB.x - color.meanRGB.z))
            + abs(Double(color.meanRGB.y - (color.meanRGB.x + color.meanRGB.z) / 2))

        // Global exposure against the frozen intent-preserving target.
        let globalExposure = abs(median - targets.globalTargetMedian)

        // Important-region exposure from the candidate's own pixels cropped to the frozen
        // bounds. Unscorable regions contribute weight zero plus the missing-evidence penalty.
        var regionExposure = 0.0
        var regionWeight = 0.0
        var missingRegions = 0
        for region in targets.regions {
            guard region.isScorable, let bounds = region.bounds else {
                missingRegions += 1
                continue
            }
            guard let cropMedian = cropMedianLuma(samples, bounds: bounds) else {
                missingRegions += 1
                continue
            }
            let weight = region.importance * region.confidence
            regionExposure += abs(cropMedian - region.targetMedian) * weight
            regionWeight += weight
        }
        if regionWeight > 0 { regionExposure /= regionWeight }

        // Clipping above the restrained baseline.
        let clipping = max(0, highlightClip - max(targets.baselineHighlightClipping, 0.002))

        // Neutral-color error where supported: residual cast beyond 60% of the baseline cast.
        // A candidate that halves the cast scores zero here; one that invents cast pays.
        let neutral: Double
        let neutralUnsupported: Bool
        if targets.hasNeutralReference {
            neutral = max(0, castMagnitude - targets.baselineCastMagnitude * 0.6)
            neutralUnsupported = false
        } else {
            neutral = 0
            neutralUnsupported = true
        }

        // Excessive saturation above the restrained baseline cap.
        let saturationCap = min(targets.baselineSaturationP95, 0.85)
        let saturation = max(0, Double(color.saturationP95) - saturationCap)

        // Lost contrast and amplified noise, relative to the frozen unchanged render.
        let contrastLoss = max(0, baseline.localContrast - Double(contrast) - 0.01)
        var noiseCost = max(0, noise - baseline.noise * 1.4 - 0.005)
        if noise > absoluteNoiseCap { noiseCost += noise - absoluteNoiseCap }

        // Mask-edge proxy: a contrast spike concentrated where the candidate changed masks.
        // Candidates that touch no masks pay the spike at quarter weight (it may be legitimate
        // clarity); candidates that add masks pay full weight.
        let spike = max(0, Double(contrast) - baseline.localContrast * 1.6)
        let maskEdge = spike * (candidate.addedMaskCount > 0 ? 2.0 : 0.5)

        // Movement: normalized distance from the current edit over the candidate's own map.
        let movement = movementCost(candidate.changes)
        let complexity = Double(candidate.changedControlCount) * 0.01
            + Double(candidate.addedMaskCount) * 0.05

        var missingEvidencePenalty = Double(missingRegions) * 0.05
        if targets.regions.isEmpty { missingEvidencePenalty += 0.03 }
        if neutralUnsupported { missingEvidencePenalty += 0.02 }

        // Neutral placement is the primary defect for this policy. Giving it the strongest
        // weight prevents movement/complexity penalties from selecting a barely visible half-
        // strength candidate when a rendered full-strength lift materially closes the measured
        // luminance gap.
        let total = globalExposure * 2.0
            + regionExposure * 1.5
            + clipping * 3.0
            + neutral * 1.2
            + saturation * 1.0
            + contrastLoss * 1.0
            + noiseCost * 0.8
            + maskEdge * 2.0
            + movement * 0.15
            + complexity
            + missingEvidencePenalty

        // Guardrails: reject even when the aggregate total wins. The unchanged candidate is
        // never rejected — it is the status quo the user already sees.
        var rejectionReasons: [String] = []
        if !isUnchanged {
            if highlightClip > absoluteClippingCap
                && highlightClip > targets.baselineHighlightClipping + clippingTolerance
            {
                rejectionReasons.append("clipping")
            }
            if Double(color.saturationP95) > absoluteSaturationCap {
                rejectionReasons.append("color")
            }
            if targets.hasNeutralReference, neutral > absoluteNeutralCap {
                rejectionReasons.append("color")
            }
            if candidate.addedMaskCount > 0, maskEdge > maskEdgeRejectionCap {
                rejectionReasons.append("mask-edge")
            }
        }

        return AutoCandidateScore(
            globalExposure: finite(globalExposure),
            regionExposure: finite(regionExposure),
            clipping: finite(clipping),
            neutral: finite(neutral),
            saturation: finite(saturation),
            contrastLoss: finite(contrastLoss),
            noise: finite(noiseCost),
            maskEdge: finite(maskEdge),
            movement: finite(movement),
            complexity: finite(complexity),
            missingEvidencePenalty: finite(missingEvidencePenalty),
            total: finite(total),
            rejected: !rejectionReasons.isEmpty,
            rejectionReasons: rejectionReasons
        )
    }

    /// Normalized movement cost over a candidate's own change map. Each control contributes
    /// its delta as a fraction of its photographic envelope so one EV and one slider point
    /// are comparable.
    static func movementCost(_ changes: [AutoPolicyControl: AutoControlChange]) -> Double {
        var cost = 0.0
        for (control, change) in changes {
            let delta = abs(change.proposed - change.previous)
            let envelope: Double
            switch control {
            case .exposure: envelope = AutoExposureObjective.structurallyUnderexposedCorrectionCapEV
            case .temperature: envelope = 2500
            case .tint: envelope = 150
            default: envelope = 100
            }
            guard envelope > 0 else { continue }
            cost += min(delta / envelope, 2)
        }
        return cost
    }

    // MARK: - Pixel helpers (pure, range-checked)

    static func lumaPlanes(_ samples: RenderedPixelSamples) -> [Double] {
        let count = samples.width * samples.height
        guard count > 0, samples.bytes.count == count * 4 else { return [] }
        var luma = [Double](repeating: 0, count: count)
        samples.bytes.withUnsafeBufferPointer { buffer in
            for index in 0..<count {
                luma[index] = (0.2126 * Double(buffer[index * 4])
                    + 0.7152 * Double(buffer[index * 4 + 1])
                    + 0.0722 * Double(buffer[index * 4 + 2])) / 255
            }
        }
        return luma
    }

    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * clamped))]
    }

    static func fractionAbove(_ values: [Double], _ threshold: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        var hits = 0
        for value in values where value >= threshold { hits += 1 }
        return Double(hits) / Double(values.count)
    }

    /// Median luma of the candidate's pixels inside normalized `bounds`, or nil when the crop
    /// is degenerate — the caller degrades rather than fabricating.
    static func cropMedianLuma(
        _ samples: RenderedPixelSamples, bounds: NormalizedRect
    ) -> Double? {
        guard samples.width > 0, samples.height > 0,
              samples.bytes.count == samples.width * samples.height * 4
        else { return nil }
        let x0 = max(0, min(samples.width - 1, Int(Double(samples.width) * bounds.minX)))
        let x1 = max(0, min(samples.width, Int((Double(samples.width) * bounds.maxX).rounded(.up))))
        let y0 = max(0, min(samples.height - 1, Int(Double(samples.height) * bounds.minY)))
        let y1 = max(0, min(samples.height, Int((Double(samples.height) * bounds.maxY).rounded(.up))))
        guard x1 > x0, y1 > y0 else { return nil }
        var values: [Double] = []
        values.reserveCapacity((x1 - x0) * (y1 - y0))
        for y in y0..<y1 {
            for x in x0..<x1 {
                let offset = (y * samples.width + x) * 4
                values.append((0.2126 * Double(samples.bytes[offset])
                    + 0.7152 * Double(samples.bytes[offset + 1])
                    + 0.0722 * Double(samples.bytes[offset + 2])) / 255)
            }
        }
        guard !values.isEmpty else { return nil }
        return percentile(values.sorted(), 0.5)
    }

    /// Mean-absolute-Laplacian noise estimate over interior pixels. Same family as the
    /// native-detail estimator, operating on the small candidate render.
    static func laplacianNoise(_ samples: RenderedPixelSamples) -> Double {
        let width = samples.width
        let height = samples.height
        guard width >= 3, height >= 3,
              samples.bytes.count == width * height * 4
        else { return 0 }
        let luma = lumaPlanes(samples)
        guard luma.count == width * height else { return 0 }
        var total = 0.0
        var count = 0
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = luma[y * width + x]
                let laplacian = abs(
                    4 * center
                        - luma[y * width + x - 1] - luma[y * width + x + 1]
                        - luma[(y - 1) * width + x] - luma[(y + 1) * width + x]
                )
                total += laplacian
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let value = total / Double(count)
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func finite(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 10)
    }
}

/// The unchanged candidate's pixel facts, frozen after it renders so relative terms
/// (contrast loss, noise amplification) anchor to the status quo rather than to each
/// candidate's own render.
struct AutoPixelBaseline: Sendable, Equatable {
    let localContrast: Double
    let noise: Double

    static func frozen(samples: RenderedPixelSamples) -> AutoPixelBaseline {
        AutoPixelBaseline(
            localContrast: Double(RenderedPixelAnalyzer.localContrast(from: samples).value),
            noise: AutoCandidateScoring.laplacianNoise(samples)
        )
    }
}

// MARK: - Configuration and budget

/// Bounds for one coordinator run. Production uses `default`; tests may override individual
/// bounds through the memberwise initializer to prove the caps are hard — the override is
/// the documented seam, not a back door (the coordinator enforces whatever values it holds).
struct AutoCoordinatorConfiguration: Sendable, Equatable {
    /// Hard cap on small candidate renders per run.
    var maxSmallRenders: Int
    /// Hard cap on expensive RAW redevelopments per run.
    var maxRAWRedevelopments: Int
    /// Wall-clock budget for the whole run. Checked between candidates; the unchanged
    /// baseline always renders first even when the budget is already spent.
    var timeBudgetSeconds: Double
    /// A changed candidate must beat the unchanged total by at least this much to win;
    /// otherwise the result reports no further improvement.
    var improvementThreshold: Double
    /// Totals within this epsilon are effectively tied; ties prefer the simpler candidate.
    var tieEpsilon: Double
    /// Stop early after this many consecutive non-improving candidates (past the minimum).
    var convergenceWindow: Int
    /// Minimum evaluations before convergence can stop the run.
    var minimumEvaluationsBeforeConvergence: Int
    /// Long edge for candidate renders. Small by design — candidates are evidence, not previews.
    var candidateLongEdge: Int
    var space: WorkingSpace

    static let `default` = AutoCoordinatorConfiguration()

    init(
        maxSmallRenders: Int = 24,
        maxRAWRedevelopments: Int = 4,
        timeBudgetSeconds: Double = 8,
        improvementThreshold: Double = 0.015,
        tieEpsilon: Double = 0.004,
        convergenceWindow: Int = 3,
        minimumEvaluationsBeforeConvergence: Int = 3,
        candidateLongEdge: Int = 256,
        space: WorkingSpace = .sRGB
    ) {
        self.maxSmallRenders = max(0, maxSmallRenders)
        self.maxRAWRedevelopments = max(0, maxRAWRedevelopments)
        self.timeBudgetSeconds = max(0, timeBudgetSeconds)
        self.improvementThreshold = max(0, improvementThreshold)
        self.tieEpsilon = max(0, tieEpsilon)
        self.convergenceWindow = max(1, convergenceWindow)
        self.minimumEvaluationsBeforeConvergence = max(1, minimumEvaluationsBeforeConvergence)
        self.candidateLongEdge = max(1, candidateLongEdge)
        self.space = space
    }
}

/// Observable render-budget counters for one run. Returned with every result so tests and
/// diagnostics can assert the bounds held. The seconds fields are low-overhead
/// `ContinuousClock` reads around the sampler and the pure scoring function; they never
/// influence selection.
struct AutoRenderBudgetUsage: Sendable, Equatable {
    var smallRenders: Int
    var rawRedevelopments: Int
    var evaluated: Int
    var skipped: Int
    var elapsedSeconds: Double
    /// Time spent inside the sampler (candidate renders), for the KRMA-352 stage breakdown.
    var renderSeconds: Double = 0
    /// RAW-redevelopment subset of `renderSeconds`.
    var rawRenderSeconds: Double = 0
    /// Time spent in pure scoring and guardrail evaluation (validation).
    var scoringSeconds: Double = 0

    static let none = AutoRenderBudgetUsage(
        smallRenders: 0, rawRedevelopments: 0, evaluated: 0, skipped: 0, elapsedSeconds: 0
    )
}

// MARK: - Result

/// The outcome of one coordinator run. `document` is the selected candidate's document or the
/// unchanged input — the coordinator never partially applies edits and never mutates its input.
struct AutoEnhancementCoordinatorResult: Sendable, Equatable {
    enum Status: String, Codable, Sendable, Equatable {
        /// A changed candidate beat unchanged by more than the improvement threshold.
        case improved
        /// Unchanged wins: either the best change was negligible or no proposals existed.
        case unchanged
        /// Every changed candidate was rejected or failed to render; the document is unchanged.
        case noCandidate
        /// The run was cancelled (including caller-driven navigation teardown).
        case cancelled
        /// The document revision moved under the run; nothing was applied.
        case staleRevision
        /// Even the unchanged baseline could not be rendered; nothing was applied.
        case renderUnavailable
    }

    let status: Status
    let document: EditDocument
    /// Provenance of the selected candidate; nil unless `status == .improved`.
    let provenance: AutoCandidateProvenance?
    /// Human/agent-readable summary, including the no-improvement and no-candidate reasons.
    let message: String
    let budget: AutoRenderBudgetUsage
    /// Rejection/failure notes per changed candidate, keyed by provenance name.
    let candidateNotes: [String: String]
    /// Validation components for the selected candidate, when one completed successfully.
    /// Failure/no-op results leave this nil rather than fabricating measurements.
    let selectedScore: AutoCandidateScore?
    /// Hash of the input document this run evaluated, and the source fingerprint it rendered.
    let evaluatedDocumentHash: String
    let sourceFingerprint: String

    /// True when the caller should leave the document exactly as it is.
    var leavesDocumentUnchanged: Bool {
        switch status {
        case .unchanged, .noCandidate, .cancelled, .staleRevision, .renderUnavailable:
            return true
        case .improved:
            return false
        }
    }
}

// MARK: - Coordinator

/// Asynchronous bounded candidate evaluation and selection.
///
/// The engine is the narrow `CurrentEditSampling` seam — production passes a `RenderEngine`,
/// which renders each candidate through the real pipeline. Tests pass a deterministic stub.
/// `CIImage`/`CIFilter`/`CIContext` never cross this boundary; only `RenderedPixelSamples`
/// values do, so the coordinator stays actor-safe as a plain `Sendable` struct.
struct AutoEnhancementCoordinator: Sendable {
    let engine: any CurrentEditSampling
    let configuration: AutoCoordinatorConfiguration

    init(
        engine: any CurrentEditSampling,
        configuration: AutoCoordinatorConfiguration = .default
    ) {
        self.engine = engine
        self.configuration = configuration
    }

    /// Evaluate candidates for `current` and select the best acceptable result.
    ///
    /// - Parameters:
    ///   - expectedDocumentHash: must equal `current.editHash`. A mismatch returns
    ///     `.staleRevision` without rendering anything.
    ///   - facts/regions: frozen analysis evidence. Targets derive from these once and never
    ///     move for the rest of the run.
    ///   - native/apple: full-strength proposals; nil or no-op means that family contributes
    ///     no candidate. Reduced-strength fallbacks derive from the same proposals.
    ///   - lut: the active Look, forwarded to the sampler so candidates render under it.
    func run(
        source: ImageSource,
        current: EditDocument,
        expectedDocumentHash: String,
        facts: AutoEnhancementFacts,
        regions: [AnalyzedRegion] = [],
        native: AutoEnhancementProposal? = nil,
        apple: AppleReferenceProposal? = nil,
        sourceKind: AutoSourceKind,
        lut: CubeLUT? = nil,
        onProgress: (@MainActor @Sendable (AutoEnhancementPhase) -> Void)? = nil
    ) async -> AutoEnhancementCoordinatorResult {
        let started = Date()
        let sourceKindIsRAW = source.kind == .raw
        // KRMA-352 stage clocks. Two `ContinuousClock` reads per render/score; the values
        // are recorded in the budget and never influence selection.
        let stageClock = ContinuousClock()
        var renderSeconds = 0.0
        var rawRenderSeconds = 0.0
        var scoringSeconds = 0.0

        func budget(elapsed: Double, usage: (small: Int, raw: Int, evaluated: Int, skipped: Int))
            -> AutoRenderBudgetUsage
        {
            AutoRenderBudgetUsage(
                smallRenders: usage.small, rawRedevelopments: usage.raw,
                evaluated: usage.evaluated, skipped: usage.skipped, elapsedSeconds: elapsed,
                renderSeconds: renderSeconds, rawRenderSeconds: rawRenderSeconds,
                scoringSeconds: scoringSeconds
            )
        }

        func finish(
            _ status: AutoEnhancementCoordinatorResult.Status,
            document: EditDocument,
            provenance: AutoCandidateProvenance?,
            message: String,
            usage: (small: Int, raw: Int, evaluated: Int, skipped: Int),
            notes: [String: String],
            selectedScore: AutoCandidateScore? = nil
        ) -> AutoEnhancementCoordinatorResult {
            AutoEnhancementCoordinatorResult(
                status: status, document: document, provenance: provenance, message: message,
                budget: budget(elapsed: Date().timeIntervalSince(started), usage: usage),
                candidateNotes: notes,
                selectedScore: selectedScore,
                evaluatedDocumentHash: current.editHash,
                sourceFingerprint: source.cacheFingerprint
            )
        }

        // Freeze the revision first: a stale caller must not spend renders.
        guard current.editHash == expectedDocumentHash else {
            return finish(
                .staleRevision, document: current, provenance: nil,
                message: "The document changed before Auto finished measuring it; nothing was applied.",
                usage: (0, 0, 0, 0), notes: [:]
            )
        }
        if Task.isCancelled {
            return finish(
                .cancelled, document: current, provenance: nil,
                message: "Auto was cancelled before evaluation began; nothing was applied.",
                usage: (0, 0, 0, 0), notes: [:]
            )
        }

        await onProgress?(.renderingCandidates)

        // Freeze targets and candidates for the entire run.
        let targets = AutoEvaluationTargets.frozen(facts: facts, regions: regions)
        let candidates = AutoCandidateGenerator.generate(
            current: current, native: native, apple: apple, sourceKind: sourceKind
        )

        var smallRenders = 0
        var rawRedevelopments = 0
        var evaluated = 0
        var skipped = 0
        var notes: [String: String] = [:]

        /// Render one candidate within budget, or return nil with the skip recorded.
        func renderWithinBudget(_ candidate: AutoCandidate) async -> RenderedPixelSamples? {
            guard smallRenders < configuration.maxSmallRenders else {
                skipped += 1
                notes[candidate.provenance.displayName] =
                    "skipped: small-render budget (\(configuration.maxSmallRenders)) exhausted"
                return nil
            }
            if sourceKindIsRAW, rawRedevelopments >= configuration.maxRAWRedevelopments {
                skipped += 1
                notes[candidate.provenance.displayName] =
                    "skipped: RAW-redevelopment budget (\(configuration.maxRAWRedevelopments)) exhausted"
                return nil
            }
            if Date().timeIntervalSince(started) >= configuration.timeBudgetSeconds {
                skipped += 1
                notes[candidate.provenance.displayName] = "skipped: time budget exhausted"
                return nil
            }
            smallRenders += 1
            if sourceKindIsRAW { rawRedevelopments += 1 }
            let renderStart = stageClock.now
            let timedSamples = await engine.renderedSamples(
                source: source, document: candidate.document, lut: lut,
                targetLongEdge: configuration.candidateLongEdge, space: configuration.space
            )
            let renderElapsed = stageClock.now - renderStart
            renderSeconds += AutoTimingClock.seconds(renderElapsed)
            if sourceKindIsRAW {
                rawRenderSeconds += AutoTimingClock.seconds(renderElapsed)
            }
            return timedSamples
        }

        // The unchanged baseline always renders first: it is both candidate zero and the
        // frozen pixel reference for every relative term. Budget gates apply to changed
        // candidates only — a spent budget stops the run after the baseline, never before it.
        smallRenders += 1
        if sourceKindIsRAW { rawRedevelopments += 1 }
        let baselineRenderStart = stageClock.now
        let baselineRender = await engine.renderedSamples(
            source: source, document: candidates[0].document, lut: lut,
            targetLongEdge: configuration.candidateLongEdge, space: configuration.space
        )
        let baselineRenderElapsed = stageClock.now - baselineRenderStart
        renderSeconds += AutoTimingClock.seconds(baselineRenderElapsed)
        if sourceKindIsRAW {
            rawRenderSeconds += AutoTimingClock.seconds(baselineRenderElapsed)
        }
        guard let baselineSamples = baselineRender else {
            if Task.isCancelled {
                return finish(
                    .cancelled, document: current, provenance: nil,
                    message: "Auto was cancelled while rendering the baseline; nothing was applied.",
                    usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
                )
            }
            return finish(
                .renderUnavailable, document: current, provenance: nil,
                message: "The current edit could not be rendered for evaluation; nothing was applied.",
                usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
            )
        }
        if Task.isCancelled {
            return finish(
                .cancelled, document: current, provenance: nil,
                message: "Auto was cancelled after the baseline render; nothing was applied.",
                usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
            )
        }
        let pixelBaseline = AutoPixelBaseline.frozen(samples: baselineSamples)
        await onProgress?(.validating)
        let baselineScoreStart = stageClock.now
        let baselineScore = AutoCandidateScoring.score(
            samples: baselineSamples, candidate: candidates[0],
            targets: targets, baseline: pixelBaseline, isUnchanged: true
        )
        scoringSeconds += AutoTimingClock.seconds(stageClock.now - baselineScoreStart)
        evaluated += 1

        struct Evaluated: Sendable {
            let index: Int
            let candidate: AutoCandidate
            let score: AutoCandidateScore
        }
        var completed: [Evaluated] = [
            Evaluated(index: 0, candidate: candidates[0], score: baselineScore)
        ]

        // Sequential changed-candidate evaluation: no task or cache leaks by construction,
        // and each step re-checks cancellation, revision, budget, and convergence.
        var bestChanged: Evaluated?
        var consecutiveNonImproving = 0
        for index in candidates.indices.dropFirst() {
            if Task.isCancelled {
                return finish(
                    .cancelled, document: current, provenance: nil,
                    message: "Auto was cancelled during candidate evaluation; nothing was applied.",
                    usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
                )
            }
            // The revision cannot move under a value input, but the guard is cheap and makes
            // the stale-revision contract explicit end to end.
            guard current.editHash == expectedDocumentHash else {
                return finish(
                    .staleRevision, document: current, provenance: nil,
                    message: "The document changed during Auto evaluation; nothing was applied.",
                    usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
                )
            }
            if evaluated >= configuration.minimumEvaluationsBeforeConvergence,
               consecutiveNonImproving >= configuration.convergenceWindow
            {
                skipped += candidates.count - index
                notes["convergence"] =
                    "stopped after \(consecutiveNonImproving) consecutive non-improving candidates"
                break
            }
            guard let samples = await renderWithinBudget(candidates[index]) else { continue }
            if Task.isCancelled {
                return finish(
                    .cancelled, document: current, provenance: nil,
                    message: "Auto was cancelled during candidate evaluation; nothing was applied.",
                    usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
                )
            }
            let scoreStart = stageClock.now
            let score = AutoCandidateScoring.score(
                samples: samples, candidate: candidates[index],
                targets: targets, baseline: pixelBaseline, isUnchanged: false
            )
            scoringSeconds += AutoTimingClock.seconds(stageClock.now - scoreStart)
            evaluated += 1
            let record = Evaluated(index: index, candidate: candidates[index], score: score)
            completed.append(record)

            if score.rejected {
                notes[candidates[index].provenance.displayName] =
                    "rejected: \(score.rejectionReasons.joined(separator: ", "))"
                consecutiveNonImproving += 1
                continue
            }
            if let best = bestChanged {
                if score.total < best.score.total - configuration.tieEpsilon {
                    bestChanged = record
                    consecutiveNonImproving = 0
                } else {
                    consecutiveNonImproving += 1
                }
            } else {
                // The first acceptable changed candidate only counts as improving when it
                // actually beats the baseline; otherwise the convergence window still advances.
                bestChanged = record
                consecutiveNonImproving =
                    record.score.total < baselineScore.total - configuration.tieEpsilon ? 0 : 1
            }
        }

        // Selection over completed acceptable candidates with tie-breaking: within the tie
        // epsilon the simpler edit wins (fewer changed controls, then fewer added masks,
        // then earlier generation order — unchanged is index zero, so it wins every exact tie).
        let acceptableChanged = completed.dropFirst().filter { !$0.score.rejected }
        var winner: Evaluated?
        for record in acceptableChanged {
            guard let current = winner else {
                winner = record
                continue
            }
            if record.score.total < current.score.total - configuration.tieEpsilon {
                winner = record
            } else if abs(record.score.total - current.score.total) <= configuration.tieEpsilon {
                if record.candidate.changedControlCount < current.candidate.changedControlCount {
                    winner = record
                } else if record.candidate.changedControlCount
                    == current.candidate.changedControlCount,
                    record.candidate.addedMaskCount < current.candidate.addedMaskCount
                {
                    winner = record
                }
            }
        }

        guard let selected = winner else {
            if acceptableChanged.isEmpty, completed.count > 1 {
                let reasons = completed.dropFirst().map { record in
                    let name = record.candidate.provenance.displayName
                    if record.score.rejected {
                        return "\(name) rejected (\(record.score.rejectionReasons.joined(separator: ", ")))"
                    }
                    return "\(name) failed to render"
                }
                return finish(
                    .noCandidate, document: current, provenance: nil,
                    message: "No acceptable candidate was found (\(reasons.joined(separator: "; "))); "
                        + "the document is unchanged.",
                    usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
                )
            }
            if skipped > 0 {
                return finish(
                    .unchanged, document: current, provenance: nil,
                    message: "Changed candidates could not be evaluated within the render budget "
                        + "(\(skipped) skipped); the current edit stands.",
                    usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
                )
            }
            return finish(
                .unchanged, document: current, provenance: nil,
                message: "No proposals were offered, so the current edit stands.",
                usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
            )
        }

        // The unchanged candidate wins when improvement is negligible — even when a changed
        // candidate is technically ahead, adopting churn the viewer cannot see is churn.
        if selected.score.total > baselineScore.total - configuration.improvementThreshold {
            return finish(
                .unchanged, document: current, provenance: nil,
                message: "The best candidate (\(selected.candidate.provenance.displayName)) "
                    + "improved negligibly over the current edit; no further improvement was found.",
                usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
            )
        }

        // Final revision check before handing back an edit to apply.
        guard current.editHash == expectedDocumentHash, !Task.isCancelled else {
            if Task.isCancelled {
                return finish(
                    .cancelled, document: current, provenance: nil,
                    message: "Auto was cancelled before selection completed; nothing was applied.",
                    usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
                )
            }
            return finish(
                .staleRevision, document: current, provenance: nil,
                message: "The document changed during Auto evaluation; nothing was applied.",
                usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes
            )
        }

        return finish(
            .improved, document: selected.candidate.document,
            provenance: selected.candidate.provenance,
            message: "Selected \(selected.candidate.provenance.displayName) "
                + "(\(selected.candidate.changedControlCount) controls) over the current edit.",
            usage: (smallRenders, rawRedevelopments, evaluated, skipped), notes: notes,
            selectedScore: selected.score
        )
    }
}
