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
