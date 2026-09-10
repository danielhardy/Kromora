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
            document: EditDocument(),
            lut: nil,
            scale: .preview(
                maxSize: CGSize(width: image.dimensions.width, height: image.dimensions.height)),
            space: .sRGB,
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

        let identity = Self.identity(for: image.source)
        guard mask.reference.cacheKey.assetID == identity.assetID,
            mask.reference.cacheKey.sourceFingerprint == identity.fingerprint
        else {
            throw MaskedToneAnalysisError.mismatchedImage
        }
    }

    private static func identity(for source: ImageSource) -> (
        assetID: PhotoAssetID, fingerprint: PhotoSourceFingerprint
    ) {
        switch source.backing {
        case .url(let url):
            let fingerprint = PhotoSourceFingerprint.file(at: url)
            return (PhotoAssetID.file(url, fingerprint: fingerprint), fingerprint)
        case .data(let data):
            let fingerprint = PhotoSourceFingerprint.data(data)
            return (PhotoAssetID.data(data), fingerprint)
        }
    }
}
