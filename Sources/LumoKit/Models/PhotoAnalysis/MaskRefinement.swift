import Foundation

enum MaskRefinementError: Error, Sendable, Equatable {
    case missingSeedPixels
    case invalidTargetDimensions
    case invalidTileSize
}

/// Upgrades a cached semantic mask without rerunning its detector.
///
/// The source image is represented by its existing ImageSource descriptor at this boundary. The
/// seed mask's semantic boundary is scaled into render resolution by the shared Accelerate path.
/// Cancellation is checked before and after the non-cancellable vImage call and again before the
/// durable store write.
actor MaskRefinementService {
    private let store: MaskStore

    init(store: MaskStore) {
        self.store = store
    }

    func refine(
        mask: RegionMask,
        source: ImageSource,
        targetDimensions: PixelDimensions? = nil,
        tileSize: Int = 256
    ) async throws -> RegionMask {
        guard tileSize > 0 else { throw MaskRefinementError.invalidTileSize }
        let dimensions = targetDimensions ?? Self.dimensions(for: source)
        guard dimensions.width > 0, dimensions.height > 0 else {
            throw MaskRefinementError.invalidTargetDimensions
        }

        // A refinement is deterministic for its inputs, so a stored result is reused as-is.
        // Without this every photo open recomputed (and re-persisted) the full-resolution
        // mask — minutes on a 60MP source.
        let targetKey = mask.reference.cacheKey.with(kind: mask.kind, quality: .render)
        if let existing = await store.mask(for: targetKey, quality: .render),
           existing.size == dimensions,
           let existingPixels = await store.pixels(for: existing) {
            return RegionMask(
                id: mask.id,
                kind: mask.kind,
                bounds: mask.bounds,
                quality: .render,
                reference: existing,
                confidence: mask.confidence,
                coverage: existingPixels.coverage
            )
        }

        guard let seed = await store.pixels(for: mask.reference) else {
            throw MaskRefinementError.missingSeedPixels
        }

        try Task.checkCancellation()
        let refined = try MaskOperations.resized(seed, to: dimensions)
        // vImage is not cancellable while running. This yield gives a superseded render a
        // scheduling point immediately after the scale and before any store work begins.
        await Task.yield()
        try Task.checkCancellation()
        let key = mask.reference.cacheKey.with(kind: mask.kind, quality: .render)
        let reference = try await store.store(refined, for: key, quality: .render)
        return RegionMask(
            id: mask.id,
            kind: mask.kind,
            bounds: mask.bounds,
            quality: .render,
            reference: reference,
            confidence: mask.confidence,
            coverage: refined.coverage
        )
    }

    private static func dimensions(for source: ImageSource) -> PixelDimensions {
        PixelDimensions(
            width: max(1, Int(source.nativeExtent.width.rounded())),
            height: max(1, Int(source.nativeExtent.height.rounded()))
        )
    }

}

extension PhotoAnalysisCoordinator {
    /// Refine a mask through the same durable store owned by this coordinator.
    func refineMask(
        _ mask: RegionMask,
        source: ImageSource,
        targetDimensions: PixelDimensions? = nil,
        tileSize: Int = 256
    ) async throws -> RegionMask {
        try await MaskRefinementService(store: maskStore).refine(
            mask: mask, source: source, targetDimensions: targetDimensions, tileSize: tileSize
        )
    }
}
