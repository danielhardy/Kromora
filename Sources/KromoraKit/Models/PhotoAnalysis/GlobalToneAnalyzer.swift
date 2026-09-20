import CoreGraphics
import Foundation

enum GlobalToneAnalysisError: LocalizedError, Sendable, Equatable {
    case unavailable
    case malformedHistogram

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Global tone analysis could not produce a histogram"
        case .malformedHistogram: return "Global tone analysis received a malformed histogram"
        }
    }
}

/// The Tier-0 result. It is deliberately facts-only; an Auto recommendation is a separate policy
/// concern and must not be smuggled into photo understanding state.
struct GlobalToneAnalysis: Sendable, Equatable {
    let tone: LuminanceDistribution
    let color: ColorStatistics
    let quality: AnalysisQuality
}

/// Global analysis over the one canonical `AnalysisImage`. Rasterization remains owned by the
/// injected `RenderEngining` actor, which lets production reuse RenderEngine's existing GPU-backed
/// histogram path and lets tests provide deterministic histogram values without Core Image.
struct GlobalToneAnalyzer: Sendable {
    private let engine: any RenderEngining

    init(engine: any RenderEngining = RenderEngine.shared) {
        self.engine = engine
    }

    func analyze(image: AnalysisImage) async throws -> GlobalToneAnalysis {
        try await analyze(image: image, document: EditDocument(), lut: nil, space: .sRGB)
    }

    /// Document-aware Tier-0 analysis (KRMA-343). Measures the current rendered edit instead
    /// of the source: `document`/`lut` select what the renderer tallies. The parameterless
    /// overload above preserves the source-measurement behavior for existing callers.
    func analyze(
        image: AnalysisImage,
        document: EditDocument,
        lut: CubeLUT?,
        space: WorkingSpace
    ) async throws -> GlobalToneAnalysis {
        try Task.checkCancellation()
        var interval = KromoraObservability.begin(
            .analysisGlobalTone, source: image.source, maskQuality: .analysis
        )
        defer { interval.end() }
        let dimensions = image.dimensions
        let histogram = await engine.histogram(
            source: image.source,
            document: document,
            lut: lut,
            scale: .preview(maxSize: CGSize(width: dimensions.width, height: dimensions.height)),
            space: space,
            maxDimension: max(dimensions.width, dimensions.height)
        )
        try Task.checkCancellation()
        guard let histogram else { throw GlobalToneAnalysisError.unavailable }
        let result = try Self.statistics(from: histogram)
        return GlobalToneAnalysis(
            tone: result.tone,
            color: result.color,
            quality: AnalysisQuality(globalToneAvailable: true, overallConfidence: 1)
        )
    }

    /// Pure histogram mapping shared by the async renderer-backed path and deterministic tests.
    /// Histogram RGB/luma bins are sampled from the renderer's sRGB working space. Its luma bin is
    /// Rec.709 `Y = 0.2126R + 0.7152G + 0.0722B`; the linear view applies the sRGB transfer decode
    /// to that already-computed luma sample, while the perceptual view retains the encoded value.
    static func statistics(from histogram: HistogramData) throws -> (
        tone: LuminanceDistribution, color: ColorStatistics
    ) {
        let weighted = WeightedHistogramData(
            red: histogram.red.map(Double.init), green: histogram.green.map(Double.init),
            blue: histogram.blue.map(Double.init), luma: histogram.luma.map(Double.init)
        )
        return try statistics(from: weighted)
    }

    /// The shared histogram-to-facts mapping. Fractional bins are used by masked analysis so soft
    /// masks retain their edge weights; the unmasked Tier-0 path simply supplies integer-valued
    /// bins through `HistogramData` above.
    static func statistics(from histogram: WeightedHistogramData) throws -> (
        tone: LuminanceDistribution, color: ColorStatistics
    ) {
        guard histogram.red.count == 256,
            histogram.green.count == 256,
            histogram.blue.count == 256,
            histogram.luma.count == 256,
            histogram.red.allSatisfy({ $0.isFinite && $0 >= 0 }),
            histogram.green.allSatisfy({ $0.isFinite && $0 >= 0 }),
            histogram.blue.allSatisfy({ $0.isFinite && $0 >= 0 }),
            histogram.luma.allSatisfy({ $0.isFinite && $0 >= 0 })
        else { throw GlobalToneAnalysisError.malformedHistogram }

        let count = histogram.totalWeight
        let channelTolerance = max(1e-6, count * 1e-6)
        guard count > 0,
            abs(histogram.red.reduce(0, +) - count) <= channelTolerance,
            abs(histogram.green.reduce(0, +) - count) <= channelTolerance,
            abs(histogram.blue.reduce(0, +) - count) <= channelTolerance
        else { throw GlobalToneAnalysisError.malformedHistogram }

        let perceptual = toneStatistics(
            bins: histogram.luma, count: count, variant: .perceptual, transform: { $0 }
        )
        let linear = toneStatistics(
            bins: histogram.luma, count: count, variant: .linear, transform: sRGBDecode
        )
        return (
            LuminanceDistribution(linear: linear, perceptual: perceptual),
            colorStatistics(histogram: histogram, count: count)
        )
    }

    private static func toneStatistics(
        bins: [Double], count: Double, variant: LuminanceVariant, transform: (Float) -> Float
    ) -> ToneStatistics {
        let minimum = firstValue(in: bins, transform: transform)
        let maximum = lastValue(in: bins, transform: transform)
        let mean = weightedMean(bins, count: count, transform: transform)
        func percentile(_ fraction: Double) -> Float {
            transform(rawPercentile(bins, fraction: fraction, count: count))
        }
        return ToneStatistics(
            variant: variant, minimum: minimum, maximum: maximum, mean: mean,
            p01: percentile(0.01), p05: percentile(0.05), p10: percentile(0.10),
            p25: percentile(0.25), p50: percentile(0.50), p75: percentile(0.75),
            p90: percentile(0.90), p95: percentile(0.95), p99: percentile(0.99),
            shadowClippingFraction: Float(bins[0]) / Float(count),
            highlightClippingFraction: Float(bins[255]) / Float(count)
        )
    }

    private static func colorStatistics(
        histogram: WeightedHistogramData, count: Double
    ) -> ColorStatistics {
        let means = SIMD3(
            weightedMean(histogram.red, count: count, transform: { $0 }),
            weightedMean(histogram.green, count: count, transform: { $0 }),
            weightedMean(histogram.blue, count: count, transform: { $0 })
        )
        let medians = SIMD3(
            rawPercentile(histogram.red, fraction: 0.5, count: count),
            rawPercentile(histogram.green, fraction: 0.5, count: count),
            rawPercentile(histogram.blue, fraction: 0.5, count: count)
        )
        let channelSpread = max(means.x, max(means.y, means.z))
            - min(means.x, min(means.y, means.z))
        let medianSpread = max(medians.x, max(medians.y, medians.z))
            - min(medians.x, min(medians.y, medians.z))
        // Independent channel histograms do not retain pixel correlation. These are therefore
        // conservative marginal estimates, useful as Tier-0 facts until a masked color pass exists.
        let p95Spread = max(
            rawPercentile(histogram.red, fraction: 0.95, count: count),
            max(
                rawPercentile(histogram.green, fraction: 0.95, count: count),
                rawPercentile(histogram.blue, fraction: 0.95, count: count)
            )
        ) - min(
            rawPercentile(histogram.red, fraction: 0.05, count: count),
            min(
                rawPercentile(histogram.green, fraction: 0.05, count: count),
                rawPercentile(histogram.blue, fraction: 0.05, count: count)
            )
        )
        return ColorStatistics(
            meanRGB: means,
            medianRGB: medians,
            saturationMedian: medianSpread,
            saturationP95: p95Spread,
            channelClipping: ChannelClipping(
                red: Float(histogram.red[255]) / Float(count),
                green: Float(histogram.green[255]) / Float(count),
                blue: Float(histogram.blue[255]) / Float(count)
            ),
            estimatedNeutrality: 1 - min(1, channelSpread / 0.25),
            colorfulness: min(1, max(0, medianSpread * 1.5))
        )
    }

    private static func weightedMean(
        _ bins: [Double], count: Double, transform: (Float) -> Float
    ) -> Float {
        let total = bins.enumerated().reduce(Float.zero) { partial, element in
            partial + transform(Float(element.offset) / 255) * Float(element.element)
        }
        return total / Float(count)
    }

    private static func firstValue(in bins: [Double], transform: (Float) -> Float) -> Float {
        guard let index = bins.firstIndex(where: { $0 > 0 }) else { return 0 }
        return transform(Float(index) / 255)
    }

    private static func lastValue(in bins: [Double], transform: (Float) -> Float) -> Float {
        guard let index = bins.lastIndex(where: { $0 > 0 }) else { return 0 }
        return transform(Float(index) / 255)
    }

    private static func rawPercentile(_ bins: [Double], fraction: Double, count: Double) -> Float {
        let target = max(0, (count - 1) * fraction)
        var cumulative = 0.0
        for (index, bin) in bins.enumerated() {
            cumulative += bin
            if cumulative > target { return Float(index) / 255 }
        }
        return 1
    }

    private static func sRGBDecode(_ value: Float) -> Float {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
