import CoreImage
import Metal

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
