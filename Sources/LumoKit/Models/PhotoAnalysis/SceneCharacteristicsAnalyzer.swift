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

    init(
        hasFaces: Bool = false,
        hasPeople: Bool = false,
        subjectProminence: Float = 0,
        subjectBackgroundSeparation: Float = 0,
        tonalKey: TonalKey = .mid,
        dynamicRange: Float = 0,
        backlightingLikelihood: Float = 0,
        highKeyLikelihood: Float = 0,
        lowKeyLikelihood: Float = 0
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

        return SceneCharacteristics(
            hasFaces: faceConfidence > 0,
            hasPeople: personConfidence > 0,
            subjectProminence: subjectProminence,
            subjectBackgroundSeparation: separation,
            tonalKey: tonalKey,
            dynamicRange: dynamicRange,
            backlightingLikelihood: backlighting,
            highKeyLikelihood: highKey,
            lowKeyLikelihood: lowKey
        )
    }

    static func analyze(_ analysis: PhotoAnalysis) -> SceneCharacteristics {
        analyze(
            globalTone: analysis.globalTone,
            regions: analysis.regions,
            relationships: analysis.relationships,
            primarySubject: analysis.primarySubject
        )
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
