import CoreImage
import Foundation
import Vision

/// Scene-classification evidence and per-signal confidence for content-aware Auto (KRMA-344).
///
/// The completed Photo Intelligence foundation measures tone, color, regions, and relationships,
/// and `SceneCharacteristicsAnalyzer` already infers backlighting and high/low-key likelihoods
/// from those scalar facts. This file adds what that inference cannot see on its own:
///
/// - `SceneClassificationObservation`: one on-device Vision scene label as a value type. Vision
///   objects stop at the adapter boundary; the analyzer consumes only these scalars, so every
///   likelihood below is unit-testable without image objects.
/// - `SceneClassifierProviding` / `VisionSceneClassifier`: the sole Vision classification
///   boundary. Classification is optional: an unavailable API, an undecodable image, or a failed
///   request yields `nil` (missing evidence), never a fatal analysis error, and no image data
///   leaves the device.
/// - `SceneColorFacts`: the minimal color evidence the scene analyzer needs, bridged from either
///   `ColorStatistics` (source analysis, no hue correlation available) or `PixelCorrelatedColor`
///   (current-render measurement, hue entropy and mixed-frame flags available).
/// - `SceneProvenance`: which signals contributed to one scene result, so policy can explain and
///   scale a correction.
/// - `AutoSignalConfidence`: independent confidence for global tone, color/neutral, scene,
///   subject/regions, detail, and each semantic provider Auto consumes. Missing or conflicting
///   signals reduce confidence predictably; they never invent a white balance or a mask.
///
/// Facts only — no slider values and no edit recommendations. Those belong to
/// `AutoEnhancementPolicy` (KRMA-345).

// MARK: - Classification observations

/// One on-device scene label. `identifier` is Vision's taxonomy string (for example a label
/// containing "sunset" or "snow"); matching is substring-based and case-insensitive so minor
/// taxonomy revisions degrade to weaker evidence rather than a hard failure.
struct SceneClassificationObservation: Codable, Sendable, Equatable, Hashable {
    let identifier: String
    let confidence: Float

    init(identifier: String, confidence: Float) {
        self.identifier = identifier
        self.confidence = Self.unit(confidence)
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// The classification seam. Non-throwing by contract: implementations report `nil` when labels
/// are unavailable rather than failing the analysis that requested them.
protocol SceneClassifierProviding: Sendable {
    func classifications(for image: AnalysisImage) async -> [SceneClassificationObservation]?
}

/// On-device Vision scene classification (`VNClassifyImageRequest`, no model bundle, no network).
/// Failures at any stage — unavailable revision, undecodable image, cancelled task, empty
/// results — return `nil` so the caller treats labels as missing evidence.
struct VisionSceneClassifier: SceneClassifierProviding {
    /// Preferred taxonomy revision. When the runtime does not support it, revision 1 is tried
    /// before giving up, so a newer SDK default never hard-fails on an older OS.
    let preferredRevision: Int
    let maximumObservations: Int

    init(preferredRevision: Int = 2, maximumObservations: Int = 10) {
        self.preferredRevision = max(1, preferredRevision)
        self.maximumObservations = max(1, maximumObservations)
    }

    func classifications(for image: AnalysisImage) async -> [SceneClassificationObservation]? {
        guard !Task.isCancelled else { return nil }
        guard let revision = Self.revision(preferred: preferredRevision) else { return nil }
        guard let ciImage = Self.ciImage(for: image) else { return nil }
        guard !Task.isCancelled else { return nil }
        let request = VNClassifyImageRequest()
        request.revision = revision
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        guard let results = request.results, !results.isEmpty else { return nil }
        return results.prefix(maximumObservations).map {
            SceneClassificationObservation(identifier: $0.identifier, confidence: $0.confidence)
        }
    }

    private static func revision(preferred: Int) -> Int? {
        let supported = VNClassifyImageRequest.supportedRevisions
        if supported.contains(preferred) { return preferred }
        if supported.contains(1) { return 1 }
        return nil
    }

    private static func ciImage(for image: AnalysisImage) -> CIImage? {
        switch image.source.backing {
        case .url(let url): return try? ImageDecoder.load(from: url)
        case .data(let data): return try? ImageDecoder.load(from: data, name: "scene-classification")
        }
    }
}

// MARK: - Color facts bridge

/// The minimal color evidence scene inference consumes. `hueEntropy` and `isMixed` are `nil`/`false`
/// when the source analysis never measured pixel-correlated hue (see `ColorStatistics`): the
/// analyzer then keeps mixed-light evidence near zero rather than inventing it from marginals.
struct SceneColorFacts: Codable, Sendable, Equatable {
    let meanR: Float
    let meanG: Float
    let meanB: Float
    let saturationMedian: Float
    let colorfulness: Float
    let estimatedNeutrality: Float
    let isMixed: Bool
    let hueEntropy: Float?

    init(
        meanR: Float = 0,
        meanG: Float = 0,
        meanB: Float = 0,
        saturationMedian: Float = 0,
        colorfulness: Float = 0,
        estimatedNeutrality: Float = 0,
        isMixed: Bool = false,
        hueEntropy: Float? = nil
    ) {
        self.meanR = Self.unit(meanR)
        self.meanG = Self.unit(meanG)
        self.meanB = Self.unit(meanB)
        self.saturationMedian = Self.unit(saturationMedian)
        self.colorfulness = Self.unit(colorfulness)
        self.estimatedNeutrality = Self.unit(estimatedNeutrality)
        self.isMixed = isMixed
        self.hueEntropy = hueEntropy.flatMap(Self.unitOptional)
    }

    static func from(_ color: ColorStatistics) -> SceneColorFacts {
        SceneColorFacts(
            meanR: color.meanRGB.x,
            meanG: color.meanRGB.y,
            meanB: color.meanRGB.z,
            saturationMedian: color.saturationMedian,
            colorfulness: color.colorfulness,
            estimatedNeutrality: color.estimatedNeutrality,
            isMixed: false,
            hueEntropy: nil
        )
    }

    static func from(_ color: PixelCorrelatedColor) -> SceneColorFacts {
        SceneColorFacts(
            meanR: color.meanRGB.x,
            meanG: color.meanRGB.y,
            meanB: color.meanRGB.z,
            saturationMedian: color.saturationMedian,
            colorfulness: color.colorfulness,
            estimatedNeutrality: color.estimatedNeutrality,
            isMixed: color.isMixed,
            hueEntropy: color.hueEntropy
        )
    }

    /// Warm cast as a signed red-minus-blue difference, 0…1. Positive values indicate warm
    /// illumination; cool frames yield zero rather than a negative "coolness" score.
    var warmth: Float {
        max(0, meanR - meanB)
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func unitOptional(_ value: Float) -> Float? {
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}

// MARK: - Provenance

/// Which signals contributed to one scene result. Persisted alongside the likelihoods so a later
/// policy or diagnostic can tell "confident daylight" from "daylight by default, no labels".
struct SceneProvenance: Codable, Sendable, Equatable {
    let usedTone: Bool
    let usedColor: Bool
    let usedRegions: Bool
    let usedVisionLabels: Bool
    /// False when the classifier was never consulted or returned no labels. Distinct from
    /// `usedVisionLabels` (which is false when labels were consulted but matched nothing), this
    /// records whether the Vision signal existed at all.
    let visionLabelsAvailable: Bool

    init(
        usedTone: Bool = true,
        usedColor: Bool = true,
        usedRegions: Bool = false,
        usedVisionLabels: Bool = false,
        visionLabelsAvailable: Bool = false
    ) {
        self.usedTone = usedTone
        self.usedColor = usedColor
        self.usedRegions = usedRegions
        self.usedVisionLabels = usedVisionLabels
        self.visionLabelsAvailable = visionLabelsAvailable
    }

    /// Neutral provenance for cached values persisted before KRMA-344 recorded it: tone and color
    /// were always measured, regions only when present, Vision labels never.
    static func legacy(hasRegions: Bool) -> SceneProvenance {
        SceneProvenance(
            usedTone: true, usedColor: true, usedRegions: hasRegions,
            usedVisionLabels: false, visionLabelsAvailable: false
        )
    }
}

// MARK: - Per-signal confidence

/// Confidence per semantic provider Auto consumes. `nil` means the provider was not consulted or
/// produced nothing usable — missing evidence, not a zero-confidence measurement.
struct SemanticProviderConfidence: Codable, Sendable, Equatable {
    let attention: Float?
    let face: Float?
    let foreground: Float?
    let person: Float?
    let sceneClassifier: Float?

    init(
        attention: Float? = nil,
        face: Float? = nil,
        foreground: Float? = nil,
        foregroundInstance: Float? = nil,
        person: Float? = nil,
        sceneClassifier: Float? = nil
    ) {
        // The union foreground target and its instances share one Vision segmentation result;
        // callers report whichever they consulted and this value keeps the stronger evidence.
        let foregroundConfidence = [foreground, foregroundInstance]
            .compactMap { $0 }.max()
        self.attention = attention.flatMap(Self.unitOptional)
        self.face = face.flatMap(Self.unitOptional)
        self.foreground = foregroundConfidence.flatMap(Self.unitOptional)
        self.person = person.flatMap(Self.unitOptional)
        self.sceneClassifier = sceneClassifier.flatMap(Self.unitOptional)
    }

    /// Neutral defaults for cached values persisted before per-provider confidence existed.
    static let unavailable = SemanticProviderConfidence()

    /// The providers that produced usable evidence.
    var availableCount: Int {
        [attention, face, foreground, person, sceneClassifier].compactMap { $0 }.count
    }

    private static func unitOptional(_ value: Float) -> Float? {
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}

/// Independent confidence for every signal Auto consumes. Constructed only through `make`, which
/// applies the one aggregation rule: `overall` is the mean of the available signals scaled by
/// the fraction of signals present, so missing signals reduce confidence predictably without
/// erasing the usable measurements.
struct AutoSignalConfidence: Codable, Sendable, Equatable {
    let globalTone: Float
    let colorNeutral: Float
    let scene: Float
    let subjectRegions: Float
    /// `nil` when native detail was never measured (source analysis path). A measured-but-empty
    /// detail result is `0`, which is weaker than "not measured" only in that policy may not
    /// consult sharpening/NR at all.
    let detail: Float?
    let providers: SemanticProviderConfidence
    let overall: Float

    init(
        globalTone: Float = 0,
        colorNeutral: Float = 0,
        scene: Float = 0,
        subjectRegions: Float = 0,
        detail: Float? = nil,
        providers: SemanticProviderConfidence = .unavailable,
        overall: Float = 0
    ) {
        self.globalTone = Self.unit(globalTone)
        self.colorNeutral = Self.unit(colorNeutral)
        self.scene = Self.unit(scene)
        self.subjectRegions = Self.unit(subjectRegions)
        self.detail = detail.flatMap(Self.unitOptional)
        self.providers = providers
        self.overall = Self.unit(overall)
    }

    static let unavailable = AutoSignalConfidence()

    /// Derive confidence from assembled facts. `detail` is `nil` unless the caller measured
    /// native-resolution patches; `classifications` is `nil` when the classifier was unavailable.
    /// Regional and provider facts come from the same `regions` array, so one failed mask reduces
    /// the subject/provider terms without touching the global tone/color terms.
    static func make(
        globalToneAvailable: Bool,
        color: SceneColorFacts,
        sceneConfidence: Float,
        regions: [AnalyzedRegion],
        primarySubject: PrimarySubjectSelection,
        classifications: [SceneClassificationObservation]?,
        detailAvailable: Bool?,
        failedMaskCount: Int = 0
    ) -> AutoSignalConfidence {
        let globalTone: Float = globalToneAvailable ? 1 : 0
        let colorNeutral: Float = {
            if color.isMixed { return 0.3 }
            if color.estimatedNeutrality >= 0.7 || color.estimatedNeutrality <= 0.3 { return 0.9 }
            return 0.5
        }()
        let subjectRegions: Float = {
            guard !regions.isEmpty else { return 0 }
            let best = regions.map(\.confidence).max() ?? 0
            // The ensemble selection carries its own confidence; blend it so a disputed primary
            // subject cannot report full regional confidence.
            let combined = 0.7 * best + 0.3 * primarySubject.confidence
            return failedMaskCount > 0 ? combined * 0.8 : combined
        }()
        let providers = SemanticProviderConfidence(
            attention: bestConfidence(where: { $0 == .subject }, in: regions),
            face: bestConfidence(where: { $0.isFaceKind }, in: regions),
            foreground: bestConfidence(where: { $0.isForegroundKind }, in: regions),
            person: bestConfidence(where: { $0 == .person }, in: regions),
            sceneClassifier: classifications.map { observations in
                observations.map(\.confidence).max() ?? 0
            }
        )
        // Reportable signal slots: tone, color, scene, regions, plus detail when measured.
        var signals: [Float] = [globalTone, colorNeutral, sceneConfidence, subjectRegions]
        let detail: Float? = detailAvailable.map { $0 ? 1 : 0 }
        if let detail { signals.append(detail) }
        let totalSlots = detail == nil ? 4 : 5
        var presentSlots = 2 // color and scene facts are always derived
        if globalToneAvailable { presentSlots += 1 }
        if !regions.isEmpty { presentSlots += 1 }
        if detail != nil { presentSlots += 1 }
        let fractionPresent = Float(presentSlots) / Float(totalSlots)
        let mean = signals.reduce(0, +) / Float(max(1, signals.count))
        // Missing signals scale the mean down: half the weight is the measured mean, half is the
        // fraction of signals present. All present → overall == mean; none usable → near zero.
        let overall = mean * (0.5 + 0.5 * fractionPresent)
        return AutoSignalConfidence(
            globalTone: globalTone,
            colorNeutral: colorNeutral,
            scene: sceneConfidence,
            subjectRegions: subjectRegions,
            detail: detail,
            providers: providers,
            overall: overall
        )
    }

    private static func bestConfidence(
        where matches: (SemanticMaskKind) -> Bool, in regions: [AnalyzedRegion]
    ) -> Float? {
        let confidences = regions.filter { matches($0.kind) }.map(\.confidence)
        guard !confidences.isEmpty else { return nil }
        return confidences.max()
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func unitOptional(_ value: Float) -> Float? {
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}

// MARK: - Mask-kind families

extension SemanticMaskKind {
    /// All face spellings (`.face` plus numbered instances) share one detection signal.
    var isFaceKind: Bool {
        switch self {
        case .face, .faceInstance: return true
        default: return false
        }
    }

    /// The union foreground target plus its numbered instances share one segmentation result.
    var isForegroundKind: Bool {
        switch self {
        case .foreground, .foregroundInstance: return true
        default: return false
        }
    }
}

// MARK: - Current-render bridge

extension SceneCharacteristicsAnalyzer {
    /// Derive scene evidence from a current-render `CurrentEditMeasurement` (KRMA-343 facts)
    /// instead of a source `PhotoAnalysis`. Relationships and the primary subject are rebuilt
    /// from the same regions through the shared selectors — no second subject/relationship
    /// implementation — and color facts carry the pixel-correlated hue evidence the source path
    /// lacks. `classifications` remain optional Vision labels; `nil` reduces scene confidence
    /// without invalidating the tone/color/regional facts.
    static func analyze(
        measurement: CurrentEditMeasurement,
        classifications: [SceneClassificationObservation]? = nil
    ) -> SceneCharacteristics {
        let regions = measurement.regions
        let primarySubject = PrimarySubjectSelector.select(from: regions)
        let relationships = RegionRelationships.make(
            globalTone: measurement.globalTone.perceptual,
            regions: regions,
            primarySubject: primarySubject
        )
        return analyze(
            globalTone: measurement.globalTone.perceptual,
            color: SceneColorFacts.from(measurement.color),
            regions: regions,
            relationships: relationships,
            primarySubject: primarySubject,
            classifications: classifications
        )
    }
}
