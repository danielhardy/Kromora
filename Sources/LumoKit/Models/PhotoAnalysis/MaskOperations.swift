import Foundation

enum MaskOperations {
    static func invert(_ mask: NormalizedMask) throws -> NormalizedMask {
        try NormalizedMask(size: mask.size, values: mask.values.map { 1 - $0 })
    }

    static func intersect(_ lhs: NormalizedMask, _ rhs: NormalizedMask) throws -> NormalizedMask {
        try combine(lhs, rhs) { min($0, $1) }
    }

    static func union(_ lhs: NormalizedMask, _ rhs: NormalizedMask) throws -> NormalizedMask {
        try combine(lhs, rhs) { max($0, $1) }
    }

    static func subtract(_ subtrahend: NormalizedMask, from minuend: NormalizedMask) throws -> NormalizedMask {
        try combine(minuend, subtrahend) { max(0, $0 - $1) }
    }

    /// A small separable box blur is deterministic and keeps this foundation free of a second image
    /// representation. The later render-quality implementation can replace this hook with a GPU
    /// blur without changing callers or the MaskStore seam.
    static func feather(_ mask: NormalizedMask, radius: Int) throws -> NormalizedMask {
        guard radius > 0 else { return mask }
        let width = mask.size.width
        let height = mask.size.height
        var blurred = Array(repeating: Float.zero, count: mask.values.count)
        for y in 0..<height {
            for x in 0..<width {
                var total: Float = 0
                var count: Float = 0
                for sampleY in max(0, y - radius)...min(height - 1, y + radius) {
                    for sampleX in max(0, x - radius)...min(width - 1, x + radius) {
                        total += mask.values[sampleY * width + sampleX]
                        count += 1
                    }
                }
                blurred[y * width + x] = total / count
            }
        }
        return try NormalizedMask(size: mask.size, values: blurred)
    }

    static func refine(_ mask: NormalizedMask) throws -> NormalizedMask {
        try feather(mask, radius: 1)
    }

    /// Bilinear resize. Providers report masks at their own output resolution (Vision returns
    /// fixed square buffers regardless of source aspect), so every consumer that combines masks
    /// from different origins needs this bridge.
    static func resized(_ mask: NormalizedMask, to size: PixelDimensions) throws -> NormalizedMask {
        guard size.width > 0, size.height > 0 else {
            throw RegionMaskError.incompatibleSizes
        }
        guard mask.size != size else { return mask }
        var values: [Float] = []
        values.reserveCapacity(size.width * size.height)
        for y in 0..<size.height {
            let sourceY = Double(y) / Double(max(1, size.height - 1)) * Double(max(1, mask.size.height - 1))
            for x in 0..<size.width {
                let sourceX = Double(x) / Double(max(1, size.width - 1)) * Double(max(1, mask.size.width - 1))
                values.append(bilinear(mask, x: sourceX, y: sourceY))
            }
        }
        return try NormalizedMask(size: size, values: values)
    }

    private static func bilinear(_ mask: NormalizedMask, x: Double, y: Double) -> Float {
        let clampedX = min(max(0, x), Double(mask.size.width - 1))
        let clampedY = min(max(0, y), Double(mask.size.height - 1))
        let x0 = Int(clampedX.rounded(.down)), y0 = Int(clampedY.rounded(.down))
        let x1 = min(mask.size.width - 1, x0 + 1), y1 = min(mask.size.height - 1, y0 + 1)
        let fx = Float(clampedX - Double(x0)), fy = Float(clampedY - Double(y0))
        func value(_ x: Int, _ y: Int) -> Float { mask.values[y * mask.size.width + x] }
        let top = value(x0, y0) * (1 - fx) + value(x1, y0) * fx
        let bottom = value(x0, y1) * (1 - fx) + value(x1, y1) * fx
        return top * (1 - fy) + bottom * fy
    }

    /// Region operations always persist their result through the same store as provider output.
    static func invert(_ region: RegionMask, using store: MaskStore) async throws -> RegionMask {
        guard let pixels = await store.pixels(for: region.reference) else {
            throw RegionMaskError.missingPixels
        }
        return try await persist(invert(pixels), basedOn: region, kind: .unknown("invert"), using: store)
    }

    static func intersect(_ lhs: RegionMask, _ rhs: RegionMask, using store: MaskStore) async throws -> RegionMask {
        guard let left = await store.pixels(for: lhs.reference), let right = await store.pixels(for: rhs.reference) else {
            throw RegionMaskError.missingPixels
        }
        return try await persist(intersect(left, right), basedOn: lhs, kind: .unknown("intersect"), using: store)
    }

    static func union(_ lhs: RegionMask, _ rhs: RegionMask, using store: MaskStore) async throws -> RegionMask {
        guard let left = await store.pixels(for: lhs.reference), let right = await store.pixels(for: rhs.reference) else {
            throw RegionMaskError.missingPixels
        }
        return try await persist(union(left, right), basedOn: lhs, kind: .unknown("union"), using: store)
    }

    private static func combine(
        _ lhs: NormalizedMask,
        _ rhs: NormalizedMask,
        operation: (Float, Float) -> Float
    ) throws -> NormalizedMask {
        guard lhs.size == rhs.size else { throw RegionMaskError.incompatibleSizes }
        return try NormalizedMask(size: lhs.size, values: zip(lhs.values, rhs.values).map(operation))
    }

    private static func persist(
        _ pixels: NormalizedMask,
        basedOn region: RegionMask,
        kind: SemanticMaskKind,
        using store: MaskStore
    ) async throws -> RegionMask {
        let quality = region.quality
        let key = region.reference.cacheKey.with(kind: kind, quality: quality)
        let reference = try await store.store(pixels, for: key, quality: quality)
        return RegionMask(kind: kind, bounds: region.bounds, quality: quality, reference: reference,
                          confidence: region.confidence, coverage: pixels.coverage)
    }
}
