import Foundation
import simd

/// The luminance space in which a distribution was measured.
enum LuminanceVariant: String, Codable, Sendable, Equatable, Hashable {
    case linear
    case perceptual
}

/// Scalar facts about one luminance distribution. This type deliberately contains no edit
/// recommendation; policy belongs to AutoLightEngine, not to photo understanding.
struct ToneStatistics: Codable, Sendable, Equatable {
    let variant: LuminanceVariant
    let minimum: Float
    let maximum: Float
    let mean: Float
    let p01: Float
    let p05: Float
    let p10: Float
    let p25: Float
    let p50: Float
    let p75: Float
    let p90: Float
    let p95: Float
    let p99: Float
    let shadowClippingFraction: Float
    let highlightClippingFraction: Float

    init(
        variant: LuminanceVariant = .linear,
        minimum: Float = 0,
        maximum: Float = 0,
        mean: Float = 0,
        p01: Float = 0,
        p05: Float = 0,
        p10: Float = 0,
        p25: Float = 0,
        p50: Float = 0,
        p75: Float = 0,
        p90: Float = 0,
        p95: Float = 0,
        p99: Float = 0,
        shadowClippingFraction: Float = 0,
        highlightClippingFraction: Float = 0
    ) {
        self.variant = variant
        self.minimum = Self.finiteUnit(minimum)
        self.maximum = Self.finiteUnit(maximum)
        self.mean = Self.finiteUnit(mean)
        self.p01 = Self.finiteUnit(p01)
        self.p05 = Self.finiteUnit(p05)
        self.p10 = Self.finiteUnit(p10)
        self.p25 = Self.finiteUnit(p25)
        self.p50 = Self.finiteUnit(p50)
        self.p75 = Self.finiteUnit(p75)
        self.p90 = Self.finiteUnit(p90)
        self.p95 = Self.finiteUnit(p95)
        self.p99 = Self.finiteUnit(p99)
        self.shadowClippingFraction = Self.finiteUnit(shadowClippingFraction)
        self.highlightClippingFraction = Self.finiteUnit(highlightClippingFraction)
    }

    static let neutral = ToneStatistics()

    private static func finiteUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// Both transfer-space views of luminance are retained when an analyzer needs them.
struct LuminanceDistribution: Codable, Sendable, Equatable {
    let linear: ToneStatistics
    let perceptual: ToneStatistics

    init(linear: ToneStatistics = .neutral, perceptual: ToneStatistics = ToneStatistics(variant: .perceptual)) {
        self.linear = ToneStatistics(variant: .linear, minimum: linear.minimum, maximum: linear.maximum,
                                     mean: linear.mean, p01: linear.p01, p05: linear.p05, p10: linear.p10,
                                     p25: linear.p25, p50: linear.p50, p75: linear.p75, p90: linear.p90,
                                     p95: linear.p95, p99: linear.p99,
                                     shadowClippingFraction: linear.shadowClippingFraction,
                                     highlightClippingFraction: linear.highlightClippingFraction)
        self.perceptual = ToneStatistics(variant: .perceptual, minimum: perceptual.minimum,
                                         maximum: perceptual.maximum, mean: perceptual.mean,
                                         p01: perceptual.p01, p05: perceptual.p05, p10: perceptual.p10,
                                         p25: perceptual.p25, p50: perceptual.p50, p75: perceptual.p75,
                                         p90: perceptual.p90, p95: perceptual.p95, p99: perceptual.p99,
                                         shadowClippingFraction: perceptual.shadowClippingFraction,
                                         highlightClippingFraction: perceptual.highlightClippingFraction)
    }

    static let neutral = LuminanceDistribution()
}

struct ChannelClipping: Codable, Sendable, Equatable {
    let red: Float
    let green: Float
    let blue: Float

    init(red: Float = 0, green: Float = 0, blue: Float = 0) {
        self.red = Self.finiteUnit(red)
        self.green = Self.finiteUnit(green)
        self.blue = Self.finiteUnit(blue)
    }

    static let none = ChannelClipping()

    private static func finiteUnit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct ColorStatistics: Codable, Sendable, Equatable {
    let meanRGB: SIMD3<Float>
    let medianRGB: SIMD3<Float>
    let saturationMedian: Float
    let saturationP95: Float
    let channelClipping: ChannelClipping
    let estimatedNeutrality: Float
    let colorfulness: Float

    init(
        meanRGB: SIMD3<Float> = .zero,
        medianRGB: SIMD3<Float> = .zero,
        saturationMedian: Float = 0,
        saturationP95: Float = 0,
        channelClipping: ChannelClipping = .none,
        estimatedNeutrality: Float = 0,
        colorfulness: Float = 0
    ) {
        self.meanRGB = Self.unitVector(meanRGB)
        self.medianRGB = Self.unitVector(medianRGB)
        self.saturationMedian = Self.unit(saturationMedian)
        self.saturationP95 = Self.unit(saturationP95)
        self.channelClipping = channelClipping
        self.estimatedNeutrality = Self.unit(estimatedNeutrality)
        self.colorfulness = Self.unit(colorfulness)
    }

    static let neutral = ColorStatistics()

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func unitVector(_ value: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(unit(value.x), unit(value.y), unit(value.z))
    }
}

struct AnalysisQuality: Codable, Sendable, Equatable {
    let globalToneAvailable: Bool
    let attentionAvailable: Bool
    let foregroundAvailable: Bool
    let faceAnalysisAvailable: Bool
    let peopleAnalysisAvailable: Bool
    let overallConfidence: Float

    init(
        globalToneAvailable: Bool = false,
        attentionAvailable: Bool = false,
        foregroundAvailable: Bool = false,
        faceAnalysisAvailable: Bool = false,
        peopleAnalysisAvailable: Bool = false,
        overallConfidence: Float = 0
    ) {
        self.globalToneAvailable = globalToneAvailable
        self.attentionAvailable = attentionAvailable
        self.foregroundAvailable = foregroundAvailable
        self.faceAnalysisAvailable = faceAnalysisAvailable
        self.peopleAnalysisAvailable = peopleAnalysisAvailable
        self.overallConfidence = overallConfidence.isFinite ? min(max(overallConfidence, 0), 1) : 0
    }

    static let unavailable = AnalysisQuality()
    static let globalOnly = AnalysisQuality(globalToneAvailable: true, overallConfidence: 1)
}

struct AnalysisTimings: Codable, Sendable, Equatable {
    let imagePreparation: Duration
    let globalTone: Duration
    let faceDetection: Duration
    let saliency: Duration
    let foregroundMasking: Duration
    let personSegmentation: Duration
    let regionalAnalysis: Duration
    let total: Duration

    init(
        imagePreparation: Duration = .zero,
        globalTone: Duration = .zero,
        faceDetection: Duration = .zero,
        saliency: Duration = .zero,
        foregroundMasking: Duration = .zero,
        personSegmentation: Duration = .zero,
        regionalAnalysis: Duration = .zero,
        total: Duration = .zero
    ) {
        self.imagePreparation = imagePreparation
        self.globalTone = globalTone
        self.faceDetection = faceDetection
        self.saliency = saliency
        self.foregroundMasking = foregroundMasking
        self.personSegmentation = personSegmentation
        self.regionalAnalysis = regionalAnalysis
        self.total = total
    }

    static let zero = AnalysisTimings()

    func replacing(
        imagePreparation: Duration? = nil,
        globalTone: Duration? = nil,
        faceDetection: Duration? = nil,
        saliency: Duration? = nil,
        foregroundMasking: Duration? = nil,
        personSegmentation: Duration? = nil,
        regionalAnalysis: Duration? = nil,
        total: Duration? = nil
    ) -> AnalysisTimings {
        AnalysisTimings(
            imagePreparation: imagePreparation ?? self.imagePreparation,
            globalTone: globalTone ?? self.globalTone,
            faceDetection: faceDetection ?? self.faceDetection,
            saliency: saliency ?? self.saliency,
            foregroundMasking: foregroundMasking ?? self.foregroundMasking,
            personSegmentation: personSegmentation ?? self.personSegmentation,
            regionalAnalysis: regionalAnalysis ?? self.regionalAnalysis,
            total: total ?? self.total
        )
    }

    func adding(duration: Duration, for kind: SemanticMaskKind) -> AnalysisTimings {
        switch kind {
        case .subject:
            return replacing(saliency: saliency + duration)
        case .face, .faceInstance:
            return replacing(faceDetection: faceDetection + duration)
        case .foreground, .foregroundInstance, .background:
            return replacing(foregroundMasking: foregroundMasking + duration)
        case .person:
            return replacing(personSegmentation: personSegmentation + duration)
        case .unknown:
            return self
        }
    }
}

struct AnalysisVersion: Codable, Sendable, Equatable, Hashable, Comparable {
    static let current = AnalysisVersion(rawValue: 1)
    let rawValue: UInt16

    init(rawValue: UInt16) {
        // Keep future versions representable when reading persisted keys. The convenience Int
        // initializer remains clamped for user/configuration input; cache versioning needs a
        // decoded future value to remain distinct so it can be treated as a clean cache miss.
        self.rawValue = max(1, rawValue)
    }

    init(_ value: Int) {
        self.rawValue = max(1, min(UInt16(clamping: value), Self.currentRawValue))
    }

    private static let currentRawValue: UInt16 = 1

    static func < (lhs: AnalysisVersion, rhs: AnalysisVersion) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
