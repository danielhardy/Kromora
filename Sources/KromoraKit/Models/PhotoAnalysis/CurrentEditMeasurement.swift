import CoreGraphics
import Foundation

/// Document-aware measurement for content-aware Auto (KRMA-343).
///
/// The completed Photo Intelligence foundation (KRMA-181) measures source data — or an empty
/// `EditDocument` — through `GlobalToneAnalyzer`/`MaskedToneAnalyzer`. Auto must instead measure
/// the **current rendered edit** and evaluate proposals against the same measurable facts. This
/// file owns that pipeline:
///
/// - `CurrentEditMeasurer` renders the effective document at an ~768px analysis scale through the
///   real pipeline seam (`CurrentEditSampling`, implemented by `RenderEngine` in production and by
///   the test fake in tests), then derives every fact from those same rendered samples;
/// - linear luminance is computed from linearized RGB while the display/perceptual histogram is
///   retained separately, and highlight headroom is a separate value that is never inferred from
///   clipped display pixels alone;
/// - saturation/hue/neutral facts come from the same per-pixel samples, not from independent
///   channel histograms;
/// - regional statistics reuse `MaskedToneAnalyzer`/`MaskStore`, but a failed mask only reduces
///   confidence — it never discards the global facts;
/// - noise/detail comes from a bounded, deterministic set of native-resolution patches and reports
///   `.unavailable` rather than guessing when the sampler cannot provide them.
///
/// What this ticket does NOT own: choosing slider values (KRMA-345), scene classification
/// (KRMA-344), or candidate selection (KRMA-347). The analysis-view transform
/// (`AutoCandidateEvaluation.analysisDocument`) is reused, not duplicated.

// MARK: - Rendered samples

/// Bounded RGBA8 pixels of one rendered document at the analysis scale.
///
/// Value-only so it can cross the render-actor boundary. The bytes are in `space`; every
/// downstream fact (tone, correlated color, contrast, neutrals) is derived from this one buffer.
struct RenderedPixelSamples: Sendable, Equatable {
    let width: Int
    let height: Int
    /// Row-major RGBA8, `width * height * 4` bytes.
    let bytes: [UInt8]
    let space: WorkingSpace

    init(width: Int, height: Int, bytes: [UInt8], space: WorkingSpace) {
        self.width = width
        self.height = height
        self.bytes = bytes
        self.space = space
    }

    var isEmpty: Bool { width <= 0 || height <= 0 || bytes.count != width * height * 4 }

    var pixelCount: Int { width * height }
}

/// One native-resolution patch raster for noise/detail estimation.
struct NativePatchPixels: Sendable, Equatable {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    var isEmpty: Bool { width <= 0 || height <= 0 || bytes.count != width * height * 4 }
}

/// The sampling half of the measurement seam. `RenderEngining` stays untouched: histogram callers
/// keep their API, while measurement opts into pixel-correlated facts through this protocol.
/// Default implementations report unavailable so lightweight conformers never guess.
protocol CurrentEditSampling: Sendable {
    /// Render `document` over `source` at `targetLongEdge` and return bounded RGBA8 samples.
    func renderedSamples(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        targetLongEdge: Int,
        space: WorkingSpace
    ) async -> RenderedPixelSamples?

    /// Render native-resolution crops for `specs`. `nil` (or an empty array) means unsupported —
    /// the measurement reports detail as unavailable rather than deciding sharpening or noise
    /// reduction from the reduced preview.
    func nativeDetailPatches(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        specs: [NativePatchSpec],
        space: WorkingSpace
    ) async -> [NativePatchPixels]?
}

extension CurrentEditSampling {
    func renderedSamples(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        targetLongEdge: Int,
        space: WorkingSpace
    ) async -> RenderedPixelSamples? { nil }

    func nativeDetailPatches(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        specs: [NativePatchSpec],
        space: WorkingSpace
    ) async -> [NativePatchPixels]? { nil }
}

extension RenderEngine: CurrentEditSampling {
    func renderedSamples(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        targetLongEdge: Int,
        space: WorkingSpace
    ) async -> RenderedPixelSamples? {
        guard !Task.isCancelled, targetLongEdge > 0 else { return nil }
        let oriented = document.rotation.orientedExtent(source.nativeExtent)
        let box = AutoCandidateEvaluation.targetSize(for: oriented, longEdge: targetLongEdge)
        guard box.width > 0, box.height > 0 else { return nil }
        let request = RenderRequest(
            source: source, document: document, lut: lut,
            targetSize: box, quality: .preview, output: .raster, space: space
        )
        guard let image = await makeCGImage(request), !Task.isCancelled else { return nil }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let captured = bytes.withUnsafeMutableBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            guard let context = CGContext(
                data: base, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard captured, !Task.isCancelled else { return nil }
        return RenderedPixelSamples(width: width, height: height, bytes: bytes, space: space)
    }

    /// Native ROI crops are not yet wired: `RenderRequest.sourceROI` shares the developed-source
    /// memo path and its coordinate contract is not one this ticket may guess at. Returning `nil`
    /// keeps the measurement honest — detail reports `.unavailable` — until a bounded ROI render
    /// exists. See the `nativeDetailPatches` contract above.
    func nativeDetailPatches(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        specs: [NativePatchSpec],
        space: WorkingSpace
    ) async -> [NativePatchPixels]? { nil }
}

// MARK: - Request, configuration, errors

/// How the current edit is measured. `maximumDimension` matches the analysis default (768px);
/// `analysisView` selects the correction-proposal view (LUT/grading/grain/decorative vignette
/// excluded via `AutoCandidateEvaluation.analysisDocument`) versus the complete edit used for
/// final candidate evaluation.
struct CurrentEditMeasurementConfiguration: Codable, Sendable, Equatable, Hashable {
    var maximumDimension: Int
    var space: WorkingSpace
    var analysisView: Bool
    /// Bounded native patch sampling. A reduced preview must not decide sharpening or NR.
    var nativePatchCount: Int
    var nativePatchSize: Int

    static let `default` = CurrentEditMeasurementConfiguration()

    init(
        maximumDimension: Int = 768,
        space: WorkingSpace = .sRGB,
        analysisView: Bool = true,
        nativePatchCount: Int = 5,
        nativePatchSize: Int = 128
    ) {
        self.maximumDimension = max(1, maximumDimension)
        self.space = space
        self.analysisView = analysisView
        self.nativePatchCount = min(max(nativePatchCount, 0), NativePatchPlanner.maxPatches)
        self.nativePatchSize = min(
            max(nativePatchSize, NativePatchPlanner.minPatchSize),
            NativePatchPlanner.maxPatchSize
        )
    }

    /// Stable fingerprint so cache keys distinguish analysis configurations.
    var fingerprint: String {
        "\(maximumDimension):\(space.rawValue):\(analysisView):\(nativePatchCount)x\(nativePatchSize)"
    }
}

enum CurrentEditMeasurementError: LocalizedError, Sendable, Equatable {
    /// The caller did not echo the document it intended to measure. Measuring an empty or stale
    /// document must be explicit, never a defaulted argument.
    case staleDocument(expected: String, actual: String)
    case invalidSource
    /// The sampler could not render the edit. The document is left unchanged; nothing is guessed.
    case renderUnavailable

    var errorDescription: String? {
        switch self {
        case .staleDocument(let expected, let actual):
            return "Measurement request is stale (expected \(expected), got \(actual))"
        case .invalidSource:
            return "The source has no measurable extent"
        case .renderUnavailable:
            return "The current edit could not be rendered for measurement"
        }
    }
}

// MARK: - Highlight headroom

/// Headroom kept separate from the display histogram so highlight recovery is never inferred
/// from clipped display pixels alone. `headroomEV` is only populated when a decoder reports it;
/// otherwise the display clipping fraction is carried as its own fact and `available` is false.
struct HighlightHeadroom: Codable, Sendable, Equatable {
    enum Source: String, Codable, Sendable, Equatable {
        case rawDecoder
        case unavailable
    }

    let source: Source
    let available: Bool
    /// True when a RAW decoder reports recovery support and display pixels are actually clipped.
    let rawRecoveryLikely: Bool
    /// The display-pipeline highlight clipping fraction — a fact about the render, not headroom.
    let displayHighlightClipping: Float
    /// Reserved for a decoder-reported value. Never estimated from display bins.
    let headroomEV: Float?

    init(
        source: Source = .unavailable,
        available: Bool = false,
        rawRecoveryLikely: Bool = false,
        displayHighlightClipping: Float = 0,
        headroomEV: Float? = nil
    ) {
        self.source = source
        self.available = available
        self.rawRecoveryLikely = rawRecoveryLikely
        self.displayHighlightClipping = Self.unit(displayHighlightClipping)
        self.headroomEV = headroomEV
    }

    static func raw(
        capabilities: RAWCapabilities?,
        displayHighlightClipping: Float
    ) -> HighlightHeadroom {
        guard let capabilities else {
            return HighlightHeadroom(
                source: .unavailable, available: false,
                displayHighlightClipping: displayHighlightClipping
            )
        }
        return HighlightHeadroom(
            source: .rawDecoder,
            available: true,
            rawRecoveryLikely: capabilities.isHighlightRecoverySupported
                && displayHighlightClipping > 0.001,
            displayHighlightClipping: displayHighlightClipping
        )
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

// MARK: - Pixel-correlated color

/// One low-chroma region that could anchor a neutral correction, with the evidence a policy
/// needs to decline: confidence, location, and whether the frame is too mixed to trust.
struct NeutralCandidate: Codable, Sendable, Equatable {
    /// 3×3 cell address plus normalized bounds, so a later policy can compare regions spatially
    /// without seeing pixels.
    let column: Int
    let row: Int
    let bounds: NormalizedRect
    /// Fraction of sampled pixels inside the cell contributing to the estimate.
    let coverage: Float
    /// Mean chroma distance (max−min over RGB, 0…1). Lower is more neutral.
    let meanChroma: Float
    let meanLuma: Float
    let confidence: Float
    /// False when evidence is weak (low confidence) or mixed (several strong hues compete
    /// frame-wide), in which case no neutral correction may be recommended.
    let recommendsCorrection: Bool

    init(
        column: Int, row: Int, bounds: NormalizedRect,
        coverage: Float, meanChroma: Float, meanLuma: Float,
        confidence: Float, recommendsCorrection: Bool
    ) {
        self.column = column
        self.row = row
        self.bounds = bounds
        self.coverage = Self.unit(coverage)
        self.meanChroma = Self.unit(meanChroma)
        self.meanLuma = Self.unit(meanLuma)
        self.confidence = Self.unit(confidence)
        self.recommendsCorrection = recommendsCorrection
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// Color facts derived from the same rendered pixel samples as luminance — never approximated
/// from independent channel histograms.
struct PixelCorrelatedColor: Codable, Sendable, Equatable {
    static let hueBinCount = 12

    let meanRGB: SIMD3<Float>
    let medianRGB: SIMD3<Float>
    let saturationMean: Float
    let saturationMedian: Float
    let saturationP95: Float
    /// Normalized 12-bin HSV-hue distribution over chromatic pixels (0…1, sums to 1 when defined).
    let hueHistogram: [Float]
    /// Normalized Shannon entropy of the hue distribution (0 = single hue, 1 = uniform).
    let hueEntropy: Float
    let channelClipping: ChannelClipping
    let estimatedNeutrality: Float
    let colorfulness: Float
    /// True when three or more hue bins each hold a significant share — a mixed frame in which
    /// no neutral correction may be recommended.
    let isMixed: Bool
    let neutralCandidates: [NeutralCandidate]

    /// Whether any neutral correction is supportable: a confident, non-mixed candidate exists.
    var recommendsNeutralCorrection: Bool {
        !isMixed && neutralCandidates.contains(where: \.recommendsCorrection)
    }

    init(
        meanRGB: SIMD3<Float> = .zero,
        medianRGB: SIMD3<Float> = .zero,
        saturationMean: Float = 0,
        saturationMedian: Float = 0,
        saturationP95: Float = 0,
        hueHistogram: [Float] = [Float](repeating: 0, count: PixelCorrelatedColor.hueBinCount),
        hueEntropy: Float = 0,
        channelClipping: ChannelClipping = .none,
        estimatedNeutrality: Float = 0,
        colorfulness: Float = 0,
        isMixed: Bool = false,
        neutralCandidates: [NeutralCandidate] = []
    ) {
        self.meanRGB = Self.unitVector(meanRGB)
        self.medianRGB = Self.unitVector(medianRGB)
        self.saturationMean = Self.unit(saturationMean)
        self.saturationMedian = Self.unit(saturationMedian)
        self.saturationP95 = Self.unit(saturationP95)
        self.hueHistogram = hueHistogram.map(Self.unit)
        self.hueEntropy = Self.unit(hueEntropy)
        self.channelClipping = channelClipping
        self.estimatedNeutrality = Self.unit(estimatedNeutrality)
        self.colorfulness = Self.unit(colorfulness)
        self.isMixed = isMixed
        self.neutralCandidates = neutralCandidates
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func unitVector(_ value: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(unit(value.x), unit(value.y), unit(value.z))
    }
}

// MARK: - Native detail

/// Deterministic native-resolution patch specification in normalized image coordinates.
struct NativePatchSpec: Codable, Sendable, Equatable, Hashable {
    let rect: NormalizedRect
    /// Requested square edge in native pixels (clamped by the planner).
    let edge: Int
}

enum NativePatchPlanner {
    static let maxPatches = 8
    static let minPatchSize = 64
    static let maxPatchSize = 256

    /// Deterministic patch layout from the source fingerprint: the same fixture always yields
    /// the same rects, and unrelated sources share no layout coupling beyond the bounds.
    static func plan(
        fingerprint: PhotoSourceFingerprint,
        count: Int,
        edge: Int,
        imageExtent: CGSize
    ) -> [NativePatchSpec] {
        let boundedCount = min(max(count, 0), maxPatches)
        guard boundedCount > 0,
              imageExtent.width >= 1, imageExtent.height >= 1,
              imageExtent.width.isFinite, imageExtent.height.isFinite else { return [] }
        let boundedEdge = min(max(edge, minPatchSize), maxPatchSize)
        let normalizedWidth = min(1, CGFloat(boundedEdge) / imageExtent.width)
        let normalizedHeight = min(1, CGFloat(boundedEdge) / imageExtent.height)
        var rng = SplitMix64(seed: fnv1a64(fingerprint.cacheKey))
        var specs: [NativePatchSpec] = []
        specs.reserveCapacity(boundedCount)
        // Fixed probe points (center + thirds) come first so a reduced count still covers the
        // frame; remaining slots are fingerprint-deterministic pseudo-random placements.
        let probes: [(Double, Double)] = [(0.5, 0.5), (1 / 3, 1 / 3), (2 / 3, 1 / 3),
                                          (1 / 3, 2 / 3), (2 / 3, 2 / 3)]
        for index in 0..<boundedCount {
            let center: (Double, Double)
            if index < probes.count {
                center = probes[index]
            } else {
                center = (rng.nextUnit(), rng.nextUnit())
            }
            let x = min(max(center.0 - Double(normalizedWidth) / 2, 0), 1 - Double(normalizedWidth))
            let y = min(max(center.1 - Double(normalizedHeight) / 2, 0), 1 - Double(normalizedHeight))
            specs.append(NativePatchSpec(
                rect: NormalizedRect(
                    x: x, y: y,
                    width: Double(normalizedWidth), height: Double(normalizedHeight)
                ),
                edge: boundedEdge
            ))
        }
        return specs
    }

    private static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return hash
    }

    private struct SplitMix64 {
        var state: UInt64

        init(seed: UInt64) {
            // Zero is a legal seed but a fixed point for the first step; perturb it.
            self.state = seed &+ 0x9E37_79B9_7F4A_7C15
        }

        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func nextUnit() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }
    }
}

/// Bounded noise/detail facts from native-resolution patches. `.unavailable` (no patches) is a
/// normal outcome — the reduced preview must not decide sharpening or noise reduction.
struct NativeDetailMeasurement: Codable, Sendable, Equatable {
    let requested: Int
    let completed: Int
    let available: Bool
    /// Mean-absolute-Laplacian noise estimate over completed patches, 0…1.
    let noiseSigma: Float
    /// Fraction of patch pixels above the edge threshold, 0…1.
    let edgeDensity: Float
    let patchSpecs: [NativePatchSpec]

    static let unavailable = NativeDetailMeasurement(
        requested: 0, completed: 0, available: false,
        noiseSigma: 0, edgeDensity: 0, patchSpecs: []
    )

    init(
        requested: Int, completed: Int, available: Bool,
        noiseSigma: Float, edgeDensity: Float, patchSpecs: [NativePatchSpec]
    ) {
        self.requested = max(0, requested)
        self.completed = max(0, completed)
        self.available = available && completed > 0
        self.noiseSigma = Self.unit(noiseSigma)
        self.edgeDensity = Self.unit(edgeDensity)
        self.patchSpecs = patchSpecs
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

// MARK: - Measurement value

/// The measurable facts about one rendered edit: global tone/color from the same samples,
/// headroom kept apart from display clipping, regional facts with independent confidence, and
/// bounded native detail. Facts only — no slider values (KRMA-345) and no scene labels (KRMA-344).
struct CurrentEditMeasurement: Codable, Sendable, Equatable {
    static let version = 1

    let version: Int
    let sourceFingerprint: PhotoSourceFingerprint
    /// Hash of the document the caller asked to measure.
    let documentHash: String
    /// Hash of the document actually rendered (analysis view when configured).
    let effectiveDocumentHash: String
    let configurationFingerprint: String
    let space: WorkingSpace
    let isAnalysisView: Bool
    /// True for `EditDocument()` measured explicitly — the identity baseline, not a silent empty.
    let isBaseline: Bool

    let globalTone: LuminanceDistribution
    let color: PixelCorrelatedColor
    let highlightHeadroom: HighlightHeadroom
    /// Mean adjacent-block luma difference, 0…1, with its own confidence.
    let localContrast: Float
    let localContrastConfidence: Float
    /// Only successfully analyzed masks. Omission + `failedMaskCount` is the mask-failure shape.
    let regions: [AnalyzedRegion]
    let failedMaskCount: Int
    let detail: NativeDetailMeasurement
    /// 0…1. Optional signals reduce it; they never invalidate the global facts.
    let globalConfidence: Float

    init(
        sourceFingerprint: PhotoSourceFingerprint,
        documentHash: String,
        effectiveDocumentHash: String,
        configurationFingerprint: String,
        space: WorkingSpace,
        isAnalysisView: Bool,
        isBaseline: Bool,
        globalTone: LuminanceDistribution,
        color: PixelCorrelatedColor,
        highlightHeadroom: HighlightHeadroom,
        localContrast: Float,
        localContrastConfidence: Float,
        regions: [AnalyzedRegion] = [],
        failedMaskCount: Int = 0,
        detail: NativeDetailMeasurement = .unavailable,
        globalConfidence: Float = 1
    ) {
        self.version = Self.version
        self.sourceFingerprint = sourceFingerprint
        self.documentHash = documentHash
        self.effectiveDocumentHash = effectiveDocumentHash
        self.configurationFingerprint = configurationFingerprint
        self.space = space
        self.isAnalysisView = isAnalysisView
        self.isBaseline = isBaseline
        self.globalTone = globalTone
        self.color = color
        self.highlightHeadroom = highlightHeadroom
        self.localContrast = Self.unit(localContrast)
        self.localContrastConfidence = Self.unit(localContrastConfidence)
        self.regions = regions
        self.failedMaskCount = max(0, failedMaskCount)
        self.detail = detail
        self.globalConfidence = Self.unit(globalConfidence)
    }

    private static func unit(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

/// Cache identity for one measurement. Source, effective document, analysis configuration, and
/// render revision (space + measurement schema) are all part of the key: changing the Light
/// panel must not read back facts measured under an older edit.
struct CurrentEditMeasurementKey: Sendable, Codable, Hashable, Equatable {
    let assetID: PhotoAssetID
    let sourceFingerprint: PhotoSourceFingerprint
    let effectiveDocumentHash: String
    let completeDocumentHash: String
    let configurationFingerprint: String
    let space: WorkingSpace
    let measurementVersion: Int

    var cacheKey: String {
        [
            assetID.raw,
            sourceFingerprint.cacheKey,
            effectiveDocumentHash,
            completeDocumentHash,
            configurationFingerprint,
            space.rawValue,
            String(measurementVersion),
        ].joined(separator: "|")
    }
}

// MARK: - Pure pixel analysis

/// Pure per-pixel analysis over one RGBA8 buffer. No renderer, no `CGImage`, no framework: the
/// sampler owns rasterization and these functions own the arithmetic, so every fact below is
/// unit-testable against hand-built bytes.
enum RenderedPixelAnalyzer {
    /// Tone via the shared histogram-to-facts mapping, so global tone stays consistent with the
    /// Tier-0 path while operating on the current edit's pixels.
    static func tone(from samples: RenderedPixelSamples) throws -> LuminanceDistribution {
        guard !samples.isEmpty,
              let histogram = HistogramData(
                  rgba8: samples.bytes, width: samples.width, height: samples.height
              )
        else { throw GlobalToneAnalysisError.malformedHistogram }
        return try GlobalToneAnalyzer.statistics(from: histogram).tone
    }

    /// Saturation, hue, chroma, and neutral evidence from the same samples as luminance.
    static func correlatedColor(from samples: RenderedPixelSamples) -> PixelCorrelatedColor {
        guard !samples.isEmpty else { return PixelCorrelatedColor() }
        let width = samples.width
        let height = samples.height
        let count = width * height

        var sumR = 0.0
        var sumG = 0.0
        var sumB = 0.0
        var saturations: [Float] = []
        saturations.reserveCapacity(count)
        var hueBins = [Double](repeating: 0, count: PixelCorrelatedColor.hueBinCount)
        var chromaticCount = 0
        // Hasler–Süsstrunk colorfulness accumulators.
        var rgValues: [Double] = []
        var ybValues: [Double] = []
        rgValues.reserveCapacity(count)
        ybValues.reserveCapacity(count)
        // 3×3 neutral-cell accumulators.
        var cellChroma = [Double](repeating: 0, count: 9)
        var cellLuma = [Double](repeating: 0, count: 9)
        var cellCounts = [Int](repeating: 0, count: 9)

        samples.bytes.withUnsafeBufferPointer { buffer in
            for y in 0..<height {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let r = Double(buffer[offset]) / 255
                    let g = Double(buffer[offset + 1]) / 255
                    let b = Double(buffer[offset + 2]) / 255
                    sumR += r
                    sumG += g
                    sumB += b
                    let maximum = max(r, max(g, b))
                    let minimum = min(r, min(g, b))
                    let delta = maximum - minimum
                    let saturation = maximum > 0 ? delta / maximum : 0
                    saturations.append(Float(saturation))
                    let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
                    let rg = r - g
                    let yb = 0.5 * (r + g) - b
                    rgValues.append(rg)
                    ybValues.append(yb)
                    if delta > 0.02, maximum > 0 {
                        chromaticCount += 1
                        hueBins[hueBin(r: r, g: g, b: b, max: maximum, delta: delta)] += 1
                    }
                    let cellX = min(2, x * 3 / max(1, width))
                    let cellY = min(2, y * 3 / max(1, height))
                    let cell = cellY * 3 + cellX
                    cellChroma[cell] += delta
                    cellLuma[cell] += luma
                    cellCounts[cell] += 1
                }
            }
        }

        let meanRGB = SIMD3<Float>(
            Float(sumR / Double(count)), Float(sumG / Double(count)), Float(sumB / Double(count))
        )
        let sorted = saturations.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        let saturationMean = saturations.reduce(0, +) / Float(max(1, saturations.count))

        let total = max(1, Double(chromaticCount))
        let normalized = hueBins.map { Float($0 / total) }
        var entropy = 0.0
        for probability in normalized where probability > 0 {
            entropy -= Double(probability) * log2(Double(probability))
        }
        let hueEntropy = Float(entropy / log2(Double(PixelCorrelatedColor.hueBinCount)))
        let strongBins = normalized.filter { $0 > 0.15 }.count
        let isMixed = strongBins >= 3

        let meanRG = rgValues.reduce(0, +) / Double(max(1, rgValues.count))
        let meanYB = ybValues.reduce(0, +) / Double(max(1, ybValues.count))
        let stdRG = standardDeviation(rgValues, mean: meanRG)
        let stdYB = standardDeviation(ybValues, mean: meanYB)
        let colorfulness = min(1, (sqrt(stdRG * stdRG + stdYB * stdYB)
            + 0.3 * sqrt(meanRG * meanRG + meanYB * meanYB)) / 0.4)

        let spread = max(meanRGB.x, max(meanRGB.y, meanRGB.z))
            - min(meanRGB.x, min(meanRGB.y, meanRGB.z))
        let neutrality = 1 - min(1, spread / 0.25)

        // Channel clipping + per-channel medians reuse the marginal bins of the same buffer.
        var clipping = ChannelClipping.none
        var medianRGB = meanRGB
        if let histogram = HistogramData(
            rgba8: samples.bytes, width: width, height: height
        ) {
            let total = Double(count)
            clipping = ChannelClipping(
                red: Float(histogram.red[255]) / Float(total),
                green: Float(histogram.green[255]) / Float(total),
                blue: Float(histogram.blue[255]) / Float(total)
            )
            medianRGB = SIMD3(
                percentile(histogram.red, fraction: 0.5, count: total),
                percentile(histogram.green, fraction: 0.5, count: total),
                percentile(histogram.blue, fraction: 0.5, count: total)
            )
        }

        var candidates: [NeutralCandidate] = []
        for row in 0..<3 {
            for column in 0..<3 {
                let cell = row * 3 + column
                let cellCount = cellCounts[cell]
                guard cellCount > 0 else { continue }
                let meanChroma = cellChroma[cell] / Double(cellCount)
                let meanLuma = cellLuma[cell] / Double(cellCount)
                let coverage = Float(cellCount) / Float(count)
                // Pure black/white cells carry no white-balance evidence.
                let brightnessWeight: Double =
                    meanLuma < 0.12 || meanLuma > 0.92 ? 0 :
                    1 - abs(meanLuma - 0.5) / 0.5 * 0.5
                let chromaWeight = max(0, 1 - meanChroma / 0.06)
                let confidence = Float(chromaWeight * brightnessWeight)
                let recommends = confidence >= 0.5 && !isMixed
                candidates.append(NeutralCandidate(
                    column: column, row: row,
                    bounds: NormalizedRect(
                        x: Double(column) / 3, y: Double(row) / 3,
                        width: 1 / 3, height: 1 / 3
                    ),
                    coverage: coverage,
                    meanChroma: Float(meanChroma),
                    meanLuma: Float(meanLuma),
                    confidence: confidence,
                    recommendsCorrection: recommends
                ))
            }
        }

        return PixelCorrelatedColor(
            meanRGB: meanRGB,
            medianRGB: medianRGB,
            saturationMean: saturationMean,
            saturationMedian: median,
            saturationP95: p95,
            hueHistogram: normalized,
            hueEntropy: hueEntropy,
            channelClipping: clipping,
            estimatedNeutrality: neutrality,
            colorfulness: Float(colorfulness),
            isMixed: isMixed,
            neutralCandidates: candidates
        )
    }

    /// Block-contrast estimate: mean adjacent-block luma difference over 32px blocks, with
    /// confidence from the block population. Deterministic for a fixture.
    static func localContrast(from samples: RenderedPixelSamples) -> (value: Float, confidence: Float) {
        guard !samples.isEmpty else { return (0, 0) }
        let block = 32
        let blocksX = max(1, samples.width / block)
        let blocksY = max(1, samples.height / block)
        var means = [Double](repeating: 0, count: blocksX * blocksY)
        var counts = [Int](repeating: 0, count: blocksX * blocksY)
        samples.bytes.withUnsafeBufferPointer { buffer in
            for y in 0..<samples.height {
                for x in 0..<samples.width {
                    let offset = (y * samples.width + x) * 4
                    let luma = (0.2126 * Double(buffer[offset])
                        + 0.7152 * Double(buffer[offset + 1])
                        + 0.0722 * Double(buffer[offset + 2])) / 255
                    let blockIndex = min(blocksY - 1, y / block) * blocksX
                        + min(blocksX - 1, x / block)
                    means[blockIndex] += luma
                    counts[blockIndex] += 1
                }
            }
        }
        for index in means.indices where counts[index] > 0 {
            means[index] /= Double(counts[index])
        }
        var total = 0.0
        var pairs = 0
        for y in 0..<blocksY {
            for x in 0..<blocksX {
                if x + 1 < blocksX {
                    total += abs(means[y * blocksX + x] - means[y * blocksX + x + 1])
                    pairs += 1
                }
                if y + 1 < blocksY {
                    total += abs(means[y * blocksX + x] - means[(y + 1) * blocksX + x])
                    pairs += 1
                }
            }
        }
        guard pairs > 0 else {
            // A single block carries no adjacency evidence; report zero contrast with zero
            // confidence rather than a spurious value.
            return (0, 0)
        }
        let value = Float(total / Double(pairs))
        // Confidence grows with the block population and saturates at a modest grid.
        let confidence = Float(min(1, Double(blocksX * blocksY) / 24))
        return (min(max(value, 0), 1), confidence)
    }

    /// Bounded noise/detail facts from native patches. Pure: rasterization is the sampler's job.
    static func detail(
        from patches: [NativePatchPixels], specs: [NativePatchSpec], requested: Int
    ) -> NativeDetailMeasurement {
        let completed = patches.filter { !$0.isEmpty }
        guard !completed.isEmpty else {
            return NativeDetailMeasurement(
                requested: requested, completed: 0, available: false,
                noiseSigma: 0, edgeDensity: 0, patchSpecs: specs
            )
        }
        var noiseTotal = 0.0
        var noiseSamples = 0
        var edgeHits = 0
        var edgeSamples = 0
        for patch in completed {
            let luma = patchLuma(patch)
            guard !luma.isEmpty else { continue }
            for y in 1..<(patch.height - 1) {
                for x in 1..<(patch.width - 1) {
                    let center = luma[y * patch.width + x]
                    let laplacian = abs(
                        4 * center
                            - luma[y * patch.width + x - 1]
                            - luma[y * patch.width + x + 1]
                            - luma[(y - 1) * patch.width + x]
                            - luma[(y + 1) * patch.width + x]
                    )
                    noiseTotal += laplacian
                    noiseSamples += 1
                    let gradientX = abs(
                        luma[y * patch.width + x + 1] - luma[y * patch.width + x - 1]
                    )
                    let gradientY = abs(
                        luma[(y + 1) * patch.width + x] - luma[(y - 1) * patch.width + x]
                    )
                    if max(gradientX, gradientY) > 0.12 { edgeHits += 1 }
                    edgeSamples += 1
                }
            }
        }
        guard noiseSamples > 0, edgeSamples > 0 else {
            return NativeDetailMeasurement(
                requested: requested, completed: completed.count, available: false,
                noiseSigma: 0, edgeDensity: 0, patchSpecs: specs
            )
        }
        return NativeDetailMeasurement(
            requested: requested,
            completed: completed.count,
            available: true,
            noiseSigma: Float(noiseTotal / Double(noiseSamples)),
            edgeDensity: Float(Double(edgeHits) / Double(edgeSamples)),
            patchSpecs: specs
        )
    }

    // MARK: - Private helpers

    private static func hueBin(r: Double, g: Double, b: Double, max: Double, delta: Double) -> Int {
        var hue: Double
        if max == r {
            hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if max == g {
            hue = (b - r) / delta + 2
        } else {
            hue = (r - g) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return min(PixelCorrelatedColor.hueBinCount - 1, Int(hue / 30))
    }

    private static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
        return sqrt(max(0, variance))
    }

    private static func percentile(_ bins: [Int], fraction: Double, count: Double) -> Float {
        let target = max(0, (count - 1) * fraction)
        var cumulative = 0.0
        for (index, bin) in bins.enumerated() {
            cumulative += Double(bin)
            if cumulative > target { return Float(index) / 255 }
        }
        return 1
    }

    private static func patchLuma(_ patch: NativePatchPixels) -> [Double] {
        guard !patch.isEmpty else { return [] }
        var luma = [Double](repeating: 0, count: patch.width * patch.height)
        patch.bytes.withUnsafeBufferPointer { buffer in
            for index in 0..<(patch.width * patch.height) {
                luma[index] = (0.2126 * Double(buffer[index * 4])
                    + 0.7152 * Double(buffer[index * 4 + 1])
                    + 0.0722 * Double(buffer[index * 4 + 2])) / 255
            }
        }
        return luma
    }
}

// MARK: - Measurer

/// Measures the current rendered edit through the real pipeline seam.
///
/// The engine is injected as `any RenderEngining & CurrentEditSampling` so production passes a
/// `RenderEngine` (real pixels) while tests pass a stub with deterministic bytes. Masks are
/// resolved through the caller's `MaskStore`; regional failures reduce confidence and are
/// counted, never promoted into global failures.
struct CurrentEditMeasurer: Sendable {
    let engine: any RenderEngining & CurrentEditSampling
    let store: MaskStore

    init(engine: any RenderEngining & CurrentEditSampling, store: MaskStore = MaskStore()) {
        self.engine = engine
        self.store = store
    }

    /// Measure `document` over `source`.
    ///
    /// - Parameters:
    ///   - expectedDocumentHash: must equal `document.editHash`. This is the staleness guard:
    ///     there is no defaulted document, and an empty `EditDocument()` only measures when its
    ///     hash is explicitly echoed (reported via `isBaseline`).
    ///   - masks: semantic masks to analyze regionally. Failures are counted in
    ///     `failedMaskCount`; global facts are always returned when the render succeeds.
    func measure(
        source: ImageSource,
        assetID: PhotoAssetID? = nil,
        document: EditDocument,
        expectedDocumentHash: String,
        lut: CubeLUT? = nil,
        configuration: CurrentEditMeasurementConfiguration = .default,
        masks: [RegionMask] = []
    ) async throws -> CurrentEditMeasurement {
        guard document.editHash == expectedDocumentHash else {
            throw CurrentEditMeasurementError.staleDocument(
                expected: expectedDocumentHash, actual: document.editHash
            )
        }
        guard source.nativeExtent.width >= 1, source.nativeExtent.height >= 1,
              source.nativeExtent.width.isFinite, source.nativeExtent.height.isFinite
        else { throw CurrentEditMeasurementError.invalidSource }
        try Task.checkCancellation()

        let effectiveDocument = configuration.analysisView
            ? AutoCandidateEvaluation.analysisDocument(from: document)
            : document

        guard let samples = await engine.renderedSamples(
            source: source, document: effectiveDocument, lut: lut,
            targetLongEdge: configuration.maximumDimension, space: configuration.space
        ), !samples.isEmpty else {
            throw CurrentEditMeasurementError.renderUnavailable
        }
        try Task.checkCancellation()

        let tone = try RenderedPixelAnalyzer.tone(from: samples)
        let color = RenderedPixelAnalyzer.correlatedColor(from: samples)
        let contrast = RenderedPixelAnalyzer.localContrast(from: samples)

        let headroom: HighlightHeadroom
        if source.kind == .raw {
            let capabilities = await engine.rawCapabilities(for: source)
            headroom = .raw(
                capabilities: capabilities,
                displayHighlightClipping: tone.perceptual.highlightClippingFraction
            )
        } else {
            headroom = HighlightHeadroom(
                source: .unavailable, available: false,
                displayHighlightClipping: tone.perceptual.highlightClippingFraction
            )
        }
        try Task.checkCancellation()

        // Regional facts through the shared mask seam, measured under the same effective
        // document as the global facts. Each mask stands on its own: a missing pixel payload
        // or analyzer failure omits that region and counts it, never the globals.
        var regions: [AnalyzedRegion] = []
        regions.reserveCapacity(masks.count)
        var failedMasks = 0
        if !masks.isEmpty {
            let image = try AnalysisImageFactory.make(
                from: source, assetID: assetID,
                configuration: AnalysisConfiguration(
                    maximumDimension: configuration.maximumDimension
                )
            )
            let regional = MaskedToneAnalyzer(engine: engine, store: store)
            for mask in masks {
                do {
                    try Task.checkCancellation()
                    let statistics = try await regional.statistics(
                        image: image, through: mask,
                        document: effectiveDocument, lut: lut, space: configuration.space
                    )
                    regions.append(AnalyzedRegion(
                        id: mask.id, kind: mask.kind, mask: mask.reference,
                        bounds: mask.bounds, confidence: mask.confidence,
                        importance: mask.confidence * mask.coverage,
                        tone: statistics.tone, color: statistics.color,
                        coverage: mask.coverage
                    ))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failedMasks += 1
                }
            }
        }
        try Task.checkCancellation()

        let specs = NativePatchPlanner.plan(
            fingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: source),
            count: configuration.nativePatchCount,
            edge: configuration.nativePatchSize,
            imageExtent: source.nativeExtent
        )
        let detail: NativeDetailMeasurement
        if specs.isEmpty {
            detail = NativeDetailMeasurement(
                requested: 0, completed: 0, available: false,
                noiseSigma: 0, edgeDensity: 0, patchSpecs: []
            )
        } else if let patches = await engine.nativeDetailPatches(
            source: source, document: effectiveDocument, lut: lut,
            specs: specs, space: configuration.space
        ) {
            detail = RenderedPixelAnalyzer.detail(
                from: patches, specs: specs, requested: specs.count
            )
        } else {
            detail = NativeDetailMeasurement(
                requested: specs.count, completed: 0, available: false,
                noiseSigma: 0, edgeDensity: 0, patchSpecs: specs
            )
        }

        // Confidence degrades per missing optional signal; global tone/color facts stand.
        var confidence: Float = 1
        if !headroom.available { confidence -= 0.1 }
        if !detail.available { confidence -= 0.1 }
        if failedMasks > 0 { confidence -= 0.1 }
        if regions.isEmpty, !masks.isEmpty { confidence -= 0.1 }

        return CurrentEditMeasurement(
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: source),
            documentHash: document.editHash,
            effectiveDocumentHash: effectiveDocument.editHash,
            configurationFingerprint: configuration.fingerprint,
            space: configuration.space,
            isAnalysisView: configuration.analysisView,
            isBaseline: document.isIdentity,
            globalTone: tone,
            color: color,
            highlightHeadroom: headroom,
            localContrast: contrast.value,
            localContrastConfidence: contrast.confidence,
            regions: regions,
            failedMaskCount: failedMasks,
            detail: detail,
            globalConfidence: confidence
        )
    }

    /// Cache identity for a measurement request. Distinguishes source, effective document,
    /// analysis configuration, and render revision (space + schema version).
    func key(
        source: ImageSource,
        assetID: PhotoAssetID,
        document: EditDocument,
        configuration: CurrentEditMeasurementConfiguration
    ) -> CurrentEditMeasurementKey {
        let effective = configuration.analysisView
            ? AutoCandidateEvaluation.analysisDocument(from: document)
            : document
        return CurrentEditMeasurementKey(
            assetID: assetID,
            sourceFingerprint: PhotoAnalysisCoordinator.sourceFingerprint(for: source),
            effectiveDocumentHash: effective.editHash,
            completeDocumentHash: document.editHash,
            configurationFingerprint: configuration.fingerprint,
            space: configuration.space,
            measurementVersion: CurrentEditMeasurement.version
        )
    }
}

// MARK: - Cache

/// Small, durable storage for `CurrentEditMeasurement` values. Same atomic-file discipline as
/// `PhotoAnalysisCache`: each key gets its own atomically replaced JSON file, and a missing,
/// malformed, or stale entry is a miss rather than a measurement failure.
actor CurrentEditMeasurementCache {
    private struct PersistedMeasurement: Codable, Sendable, Equatable {
        let key: CurrentEditMeasurementKey
        let measurement: CurrentEditMeasurement
    }

    private let directory: URL

    init(directory: URL = CurrentEditMeasurementCache.defaultDirectory()) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func measurement(for key: CurrentEditMeasurementKey) throws -> CurrentEditMeasurement? {
        try Task.checkCancellation()
        guard let data = try? Data(contentsOf: fileURL(for: key)) else { return nil }
        try Task.checkCancellation()
        guard let persisted = try? JSONDecoder().decode(PersistedMeasurement.self, from: data),
              persisted.key == key,
              persisted.measurement.version == CurrentEditMeasurement.version,
              persisted.measurement.effectiveDocumentHash == key.effectiveDocumentHash,
              persisted.measurement.configurationFingerprint == key.configurationFingerprint
        else { return nil }
        return persisted.measurement
    }

    func store(_ measurement: CurrentEditMeasurement, for key: CurrentEditMeasurementKey) throws {
        try Task.checkCancellation()
        guard measurement.effectiveDocumentHash == key.effectiveDocumentHash,
              measurement.configurationFingerprint == key.configurationFingerprint
        else { throw CurrentEditMeasurementError.staleDocument(
            expected: key.effectiveDocumentHash, actual: measurement.effectiveDocumentHash
        ) }
        let data = try JSONEncoder().encode(PersistedMeasurement(key: key, measurement: measurement))
        try Task.checkCancellation()
        try data.write(to: fileURL(for: key), options: .atomic)
    }

    private func fileURL(for key: CurrentEditMeasurementKey) -> URL {
        directory.appendingPathComponent(Self.filename(for: key), isDirectory: false)
    }

    private static func filename(for key: CurrentEditMeasurementKey) -> String {
        var hasher = Hasher()
        hasher.combine(key.cacheKey)
        let digest = String(format: "%016llx", UInt64(bitPattern: Int64(hasher.finalize())))
        return "current-edit-\(digest).json"
    }

    private static func defaultDirectory() -> URL {
        KromoraStorage.applicationSupportRoot()
            .appendingPathComponent("CurrentEditMeasurement", isDirectory: true)
    }
}
