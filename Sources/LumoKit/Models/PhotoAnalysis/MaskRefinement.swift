import Foundation

enum MaskRefinementError: Error, Sendable, Equatable {
    case missingSeedPixels
    case invalidTargetDimensions
    case invalidTileSize
}

/// Upgrades a cached semantic mask without rerunning its detector.
///
/// The source image is represented by its existing ImageSource descriptor at this boundary. The
/// seed mask's semantic boundary is sampled into render-resolution tiles; the full result is only
/// assembled after each tile has passed cancellation. The tile buffer is bounded by
/// `tileSize * targetWidth`, while the final NormalizedMask is the unavoidable persisted output.
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

        var values: [Float] = []
        values.reserveCapacity(dimensions.width * dimensions.height)
        let width = dimensions.width
        let height = dimensions.height
        let rowsPerTile = min(tileSize, height)
        var y = 0
        while y < height {
            try Task.checkCancellation()
            let endY = min(height, y + rowsPerTile)
            var tile: [Float] = []
            tile.reserveCapacity((endY - y) * width)
            for outputY in y..<endY {
                try Task.checkCancellation()
                let sourceY = Float(outputY) / Float(max(1, height - 1))
                    * Float(max(1, seed.size.height - 1))
                for outputX in 0..<width {
                    let sourceX = Float(outputX) / Float(max(1, width - 1))
                        * Float(max(1, seed.size.width - 1))
                    tile.append(Self.bilinear(seed, x: sourceX, y: sourceY))
                }
            }
            values.append(contentsOf: tile)
            y = endY
            // Give cancellation a scheduling point between large tiles without creating a second
            // task or moving storage ownership outside this actor.
            await Task.yield()
        }

        try Task.checkCancellation()
        let refined = try NormalizedMask(size: dimensions, values: values)
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

    private static func bilinear(_ mask: NormalizedMask, x: Float, y: Float) -> Float {
        let maxX = mask.size.width - 1
        let maxY = mask.size.height - 1
        let clampedX = min(max(0, x), Float(maxX))
        let clampedY = min(max(0, y), Float(maxY))
        let x0 = Int(clampedX.rounded(.down))
        let y0 = Int(clampedY.rounded(.down))
        let x1 = min(maxX, x0 + 1)
        let y1 = min(maxY, y0 + 1)
        let fx = clampedX - Float(x0)
        let fy = clampedY - Float(y0)

        func value(_ px: Int, _ py: Int) -> Float {
            mask.values[py * mask.size.width + px]
        }
        let top = value(x0, y0) * (1 - fx) + value(x1, y0) * fx
        let bottom = value(x0, y1) * (1 - fx) + value(x1, y1) * fx
        return top * (1 - fy) + bottom * fy
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
