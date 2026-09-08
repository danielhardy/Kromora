import Accelerate
import Foundation

enum MaskResamplingError: Error, Sendable, Equatable {
    case vImageScaleFailed(Int32)
}

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

    /// Resize a mask. Providers report masks at their own output resolution (Vision returns fixed
    /// square buffers regardless of source aspect), so every consumer that combines masks from
    /// different origins needs this bridge.
    static func resized(_ mask: NormalizedMask, to size: PixelDimensions) throws -> NormalizedMask {
        guard size.width > 0, size.height > 0 else {
            throw RegionMaskError.incompatibleSizes
        }
        guard mask.size != size else { return mask }

        return NormalizedMask(resampledSize: size, values: try scaleValues(mask, to: size))
    }

    /// Shared PlanarF bridge for every semantic-mask upscale. vImage's default resampling kernel
    /// is a SIMD/multithreaded, bilinear-equivalent filter for these soft semantic boundaries. It
    /// is not bit-for-bit bilinear: its small high-quality edge response is intentionally bounded
    /// by NormalizedMask's existing [0, 1] normalization. `kvImageEdgeExtend` preserves the old
    /// clamp-to-edge behavior, including the one-pixel source/target dimensions guarded above.
    static func scaleValues(_ mask: NormalizedMask, to size: PixelDimensions) throws -> [Float] {
        guard mask.size.width > 0, mask.size.height > 0,
              size.width > 0, size.height > 0 else {
            throw RegionMaskError.incompatibleSizes
        }

        var values = [Float](repeating: 0, count: size.width * size.height)
        let error = mask.values.withUnsafeBufferPointer { source in
            values.withUnsafeMutableBufferPointer { destination in
                var sourceBuffer = vImage_Buffer(
                    data: UnsafeMutableRawPointer(mutating: source.baseAddress!),
                    height: vImagePixelCount(mask.size.height),
                    width: vImagePixelCount(mask.size.width),
                    rowBytes: mask.size.width * MemoryLayout<Float>.stride
                )
                var destinationBuffer = vImage_Buffer(
                    data: destination.baseAddress!,
                    height: vImagePixelCount(size.height),
                    width: vImagePixelCount(size.width),
                    rowBytes: size.width * MemoryLayout<Float>.stride
                )
                return vImageScale_PlanarF(
                    &sourceBuffer,
                    &destinationBuffer,
                    nil,
                    vImage_Flags(kvImageEdgeExtend)
                )
            }
        }
        guard error == kvImageNoError else {
            throw MaskResamplingError.vImageScaleFailed(Int32(error))
        }

        // vImage's resampling kernel can ring slightly at a hard mask edge. Clip in Accelerate
        // before handing the result to NormalizedMask's trusted resampled-value initializer; this
        // preserves its public [0, 1] invariant without another scalar validation/copy pass.
        values.withUnsafeMutableBufferPointer { buffer in
            var lowerBound: Float = 0
            var upperBound: Float = 1
            vDSP_vclip(
                buffer.baseAddress!, 1,
                &lowerBound, &upperBound,
                buffer.baseAddress!, 1,
                vDSP_Length(buffer.count)
            )
        }
        return values
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
