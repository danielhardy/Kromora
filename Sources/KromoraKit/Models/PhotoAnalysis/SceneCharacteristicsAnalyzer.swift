import Foundation

/// The broad tonal intent suggested by the analyzed luminance distribution.
enum TonalKey: String, Codable, Sendable, Equatable, CaseIterable {
    case low
    case mid
    case high
}

/// Descriptive scene facts consumed by policy layers such as AutoLightEngine.
///
/// The likelihoods are deliberately independent, continuous scores. A scene can therefore be
/// both somewhat low-key and somewhat backlit; Auto decides how to respond to that combination.
/// No likelihood is a preset: policy scales or skips each correction by the likelihood and by
/// `sceneConfidence`, never by a winning label.
struct SceneCharacteristics: Codable, Sendable, Equatable {
    let hasFaces: Bool
    let hasPeople: Bool
    let subjectProminence: Float
    let subjectBackgroundSeparation: Float
    let tonalKey: TonalKey
    let dynamicRange: Float
    let backlightingLikelihood: Float
    let highKeyLikelihood: Float
    let lowKeyLikelihood: Float
    // KRMA-344 scene evidence. Each is an independent 0…1 likelihood, not a preset.
    let nightLikelihood: Float
    let sunsetWarmLikelihood: Float
    let snowLikelihood: Float
    let fogLikelihood: Float
    let monochromeLikelihood: Float
    let mixedLightLikelihood: Float
    let daylightLikelihood: Float
    /// Aggregated confidence in the likelihoods above. Missing signals (no regions, no Vision
    /// labels) and contradictory strong likelihoods reduce it; usable tone/color facts remain.
    let sceneConfidence: Float
    let provenance: SceneProvenance

    /// Neutral confidence for values persisted before KRMA-344 recorded it: exactly halfway
    /// between usable and unusable, so policy scales corrections down without discarding the
    /// older backlight/high/low-key likelihoods.
    static let legacyConfidence: Float = 0.5

    init(
        hasFaces: Bool = false,
        hasPeople: Bool = false,
        subjectProminence: Float = 0,
        subjectBackgroundSeparation: Float = 0,
        tonalKey: TonalKey = .mid,
        dynamicRange: Float = 0,
        backlightingLikelihood: Float = 0,
        highKeyLikelihood: Float = 0,
        lowKeyLikelihood: Float = 0,
        nightLikelihood: Float = 0,
        sunsetWarmLikelihood: Float = 0,
        snowLikelihood: Float = 0,
        fogLikelihood: Float = 0,
        monochromeLikelihood: Float = 0,
        mixedLightLikelihood: Float = 0,
        daylightLikelihood: Float = 0,
        sceneConfidence: Float = 1,
        provenance: SceneProvenance = SceneProvenance()
    ) {
        self.hasFaces = hasFaces
        self.hasPeople = hasPeople
        self.subjectProminence = Self.unit(subjectProminence)
        self.subjectBackgroundSeparation = Self.unit(subjectBackgroundSeparation)
        self.tonalKey = tonalKey
        self.dynamicRange = Self.unit(dynamicRange)
        self.backlightingLikelihood = Self.unit(backlightingLikelihood)
        self.highKeyLikelihood = Self.unit(highKeyLikelihood)
        self.lowKeyLikelihood = Self.unit(lowKeyLikelihood)
        self.nightLikelihood = Self.unit(nightLikelihood)
        self.sunsetWarmLikelihood = Self.unit(sunsetWarmLikelihood)
        self.snowLikelihood = Self.unit(snowLikelihood)
        self.fogLikelihood = Self.unit(fogLikelihood)
        self.monochromeLikelihood = Self.unit(monochromeLikelihood)
        self.mixedLightLikelihood = Self.unit(mixedLightLikelihood)
        self.daylightLikelihood = Self.unit(daylightLikelihood)
        self.sceneConfidence = Self.unit(sceneConfidence)
        self.provenance = provenance
    }

    private enum CodingKeys: String, CodingKey {
        case hasFaces, hasPeople, subjectProminence, subjectBackgroundSeparation, tonalKey,
             dynamicRange, backlightingLikelihood, highKeyLikelihood, lowKeyLikelihood,
             nightLikelihood, sunsetWarmLikelihood, snowLikelihood, fogLikelihood,
             monochromeLikelihood, mixedLightLikelihood, daylightLikelihood,
             sceneConfidence, provenance
    }

    /// Values persisted before KRMA-344 lack every key after `lowKeyLikelihood`. Those decode
    /// to neutral zeros with `legacyConfidence` and legacy provenance rather than invalidating
    /// an otherwise usable cache entry.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hasFaces = try container.decodeIfPresent(Bool.self, forKey: .hasFaces) ?? false
        self.hasPeople = try container.decodeIfPresent(Bool.self, forKey: .hasPeople) ?? false
        self.subjectProminence = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .subjectProminence) ?? 0)
        self.subjectBackgroundSeparation = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .subjectBackgroundSeparation) ?? 0)
        self.tonalKey = try container.decodeIfPresent(TonalKey.self, forKey: .tonalKey) ?? .mid
        self.dynamicRange = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .dynamicRange) ?? 0)
        self.backlightingLikelihood = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .backlightingLikelihood) ?? 0)
        self.highKeyLikelihood = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .highKeyLikelihood) ?? 0)
        self.lowKeyLikelihood = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .lowKeyLikelihood) ?? 0)
        self.nightLikelihood = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .nightLikelihood) ?? 0)
        self.sunsetWarmLikelihood = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .sunsetWarmLikelihood) ?? 0)
        self.snowLikelihood = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .snowLikelihood) ?? 0)
        self.fogLikelihood = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .fogLikelihood) ?? 0)
        self.monochromeLikelihood = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .monochromeLikelihood) ?? 0)
        self.mixedLightLikelihood = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .mixedLightLikelihood) ?? 0)
        self.daylightLikelihood = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .daylightLikelihood) ?? 0)
        self.sceneConfidence = Self.unit(
            try container.decodeIfPresent(Float.self, forKey: .sceneConfidence)
                ?? Self.legacyConfidence)
        self.provenance = try container.decodeIfPresent(
            SceneProvenance.self, forKey: .provenance
        ) ?? SceneProvenance(
            usedTone: true, usedColor: true, usedRegions: false,
            usedVisionLabels: false, visionLabelsAvailable: false
        )
    }

    static let unavailable = SceneCharacteristics()

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// Pure, facts-only scene inference. Vision and image data stop at the provider boundary; this
/// analyzer works only with the scalar facts already assembled into PhotoAnalysis.
enum SceneCharacteristicsAnalyzer: Sendable {
    // These are intentionally named policy constants. LUMO-207 can tune them against the fixture
    // corpus without changing the domain model or introducing hard score thresholds.
    enum Thresholds {
        static let lowKeyMeanStart: Float = 0.28
        static let lowKeyMeanFull: Float = 0.52
        static let highKeyMeanStart: Float = 0.58
        static let highKeyMeanFull: Float = 0.86
        static let lowKeyUpperToneStart: Float = 0.42
        static let lowKeyUpperToneFull: Float = 0.72
        static let highKeyLowerToneStart: Float = 0.48
        static let highKeyLowerToneFull: Float = 0.76
        static let backlightDeltaStart: Float = 0.06
        static let backlightDeltaFull: Float = 0.42
        static let backlightBackgroundStart: Float = 0.62
        static let backlightBackgroundFull: Float = 0.92
        static let meaningfulSubjectCoverageStart: Float = 0.03
        static let meaningfulSubjectCoverageFull: Float = 0.42
        static let dynamicRangeStart: Float = 0.08
        static let dynamicRangeFull: Float = 0.78
        static let smallHighlightStart: Float = 0.72
        static let smallHighlightFull: Float = 0.96
    }

    static func analyze(
        globalTone: ToneStatistics,
        regions: [AnalyzedRegion],
        relationships: RegionRelationships,
        primarySubject: PrimarySubjectSelection
    ) -> SceneCharacteristics {
        analyze(
            globalTone: globalTone,
            color: SceneColorFacts.from(.neutral),
            regions: regions,
            relationships: relationships,
            primarySubject: primarySubject,
            classifications: nil
        )
    }

    /// Full scene inference. `color` carries the tone-independent color evidence and
    /// `classifications` carries optional on-device Vision labels; both refine the likelihoods
    /// below but neither is required — a `nil` classification list only reduces
    /// `sceneConfidence`. Every likelihood stays an independent continuous score.
    static func analyze(
        globalTone: ToneStatistics,
        color: SceneColorFacts,
        regions: [AnalyzedRegion],
        relationships: RegionRelationships,
        primarySubject: PrimarySubjectSelection,
        classifications: [SceneClassificationObservation]? = nil
    ) -> SceneCharacteristics {
        let subject = primarySubject.primaryRegionID.flatMap { id in
            regions.first { $0.id == id }
        }
        let background = regions.first { $0.kind == .background }
        let faceConfidence = regions
            .filter { isFace($0.kind) }
            .map(\.confidence)
            .max() ?? 0
        let personConfidence = regions
            .filter { $0.kind == .person }
            .map(\.confidence)
            .max() ?? 0
        let foregroundConfidence = regions
            .filter { isForeground($0.kind) }
            .map(\.confidence)
            .max() ?? 0
        let subjectProminence = subject.map {
            // Importance carries confidence and support. A small additional contribution from
            // the ensemble confidence keeps an otherwise valid, small subject meaningful.
            unit(0.75 * $0.importance + 0.25 * primarySubject.confidence)
        } ?? 0
        let separation = unit(relationships.subjectContrast
            ?? abs(relationships.subjectToBackgroundLuminanceDelta ?? 0))
        let dynamicRange = unit(globalTone.p95 - globalTone.p05)
        let tonalKey = tonalKey(for: globalTone)

        let subjectMean = subject?.tone.mean ?? 0
        let backgroundMean = background?.tone.mean
        let signedBacklightDelta = relationships.subjectToBackgroundLuminanceDelta
            ?? backgroundMean.map { subjectMean - $0 }
            ?? 0
        let backlightDirection = smoothRange(
            -signedBacklightDelta,
            start: Thresholds.backlightDeltaStart,
            full: Thresholds.backlightDeltaFull
        )
        let backgroundBrightness = smoothRange(
            backgroundMean ?? globalTone.p90,
            start: Thresholds.backlightBackgroundStart,
            full: Thresholds.backlightBackgroundFull
        )
        let meaningfulArea = smoothRange(
            subject?.coverage ?? 0,
            start: Thresholds.meaningfulSubjectCoverageStart,
            full: Thresholds.meaningfulSubjectCoverageFull
        )
        let semanticConfidence = max(faceConfidence, max(personConfidence, foregroundConfidence))
        // A face, person, or foreground signal is required to keep a dark object against a bright
        // sky from being over-interpreted as a human backlight scene.
        let subjectSignal = max(semanticConfidence, subject?.confidence ?? 0)
        let backlighting = unit(
            backlightDirection * backgroundBrightness * meaningfulArea * subjectSignal
        )

        let lowMean = smoothRange(
            1 - globalTone.mean,
            start: 1 - Thresholds.lowKeyMeanFull,
            full: 1 - Thresholds.lowKeyMeanStart
        )
        let lowUpperTone = smoothRange(
            1 - globalTone.p75,
            start: 1 - Thresholds.lowKeyUpperToneFull,
            full: 1 - Thresholds.lowKeyUpperToneStart
        )
        let smallHighlights = smoothRange(
            1 - globalTone.p95,
            start: 1 - Thresholds.smallHighlightFull,
            full: 1 - Thresholds.smallHighlightStart
        )
        let lowKey = unit(
            lowMean * lowUpperTone * smallHighlights
                * max(0.35, separation)
        )

        let highMean = smoothRange(
            globalTone.mean,
            start: Thresholds.highKeyMeanStart,
            full: Thresholds.highKeyMeanFull
        )
        let highLowerTone = smoothRange(
            globalTone.p25,
            start: Thresholds.highKeyLowerToneStart,
            full: Thresholds.highKeyLowerToneFull
        )
        let littleClipping = 1 - unit(globalTone.highlightClippingFraction * 3)
        let highSubject = subject.map {
            smoothRange(
                $0.tone.mean,
                start: Thresholds.highKeyMeanStart,
                full: Thresholds.highKeyMeanFull
            )
        } ?? 0.5
        let highKey = unit(highMean * highLowerTone * littleClipping * highSubject)

        // KRMA-344 evidence. Each is a continuous product of smooth ranges over measured tone
        // and color facts, optionally nudged by matching Vision labels (capped at a +0.4
        // probabilistic-OR contribution so labels refine but never decide alone).
        let labelsAvailable = (classifications?.isEmpty == false)
        let nightBase = unit(
            smoothRange(1 - globalTone.mean, start: 0.55, full: 0.8)
                * smoothRange(1 - globalTone.p90, start: 0.35, full: 0.6)
        )
        let night = unit(
            nightBase + 0.4 * labelBoost(for: .night, in: classifications) * (1 - nightBase)
        )

        let warmBand = smoothRange(globalTone.mean, start: 0.18, full: 0.32)
            * (1 - smoothRange(globalTone.mean, start: 0.62, full: 0.82))
        let sunsetBase = unit(
            smoothRange(color.warmth, start: 0.03, full: 0.12)
                * smoothRange(color.saturationMedian, start: 0.02, full: 0.12)
                * warmBand
        )
        let sunsetWarm = unit(
            sunsetBase + 0.4 * labelBoost(for: .sunset, in: classifications) * (1 - sunsetBase)
        )

        let snowBase = unit(
            smoothRange(globalTone.mean, start: 0.62, full: 0.85)
                * smoothRange(globalTone.p25, start: 0.5, full: 0.72)
                * (1 - smoothRange(color.saturationMedian, start: 0.03, full: 0.15))
        )
        let snow = unit(
            snowBase + 0.4 * labelBoost(for: .snow, in: classifications) * (1 - snowBase)
        )

        let fogBase = unit(
            smoothRange(1 - dynamicRange, start: 0.55, full: 0.78)
                * (1 - smoothRange(color.saturationMedian, start: 0.04, full: 0.18))
        )
        let fog = unit(
            fogBase + 0.4 * labelBoost(for: .fog, in: classifications) * (1 - fogBase)
        )

        let monochrome = unit(
            (1 - smoothRange(color.colorfulness, start: 0.03, full: 0.15))
                * smoothRange(color.estimatedNeutrality, start: 0.5, full: 0.85)
        )

        // Mixed illumination requires pixel-correlated hue evidence. The source-analysis color
        // path reports `isMixed == false` with no hue entropy, so this stays at zero there
        // rather than inventing mixed light from marginal channel histograms.
        let mixedLight: Float = {
            if color.isMixed { return 0.75 }
            if let entropy = color.hueEntropy {
                return unit(smoothRange(entropy, start: 0.6, full: 0.9) * 0.8)
            }
            return 0
        }()

        let daylightBase = unit(
            smoothRange(globalTone.mean, start: 0.3, full: 0.42)
                * (1 - smoothRange(globalTone.mean, start: 0.62, full: 0.78))
                * smoothRange(color.estimatedNeutrality, start: 0.4, full: 0.7)
                * smoothRange(dynamicRange, start: 0.25, full: 0.5)
                * (1 - smoothRange(dynamicRange, start: 0.75, full: 0.95))
        )
        let daylight = unit(
            daylightBase + 0.4 * labelBoost(for: .daylight, in: classifications)
                * (1 - daylightBase)
        )

        let strongestLabelBoost = VisionSceneCue.allCases.map {
            labelBoost(for: $0, in: classifications)
        }.max() ?? 0
        let provenance = SceneProvenance(
            usedTone: true,
            usedColor: true,
            usedRegions: !regions.isEmpty,
            usedVisionLabels: strongestLabelBoost > 0,
            visionLabelsAvailable: labelsAvailable
        )
        // A confident Vision label that the measured pixels contradict (strong label evidence
        // against a weak physical base) scales confidence down instead of overriding the
        // measurement. This is the only contradiction the analyzer can observe honestly:
        // physical likelihoods that genuinely conflict (night versus snow, for example) cannot
        // both exceed one half from the same tone distribution, so counting strong likelihoods
        // would only penalize agreement such as snow with high-key.
        let disagreement = VisionSceneCue.allCases.map { cue -> Float in
            let confidence = labelBoost(for: cue, in: classifications)
            let base: Float
            switch cue {
            case .night: base = nightBase
            case .sunset: base = sunsetBase
            case .snow: base = snowBase
            case .fog: base = fogBase
            case .daylight: base = daylightBase
            }
            return confidence * (1 - base)
        }.max() ?? 0
        var sceneConfidence: Float = 1
        if !labelsAvailable { sceneConfidence -= 0.15 }
        if regions.isEmpty { sceneConfidence -= 0.2 }
        if disagreement > 0.5 { sceneConfidence *= 0.6 }

        return SceneCharacteristics(
            hasFaces: faceConfidence > 0,
            hasPeople: personConfidence > 0,
            subjectProminence: subjectProminence,
            subjectBackgroundSeparation: separation,
            tonalKey: tonalKey,
            dynamicRange: dynamicRange,
            backlightingLikelihood: backlighting,
            highKeyLikelihood: highKey,
            lowKeyLikelihood: lowKey,
            nightLikelihood: night,
            sunsetWarmLikelihood: sunsetWarm,
            snowLikelihood: snow,
            fogLikelihood: fog,
            monochromeLikelihood: monochrome,
            mixedLightLikelihood: mixedLight,
            daylightLikelihood: daylight,
            sceneConfidence: sceneConfidence,
            provenance: provenance
        )
    }

    static func analyze(_ analysis: PhotoAnalysis) -> SceneCharacteristics {
        analyze(
            globalTone: analysis.globalTone,
            color: SceneColorFacts.from(analysis.colorStatistics),
            regions: analysis.regions,
            relationships: analysis.relationships,
            primarySubject: analysis.primarySubject,
            classifications: analysis.sceneClassifications
        )
    }

    /// Best-effort Vision taxonomy cue. Matching is case-insensitive substring-based so minor
    /// taxonomy revisions weaken the boost instead of breaking it; unknown identifiers simply
    /// never match. Returns the strongest matching label confidence, or zero.
    enum VisionSceneCue: String, CaseIterable, Sendable {
        case night, sunset, snow, fog, daylight

        var identifiers: [String] {
            switch self {
            case .night: return ["night", "moon", "stars", "milky", "aurora"]
            case .sunset: return ["sunset", "sunrise", "dusk", "dawn", "sundown", "golden"]
            case .snow: return ["snow", "winter", "ski", "blizzard", "glacier"]
            case .fog: return ["fog", "mist", "haze"]
            case .daylight: return ["daylight", "sunny", "blue_sky", "clear_sky"]
            }
        }
    }

    static func labelBoost(
        for cue: VisionSceneCue, in classifications: [SceneClassificationObservation]?
    ) -> Float {
        guard let classifications, !classifications.isEmpty else { return 0 }
        var best: Float = 0
        for observation in classifications {
            let identifier = observation.identifier.lowercased()
            guard cue.identifiers.contains(where: { identifier.contains($0) }) else { continue }
            best = max(best, observation.confidence)
        }
        return unit(best)
    }

    private static func tonalKey(for tone: ToneStatistics) -> TonalKey {
        if tone.p50 < 0.38 { return .low }
        if tone.p50 > 0.62 { return .high }
        return .mid
    }

    /// A cubic smoothstep gives a monotonic, continuous response with zero slope at both ends.
    private static func smoothRange(_ value: Float, start: Float, full: Float) -> Float {
        guard value.isFinite, full > start else { return value >= full ? 1 : 0 }
        let t = unit((value - start) / (full - start))
        return t * t * (3 - 2 * t)
    }

    private static func isForeground(_ kind: RegionKind) -> Bool {
        if case .foregroundInstance = kind { return true }
        return false
    }

    private static func isFace(_ kind: RegionKind) -> Bool {
        switch kind {
        case .face, .faceInstance: return true
        default: return false
        }
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
