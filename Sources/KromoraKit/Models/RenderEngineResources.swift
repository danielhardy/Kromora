import CoreImage
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// A finished canonical preview as plain values: the encoded JPEG, its pixel size and color space,
/// and its perceptual digest. Produced beside the engine's `CIContext` so nothing Core Image
/// reaches the frame store.
struct CanonicalPreviewRaster: Sendable {
    let jpegData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let rasterColorSpace: RasterColorSpace
    let perceptualDigest: PerceptualDigest
}

/// Actor-confined GPU and cache resources used by `RenderEngine`.
///
/// This is intentionally a small storage object rather than another renderer. It centralizes
/// construction and lifetime of the mutable Core Image/Metal resources while `RenderPipeline`
/// remains the pure stage builder and `RenderEngine` remains the request façade. The class is never
/// sent out of the engine actor; its non-Sendable members therefore stay behind the same isolation
/// boundary as before.
final class RenderEngineResources {
    let configuration: RenderCacheConfiguration
    let context: CIContext
    let device: MTLDevice?
    let commandQueue: MTLCommandQueue?
    let lutCache = LUTFilterCache()
    let toneCurveCache = ToneCurveFilterCache()
    var toneCurveSource: RenderSourceFingerprint?
    var toneCurveSpace: WorkingSpace?
    let previewCache: BoundedLRUCache<PreviewCacheKey, RenderResult>
    let developedSourceCache: BoundedLRUCache<DevelopedSourceCacheKey, CIImage>
    let thumbnailDevelopedSourceCache: BoundedLRUCache<DevelopedSourceCacheKey, CIImage>
    let processingPrefixCache: BoundedLRUCache<ProcessingPrefixCacheKey, CIImage>
    let localMaskCache: BoundedLRUCache<LocalMaskCacheKey, LocalMaskPayload>
    let localMaskRenderer: LocalMaskRenderer

    /// Create a context for an isolated, value-only sampler. Keeping this factory beside the
    /// engine-owned context makes every Core Image context construction auditable in one place;
    /// these contexts are intentionally not retained by the live render engine.
    static func makeOneShotContext(
        workingColorSpace: CGColorSpace? = nil,
        cacheIntermediates: Bool = true,
        preferMetal: Bool = false
    ) -> CIContext {
        var options: [CIContextOption: Any] = [
            .cacheIntermediates: cacheIntermediates
        ]
        if let workingColorSpace {
            options[.workingColorSpace] = workingColorSpace
        }
        if preferMetal, let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: options)
        }
        return CIContext(options: options)
    }

    /// Rasterize a completed image at the durable preview size. The production overload uses the
    /// engine's retained context; the static overload exists only for legacy/test samplers.
    func canonicalPreviewRaster(
        from image: CIImage,
        space: WorkingSpace,
        longEdge: Int
    ) -> CGImage? {
        Self.canonicalPreviewRaster(
            from: image, space: space, longEdge: longEdge, context: context
        )
    }

    static func canonicalPreviewRaster(
        from image: CIImage,
        space: WorkingSpace,
        longEdge: Int,
        context: CIContext
    ) -> CGImage? {
        let extent = image.extent.integral
        guard longEdge > 0, extent.width > 0, extent.height > 0,
              extent.width.isFinite, extent.height.isFinite else { return nil }

        let scale = CGFloat(longEdge) / max(extent.width, extent.height)
        let width = max(1, Int((extent.width * scale).rounded()))
        let height = max(1, Int((extent.height * scale).rounded()))
        let scaled = image.transformed(by: CGAffineTransform(
            translationX: -extent.minX, y: -extent.minY
        )).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        return context.createCGImage(
            scaled, from: target, format: .RGBA8, colorSpace: space.cgColorSpace
        )
    }

    static func canonicalPreviewRaster(
        from image: CIImage,
        space: WorkingSpace,
        longEdge: Int
    ) -> CGImage? {
        let context = makeOneShotContext(workingColorSpace: space.cgColorSpace)
        return canonicalPreviewRaster(
            from: image, space: space, longEdge: longEdge, context: context
        )
    }

    /// Rasterize, encode, and fingerprint a completed preview in one pass. Everything a
    /// `LatestPreviewFrameStore` needs crosses the boundary as values; no Core Image object does.
    func canonicalPreviewFrame(
        from image: CIImage, space: WorkingSpace, longEdge: Int
    ) -> CanonicalPreviewRaster? {
        Self.canonicalPreviewFrame(
            from: image, space: space, longEdge: longEdge, context: context
        )
    }

    static func canonicalPreviewFrame(
        from image: CIImage, space: WorkingSpace, longEdge: Int
    ) -> CanonicalPreviewRaster? {
        canonicalPreviewFrame(
            from: image, space: space, longEdge: longEdge,
            context: makeOneShotContext(workingColorSpace: space.cgColorSpace)
        )
    }

    static func canonicalPreviewFrame(
        from image: CIImage, space: WorkingSpace, longEdge: Int, context: CIContext
    ) -> CanonicalPreviewRaster? {
        guard let raster = canonicalPreviewRaster(
                  from: image, space: space, longEdge: longEdge, context: context
              ),
              let digest = perceptualDigest(of: image, space: space, context: context),
              let jpeg = jpegData(for: raster, quality: canonicalJPEGQuality)
        else { return nil }
        return CanonicalPreviewRaster(
            jpegData: jpeg, pixelWidth: raster.width, pixelHeight: raster.height,
            rasterColorSpace: RasterColorSpace(space), perceptualDigest: digest
        )
    }

    static let canonicalJPEGQuality = 0.9

    static func jpegData(for image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The fingerprint of `image` as it would be displayed in `space`: one 64×64 render, then an
    /// 8×8 grid of block means. Deterministic for equal inputs, bounded, and independent of the
    /// image's size, so a 2048 px frame and a viewport-sized refinement of it are comparable.
    func perceptualDigest(of image: CIImage, space: WorkingSpace) -> PerceptualDigest? {
        Self.perceptualDigest(of: image, space: space, context: context)
    }

    static func perceptualDigest(
        of image: CIImage, space: WorkingSpace, context: CIContext
    ) -> PerceptualDigest? {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0,
              extent.width.isFinite, extent.height.isFinite else { return nil }
        let side = PerceptualDigest.gridSide
        let block = 8
        let pixels = side * block
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: CGFloat(pixels) / extent.height,
                kCIInputAspectRatioKey: (CGFloat(pixels) / extent.width)
                    / (CGFloat(pixels) / extent.height),
            ])
        let rowBytes = pixels * 4
        var buffer = [UInt8](repeating: 0, count: rowBytes * pixels)
        context.render(
            scaled, toBitmap: &buffer, rowBytes: rowBytes,
            bounds: CGRect(x: 0, y: 0, width: pixels, height: pixels),
            format: .RGBA8, colorSpace: space.cgColorSpace
        )
        var cells = Data(count: PerceptualDigest.byteCount)
        let area = block * block
        for cellY in 0..<side {
            for cellX in 0..<side {
                var sums = (r: 0, g: 0, b: 0)
                for y in 0..<block {
                    let rowStart = (cellY * block + y) * rowBytes + cellX * block * 4
                    for x in 0..<block {
                        let offset = rowStart + x * 4
                        sums.r += Int(buffer[offset])
                        sums.g += Int(buffer[offset + 1])
                        sums.b += Int(buffer[offset + 2])
                    }
                }
                let out = (cellY * side + cellX) * 3
                cells[out] = UInt8((sums.r + area / 2) / area)
                cells[out + 1] = UInt8((sums.g + area / 2) / area)
                cells[out + 2] = UInt8((sums.b + area / 2) / area)
            }
        }
        return PerceptualDigest(bytes: cells)
    }

    init(configuration: RenderCacheConfiguration) {
        self.configuration = configuration
        if let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() {
            self.device = device
            self.commandQueue = queue
            self.context = CIContext(mtlCommandQueue: queue)
        } else {
            self.device = nil
            self.commandQueue = nil
            self.context = CIContext()
        }
        self.previewCache = BoundedLRUCache(
            maxEntries: configuration.previewMaxEntries,
            maxCostBytes: configuration.previewMaxCostBytes
        )
        self.developedSourceCache = BoundedLRUCache(
            maxEntries: configuration.developedSourceMaxEntries,
            maxCostBytes: configuration.developedSourceMaxCostBytes
        )
        self.thumbnailDevelopedSourceCache = BoundedLRUCache(
            maxEntries: configuration.thumbnailDevelopedSourceMaxEntries,
            maxCostBytes: configuration.thumbnailDevelopedSourceMaxCostBytes
        )
        self.processingPrefixCache = BoundedLRUCache(
            maxEntries: configuration.processingPrefixMaxEntries,
            maxCostBytes: configuration.processingPrefixMaxCostBytes
        )
        self.localMaskCache = BoundedLRUCache(
            maxEntries: configuration.localMaskMaxEntries,
            maxCostBytes: configuration.localMaskMaxCostBytes
        )
        self.localMaskRenderer = LocalMaskRenderer(
            maxBrushStrokeCacheCostBytes: configuration.localMaskMaxCostBytes)
    }

    init(context: CIContext, configuration: RenderCacheConfiguration) {
        self.configuration = configuration
        self.context = context
        // An injected context may target a device unknown to the caller. Keep the deterministic
        // graph seam and do not guess a mismatched queue/device pair.
        self.device = nil
        self.commandQueue = nil
        self.previewCache = BoundedLRUCache(
            maxEntries: configuration.previewMaxEntries,
            maxCostBytes: configuration.previewMaxCostBytes
        )
        self.developedSourceCache = BoundedLRUCache(
            maxEntries: configuration.developedSourceMaxEntries,
            maxCostBytes: configuration.developedSourceMaxCostBytes
        )
        self.thumbnailDevelopedSourceCache = BoundedLRUCache(
            maxEntries: configuration.thumbnailDevelopedSourceMaxEntries,
            maxCostBytes: configuration.thumbnailDevelopedSourceMaxCostBytes
        )
        self.processingPrefixCache = BoundedLRUCache(
            maxEntries: configuration.processingPrefixMaxEntries,
            maxCostBytes: configuration.processingPrefixMaxCostBytes
        )
        self.localMaskCache = BoundedLRUCache(
            maxEntries: configuration.localMaskMaxEntries,
            maxCostBytes: configuration.localMaskMaxCostBytes
        )
        self.localMaskRenderer = LocalMaskRenderer(
            maxBrushStrokeCacheCostBytes: configuration.localMaskMaxCostBytes)
    }

    func invalidateLUTDependentCaches() {
        lutCache.removeAll()
        previewCache.removeAll()
    }

    /// Release cube filters built for `ids`. Engine preview entries are keyed by Look content, so an
    /// old render of a replaced Look is already unreachable and simply ages out; nothing else here
    /// depends on a `LUTID` alone.
    func invalidateLUTDependentCaches(for ids: Set<LUTID>) {
        lutCache.remove(lutIDs: ids)
    }

    func evictAll() {
        previewCache.removeAll(countAsEvictions: true)
        developedSourceCache.removeAll(countAsEvictions: true)
        thumbnailDevelopedSourceCache.removeAll(countAsEvictions: true)
        processingPrefixCache.removeAll(countAsEvictions: true)
        localMaskCache.removeAll(countAsEvictions: true)
        localMaskRenderer.removeAllCachedBrushStrokes()
        lutCache.removeAll()
        toneCurveCache.removeAll()
        toneCurveSource = nil
        toneCurveSpace = nil
    }

    func invalidateAll() {
        previewCache.removeAll()
        developedSourceCache.removeAll()
        thumbnailDevelopedSourceCache.removeAll()
        processingPrefixCache.removeAll()
        localMaskCache.removeAll()
        localMaskRenderer.removeAllCachedBrushStrokes()
        toneCurveCache.removeAll()
        toneCurveSource = nil
        toneCurveSpace = nil
    }

    /// The completed presentation texture is quantized only for interactive frames. Settled
    /// previews and every processing-prefix boundary retain half-float precision.
    static func previewTexturePixelFormat(for quality: RenderQuality) -> MTLPixelFormat {
        quality == .interactive ? .rgba8Unorm : .rgba16Float
    }

    /// Allocate an actor-confined texture for a completed intermediate. The texture is private so
    /// Core Image can consume the prefix through Metal without exposing a CPU staging buffer. The
    /// default keeps processing-prefix materialization at its existing half-float precision;
    /// callers may opt into 8-bit only for the interactive presentation boundary.
    func makeProcessingTexture(
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat = .rgba16Float
    ) -> MTLTexture? {
        guard let device, width > 0, height > 0 else { return nil }
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = pixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.mipmapLevelCount = 1
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }
}
