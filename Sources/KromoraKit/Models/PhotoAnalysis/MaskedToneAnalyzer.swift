import CoreGraphics
import Foundation

enum MaskedToneAnalysisError: LocalizedError, Sendable, Equatable {
    case mismatchedImage
    case mismatchedMask
    case missingPixels
    case emptyMask
    case unavailable

    var errorDescription: String? {
        switch self {
        case .mismatchedImage:
            return "The region mask was computed for a different source image"
        case .mismatchedMask:
            return "The region mask does not match the canonical analysis dimensions or quality"
        case .missingPixels:
            return "The region mask pixels are no longer available"
        case .emptyMask:
            return "The region mask does not cover any pixels"
        case .unavailable:
            return "Masked tone analysis could not produce a histogram"
        }
    }
}

/// Computes regional facts through the shared `RegionMask`/`MaskStore` seam. It deliberately owns
/// no Vision or Core Image state: image materialization stays behind `RenderEngining`, while the
/// percentile and color math is the same implementation used by Tier-0 global analysis.
struct MaskedToneAnalyzer: Sendable {
    private let engine: any RenderEngining
    private let store: MaskStore

    init(engine: any RenderEngining = RenderEngine.shared, store: MaskStore = MaskStore()) {
        self.engine = engine
        self.store = store
    }

    func statistics(
        image: AnalysisImage,
        through mask: RegionMask
    ) async throws -> (tone: ToneStatistics, color: ColorStatistics) {
        try await statistics(
            image: image, through: mask, document: EditDocument(), lut: nil, space: .sRGB
        )
    }

    /// Document-aware regional analysis (KRMA-343). Measures the mask through the current
    /// rendered edit so regional facts describe what the photographer sees. The overload above
    /// preserves source measurement for existing callers.
    func statistics(
        image: AnalysisImage,
        through mask: RegionMask,
        document: EditDocument,
        lut: CubeLUT?,
        space: WorkingSpace
    ) async throws -> (tone: ToneStatistics, color: ColorStatistics) {
        try Task.checkCancellation()
        var interval = KromoraObservability.begin(
            .analysisMaskedStatistics, source: image.source, maskQuality: mask.quality
        )
        defer { interval.end() }
        try validate(mask: mask, for: image)
        guard let pixels = await store.pixels(for: mask.reference) else {
            throw MaskedToneAnalysisError.missingPixels
        }
        guard pixels.size == image.dimensions else {
            throw MaskedToneAnalysisError.mismatchedMask
        }
        guard pixels.coverage > 0 else { throw MaskedToneAnalysisError.emptyMask }

        let histogram = await engine.maskedHistogram(
            source: image.source,
            document: document,
            lut: lut,
            scale: .preview(
                maxSize: CGSize(width: image.dimensions.width, height: image.dimensions.height)),
            space: space,
            mask: pixels
        )
        try Task.checkCancellation()
        guard let histogram else { throw MaskedToneAnalysisError.unavailable }
        do {
            let result = try GlobalToneAnalyzer.statistics(from: histogram)
            return (tone: result.tone.perceptual, color: result.color)
        } catch GlobalToneAnalysisError.malformedHistogram {
            throw MaskedToneAnalysisError.unavailable
        }
    }

    private func validate(mask: RegionMask, for image: AnalysisImage) throws {
        guard mask.quality == mask.reference.quality,
            mask.reference.cacheKey.quality == mask.quality,
            mask.reference.cacheKey.kind == mask.kind,
            mask.reference.size == image.dimensions
        else {
            throw MaskedToneAnalysisError.mismatchedMask
        }

        let expectedAssetID = image.assetID.map(PortablePhotoAssetID.compatibility(from:))
            ?? image.source.cacheIdentity.assetID
        guard mask.reference.cacheKey.identity.assetID
                == expectedAssetID,
            mask.reference.cacheKey.identity.sourceFingerprint
                .matches(image.source.cacheIdentity.sourceFingerprint)
        else {
            throw MaskedToneAnalysisError.mismatchedImage
        }
    }

}
