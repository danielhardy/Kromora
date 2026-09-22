import CoreImage
import CoreGraphics
import Foundation

/// Actor-confined conversion of sendable mask payloads into Core Image. The resolver never sees
/// this type and no `CIContext` is created here; RenderEngineResources owns the instance and the
/// engine's one processing context evaluates the returned graphs.
final class LocalMaskRenderer {
    static let version = 8
    private let maxBrushStrokeCacheEntries = 8
    private let maxBrushStrokeCacheCostBytes: Int
    private struct BrushRasterRegion: Equatable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int

        var isEmpty: Bool { width <= 0 || height <= 0 }
    }

    private struct CachedBrushStroke {
        let region: BrushRasterRegion
        let values: [Float]
    }

    private struct BrushStrokeCacheEntry {
        let raster: CachedBrushStroke
        let cost: Int
        var older: String?
        var newer: String?
    }

    private var brushStrokeCache: [String: BrushStrokeCacheEntry] = [:]
    private var brushStrokeCacheOldest: String?
    private var brushStrokeCacheNewest: String?
    private var brushStrokeCacheCostBytes = 0

    init(maxBrushStrokeCacheCostBytes: Int = 64 * 1024 * 1024) {
        self.maxBrushStrokeCacheCostBytes = max(0, maxBrushStrokeCacheCostBytes)
    }

    /// Diagnostics exposed to the package tests so the byte bound is testable, not aspirational.
    var cachedBrushStrokeCount: Int { brushStrokeCache.count }
    var cachedBrushStrokeCostBytes: Int { brushStrokeCacheCostBytes }

    private let analyticKernel: CIKernel? = CIKernel(source: """
    kernel vec4 localAnalyticMask(
        sampler image, vec4 geometry, vec4 firstPoint, vec4 secondPoint,
        vec4 transform, vec4 radial, vec4 controls
    ) {
        vec2 coordinate = samplerCoord(image);
        vec2 normalized = (coordinate - geometry.xy) / max(geometry.zw, vec2(0.00001));
        normalized.y = 1.0 - normalized.y;

        // Transform around the source centre. Translation is normalized source-space movement.
        vec2 shifted = normalized - vec2(0.5);
        float cosine = cos(-transform.z);
        float sine = sin(-transform.z);
        shifted = vec2(shifted.x * cosine - shifted.y * sine,
                       shifted.x * sine + shifted.y * cosine);
        shifted /= max(transform.xy, vec2(0.00001));
        normalized = shifted + vec2(0.5) - transform.wz;

        float alpha;
        if (controls.x < 0.5) {
            vec2 direction = secondPoint.xy - firstPoint.xy;
            float denominator = max(dot(direction, direction), 0.0000001);
            float projection = dot(normalized - firstPoint.xy, direction) / denominator;
            // This is the GPU form of LinearGradientMaskMath.smoothstep(0, 1, projection).
            // The persisted endpoints encode the falloff width, so no resolution-dependent
            // feather/raster value is introduced here.
            alpha = smoothstep(0.0, 1.0, projection);
            alpha *= controls.y;
        } else {
            vec2 delta = normalized - firstPoint.xy;
            // Rotation is defined in source-pixel space. Scaling normalized x/y by the
            // requested extent before rotating keeps an ellipse aligned on non-square sources
            // at interactive, preview, and export resolutions.
            delta *= geometry.zw;
            float radialCosine = cos(radial.z);
            float radialSine = sin(radial.z);
            delta = vec2(delta.x * radialCosine + delta.y * radialSine,
                         -delta.x * radialSine + delta.y * radialCosine);
            float distance = length(delta / max(radial.xy, vec2(0.00001)));
            float inner = max(0.0, 1.0 - radial.w);
            if (distance <= inner) {
                alpha = 1.0;
            } else if (distance >= 1.0) {
                alpha = 0.0;
            } else {
                alpha = 1.0 - smoothstep(inner, 1.0, distance);
            }
            if (controls.z < 0.5) { alpha = 1.0 - alpha; }
            alpha *= controls.y;
        }
        return vec4(0.0, 0.0, 0.0, clamp(alpha, 0.0, 1.0));
    }
    """)

    private let invertKernel: CIKernel? = CIKernel(source: """
    kernel vec4 localInvertMask(sampler image) {
        vec4 pixel = sample(image, samplerCoord(image));
        return vec4(0.0, 0.0, 0.0, 1.0 - clamp(pixel.a, 0.0, 1.0));
    }
    """)

    private let combineKernel: CIKernel? = CIKernel(source: """
    kernel vec4 localCombineMask(sampler current, sampler next, vec4 controls) {
        float a = clamp(sample(current, samplerCoord(current)).a, 0.0, 1.0);
        float b = clamp(sample(next, samplerCoord(next)).a, 0.0, 1.0);
        float result;
        if (controls.x < 0.5) {
            result = b;                 // replace
        } else if (controls.x < 1.5) {
            result = max(a, b);         // add
        } else if (controls.x < 2.5) {
            result = a * (1.0 - b);     // subtract
        } else {
            result = min(a, b);         // intersect
        }
        return vec4(0.0, 0.0, 0.0, clamp(result, 0.0, 1.0));
    }
    """)

    func image(
        for payload: LocalMaskPayload,
        extent: CGRect,
        transform: LocalMaskRenderTransform
    ) -> CIImage? {
        let dimensions = PixelDimensions(width: Int(extent.width), height: Int(extent.height))
        guard extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return nil }

        switch payload.descriptor {
        case .raster(let mask):
            guard payload.targetSize == mask.size else { return nil }
            return rasterImage(mask, extent: extent)
        case .brush(let brush):
            guard payload.targetSize == dimensions else { return nil }
            return brushImage(brush, dimensions: dimensions, extent: extent, transform: transform)
        case .linear(let definition):
            guard payload.targetSize == dimensions else { return nil }
            let points = [transformPoint(definition.zeroStrengthPoint, transform),
                          transformPoint(definition.fullStrengthPoint, transform)]
            return analyticImage(
                extent: extent, firstPoint: points[0], secondPoint: points[1],
                transform: .identity, radial: CIVector(x: 0, y: 0, z: 0, w: 0),
                controls: CIVector(x: 0, y: definition.density, z: 1, w: 0)
            )
        case .radial(let definition):
            guard payload.targetSize == dimensions else { return nil }
            let center = transformPoint(definition.center, transform)
            let radii = CGSize(
                width: max(0.0001, definition.horizontalRadius * abs(transform.scaleX) * extent.width),
                height: max(0.0001, definition.verticalRadius * abs(transform.scaleY) * extent.height)
            )
            return analyticImage(
                extent: extent, firstPoint: center, secondPoint: .zero,
                transform: .identity,
                radial: CIVector(
                    x: radii.width, y: radii.height,
                    z: definition.rotation + transform.rotation, w: definition.feather),
                controls: CIVector(x: 1, y: definition.density, z: definition.isInside ? 1 : 0, w: 0)
            )
        }
    }

    func inverted(_ image: CIImage, extent: CGRect) -> CIImage {
        invertKernel?.apply(extent: extent, roiCallback: { _, rect in rect }, arguments: [image])?
            .cropped(to: extent) ?? image
    }

    func combined(_ current: CIImage, with next: CIImage, mode: MaskCombineMode, extent: CGRect) -> CIImage {
        let value: CGFloat
        switch mode {
        case .replace: value = 0
        case .add: value = 1
        case .subtract: value = 2
        case .intersect: value = 3
        }
        return combineKernel?.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [current, next, CIVector(x: value, y: 0, z: 0, w: 0)]
        )?.cropped(to: extent) ?? current
    }

    func emptyMask(extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
    }

    func removeAllCachedBrushStrokes() {
        brushStrokeCache.removeAll(keepingCapacity: true)
        brushStrokeCacheOldest = nil
        brushStrokeCacheNewest = nil
        brushStrokeCacheCostBytes = 0
    }

    private func analyticImage(
        extent: CGRect,
        firstPoint: CGPoint,
        secondPoint: CGPoint,
        transform: LocalMaskRenderTransform,
        radial: CIVector,
        controls: CIVector
    ) -> CIImage? {
        analyticKernel?.apply(
            extent: extent,
            roiCallback: { _, rect in rect },
            arguments: [
                CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent),
                CIVector(x: extent.minX, y: extent.minY, z: extent.width, w: extent.height),
                CIVector(x: firstPoint.x, y: firstPoint.y, z: 0, w: 0),
                CIVector(x: secondPoint.x, y: secondPoint.y, z: 0, w: 0),
                CIVector(x: transform.scaleX, y: transform.scaleY,
                         z: transform.rotation, w: transform.translationY),
                radial,
                controls,
            ]
        )?.cropped(to: extent)
    }

    private func rasterImage(
        _ mask: NormalizedMask,
        extent: CGRect,
        pixelOrigin: CGPoint = .zero,
        fullDimensions: PixelDimensions? = nil
    ) -> CIImage? {
        guard mask.size.width > 0, mask.size.height > 0,
              mask.size.width <= Int.max / 4,
              mask.values.count <= Int.max / 4 else { return nil }
        let width = mask.size.width
        let bytesPerRow = width * 4
        let byteCount = mask.values.count * 4

        // The mask is consumed only through the alpha channel by blendWithAlphaMask. Keeping
        // that channel in RGBA8 avoids the old 4x Float staging buffer (and its Data copy): a
        // 60MP mask now needs 60MB for bitmap data, or 120MB if Core Image makes its own copy.
        var data = Data(count: byteCount)
        data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
            for index in mask.values.indices {
                // Persisted mask rows and `CIImage(bitmapData:)` memory rows are both upper-left
                // oriented as consumed by `CIContext.createCGImage`: memory row 0 renders as the
                // top output row. No row flip belongs here.
                let value = min(max(mask.values[index], 0), 1)
                bytes[index * 4 + 3] = UInt8((value * 255).rounded())
            }
        }
        let image = CIImage(
            bitmapData: data, bytesPerRow: bytesPerRow,
            size: CGSize(width: width, height: mask.size.height), format: .RGBA8, colorSpace: nil
        )
        let sourceDimensions = fullDimensions ?? mask.size
        guard sourceDimensions.width > 0, sourceDimensions.height > 0 else { return nil }
        let scale = CGAffineTransform(
            scaleX: extent.width / CGFloat(sourceDimensions.width),
            y: extent.height / CGFloat(sourceDimensions.height)
        )
        // Preserve hard semantic definitions when a binary raster is enlarged. Smooth sampling
        // is correct for Vision's soft person boundaries, but it would introduce a visible
        // one-pixel transition into density-1/no-feather definitions.
        let sampled = mask.isBinary ? image.samplingNearest() : image.samplingLinear()
        return sampled
            .transformed(by: scale)
            .transformed(by: CGAffineTransform(
                translationX: extent.minX + pixelOrigin.x * scale.a,
                y: extent.minY + pixelOrigin.y * scale.d
            ))
            .cropped(to: extent)
    }

    private func brushImage(
        _ definition: BrushMaskDefinition,
        dimensions: PixelDimensions,
        extent: CGRect,
        transform: LocalMaskRenderTransform
    ) -> CIImage? {
        guard dimensions.width > 0, dimensions.height > 0 else { return nil }
        guard !Task.isCancelled else { return nil }
        let width = Double(dimensions.width)
        let height = Double(dimensions.height)
        let shorterSide = max(min(width, height), 1)
        var outputTiles: [BrushOutputTileKey: BrushOutputTile] = [:]
        for stroke in definition.strokes where !stroke.samples.isEmpty && stroke.radius > 0 {
            guard !Task.isCancelled else { return nil }
            let key = RenderCacheHash.digest(stroke)
                + ":\(dimensions.width)x\(dimensions.height):\(RenderCacheHash.digest(transform))"
            guard let strokeRaster = cachedStrokeRaster(
                for: stroke, key: key, dimensions: dimensions, width: width,
                height: height, shorterSide: shorterSide, transform: transform
            ) else { return nil }
            mergeBrushStroke(
                strokeRaster, density: stroke.density, into: &outputTiles,
                dimensions: dimensions
            )
        }
        guard !Task.isCancelled else { return nil }
        var resultImage: CIImage?
        for tile in outputTiles.values {
            guard let tileImage = rasterImage(
                values: tile.values, tileSize: PixelDimensions(
                    width: tile.region.width, height: tile.region.height),
                pixelOrigin: CGPoint(x: tile.region.x, y: tile.region.y),
                fullDimensions: dimensions, extent: extent
            ) else { return nil }
            resultImage = resultImage.map { tileImage.composited(over: $0) } ?? tileImage
        }
        guard let resultImage else { return emptyMask(extent: extent) }
        // A crop cannot enlarge an image extent. Put the touched tile over a transparent full
        // frame so downstream mask composition keeps the established full-frame coordinate
        // contract without allocating a full-frame CPU raster here.
        return resultImage.composited(over: emptyMask(extent: extent)).cropped(to: extent)
    }

    private static let brushOutputTileSize = 256

    private struct BrushOutputTileKey: Hashable {
        let x: Int
        let y: Int
    }

    private struct BrushOutputTile {
        let region: BrushRasterRegion
        var values: [Float]
    }

    private func mergeBrushStroke(
        _ strokeRaster: CachedBrushStroke, density: Double,
        into outputTiles: inout [BrushOutputTileKey: BrushOutputTile],
        dimensions: PixelDimensions
    ) {
        let region = strokeRaster.region
        let firstTileX = region.x / Self.brushOutputTileSize
        let lastTileX = (region.x + region.width - 1) / Self.brushOutputTileSize
        let firstTileY = region.y / Self.brushOutputTileSize
        let lastTileY = (region.y + region.height - 1) / Self.brushOutputTileSize
        let cap = min(max(density.isFinite ? density : 1, 0), 1)

        for tileY in firstTileY...lastTileY {
            for tileX in firstTileX...lastTileX {
                if Task.isCancelled { return }
                let originX = tileX * Self.brushOutputTileSize
                let originY = tileY * Self.brushOutputTileSize
                let tileRegion = BrushRasterRegion(
                    x: originX, y: originY,
                    width: min(Self.brushOutputTileSize, dimensions.width - originX),
                    height: min(Self.brushOutputTileSize, dimensions.height - originY)
                )
                let key = BrushOutputTileKey(x: tileX, y: tileY)
                if outputTiles[key] == nil {
                    outputTiles[key] = BrushOutputTile(
                        region: tileRegion,
                        values: [Float](repeating: 0, count: tileRegion.width * tileRegion.height)
                    )
                }
                guard var tile = outputTiles[key] else { continue }
                let overlap = BrushRasterRegion(
                    x: max(region.x, tile.region.x), y: max(region.y, tile.region.y),
                    width: min(region.x + region.width, tile.region.x + tile.region.width)
                        - max(region.x, tile.region.x),
                    height: min(region.y + region.height, tile.region.y + tile.region.height)
                        - max(region.y, tile.region.y)
                )
                guard !overlap.isEmpty else { continue }
                for y in 0..<overlap.height {
                    if Task.isCancelled { return }
                    for x in 0..<overlap.width {
                        let globalX = overlap.x + x
                        let globalY = overlap.y + y
                        let sourceIndex = (globalY - region.y) * region.width
                            + (globalX - region.x)
                        let tileIndex = (globalY - tile.region.y) * tile.region.width
                            + (globalX - tile.region.x)
                        tile.values[tileIndex] = Float(BrushMaskMath.accumulatedOpacity(
                            current: Double(tile.values[tileIndex]),
                            stamp: Double(strokeRaster.values[sourceIndex]), density: cap
                        ))
                    }
                }
                outputTiles[key] = tile
            }
        }
    }

    private func cachedStrokeRaster(
        for stroke: BrushStroke, key: String, dimensions: PixelDimensions,
        width: Double, height: Double, shorterSide: Double,
        transform: LocalMaskRenderTransform
    ) -> CachedBrushStroke? {
        if let cached = brushStrokeCache[key] {
            touchBrushStrokeCache(key)
            return cached.raster
        }
        let sourceSize = CGSize(width: width, height: height)
        let resampled = BrushMaskMath.resampledAndSimplified(
            stroke.samples, sourceSize: sourceSize, radius: stroke.radius)
        guard !Task.isCancelled, !resampled.isEmpty else { return nil }
        let transformed = resampled.map { sample in
            BrushSample(point: transformPoint(sample.point, transform), pressure: sample.pressure)
        }
        let region = brushRasterRegion(
            for: transformed, stroke: stroke, dimensions: dimensions,
            width: width, height: height, shorterSide: shorterSide
        )
        guard !region.isEmpty else { return nil }
        let resultCount = region.width.multipliedReportingOverflow(by: region.height)
        guard !resultCount.overflow else {
            return nil
        }
        var result = [Float](repeating: 0, count: resultCount.partialValue)
        for y in 0..<region.height {
            guard !Task.isCancelled else { return nil }
            for x in 0..<region.width {
                let point = CGPoint(
                    x: (Double(region.x + x) + 0.5) / width,
                    y: (Double(region.y + y) + 0.5) / height
                )
                let index = y * region.width + x
                var opacity = 0.0
                for (sampleIndex, sample) in transformed.enumerated() {
                    if sampleIndex % 64 == 0 && Task.isCancelled { return nil }
                    let distance = hypot(
                        (point.x - sample.point.x) * width,
                        (point.y - sample.point.y) * height
                    ) / shorterSide
                    let deposited = BrushMaskMath.stampAlpha(
                        distance: distance, radius: stroke.radius, feather: stroke.feather,
                        flow: stroke.flow, pressure: sample.pressure
                    )
                    opacity = BrushMaskMath.accumulatedOpacity(
                        current: opacity, stamp: deposited, density: stroke.density
                    )
                    if opacity >= stroke.density { break }
                }
                result[index] = Float(opacity)
            }
        }
        let cost = result.count.multipliedReportingOverflow(by: MemoryLayout<Float>.size)
        let raster = CachedBrushStroke(region: region, values: result)
        guard !cost.overflow, maxBrushStrokeCacheCostBytes > 0,
              cost.partialValue <= maxBrushStrokeCacheCostBytes else {
            return raster
        }
        insertBrushStroke(raster, for: key, cost: cost.partialValue)
        return raster
    }

    private func brushRasterRegion(
        for samples: [BrushSample], stroke: BrushStroke, dimensions: PixelDimensions,
        width: Double, height: Double, shorterSide: Double
    ) -> BrushRasterRegion {
        guard let first = samples.first else {
            return BrushRasterRegion(x: 0, y: 0, width: 0, height: 0)
        }
        var minX = first.point.x
        var maxX = first.point.x
        var minY = first.point.y
        var maxY = first.point.y
        for sample in samples.dropFirst() {
            minX = min(minX, sample.point.x)
            maxX = max(maxX, sample.point.x)
            minY = min(minY, sample.point.y)
            maxY = max(maxY, sample.point.y)
        }
        let radius = stroke.radius * shorterSide
        let normalizedRadiusX = radius / width
        let normalizedRadiusY = radius / height
        let lowerX = minX - normalizedRadiusX
        let upperX = maxX + normalizedRadiusX
        let lowerY = minY - normalizedRadiusY
        let upperY = maxY + normalizedRadiusY

        // Include a one-pixel halo around the mathematical dab bounds. This keeps pixel-center
        // rounding and Core Image's later sampling from clipping a feather at a tile edge.
        let xRange = pixelRange(lower: lowerX, upper: upperX, count: dimensions.width)
        let yRange = pixelRange(lower: lowerY, upper: upperY, count: dimensions.height)
        guard let xRange, let yRange else {
            return BrushRasterRegion(x: 0, y: 0, width: 0, height: 0)
        }
        return BrushRasterRegion(
            x: xRange.lowerBound, y: yRange.lowerBound,
            width: xRange.count, height: yRange.count
        )
    }

    private func pixelRange(lower: Double, upper: Double, count: Int) -> ClosedRange<Int>? {
        guard count > 0, lower < Double(count), upper >= 0 else { return nil }
        let lowerPixel = lower * Double(count) - 0.5
        let upperPixel = upper * Double(count) - 0.5
        let lowerIndex = lowerPixel.isFinite
            ? max(0, Int(floor(lowerPixel)) - 1)
            : 0
        let upperIndex = upperPixel.isFinite
            ? min(count - 1, Int(ceil(upperPixel)) + 1)
            : count - 1
        guard upperIndex >= lowerIndex else { return nil }
        return lowerIndex...upperIndex
    }

    private func rasterImage(
        values: [Float], tileSize: PixelDimensions, pixelOrigin: CGPoint,
        fullDimensions: PixelDimensions, extent: CGRect
    ) -> CIImage? {
        guard let mask = try? NormalizedMask(size: tileSize, values: values) else { return nil }
        return rasterImage(
            mask, extent: extent, pixelOrigin: pixelOrigin, fullDimensions: fullDimensions
        )
    }

    private func touchBrushStrokeCache(_ key: String) {
        guard let entry = brushStrokeCache[key], brushStrokeCacheNewest != key else { return }
        unlinkBrushStrokeCache(key, entry: entry)
        appendBrushStrokeCache(key, entry: entry)
    }

    private func insertBrushStroke(_ raster: CachedBrushStroke, for key: String, cost: Int) {
        if let existing = brushStrokeCache[key] {
            removeBrushStrokeCache(key, entry: existing)
        }
        while brushStrokeCache.count >= maxBrushStrokeCacheEntries
                || brushStrokeCacheCostBytes > maxBrushStrokeCacheCostBytes - cost {
            guard let oldest = brushStrokeCacheOldest,
                  let entry = brushStrokeCache[oldest] else { break }
            removeBrushStrokeCache(oldest, entry: entry)
        }
        let entry = BrushStrokeCacheEntry(
            raster: raster, cost: cost, older: brushStrokeCacheNewest, newer: nil
        )
        brushStrokeCache[key] = entry
        if let newest = brushStrokeCacheNewest {
            brushStrokeCache[newest]?.newer = key
        } else {
            brushStrokeCacheOldest = key
        }
        brushStrokeCacheNewest = key
        brushStrokeCacheCostBytes += cost
    }

    private func removeBrushStrokeCache(_ key: String, entry: BrushStrokeCacheEntry) {
        unlinkBrushStrokeCache(key, entry: entry)
        brushStrokeCache.removeValue(forKey: key)
        brushStrokeCacheCostBytes -= entry.cost
    }

    private func unlinkBrushStrokeCache(_ key: String, entry: BrushStrokeCacheEntry) {
        if let older = entry.older {
            brushStrokeCache[older]?.newer = entry.newer
        } else {
            brushStrokeCacheOldest = entry.newer
        }
        if let newer = entry.newer {
            brushStrokeCache[newer]?.older = entry.older
        } else {
            brushStrokeCacheNewest = entry.older
        }
    }

    private func appendBrushStrokeCache(_ key: String, entry: BrushStrokeCacheEntry) {
        var updated = entry
        updated.older = brushStrokeCacheNewest
        updated.newer = nil
        brushStrokeCache[key] = updated
        if let newest = brushStrokeCacheNewest {
            brushStrokeCache[newest]?.newer = key
        } else {
            brushStrokeCacheOldest = key
        }
        brushStrokeCacheNewest = key
    }

    private func transformPoint(_ point: CGPoint, _ transform: LocalMaskRenderTransform) -> CGPoint {
        let shifted = CGPoint(x: (point.x - 0.5) * transform.scaleX,
                              y: (point.y - 0.5) * transform.scaleY)
        let cosine = cos(transform.rotation)
        let sine = sin(transform.rotation)
        return CGPoint(
            x: shifted.x * cosine - shifted.y * sine + 0.5 + transform.translationX,
            y: shifted.x * sine + shifted.y * cosine + 0.5 + transform.translationY
        )
    }

}
