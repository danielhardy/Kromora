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

    /// A separable box blur over the clipped (2r+1)² window, averaged by the in-bounds sample count.
    /// Each pass uses a running sum, so cost is O(pixels) regardless of radius; a naive window scan
    /// is O(pixels × r²) and stalls the render at the radii "Soften edges" produces on a
    /// full-resolution mask. Cancellable between rows so a dragged slider can abandon stale work.
    static func feather(_ mask: NormalizedMask, radius: Int) throws -> NormalizedMask {
        guard radius > 0 else { return mask }
        let width = mask.size.width
        let height = mask.size.height
        guard width > 0, height > 0 else { return mask }

        // Horizontal pass: windowed sums per row.
        var horizontal = [Double](repeating: 0, count: mask.values.count)
        for y in 0..<height {
            if y & 63 == 0 { try Task.checkCancellation() }
            let row = y * width
            var sum = 0.0
            for x in 0...min(width - 1, radius) { sum += Double(mask.values[row + x]) }
            horizontal[row] = sum
            for x in 1..<max(width, 1) {
                let entering = x + radius
                if entering < width { sum += Double(mask.values[row + entering]) }
                let leaving = x - radius - 1
                if leaving >= 0 { sum -= Double(mask.values[row + leaving]) }
                horizontal[row + x] = sum
            }
        }

        // Vertical pass over the row sums, then divide by the clipped window area.
        var blurred = [Float](repeating: 0, count: mask.values.count)
        var columnSums = [Double](repeating: 0, count: width)
        for y in 0...min(height - 1, radius) {
            for x in 0..<width { columnSums[x] += horizontal[y * width + x] }
        }
        var outputTotal: Float = 0
        var outputIsBinary = true
        for y in 0..<height {
            if y & 63 == 0 { try Task.checkCancellation() }
            if y > 0 {
                let entering = y + radius
                if entering < height {
                    for x in 0..<width { columnSums[x] += horizontal[entering * width + x] }
                }
                let leaving = y - radius - 1
                if leaving >= 0 {
                    for x in 0..<width { columnSums[x] -= horizontal[leaving * width + x] }
                }
            }
            let rows = Double(min(height - 1, y + radius) - max(0, y - radius) + 1)
            for x in 0..<width {
                let columns = Double(min(width - 1, x + radius) - max(0, x - radius) + 1)
                let value = min(max(Float(columnSums[x] / (rows * columns)), 0), 1)
                blurred[y * width + x] = value
                outputTotal += value
                if value != 0, value != 1 { outputIsBinary = false }
            }
        }
        return NormalizedMask(
            trustingSize: mask.size, values: blurred,
            coverage: blurred.isEmpty ? 0 : outputTotal / Float(blurred.count),
            isBinary: outputIsBinary
        )
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

        let result = try scaleValuesAndCoverage(mask, to: size)
        return NormalizedMask(
            trustingSize: size,
            values: result.values,
            coverage: result.coverage,
            isBinary: result.isBinary
        )
    }

    /// Shared PlanarF bridge for every semantic-mask upscale. vImage's default resampling kernel
    /// is a SIMD/multithreaded, bilinear-equivalent filter for these soft semantic boundaries. It
    /// is not bit-for-bit bilinear: its small high-quality edge response is intentionally bounded
    /// by NormalizedMask's existing [0, 1] normalization. `kvImageEdgeExtend` preserves the old
    /// clamp-to-edge behavior, including the one-pixel source/target dimensions guarded above.
    static func scaleValues(_ mask: NormalizedMask, to size: PixelDimensions) throws -> [Float] {
        try scaleValuesAndCoverage(mask, to: size).values
    }

    private static func scaleValuesAndCoverage(
        _ mask: NormalizedMask, to size: PixelDimensions
    ) throws -> (values: [Float], coverage: Float, isBinary: Bool) {
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

        // vImage's resampling kernel can ring slightly at a hard mask edge. Clip and accumulate
        // in one pass before handing the result to NormalizedMask's trusted initializer; this
        // preserves its public [0, 1] invariant and avoids a second post-generation walk.
        var total: Float = 0
        var isBinary = true
        values.withUnsafeMutableBufferPointer { buffer in
            for index in buffer.indices {
                let value = min(max(buffer[index], 0), 1)
                buffer[index] = value
                total += value
                if value != 0, value != 1 { isBinary = false }
            }
        }
        return (values, values.isEmpty ? 0 : total / Float(values.count), isBinary)
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
