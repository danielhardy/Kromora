import Foundation

enum AutoLightParameter: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case exposure
    case contrast
    case highlights
    case shadows
    case whites
    case blacks
}

/// One evaluator's bounded proposal. Preferred/minimum/maximum are concrete Light-control values,
/// not renderer units. Reconciliation uses the intersection of all applicable bounds.
struct AdjustmentProposal: Codable, Sendable, Equatable {
    let parameter: AutoLightParameter
    let preferred: Double
    let minimum: Double
    let maximum: Double
    let confidence: Float
    let reason: String

    init(
        parameter: AutoLightParameter,
        preferred: Double,
        minimum: Double,
        maximum: Double,
        confidence: Float,
        reason: String
    ) {
        self.parameter = parameter
        self.preferred = preferred.isFinite ? preferred : 0
        self.minimum = minimum.isFinite ? minimum : 0
        self.maximum = maximum.isFinite ? maximum : 0
        self.confidence = Self.unit(confidence)
        self.reason = reason
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct AutoParameterRationale: Codable, Sendable, Equatable {
    let parameter: AutoLightParameter
    let adjustment: Double
    let confidence: Float
    let explanation: String

    init(
        parameter: AutoLightParameter,
        adjustment: Double = 0,
        confidence: Float = 0,
        explanation: String = "No subject-aware evidence was available."
    ) {
        self.parameter = parameter
        self.adjustment = adjustment.isFinite ? adjustment : 0
        self.confidence = min(max(confidence.isFinite ? confidence : 0, 0), 1)
        self.explanation = explanation
    }
}

/// Structured, inspectable explanations for the six global Light values.
struct AutoRationale: Codable, Sendable, Equatable {
    let exposure: AutoParameterRationale
    let contrast: AutoParameterRationale
    let highlights: AutoParameterRationale
    let shadows: AutoParameterRationale
    let whites: AutoParameterRationale
    let blacks: AutoParameterRationale

    init(
        exposure: AutoParameterRationale = AutoParameterRationale(parameter: .exposure),
        contrast: AutoParameterRationale = AutoParameterRationale(parameter: .contrast),
        highlights: AutoParameterRationale = AutoParameterRationale(parameter: .highlights),
        shadows: AutoParameterRationale = AutoParameterRationale(parameter: .shadows),
        whites: AutoParameterRationale = AutoParameterRationale(parameter: .whites),
        blacks: AutoParameterRationale = AutoParameterRationale(parameter: .blacks)
    ) {
        self.exposure = exposure
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
    }

    static let neutral = AutoRationale()

    func value(for parameter: AutoLightParameter) -> AutoParameterRationale {
        switch parameter {
        case .exposure: return exposure
        case .contrast: return contrast
        case .highlights: return highlights
        case .shadows: return shadows
        case .whites: return whites
        case .blacks: return blacks
        }
    }
}

struct AutoLightConfiguration: Codable, Sendable, Equatable {
    static let currentVersion = 2
    static let `default` = AutoLightConfiguration()

    let version: Int
    let confidenceFloor: Float
    let targetMedian: Float

    init(
        version: Int = AutoLightConfiguration.currentVersion,
        confidenceFloor: Float = 0.45,
        targetMedian: Float = 0.48
    ) {
        self.version = max(1, min(version, Self.currentVersion))
        self.confidenceFloor = Self.unit(confidenceFloor)
        self.targetMedian = min(max(targetMedian.isFinite ? targetMedian : 0.48, 0.05), 0.95)
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// The pure subject-aware Auto policy. It consumes only scalar photo facts and emits value-state;
/// all Vision/Core Image work is performed before this boundary by PhotoAnalysisCoordinator.
struct AutoLightEngine: Sendable {
    static let currentVersion = AutoLightConfiguration.currentVersion

    func evaluate(
        analysis: PhotoAnalysis,
        currentEdits: EditDocument = EditDocument(),
        configuration: AutoLightConfiguration = .default
    ) -> AutoAdjustmentResult {
        let proposals = Self.proposals(analysis: analysis, configuration: configuration)
        let light = Self.reconcile(proposals: proposals, current: currentEdits.light)
        let rationale = Self.rationale(from: proposals, light: light)
        let statistics = AutoImageStatistics(analysis: analysis)
        return AutoAdjustmentResult(
            statistics: statistics,
            light: light,
            color: .neutral,
            algorithmVersion: configuration.version,
            rationale: rationale
        )
    }

    static func evaluate(
        analysis: PhotoAnalysis,
        currentEdits: EditDocument = EditDocument(),
        configuration: AutoLightConfiguration = .default
    ) -> AutoAdjustmentResult {
        AutoLightEngine().evaluate(
            analysis: analysis, currentEdits: currentEdits, configuration: configuration
        )
    }

    static func proposals(
        analysis: PhotoAnalysis,
        configuration: AutoLightConfiguration = .default
    ) -> [AdjustmentProposal] {
        [
            ExposureEvaluator.evaluate(analysis: analysis, configuration: configuration),
            HighlightEvaluator.evaluate(analysis: analysis, configuration: configuration),
            ShadowEvaluator.evaluate(analysis: analysis, configuration: configuration),
            WhitePointEvaluator.evaluate(analysis: analysis, configuration: configuration),
            BlackPointEvaluator.evaluate(analysis: analysis, configuration: configuration),
            ContrastEvaluator.evaluate(analysis: analysis, configuration: configuration),
        ]
    }

    private static func reconcile(
        proposals: [AdjustmentProposal], current: LightAdjustments
    ) -> LightAdjustments {
        var result = current
        for parameter in AutoLightParameter.allCases {
            guard let proposal = proposals.first(where: { $0.parameter == parameter }) else { continue }
            let modelRange = modelRange(for: parameter)
            let lower = max(modelRange.lowerBound, min(proposal.minimum, proposal.maximum))
            let upper = min(modelRange.upperBound, max(proposal.minimum, proposal.maximum))
            let value: Double
            if lower <= upper {
                value = min(max(proposal.preferred, lower), upper)
            } else {
                // Conflicting evaluators have no common interval. Prefer the conservative value
                // nearest neutral, still respecting the actual Light model range.
                value = min(max(0, modelRange.lowerBound), modelRange.upperBound)
            }
            set(value, for: parameter, in: &result)
        }
        return result
    }

    private static func rationale(
        from proposals: [AdjustmentProposal], light: LightAdjustments
    ) -> AutoRationale {
        func make(_ parameter: AutoLightParameter) -> AutoParameterRationale {
            guard let proposal = proposals.first(where: { $0.parameter == parameter }) else {
                return AutoParameterRationale(parameter: parameter)
            }
            return AutoParameterRationale(
                parameter: parameter,
                adjustment: value(for: parameter, in: light),
                confidence: proposal.confidence,
                explanation: proposal.reason
            )
        }
        return AutoRationale(
            exposure: make(.exposure), contrast: make(.contrast),
            highlights: make(.highlights), shadows: make(.shadows),
            whites: make(.whites), blacks: make(.blacks)
        )
    }

    private static func modelRange(for parameter: AutoLightParameter) -> ClosedRange<Double> {
        switch parameter {
        case .exposure: return LightAdjustments.exposureRange
        case .contrast: return LightAdjustments.contrastRange
        case .highlights: return LightAdjustments.highlightsRange
        case .shadows: return LightAdjustments.shadowsRange
        case .whites: return LightAdjustments.whitesRange
        case .blacks: return LightAdjustments.blacksRange
        }
    }

    private static func value(for parameter: AutoLightParameter, in light: LightAdjustments) -> Double {
        switch parameter {
        case .exposure: return light.exposure
        case .contrast: return light.contrast
        case .highlights: return light.highlights
        case .shadows: return light.shadows
        case .whites: return light.whites
        case .blacks: return light.blacks
        }
    }

    private static func set(_ value: Double, for parameter: AutoLightParameter, in light: inout LightAdjustments) {
        switch parameter {
        case .exposure: light.exposure = value
        case .contrast: light.contrast = value
        case .highlights: light.highlights = value
        case .shadows: light.shadows = value
        case .whites: light.whites = value
        case .blacks: light.blacks = value
        }
    }
}

private enum AutoLightMath {
    static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    static func smooth(_ value: Float, start: Float, full: Float) -> Float {
        guard full > start else { return value >= full ? 1 : 0 }
        let t = unit((value - start) / (full - start))
        return t * t * (3 - 2 * t)
    }

    static func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    static func confidence(_ analysis: PhotoAnalysis) -> Float {
        unit(analysis.quality.overallConfidence)
    }
}

private enum AutoLightBounds {
    static let exposure = -1.25...1.25
    static let contrast = -30.0...42.0
    static let highlights = -38.0...8.0
    static let shadows = -8.0...38.0
    static let whites = -22.0...18.0
    static let blacks = -18.0...22.0
}

/// Corpus-tuned response constants. These remain grouped by policy rather than being exposed as
/// configuration: changing them changes the meaning of an Auto result and therefore requires an
/// algorithm-version bump. The before/after corpus measurements are recorded in
/// `docs/ENGINEERING_GUIDE.md`.
private enum AutoLightTuning {
    static let exposureIntentExponent = 4.0
    static let backlightExposureLift = 0.20
    static let highlightTailScale = 14.0
    static let highlightClippingScale = 24.0
    static let backlightHighlightScale = 14.0
    static let highKeyHighlightBrake = 0.75
    static let shadowLiftScale = 10.0
    static let backlightShadowLiftScale = 20.0
    static let lowKeyShadowBrake = 0.85
    static let lowKeyWhitePointBrake = 0.80
    static let highKeyBlackPointBrake = 0.80
    static let contrastTargetSpread = 0.78
}

private enum AutoLightSceneSignals {
    static func exposure(_ analysis: PhotoAnalysis, configuration: AutoLightConfiguration) -> AdjustmentProposal {
        let tone = analysis.globalTone
        let median = max(tone.p50, 0.03)
        var desired = log2(Double(configuration.targetMedian / median))
        // Tonal intent is a soft brake, not a switch. Fourth-power attenuation keeps an intentional
        // key close to its original exposure while still allowing a clearly misplaced median to
        // receive a modest correction.
        desired *= pow(
            Double(1 - analysis.scene.highKeyLikelihood),
            AutoLightTuning.exposureIntentExponent
        )
        desired *= pow(
            Double(1 - analysis.scene.lowKeyLikelihood),
            AutoLightTuning.exposureIntentExponent
        )
        let backlightLift = Double(analysis.scene.backlightingLikelihood)
            * Double(analysis.scene.subjectProminence) * AutoLightTuning.backlightExposureLift
        desired += backlightLift
        return AdjustmentProposal(
            parameter: .exposure,
            preferred: AutoLightMath.bounded(desired, AutoLightBounds.exposure),
            minimum: AutoLightBounds.exposure.lowerBound,
            maximum: AutoLightBounds.exposure.upperBound,
            confidence: AutoLightMath.confidence(analysis),
            reason: "Median (\(format(tone.p50))) EV correction, restrained by tonal-key intent."
        )
    }

    static func highlights(_ analysis: PhotoAnalysis) -> AdjustmentProposal {
        let tone = analysis.globalTone
        let tail = Double(AutoLightMath.smooth(tone.p95, start: 0.72, full: 0.94))
        let clipping = Double(AutoLightMath.unit(tone.highlightClippingFraction * 3))
        let backlightProtection = Double(analysis.scene.backlightingLikelihood) * 0.35
        let intentBrake = 1
            - Double(analysis.scene.highKeyLikelihood) * AutoLightTuning.highKeyHighlightBrake
        let value = -(tail * AutoLightTuning.highlightTailScale
            + clipping * AutoLightTuning.highlightClippingScale
            + backlightProtection * AutoLightTuning.backlightHighlightScale) * intentBrake
        return AdjustmentProposal(
            parameter: .highlights,
            preferred: AutoLightMath.bounded(value, AutoLightBounds.highlights),
            minimum: AutoLightBounds.highlights.lowerBound, maximum: AutoLightBounds.highlights.upperBound,
            confidence: AutoLightMath.confidence(analysis),
            reason: "Protects bright percentile tails and backlit background."
        )
    }

    static func shadows(_ analysis: PhotoAnalysis) -> AdjustmentProposal {
        let tone = analysis.globalTone
        let lift = Double(AutoLightMath.smooth(1 - tone.p10, start: 0.55, full: 0.90))
            * AutoLightTuning.shadowLiftScale
        let backlightLift = Double(analysis.scene.backlightingLikelihood)
            * AutoLightTuning.backlightShadowLiftScale
        let intentPreservation = 1 - Double(analysis.scene.lowKeyLikelihood)
            * AutoLightTuning.lowKeyShadowBrake
        let value = (lift + backlightLift) * intentPreservation
        return AdjustmentProposal(
            parameter: .shadows,
            preferred: AutoLightMath.bounded(value, AutoLightBounds.shadows),
            minimum: AutoLightBounds.shadows.lowerBound, maximum: AutoLightBounds.shadows.upperBound,
            confidence: AutoLightMath.confidence(analysis),
            reason: "Opens dark subject tones while preserving intentional low-key scenes."
        )
    }

    static func whites(_ analysis: PhotoAnalysis) -> AdjustmentProposal {
        let tone = analysis.globalTone
        let value = ((0.86 - Double(tone.p95)) * 62
            - Double(AutoLightMath.unit(tone.highlightClippingFraction * 2)) * 18)
            * (1
                - Double(analysis.scene.lowKeyLikelihood) * AutoLightTuning.lowKeyWhitePointBrake)
        return AdjustmentProposal(
            parameter: .whites,
            preferred: AutoLightMath.bounded(value, AutoLightBounds.whites),
            minimum: AutoLightBounds.whites.lowerBound, maximum: AutoLightBounds.whites.upperBound,
            confidence: AutoLightMath.confidence(analysis),
            reason: "Sets the white point from the upper percentile without clipping."
        )
    }

    static func blacks(_ analysis: PhotoAnalysis) -> AdjustmentProposal {
        let tone = analysis.globalTone
        let value = (0.12 - Double(tone.p05)) * 48
            * (1 - Double(analysis.scene.lowKeyLikelihood) * 0.8)
            * (1
                - Double(analysis.scene.highKeyLikelihood) * AutoLightTuning.highKeyBlackPointBrake)
        return AdjustmentProposal(
            parameter: .blacks,
            preferred: AutoLightMath.bounded(value, AutoLightBounds.blacks),
            minimum: AutoLightBounds.blacks.lowerBound, maximum: AutoLightBounds.blacks.upperBound,
            confidence: AutoLightMath.confidence(analysis),
            reason: "Sets the black point while respecting low-key intent."
        )
    }

    static func contrast(_ analysis: PhotoAnalysis) -> AdjustmentProposal {
        let spread = analysis.globalTone.p95 - analysis.globalTone.p05
        let value = (AutoLightTuning.contrastTargetSpread - Double(spread)) * 46
            * (1 - Double(analysis.scene.backlightingLikelihood) * 0.35)
        return AdjustmentProposal(
            parameter: .contrast,
            preferred: AutoLightMath.bounded(value, AutoLightBounds.contrast),
            minimum: AutoLightBounds.contrast.lowerBound, maximum: AutoLightBounds.contrast.upperBound,
            confidence: AutoLightMath.confidence(analysis),
            reason: "Responds to usable dynamic range without flattening a backlit scene."
        )
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.2f", value)
    }
}

enum ExposureEvaluator {
    static func evaluate(analysis: PhotoAnalysis, configuration: AutoLightConfiguration = .default) -> AdjustmentProposal {
        AutoLightSceneSignals.exposure(analysis, configuration: configuration)
    }
}

enum HighlightEvaluator {
    static func evaluate(analysis: PhotoAnalysis, configuration: AutoLightConfiguration = .default) -> AdjustmentProposal {
        AutoLightSceneSignals.highlights(analysis)
    }
}

enum ShadowEvaluator {
    static func evaluate(analysis: PhotoAnalysis, configuration: AutoLightConfiguration = .default) -> AdjustmentProposal {
        AutoLightSceneSignals.shadows(analysis)
    }
}

enum WhitePointEvaluator {
    static func evaluate(analysis: PhotoAnalysis, configuration: AutoLightConfiguration = .default) -> AdjustmentProposal {
        AutoLightSceneSignals.whites(analysis)
    }
}

enum BlackPointEvaluator {
    static func evaluate(analysis: PhotoAnalysis, configuration: AutoLightConfiguration = .default) -> AdjustmentProposal {
        AutoLightSceneSignals.blacks(analysis)
    }
}

enum ContrastEvaluator {
    static func evaluate(analysis: PhotoAnalysis, configuration: AutoLightConfiguration = .default) -> AdjustmentProposal {
        AutoLightSceneSignals.contrast(analysis)
    }
}
