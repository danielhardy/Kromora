import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers

/// What the app needs from a renderer, so a test can hand it something that is not the GPU.
///
/// The point of the protocol is not abstraction for its own sake — it is that once the view model
/// renders through this (Step 5), a test can drive the whole preview/export flow against a fake and
/// assert on *what was asked for* rather than on pixels. Pixel assertions belong to the engine's own
/// tests; everything above it should be testable without a Metal device.
///
/// `Sendable` because every conformer is crossed from the main actor. `actor RenderEngine` gets that
/// for free; a fake has to earn it.
protocol RenderEngining: Sendable {

    /// Prepare source value state without requesting source pixels. The production renderer owns
    /// RAW preparation so the same decoder session can answer geometry/capability questions and
    /// later develop the visible image.
    func prepareSource(_ source: ImageSource) async -> ImageSourcePreparation?

    /// Completed Core Image output for the persistent GPU presentation surface.
    ///
    /// A production implementation must not return a lazy source graph here. The returned image
    /// is backed by a completed GPU texture, so the caller may apply presentation-only transforms
    /// without causing source development or adjustment evaluation on its actor.
    func makeCIImage(_ request: RenderRequest) async -> sending CIImage?

    /// Render one UI-independent request through the deterministic pipeline.
    func render(_ request: RenderRequest) async throws -> RenderResult

    /// Render a bounded browsing thumbnail through the same document/look pipeline while keeping
    /// thumbnail work distinct from the editor preview lifecycle.
    func renderThumbnail(_ request: RenderRequest) async throws -> RenderResult

    /// Produce a display image for a request without changing the Sendable render-result boundary.
    ///
    /// The default keeps conformers that only implement `render` source-compatible. The real
    /// engine overrides this with an actor-local `CIContext.createCGImage` path so interactive
    /// preview frames do not pay for an encoded PNG that is immediately decoded again.
    func makeCGImage(_ request: RenderRequest) async -> sending CGImage?

    /// Rasterize a completed preview frame into the durable cache's canonical long-edge size.
    /// Core Image work stays beside the engine-owned context; callers receive only the finished
    /// value that the disk cache can encode.
    func makeCanonicalPreviewRaster(
        _ image: sending CIImage,
        space: WorkingSpace,
        longEdge: Int
    ) async -> sending CGImage?

    /// Produce a thumbnail CGImage. The default preserves older conformers' thumbnail recording
    /// seam; `RenderEngine` overrides it to rasterize directly without encoded bytes.
    func makeThumbnailCGImage(_ request: RenderRequest) async -> sending CGImage?

    /// Produce one Look-browser candidate. Production engines can reuse the candidate's shared
    /// developed/pre-LUT prefix when the candidate differs from the base document only by LUT.
    func makeLookPreviewCGImage(_ request: LookPreviewRequest) async -> sending CGImage?

    /// Produce the presentation-only resolved alpha overlay for the masking workspace. This is a
    /// separate seam from `RenderRequest` so inspection state can never affect preview or export.
    func makeMaskOverlayImage(_ request: MaskOverlayRequest) async -> sending CGImage?

    /// Tally `document` over `source` into a 256-bin per-channel histogram.
    ///
    /// On the protocol rather than left to the caller because tallying needs a rasterizer, and the
    /// rasterizer is this actor. The alternative — handing the caller a `CIImage` to tally itself —
    /// is the old `ImageProcessor` shape, and it is what let the histogram describe a *different*
    /// image from the one on screen: it graded a full-resolution neutral decode with only the LUT,
    /// while the preview showed develop and adjustments too.
    ///
    /// `scale` should be the **display** scale, not a histogram-sized one, so the call reuses the
    /// engine's developed-source memo instead of evicting it; the tally buffer is capped separately
    /// by `maxDimension`.
    func histogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace,
        maxDimension: Int
    ) async -> HistogramData?

    /// Tally the already-rendered frame that reached the presentation surface.
    ///
    /// This is deliberately separate from the source/document overload above: a settled preview
    /// must not rebuild its graph just to feed the Info inspector. The image is completed before it
    /// crosses the renderer boundary, so this operation only performs the bounded RGBA8 raster
    /// and byte tally. Lightweight compatibility conformers may leave this at its default `nil`.
    func histogram(
        presentedImage: sending CIImage,
        space: WorkingSpace,
        maxDimension: Int
    ) async -> HistogramData?

    /// Tally the rendered canonical image through a soft mask. The default implementation uses
    /// the same raster request seam as `histogram`; production engines may override it with an
    /// actor-local GPU tally without changing the analysis API.
    func maskedHistogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace,
        mask: NormalizedMask
    ) async -> WeightedHistogramData?

    /// Drop every cached cube filter, because the bytes behind a `LUTID` may have changed.
    ///
    /// **On the protocol as of Step 9, so that the app calling it is assertable.** The engine has had
    /// this method since Step 4 and it was correct the whole time; the only caller was a test, and
    /// nothing above the actor could see whether it fired. Its absence became reachable in Step 9:
    /// saving a second derive over the same `.cube` path yields the same `LUTID`, so without this the
    /// cache keeps serving the first cube and the second save silently does nothing on screen.
    func invalidateLUTCache() async

    /// Drop in-memory render resources after a source is deleted from the library.
    func invalidateRenderCaches() async

    /// What this source's RAW decoder can do, and where its own defaults sit. `nil` for a non-RAW.
    ///
    /// On the protocol because the develop inspector needs it and cannot reach a `CIRAWFilter`:
    /// the flags live on a non-`Sendable` type confined to the actor (§4.5). Returning a value is
    /// the only way the panel can be gated on what the decoder actually supports.
    func rawCapabilities(for source: ImageSource) async -> RAWCapabilities?
}

extension RenderEngining {
    /// Compatibility default for lightweight render test doubles and integrations.
    func invalidateRenderCaches() async {}
}

/// Actor-local counters used by performance captures to separate RAW configuration, decoder output
/// requests, and completed prefix work. They are diagnostics only and do not affect cache identity.
struct RenderWorkStatistics: Sendable, Equatable {
    let rawFilterConstructions: Int
    let rawPropertyWrites: Int
    let rawOutputRequests: Int
    let processingPrefixMaterializations: Int
    /// Number of processing-prefix completions that used the CPU bitmap fallback.
    ///
    /// This is diagnostic state for the acceptance/performance tests. A GPU-backed prefix should
    /// leave this at zero; the injected-context path deliberately increments it to prove the
    /// compatibility branch remains alive.
    let processingPrefixCPUReadbacks: Int
    /// Number of processing-prefix command-buffer submissions. A downstream LUT/grain tick should
    /// reuse the retained texture and therefore add no submissions.
    let processingPrefixTextureSubmissions: Int
    let materializationBudgetSkips: Int
}

/// The value-only part of a render request.
///
/// Keeping the scale/ROI/crop decisions in a Sendable value is the important half of the render
/// split: callers can prepare several requests without touching Core Image or the actor-owned
/// decoder/context. The plan deliberately contains no CIImage, CIFilter, Metal, or cache object;
/// those are materialized only after the request has passed its cancellation and supersession
/// fences on `RenderEngine`.
struct RenderBuildPlan: Sendable, Equatable {
    let scale: RenderScale
    let sourceROI: CGRect?
    let presentationROI: CGRect?
    let processingROI: CGRect?
    let fullFrameExtent: CGRect
    let hasEarlyCrop: Bool
    let finalFrameExtent: CGRect?
    let includePostRenderWhiteBalance: Bool
    let maskIdentity: String
    let documentIdentity: String

    static func make(
        source: ImageSource,
        document: EditDocument,
        scale: RenderScale,
        sourceROI: CGRect?,
        presentationROI: CGRect?
    ) -> Self {
        let maskIdentity = RenderCacheHash.digest(RenderEngine.MaskRecipeIdentity(document.localAdjustments))
        let documentIdentity = RenderCacheHash.digest(document)
        let nativeExtent = document.rotation.orientedExtent(source.nativeExtent)
        let cropNativeRect = document.crop.normalizedRect.map { rect in
            CGRect(
                x: rect.minX * nativeExtent.width,
                y: rect.minY * nativeExtent.height,
                width: rect.width * nativeExtent.width,
                height: rect.height * nativeExtent.height
            )
        } ?? CGRect(origin: .zero, size: nativeExtent)
        let effectiveROI = sourceROI.flatMap { roi -> CGRect? in
            // A geometry ROI is only safe when the caller also supplied the post-geometry
            // rectangle; without it the native ROI cannot be applied after the transform.
            if document.crop.hasGeometryTransform, presentationROI == nil { return nil }
            let boundary = document.crop.hasGeometryTransform
                ? CGRect(origin: .zero, size: nativeExtent)
                : cropNativeRect
            let intersection = roi.intersection(boundary)
            return intersection.isNull || intersection.width <= 0 || intersection.height <= 0
                ? nil : intersection
        }
        let processingROI = effectiveROI.map {
            RenderPipeline.expandedSourceROI(
                $0, nativeExtent: nativeExtent,
                needsSpatialSupport: document.effects.hasSpatialWork
            )
        }
        // This is the geometry of the complete scaled source, even when the graph below is
        // evaluated from a smaller ROI. Spatial effects use it as their photographic reference.
        let geometryNativeExtent = RenderPipeline.geometryExtent(
            of: nativeExtent, for: document.crop
        )
        let factor = scale.factor(for: nativeExtent)
        let fullFrameExtent = CGRect(
            origin: .zero,
            size: CGSize(width: geometryNativeExtent.width * factor,
                         height: geometryNativeExtent.height * factor)
        )
        let hasEarlyCrop = !scale.isFull && effectiveROI != nil
        let finalFrameExtent: CGRect? = {
            guard hasEarlyCrop, let crop = document.crop.normalizedRect else {
                return hasEarlyCrop ? fullFrameExtent : nil
            }
            return CGRect(
                x: fullFrameExtent.minX + crop.minX * fullFrameExtent.width,
                y: fullFrameExtent.minY + crop.minY * fullFrameExtent.height,
                width: crop.width * fullFrameExtent.width,
                height: crop.height * fullFrameExtent.height
            )
        }()
        return Self(
            scale: scale, sourceROI: effectiveROI, presentationROI: presentationROI,
            processingROI: processingROI,
            fullFrameExtent: fullFrameExtent, hasEarlyCrop: hasEarlyCrop,
            finalFrameExtent: finalFrameExtent,
            includePostRenderWhiteBalance: source.kind == .standard,
            maskIdentity: maskIdentity, documentIdentity: documentIdentity
        )
    }

    /// Rebase the plan's frame geometry on the decoder's authoritative extent. Standard image
    /// orientation and RAW metadata normally agree with `ImageSource.nativeExtent`, but the
    /// decoder remains the source of truth for the graph's actual extent.
    func rebased(to decodedExtent: CGRect, crop: CropAdjustments) -> Self {
        // `decodedExtent` is already the authoritative post-geometry raster extent. Re-scaling
        // it here would apply the preview factor a second time for a rotated AABB.
        let fullFrameExtent = CGRect(origin: .zero, size: decodedExtent.size)
        let finalFrameExtent: CGRect? = {
            guard hasEarlyCrop, let crop = crop.normalizedRect else {
                return hasEarlyCrop ? fullFrameExtent : nil
            }
            return CGRect(
                x: fullFrameExtent.minX + crop.minX * fullFrameExtent.width,
                y: fullFrameExtent.minY + crop.minY * fullFrameExtent.height,
                width: crop.width * fullFrameExtent.width,
                height: crop.height * fullFrameExtent.height
            )
        }()
        return Self(
            scale: scale, sourceROI: sourceROI, presentationROI: presentationROI,
            processingROI: processingROI,
            fullFrameExtent: fullFrameExtent, hasEarlyCrop: hasEarlyCrop,
            finalFrameExtent: finalFrameExtent,
            includePostRenderWhiteBalance: includePostRenderWhiteBalance,
            maskIdentity: maskIdentity, documentIdentity: documentIdentity
        )
    }
}

private struct ResolvedLocalMaskSet {
    let images: [UUID: CIImage]
    let cacheIdentity: MaskRasterCacheIdentity?
}

private struct MaskRasterCacheIdentity: Sendable, Hashable {
    let resolutionState: String
    let payloadVersion: String
}

extension RenderEngining {
    func renderThumbnail(_ request: RenderRequest) async throws -> RenderResult {
        try await render(request)
    }

    func prepareSource(_ source: ImageSource) async -> ImageSourcePreparation? {
        guard source.kind == .standard else { return nil }
        let extent: CGSize?
        switch source.backing {
        case .url(let url):
            extent = try? ImageDecoder.prepareStandard(from: url)
        case .data(let data):
            extent = try? ImageDecoder.prepareStandard(from: data, name: "import")
        }
        guard let extent else { return nil }
        return ImageSourcePreparation(source: ImageSource(
            backing: source.backing, kind: source.kind, nativeExtent: extent,
            portableIdentity: source.cacheIdentity.with(
                geometry: PhotoPixelDimensions(width: Int(extent.width), height: Int(extent.height))
            )
        ))
    }

    func makeCIImage(_ request: RenderRequest) async -> sending CIImage? { nil }

    func histogram(
        presentedImage: sending CIImage,
        space: WorkingSpace,
        maxDimension: Int
    ) async -> HistogramData? { nil }

    func makeCGImage(_ request: RenderRequest) async -> sending CGImage? {
        guard request.output == .raster,
              let result = try? await render(request),
              let imageSource = CGImageSourceCreateWithData(result.data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else { return nil }
        return image
    }

    func makeCanonicalPreviewRaster(
        _ image: sending CIImage,
        space: WorkingSpace,
        longEdge: Int
    ) async -> sending CGImage? {
        // Compatibility seam for fake/lightweight renderers. Production RenderEngine overrides
        // this with its retained context; the fallback still keeps context construction inside
        // RenderEngineResources and lets existing renderer doubles exercise preview caching.
        guard !Task.isCancelled else { return nil }
        return RenderEngineResources.canonicalPreviewRaster(
            from: image, space: space, longEdge: longEdge
        )
    }

    /// Thumbnail callers can use a CGImage without changing the established fake-render seam.
    /// The default is intentionally compatibility-only; `RenderEngine` overrides it below so the
    /// production badge path never encodes PNG bytes just to decode them again.
    func makeThumbnailCGImage(_ request: RenderRequest) async -> sending CGImage? {
        guard let result = try? await renderThumbnail(request),
              let source = CGImageSourceCreateWithData(result.data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func makeLookPreviewCGImage(_ request: LookPreviewRequest) async -> sending CGImage? {
        // Compatibility seam for lightweight conformers. Production RenderEngine overrides this
        // method to reuse the LUT-independent prefix before rasterizing the candidate.
        await makeCGImage(request.renderRequest)
    }

    func makeMaskOverlayImage(_ request: MaskOverlayRequest) async -> sending CGImage? { nil }

    func maskedHistogram(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace,
        mask: NormalizedMask
    ) async -> WeightedHistogramData? {
        guard !Task.isCancelled else { return nil }
        let request = RenderRequest(
            source: source, document: document, lut: lut,
            targetSize: CGSize(width: mask.size.width, height: mask.size.height),
            quality: .preview, output: .raster, space: space
        )
        guard let image = await makeCGImage(request), !Task.isCancelled,
              image.width == mask.size.width, image.height == mask.size.height else { return nil }

        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard !Task.isCancelled else { return nil }
        return WeightedHistogramData(
            rgba8: bytes, width: width, height: height, bytesPerRow: bytesPerRow, mask: mask
        )
    }

    func makeCGImage(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale,
        space: WorkingSpace = .current
    ) async -> sending CGImage? {
        let request = RenderRequest(
            source: source, document: document, lut: lut,
            targetSize: scale.targetSize,
            quality: scale == .full ? .fullResolution : .preview,
            output: .raster, space: space
        )
        return await makeCGImage(request)
    }

    func encode(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        scale: RenderScale = .full,
        format: ExportFormat,
        quality: CGFloat = 0.95,
        space: WorkingSpace = .current
    ) async throws -> Data {
        let request = RenderRequest(
            source: source, document: document, lut: lut,
            targetSize: scale.targetSize,
            quality: scale == .full ? .export : .preview,
            output: .encoded(format: format, quality: quality), space: space
        )
        return try await render(request).data
    }

    /// Encode with the complete durable export policy, without involving a panel or destination I/O.
    func encode(
        source: ImageSource,
        document: EditDocument,
        lut: CubeLUT?,
        options: ExportOptions
    ) async throws -> Data {
        try options.validate()
        return try await render(RenderRequest(
            source: source,
            document: document,
            lut: lut,
            quality: .export,
            output: .encoded(
                format: options.format,
                quality: CGFloat(options.quality)
            ),
            space: options.colorSpace,
            exportOptions: options
        )).data
    }
}

/// The render contexts have deliberately separate ownership domains. The processing context and
/// queue live behind `RenderEngine`; the presentation context and queue live on the main actor in
/// `PreviewSurfaceView.Coordinator`. They share a device, but neither context or queue crosses an
/// actor boundary. This prevents drawable acquisition/presentation from becoming part of source
/// evaluation while making the device/queue relationship explicit.
///
/// **The GPU is the isolation boundary** (`docs/ENGINEERING_GUIDE.md`). Source graphs, filters and
/// processing contexts are born and die inside this actor; only value requests and completed,
/// texture-backed preview images cross out. That is what lets Step 8 turn strict concurrency on
/// without a single `@unchecked`.
///
/// It deliberately does **not** decide *what* to render. `RenderPipeline.buildImage` is a pure
/// function that builds the graph; this evaluates it. Preview and export call the same builder and
/// differ only in explicit quality/output policy, which is what makes their agreement structural
/// rather than maintained (§1).
///
/// Added in Step 4 **alongside** the old `ImageProcessor` path, which Steps 5–7 then cut over leaf by
/// leaf — preview, export, histogram — until nothing was left of it to delete. `RecipeExtractor`
/// keeps its own context by design (§3): it sits outside this stack, never imports `EditDocument`,
/// and samples in a space pinned to sRGB regardless of `WorkingSpace.current`. The render stack now
/// has one actor-owned processing context and one explicitly main-actor-owned presentation context;
/// `RenderStackTests` continues to protect against accidental context proliferation.
actor RenderEngine: RenderEngining {

    /// Shared device for the two explicitly-owned GPU domains. The engine's processing context is
    /// created from its private queue; the presentation context is created from the main-actor
    /// presentation queue below. A device is safe to share; mutable contexts and queues are not.
    @MainActor static let presentationDevice: MTLDevice = MTLCreateSystemDefaultDevice()!

    @MainActor static let presentationQueue: MTLCommandQueue = presentationDevice.makeCommandQueue()!
    @MainActor static let presentationContext: CIContext = CIContext(mtlCommandQueue: presentationQueue)

    func makeCIImage(_ request: RenderRequest) async -> sending CIImage? {
        guard request.output == .raster, !Task.isCancelled else { return nil }
        beginRenderRequest(request)
        defer { endRenderRequest(request) }
        let image: CIImage?
        do {
            image = try await buildImage(request.source, request.document, request.lut,
                                         request.renderScale, request.space, quality: request.quality,
                                         sourceROI: request.sourceROI,
                                         presentationROI: request.presentationROI,
                                         maskTransform: request.maskTransform,
                                         assetID: request.assetID, requestRevision: request.requestRevision,
                                         resolveSemanticMasks: request.maskResolution == .resolved)
        } catch {
            return nil
        }
        // A newer request may have arrived while this build awaited value-level mask work.
        // Superseded graphs must be discarded before they can enqueue GPU work.
        guard !Task.isCancelled, isCurrentRenderRequest(request), let image,
              image.extent.isRasterizable
        else {
            return nil
        }
        guard let commandQueue else {
            // This is the CPU/no-device compatibility seam. The shipping macOS path has a Metal
            // device and therefore takes the completed-texture path below; keeping the lazy image
            // available here preserves RenderEngine's graph-only test initializer and CPU CI hosts.
            return image
        }

        let rect = image.extent.integral
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard width > 0, height > 0,
              let texture = resources.makeProcessingTexture(
                  width: width, height: height,
                  pixelFormat: RenderEngineResources.previewTexturePixelFormat(for: request.quality)
              )
        else { return nil }

        // Interactive frames are intentionally quantized at this completed-texture boundary: the
        // next request is always the settled `.preview` frame, which restores half-float precision.
        // The working-space tag is applied both while Core Image renders and when the texture is
        // wrapped as a CIImage, so presentation does not perform an implicit second conversion.
        // All other qualities retain the existing RGBA16Float path; in particular this does not
        // change processing-prefix, full-resolution, thumbnail, or export precision.
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        context.render(image, to: texture, commandBuffer: commandBuffer, bounds: rect,
                       colorSpace: request.space.cgColorSpace)
        guard await commitAndWaitForCompletion(commandBuffer), !Task.isCancelled else { return nil }
        // CIImage retains the texture. Since this image is only returned after the command buffer
        // completes, a presentation transform can sample it without racing an in-flight write.
        guard let textureImage = CIImage(
            mtlTexture: texture, options: [.colorSpace: request.space.cgColorSpace]
        ) else { return nil }
        // Metal textures start at (0, 0), while an ROI retains its source-space origin in the
        // Core Image graph. Restore that origin so the presentation surface can place the ROI
        // inside the virtual committed-crop extent without shifting it to the frame corner.
        return rect.origin == .zero
            ? textureImage
            : textureImage.transformed(by: CGAffineTransform(
                translationX: rect.minX, y: rect.minY
            ))
    }

    /// The app's engine. One instance, therefore one actor-owned processing context and queue.
    static let shared = RenderEngine()

    /// All non-Sendable GPU and cache resources live in this actor-confined storage boundary.
    let resources: RenderEngineResources

    // These narrow aliases keep the render algorithm readable while making ownership explicit in
    // `RenderEngineResources`. They are actor-isolated through their enclosing engine. Not
    // `private`: the RAW-capability and histogram extensions in their own files (KRMA-530) read
    // them too, and `private` is file-scoped rather than type-scoped.
    var context: CIContext { resources.context }
    var commandQueue: MTLCommandQueue? { resources.commandQueue }
    private var lutCache: LUTFilterCache { resources.lutCache }
    private var toneCurveCache: ToneCurveFilterCache { resources.toneCurveCache }
    private var toneCurveSource: RenderSourceFingerprint? {
        get { resources.toneCurveSource }
        set { resources.toneCurveSource = newValue }
    }
    private var toneCurveSpace: WorkingSpace? {
        get { resources.toneCurveSpace }
        set { resources.toneCurveSpace = newValue }
    }
    private var previewCache: BoundedLRUCache<PreviewCacheKey, RenderResult> { resources.previewCache }
    private var developedSourceCache: BoundedLRUCache<DevelopedSourceCacheKey, CIImage> {
        resources.developedSourceCache
    }
    private var thumbnailDevelopedSourceCache: BoundedLRUCache<DevelopedSourceCacheKey, CIImage> {
        resources.thumbnailDevelopedSourceCache
    }
    private var processingPrefixCache: BoundedLRUCache<ProcessingPrefixCacheKey, CIImage> {
        resources.processingPrefixCache
    }
    private var localMaskCache: BoundedLRUCache<LocalMaskCacheKey, LocalMaskPayload> {
        resources.localMaskCache
    }
    private var localMaskRenderer: LocalMaskRenderer { resources.localMaskRenderer }
    private var localMaskResolver: any LocalMaskResolving
    /// `nil` is used by focused comparison tests to exercise the previous full-resolution path.
    /// Production engines use the bounded preview policy below; render/export remains uncapped.
    private let semanticMaskPreviewCap: PixelDimensions?
    /// The interactive RAW decoder is deliberately a single-entry cache. `CIRAWFilter` is mutable
    /// and is only safe behind this actor; retaining one filter for the visible source avoids
    /// rebuilding its immutable source/decode setup on every pointer tick. It is discarded at the
    /// source boundary, so a replaced URL or a different photo can never reuse decoder state.
    /// Not `private`: `RenderEngine+RAWCapabilities.swift` owns the session accessor in its own
    /// file, and `private` is file-scoped rather than type-scoped (KRMA-530).
    var interactiveRAWSession: InteractiveRAWFilterSession?
    /// Bounded render/mask supersession bookkeeping. See `RenderEngine.RevisionLedger` for why this
    /// is a separate value type rather than plain dictionaries on the actor.
    private var revisionLedger = RevisionLedger()
    var rawFilterConstructionCount = 0
    private var rawPropertyWriteCount = 0
    private var rawOutputRequestCount = 0
    private var processingPrefixMaterializationCount = 0
    private var processingPrefixCPUReadbackCount = 0
    private var processingPrefixTextureSubmissionCount = 0
    private var materializationBudgetSkipCount = 0
    /// One-shot test seam for exercising actor re-entry between Metal completion and cache insert.
    private var processingPrefixCompletionHook: (@Sendable () async -> Void)?
    private var nextPrefixFlightToken: UInt64 = 0
    private var processingPrefixFlights: [ProcessingPrefixCacheKey: PrefixMaterializationFlight] = [:]
    private var nextDevelopedSourceFlightToken: UInt64 = 0
    private var developedSourceFlights: [DevelopedSourceCacheKey: DevelopedSourceFlight] = [:]
    private var thumbnailDevelopedSourceFlights: [DevelopedSourceCacheKey: DevelopedSourceFlight] = [:]
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    /// Pixel-affecting mask topology, deliberately excluding both the global look and the local
    /// adjustment values applied through the resolved mask. A layer dropping out of the visible
    /// graph still changes the identity, while an exposure/contrast tick on an active layer does
    /// not restart an unchanged semantic detector.
    struct MaskRecipeIdentity: Encodable {
        struct Layer: Encodable {
            let id: UUID
            let isInverted: Bool
            let components: [Component]
        }

        struct Component: Encodable {
            let id: UUID
            let mode: MaskCombineMode
            let isInverted: Bool
            let source: MaskSource
        }

        let layers: [Layer]

        init(_ layers: [LocalAdjustmentLayer]) {
            self.layers = layers.filter(\.hasVisibleLook).map { layer in
                Layer(
                    id: layer.id,
                    isInverted: layer.isInverted,
                    components: layer.components.filter(\.isUsable).map { component in
                        Component(
                            id: component.id, mode: component.mode,
                            isInverted: component.isInverted, source: component.source
                        )
                    }
                )
            }
        }
    }
    /// A revisioned preview owns one waiter on the coordinator for every semantic component it is
    /// currently resolving. Keeping the waiter task here lets a later source or mask recipe cancel
    /// it immediately; cancelling that task runs `PhotoAnalysisCoordinator.maskWaiterCancelled`
    /// and stops the shared provider once no still-useful consumer remains.
    private struct InFlightSemanticMaskResolution {
        let sourceKey: String
        let maskIdentity: String
        let task: Task<LocalMaskPayload, Error>
    }
    private var inFlightSemanticMaskResolutions: [UUID: InFlightSemanticMaskResolution] = [:]
    private var activeRevisionedMaskSource: String?

    init(
        maskResolver: any LocalMaskResolving = DefaultLocalMaskResolver(),
        configuration: RenderCacheConfiguration = .default,
        semanticMaskPreviewCap: PixelDimensions? = SemanticMaskPreviewResolution.defaultCap
    ) {
        self.resources = RenderEngineResources(configuration: configuration)
        self.localMaskResolver = maskResolver
        self.semanticMaskPreviewCap = semanticMaskPreviewCap
        Task { [weak self] in await self?.installMemoryPressureMonitor() }
    }

    /// Connects the render actor to the app's shared analysis coordinator after both actors have
    /// been initialized. Keeping this as an actor-isolated swap avoids a construction cycle between
    /// `RenderEngine.shared` and `PhotoAnalysisCoordinator` while preserving one Vision/cache path.
    func installSemanticMaskCoordinator(_ coordinator: PhotoAnalysisCoordinator) {
        localMaskResolver = CoordinatorLocalMaskResolver(coordinator: coordinator)
    }

    /// Inject a context — for tests that need to pin the backend rather than take whatever the
    /// machine offers.
    init(
        context: CIContext,
        maskResolver: any LocalMaskResolving = DefaultLocalMaskResolver(),
        configuration: RenderCacheConfiguration = .default,
        semanticMaskPreviewCap: PixelDimensions? = SemanticMaskPreviewResolution.defaultCap
    ) {
        self.resources = RenderEngineResources(context: context, configuration: configuration)
        self.localMaskResolver = maskResolver
        self.semanticMaskPreviewCap = semanticMaskPreviewCap
        Task { [weak self] in await self?.installMemoryPressureMonitor() }
    }


    // MARK: - Rendering

    /// Fast display-only rasterization. `CGImage` is created while the Core Image graph and context
    /// are still actor-local, then transferred to the UI as the one explicitly `sending` value.
    /// Keeping this accessor separate means `RenderResult` remains a small, UI-independent,
    /// Sendable value for exports and other renderer clients.
    func makeCGImage(_ request: RenderRequest) async -> sending CGImage? {
        guard request.output == .raster, !Task.isCancelled else { return nil }
        beginRenderRequest(request)
        defer { endRenderRequest(request) }

        var interval = KromoraObservability.begin(
            .render, source: request.source, quality: request.quality
        )
        defer { interval.end() }

        let image: CIImage?
        do {
            image = try await buildImage(
                request.source, request.document, request.lut, request.renderScale, request.space,
                quality: request.quality, sourceROI: request.sourceROI,
                presentationROI: request.presentationROI,
                maskTransform: request.maskTransform,
                assetID: request.assetID, requestRevision: request.requestRevision,
                resolveSemanticMasks: request.maskResolution == .resolved
            )
        } catch {
            return nil
        }
        guard !Task.isCancelled, isCurrentRenderRequest(request), let image,
              image.extent.isRasterizable,
              !Task.isCancelled
        else { return nil }

        let rect = image.extent.integral
        return context.createCGImage(
            image, from: rect, format: .RGBA8, colorSpace: request.space.cgColorSpace
        )
    }

    func makeCanonicalPreviewRaster(
        _ image: sending CIImage,
        space: WorkingSpace,
        longEdge: Int
    ) async -> sending CGImage? {
        guard !Task.isCancelled else { return nil }
        return resources.canonicalPreviewRaster(from: image, space: space, longEdge: longEdge)
    }

    /// The edited-thumbnail path uses the actor-local rasterizer directly. Keeping this separate
    /// from the encoded `renderThumbnail` API avoids a PNG encode/decode round trip for every
    /// 256px browsing badge.
    func makeThumbnailCGImage(_ request: RenderRequest) async -> sending CGImage? {
        await makeCGImage(request)
    }

    func makeLookPreviewCGImage(_ request: LookPreviewRequest) async -> sending CGImage? {
        guard request.targetSize.width.isFinite, request.targetSize.height.isFinite,
              request.targetSize.width > 0, request.targetSize.height > 0,
              !Task.isCancelled else { return nil }

        let renderRequest = request.renderRequest
        beginRenderRequest(renderRequest)
        defer { endRenderRequest(renderRequest) }
        let image: CIImage?
        do {
            image = try await buildImage(
                request.source, request.candidateDocument, request.look,
                renderRequest.renderScale, request.space,
                quality: .thumbnail,
                prefixDocument: request.isLUTOnlyChange ? request.baseDocument : nil
            )
        } catch {
            return nil
        }
        guard !Task.isCancelled, isCurrentRenderRequest(renderRequest),
              let image, image.extent.isRasterizable else { return nil }
        return context.createCGImage(
            image, from: image.extent.integral, format: .RGBA8,
            colorSpace: request.space.cgColorSpace
        )
    }

    func makeMaskOverlayImage(_ request: MaskOverlayRequest) async -> sending CGImage? {
        guard request.targetSize.width > 0, request.targetSize.height > 0,
              request.targetSize.width <= Int.max / 4,
              request.targetSize.height <= Int.max / 4,
              !Task.isCancelled
        else { return nil }

        revisionLedger.beginOverlayMaskRequest(
            sourceKey: request.source.cacheFingerprint, revision: request.requestRevision
        )
        defer {
            revisionLedger.endOverlayMaskRequest(
                sourceKey: request.source.cacheFingerprint, revision: request.requestRevision
            )
        }
        noteMaskRequest(source: request.source, revision: request.requestRevision)

        let extent = CGRect(
            x: 0, y: 0,
            width: CGFloat(request.targetSize.width), height: CGFloat(request.targetSize.height)
        )
        guard extent.isRasterizable else { return nil }

        let selectedID = request.soloLayerID ?? request.selectedLayerID
        guard let selectedID,
              let layer = request.layers.first(where: { $0.id == selectedID }) else { return nil }

        // A selected component id can go stale while the layer selection survives (undo,
        // component delete, fresh draft ids during creation). Resolving strictly would render
        // nothing even though usable components exist — while the tooling keeps drawing from
        // the same layer via its first-enabled fallback, so handles show with no wash and no
        // banner. Fall back to all usable components for *selection* staleness; solo
        // isolation stays strict because it is an explicit user request.
        let onlyComponentID: UUID? = {
            guard request.soloComponentID == nil,
                  let selectedComponentID = request.selectedComponentID
            else { return request.soloComponentID ?? request.selectedComponentID }
            return layer.components.contains(where: { $0.id == selectedComponentID })
                ? selectedComponentID : nil
        }()

        do {
            let masks = try await resolvedLocalMasks(
                for: [layer], source: request.source, extent: extent,
                quality: request.quality, transform: request.transform, assetID: request.assetID,
                requestRevision: request.requestRevision, includeIdentity: true,
                onlyComponentID: onlyComponentID
            )
            guard let mask = masks.images[layer.id], !Task.isCancelled else { return nil }
            let output: CIImage
            switch request.style.inspection {
            case .colorWash:
                let color = CIImage(
                    color: CIColor(
                        red: CGFloat(request.style.red), green: CGFloat(request.style.green),
                        blue: CGFloat(request.style.blue), alpha: 1
                    )
                ).cropped(to: extent)
                let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
                    .cropped(to: extent)
                let blend = CIFilter.blendWithAlphaMask()
                blend.inputImage = color
                blend.backgroundImage = clear
                blend.maskImage = mask
                output = blend.outputImage?.cropped(to: extent) ?? clear
            case .grayscale:
                // The alpha channel is the resolved coverage. Copy it into RGB and make the
                // inspection image opaque so zero coverage reads as black rather than revealing
                // the photographic preview underneath it.
                output = mask.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ]).cropped(to: extent)
            }
            return context.createCGImage(
                output, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
            )
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    func render(_ request: RenderRequest) async throws -> RenderResult {
        var interval = KromoraObservability.begin(
            .render, source: request.source, quality: request.quality
        )
        defer { interval.end() }

        // An interactive request can sit behind another Core Image operation on this actor. Check
        // before doing any work so cancellation drops queued superseded values instead of making
        // the coordinator wait for an obsolete graph to rasterize.
        try Task.checkCancellation()
        beginRenderRequest(request)
        defer { endRenderRequest(request) }
        if let options = request.exportOptions {
            try options.validate()
            guard case .encoded(let format, _) = request.output else {
                throw ExportOptionsError.outputRequiresEncoded(expected: options.format)
            }
            guard format == options.format else {
                throw ExportOptionsError.outputFormatMismatch(expected: options.format, actual: format)
            }
        }
        let scale = request.renderScale
        let previewKey = previewCacheKey(for: request, scale: scale)
        if let previewKey {
            var cacheInterval = KromoraObservability.begin(.cache, source: request.source,
                                                        quality: request.quality)
            defer { cacheInterval.end() }
            if let cached = previewCache.value(for: previewKey) {
                KromoraObservability.event(.cacheHit, source: request.source, quality: request.quality,
                                        detail: "layer=preview")
                return cached
            }
            KromoraObservability.event(.cacheMiss, source: request.source, quality: request.quality,
                                    detail: "layer=preview")
        }

        let image: CIImage?
        let outputSpace = request.exportOptions?.colorSpace ?? request.space
        if scale.isFull {
            var decodeInterval = KromoraObservability.begin(
                .decode, source: request.source, quality: request.quality
            )
            image = try await buildImage(request.source, request.document, request.lut, scale, outputSpace,
                                         quality: request.quality, sourceROI: request.sourceROI,
                                         presentationROI: request.presentationROI,
                                         maskTransform: request.maskTransform,
                                         assetID: request.assetID, requestRevision: request.requestRevision,
                                         resolveSemanticMasks: request.maskResolution == .resolved)
            decodeInterval.end()
        } else {
            image = try await buildImage(request.source, request.document, request.lut, scale, outputSpace,
                                         quality: request.quality, sourceROI: request.sourceROI,
                                         presentationROI: request.presentationROI,
                                         maskTransform: request.maskTransform,
                                         assetID: request.assetID, requestRevision: request.requestRevision,
                                         resolveSemanticMasks: request.maskResolution == .resolved)
        }
        guard let image else {
            throw ImageError.processingFailed
        }
        let outputImage: CIImage
        if let exportOutputSize = request.exportOutputSize {
            outputImage = RenderPipeline.resized(image, to: exportOutputSize)
        } else {
            outputImage = image
        }
        try Task.checkCancellation()
        guard isCurrentRenderRequest(request) else { throw CancellationError() }
        let rect = outputImage.extent.integral
        guard rect.isRasterizable else { throw ImageError.processingFailed }
        let colorSpace = outputSpace.cgColorSpace

        let data: Data
        switch request.output {
        case .raster:
            guard let raster = context.pngRepresentation(
                of: outputImage, format: .RGBA8, colorSpace: colorSpace
            ) else { throw ImageError.processingFailed }
            data = raster

        case .encoded(let format, let quality):
            let options = request.exportOptions
            let bitDepth = options?.bitDepth ?? format.defaultBitDepth
            let alpha = options?.alpha ?? format.defaultAlpha
            let encodedImage = alpha == .opaque ? opaqueImage(outputImage) : outputImage
            let representationFormat: CIFormat
            switch (bitDepth, alpha) {
            case (.sixteen, .preserve): representationFormat = .RGBA16
            case (.sixteen, .opaque): representationFormat = .RGBA16
            case (.eight, .preserve), (.eight, .opaque): representationFormat = .RGBA8
            }
            switch format {
            case .tiff:
                data = try encode(
                    encodedImage,
                    format: format,
                    representationFormat: representationFormat,
                    colorSpace: colorSpace,
                    quality: quality,
                    metadata: exportMetadata(for: request)
                )
            case .jpeg:
                data = try encode(
                    encodedImage,
                    format: format,
                    representationFormat: .RGBA8,
                    colorSpace: colorSpace,
                    quality: quality,
                    metadata: exportMetadata(for: request)
                )
            case .png:
                data = try encode(
                    encodedImage,
                    format: format,
                    representationFormat: representationFormat,
                    colorSpace: colorSpace,
                    quality: quality,
                    metadata: exportMetadata(for: request)
                )
            case .heif:
                data = try encode(
                    encodedImage,
                    format: format,
                    representationFormat: .RGBA8,
                    colorSpace: colorSpace,
                    quality: quality,
                    metadata: exportMetadata(for: request)
                )
            }
        }

        try Task.checkCancellation()

        let result = RenderResult(
            data: data, extent: rect.size, colorSpace: outputSpace,
            quality: request.quality, output: request.output
        )
        if let previewKey {
            previewCache.insert(result, for: previewKey, cost: data.count)
        }
        try Task.checkCancellation()
        return result
    }

    /// Flatten an opaque export against white while keeping the Core Image graph actor-local.
    private func opaqueImage(_ image: CIImage) -> CIImage {
        let background = CIImage(
            color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        ).cropped(to: image.extent)
        return image.composited(over: background)
    }

    /// Encode a completed Core Image graph through Image I/O so source metadata can be supplied to
    /// the destination. Core Image's representation helpers do not expose the source property
    /// dictionaries, while `CGImageDestinationAddImage` writes them for all three export formats.
    private func encode(
        _ image: CIImage,
        format: ExportFormat,
        representationFormat: CIFormat,
        colorSpace: CGColorSpace,
        quality: CGFloat,
        metadata: [CFString: Any]?
    ) throws -> Data {
        guard let cgImage = context.createCGImage(
            image,
            from: image.extent.integral,
            format: representationFormat,
            colorSpace: colorSpace
        ) else {
            throw ImageError.exportFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, format.utType.identifier as CFString, 1, nil
        ) else {
            throw ImageError.exportFailed
        }

        var imageProperties = metadata ?? [:]
        if format == .jpeg || format == .heif {
            imageProperties[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(destination, cgImage,
                                   imageProperties.isEmpty ? nil : imageProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageError.exportFailed
        }
        return data as Data
    }

    /// Read only the source's metadata dictionaries. The image itself is rendered upright before
    /// this is called, so copying the source orientation would apply that transform a second time.
    /// Pixel dimensions are likewise omitted: a long-edge export may intentionally resize them.
    /// GPS is independently controlled because preserving camera metadata does not imply consent
    /// to share precise location.
    private func exportMetadata(for request: RenderRequest) -> [CFString: Any]? {
        let policy = request.exportOptions?.metadata ?? .preserve
        guard policy == .preserve else { return nil }
        let locationPolicy = request.exportOptions?.location ?? .exclude

        let source: CGImageSource?
        switch request.source.backing {
        case .url(let url):
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        case .data(let data):
            source = CGImageSourceCreateWithData(data as CFData, nil)
        }
        guard let source,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else {
            return nil
        }

        var dictionaryKeys: [CFString] = [
            kCGImagePropertyTIFFDictionary,
            kCGImagePropertyExifDictionary,
        ]
        if locationPolicy == .include {
            dictionaryKeys.append(kCGImagePropertyGPSDictionary)
        }
        var metadata: [CFString: Any] = [:]
        for key in dictionaryKeys {
            guard var dictionary = properties[key] as? [CFString: Any], !dictionary.isEmpty else {
                continue
            }
            if key == kCGImagePropertyTIFFDictionary {
                dictionary.removeValue(forKey: kCGImagePropertyTIFFOrientation)
            } else if key == kCGImagePropertyExifDictionary {
                dictionary.removeValue(forKey: kCGImagePropertyExifPixelXDimension)
                dictionary.removeValue(forKey: kCGImagePropertyExifPixelYDimension)
            }
            if !dictionary.isEmpty {
                metadata[key] = dictionary
            }
        }
        return metadata.isEmpty ? nil : metadata
    }

    // MARK: - Cache

    /// Drop every cached LUT-dependent render resource. For a library rescan: a `LUTID` is a file
    /// path, so a `.cube` edited in place keeps its ID and would otherwise keep serving the old cube.
    func invalidateLUTCache() {
        // A preview submitted while a scan was unresolved has no LUT fingerprint. Clear it too so
        // the scan completion can safely publish a newly resolved render.
        resources.invalidateLUTDependentCaches()
    }

    /// Snapshot cache counters for instrumentation and performance diagnostics.
    func cacheStatistics() -> RenderCacheStatistics {
        RenderCacheStatistics(
            preview: previewCache.statistics,
            developedSource: developedSourceCache.statistics,
            thumbnailDevelopedSource: thumbnailDevelopedSourceCache.statistics,
            processingPrefix: processingPrefixCache.statistics,
            localMask: localMaskCache.statistics,
            lutFilter: lutCache.statistics
        )
    }

    func workStatistics() -> RenderWorkStatistics {
        RenderWorkStatistics(
            rawFilterConstructions: rawFilterConstructionCount,
            rawPropertyWrites: rawPropertyWriteCount,
            rawOutputRequests: rawOutputRequestCount,
            processingPrefixMaterializations: processingPrefixMaterializationCount,
            processingPrefixCPUReadbacks: processingPrefixCPUReadbackCount,
            processingPrefixTextureSubmissions: processingPrefixTextureSubmissionCount,
            materializationBudgetSkips: materializationBudgetSkipCount
        )
    }

    /// Install a one-shot acceptance-test hook at the processing-prefix re-entry window.
    ///
    /// The hook is intentionally internal: it lets the test suite deterministically interleave
    /// invalidation with a completed command buffer without exposing non-Sendable GPU state.
    func setProcessingPrefixCompletionHook(_ hook: (@Sendable () async -> Void)?) {
        processingPrefixCompletionHook = hook
    }

    /// Release all reusable intermediates. This is also the memory-pressure handler.
    func evictForMemoryPressure() {
        cancelAllSemanticMaskResolutions()
        cancelProcessingPrefixFlights()
        resources.evictAll()
        interactiveRAWSession = nil
        revisionLedger.clearMaskRequestState()
        Thumbnails.evictForMemoryPressure()
    }

    /// Explicit invalidation for a source-folder refresh or a caller that knows a source changed.
    func invalidateRenderCaches() async {
        cancelAllSemanticMaskResolutions()
        cancelProcessingPrefixFlights()
        resources.invalidateAll()
        interactiveRAWSession = nil
        revisionLedger.clearMaskRequestState()
        Thumbnails.invalidateCache()
    }

    // MARK: - Private

    /// Turn the processing command buffer into the renderer's pacing boundary without blocking
    /// the actor thread. The handler is installed before commit; otherwise Metal rejects a late
    /// handler on a command buffer that has already been submitted. Cancellation is checked by the
    /// caller after this continuation resumes, so the GPU resource is never handed to presentation
    /// while its write is still in flight.
    private func commitAndWaitForCompletion(_ commandBuffer: MTLCommandBuffer) async -> Bool {
        await withCheckedContinuation { continuation in
            commandBuffer.addCompletedHandler { buffer in
                continuation.resume(returning: buffer.status == .completed)
            }
            commandBuffer.commit()
        }
    }

    /// Invalidation can re-enter the actor while a prefix command buffer is waiting for Metal.
    /// Cancel and detach those flights before clearing their caches so a completed old texture
    /// cannot be inserted after the invalidation boundary.
    private func cancelProcessingPrefixFlights() {
        for flight in processingPrefixFlights.values {
            flight.task.cancel()
        }
        processingPrefixFlights.removeAll(keepingCapacity: true)
    }

    /// One funnel, so preview and export cannot diverge in how they build the graph — only in the
    /// scale they ask for. Not `private`: the histogram extension file (KRMA-530) calls this too,
    /// and `private` is file-scoped rather than type-scoped.
    func buildImage(
        _ source: ImageSource,
        _ document: EditDocument,
        _ lut: CubeLUT?,
        _ scale: RenderScale,
        _ space: WorkingSpace,
        quality: RenderQuality,
        sourceROI: CGRect? = nil,
        presentationROI: CGRect? = nil,
        maskTransform: LocalMaskRenderTransform = .identity,
        assetID: PhotoAssetID? = nil,
        requestRevision: UInt64 = 0,
        resolveSemanticMasks: Bool = true,
        prefixDocument: EditDocument? = nil
    ) async throws -> CIImage? {
        // Everything in this plan is value state. It is intentionally prepared before entering
        // the decoder/graph section so a future concurrent build worker can do this work without
        // borrowing the actor-owned Core Image resources.
        let plan = RenderBuildPlan.make(
            source: source, document: document, scale: scale, sourceROI: sourceROI,
            presentationROI: presentationROI
        )
        let maskIdentity = plan.maskIdentity
        let documentIdentity = plan.documentIdentity
        let sharedPrefixDocument = prefixDocument ?? document
        noteMaskRequest(
            source: source, revision: requestRevision,
            maskIdentity: maskIdentity, documentIdentity: documentIdentity
        )
        defer {
            revisionLedger.endMaskRequest(sourceKey: source.cacheFingerprint, revision: requestRevision)
        }
        // These are explicit Core Image resource boundaries even though the transfer function is
        // mathematically source/space independent. A replaced source or working-space switch must
        // not retain a resource from the prior render session.
        let sourceFingerprint = RenderSourceFingerprint(source)
        if toneCurveSource != sourceFingerprint || toneCurveSpace != space {
            toneCurveCache.removeAll()
            toneCurveSource = sourceFingerprint
            toneCurveSpace = space
        }
        guard let developedFull = await developedSourceForBuild(
            source, document.rawDevelop, scale, rotation: document.rotation, space: space,
            interactive: quality == .interactive,
            thumbnail: quality == .thumbnail
        ) else { return nil }
        try Task.checkCancellation()
        let orientedDeveloped = RenderPipeline.applyingRotation(document.rotation, to: developedFull)
        let geometricallyDeveloped = RenderPipeline.applyingGeometry(document.crop, to: orientedDeveloped)
        let effectivePlan = plan.rebased(to: geometricallyDeveloped.extent, crop: document.crop)
        let effectiveROI = effectivePlan.sourceROI
        let processingROI = effectivePlan.processingROI
        let working: CIImage
        if !scale.isFull, effectivePlan.hasEarlyCrop, document.crop.hasGeometryTransform,
           let presentationROI = effectivePlan.presentationROI
        {
            // Geometry changes the source coordinate system, so crop the already-transformed
            // graph in post-geometry coordinates. This lets Core Image propagate the viewport
            // demand through straighten/flip/perspective without treating a native ROI as if it
            // were still in the transformed image's coordinate space.
            let extent = geometricallyDeveloped.extent
            let support = document.effects.hasSpatialWork ? CGFloat(0.028) : CGFloat(0.001)
            let expanded = CGRect(
                x: max(0, presentationROI.minX - support) * extent.width + extent.minX,
                y: max(0, presentationROI.minY - support) * extent.height + extent.minY,
                width: min(1, presentationROI.width + support * 2) * extent.width,
                height: min(1, presentationROI.height + support * 2) * extent.height
            ).intersection(extent)
            working = geometricallyDeveloped.cropped(to: expanded)
        } else if !scale.isFull, let processingROI {
            working = RenderPipeline.cropSourceROI(
                processingROI,
                nativeExtent: document.rotation.orientedExtent(source.nativeExtent),
                in: geometricallyDeveloped
            )
        } else {
            working = geometricallyDeveloped
        }
        let hasEarlyCrop = effectivePlan.hasEarlyCrop
        let finalFrameExtent = effectivePlan.finalFrameExtent
        let fullFrameExtent = effectivePlan.fullFrameExtent
        let includePostRenderWhiteBalance = effectivePlan.includePostRenderWhiteBalance
        let upstream: CIImage
        if !scale.isFull, RenderPipeline.hasPreLUTWork(
            sharedPrefixDocument, includePostRenderWhiteBalance: includePostRenderWhiteBalance
        ) {
            upstream = await processingPrefix(
                source: source, document: sharedPrefixDocument, developed: working, scale: scale,
                sourceROI: processingROI,
                spatialReferenceExtent: fullFrameExtent,
                space: space, includePostRenderWhiteBalance: includePostRenderWhiteBalance,
                quality: quality
            ) ?? RenderPipeline.buildPreLUTImage(
                developed: working, document: sharedPrefixDocument, toneCurveCache: toneCurveCache,
                includePostRenderWhiteBalance: includePostRenderWhiteBalance,
                spatialReferenceExtent: fullFrameExtent
            )
        } else {
            upstream = RenderPipeline.buildPreLUTImage(
                developed: working, document: sharedPrefixDocument, toneCurveCache: toneCurveCache,
                includePostRenderWhiteBalance: includePostRenderWhiteBalance,
                spatialReferenceExtent: hasEarlyCrop ? fullFrameExtent : nil
            )
        }
        let resolvedMasks = try await resolvedLocalMasks(
            for: document.localAdjustments, source: source, extent: upstream.extent,
            maskExtent: fullFrameExtent,
            quality: quality, transform: maskTransform, assetID: assetID,
            requestRevision: requestRevision,
            maskIdentity: maskIdentity, documentIdentity: documentIdentity,
            resolveSemanticMasks: resolveSemanticMasks
        )
        // Give a newer request a chance to run between value resolution and final graph material-
        // ization. This is the handoff point used by the GPU-submit fence below.
        await Task.yield()
        try Task.checkCancellation()
        if requestRevision > 0,
           revisionLedger.latestRenderRevision(sourceKey: source.cacheFingerprint) > requestRevision {
            throw CancellationError()
        }
        let localAdjustedGraph = RenderPipeline.applyLocalAdjustments(
            document.localAdjustments, masks: resolvedMasks.images, to: upstream
        )
        let localAdjusted: CIImage
        if !scale.isFull, resolveSemanticMasks,
           let cacheIdentity = resolvedMasks.cacheIdentity {
            localAdjusted = await postLocalProcessingPrefix(
                source: source, document: document, localAdjusted: localAdjustedGraph,
                scale: scale, sourceROI: processingROI, space: space,
                includePostRenderWhiteBalance: includePostRenderWhiteBalance,
                quality: quality, cacheIdentity: cacheIdentity
            )
        } else {
            localAdjusted = localAdjustedGraph
        }
        let output = RenderStageFacade.buildFinalStages(
            preLUT: localAdjusted, document: document, lut: lut, space: space, lutCache: lutCache,
            grainSeed: RenderPipeline.grainSeed(for: source),
            applyCommittedCrop: !hasEarlyCrop,
            finalFrameExtent: finalFrameExtent
        )
        guard hasEarlyCrop, let effectiveROI else { return output }
        let outputROI: CGRect = {
            if document.crop.hasGeometryTransform, let presentationROI = effectivePlan.presentationROI {
                return CGRect(
                    x: presentationROI.minX * fullFrameExtent.width,
                    y: presentationROI.minY * fullFrameExtent.height,
                    width: presentationROI.width * fullFrameExtent.width,
                    height: presentationROI.height * fullFrameExtent.height
                )
            }
            return RenderPipeline.scaledSourceRect(
                effectiveROI,
                nativeExtent: document.rotation.orientedExtent(source.nativeExtent),
                imageExtent: fullFrameExtent
            )
        }()
        return output.cropped(to: outputROI)
    }

    /// Standard-image decode is immutable value work. It does not touch the interactive RAW
    /// session or any actor-owned cache, so it can run while the engine actor services another
    /// request. RAW remains on the actor because `CIRAWFilter` is mutable and its session is the
    /// single-writer boundary. The returned graph is handed back only as the next Core Image value
    /// phase; GPU submission still happens in the actor methods above.
    private func developedSourceForBuild(
        _ source: ImageSource,
        _ rawDevelop: RAWDevelopSettings,
        _ scale: RenderScale,
        rotation: ImageRotation,
        space: WorkingSpace,
        interactive: Bool,
        thumbnail: Bool
    ) async -> CIImage? {
        guard source.kind == .standard else {
            return developedSource(
                source, rawDevelop, scale, rotation: rotation, space: space, interactive: interactive,
                thumbnail: thumbnail
            )
        }
        let key: DevelopedSourceCacheKey? = scale.isFull ? nil : DevelopedSourceCacheKey(
            source: RenderSourceFingerprint(source),
            developHash: RenderCacheHash.digest(rawDevelop),
            scale: RenderScaleKey(
                scale, nativeExtent: rotation.orientedExtent(source.nativeExtent)
            ),
            pipelineVersion: RenderPipeline.cacheVersion
        )
        if let key {
            let flights = thumbnail ? thumbnailDevelopedSourceFlights : developedSourceFlights
            let cache = thumbnail ? thumbnailDevelopedSourceCache : developedSourceCache
            if let flight = flights[key] {
                return await flight.task.value
            }
            if let cached = cache.value(for: key) {
                KromoraObservability.event(.cacheHit, source: source, quality: .preview,
                                        detail: "layer=developedSource")
                return cached
            }
            KromoraObservability.event(.cacheMiss, source: source, quality: .preview,
                                    detail: "layer=developedSource")
            nextDevelopedSourceFlightToken &+= 1
            let token = nextDevelopedSourceFlightToken
            let task = Task.detached(priority: .userInitiated) { () -> CIImage? in
                guard !Task.isCancelled else { return nil }
                return RenderPipeline.developedSource(
                    source, rawDevelop: rawDevelop, scale: scale, rotation: rotation
                )
            }
            if thumbnail {
                thumbnailDevelopedSourceFlights[key] = DevelopedSourceFlight(task: task, token: token)
            } else {
                developedSourceFlights[key] = DevelopedSourceFlight(task: task, token: token)
            }
            let image = await task.value
            guard let image else {
                if thumbnail {
                    if thumbnailDevelopedSourceFlights[key]?.token == token {
                        thumbnailDevelopedSourceFlights.removeValue(forKey: key)
                    }
                } else if developedSourceFlights[key]?.token == token {
                    developedSourceFlights.removeValue(forKey: key)
                }
                return nil
            }
            let isCurrentFlight: Bool
            if thumbnail {
                isCurrentFlight = thumbnailDevelopedSourceFlights[key]?.token == token
                if isCurrentFlight { thumbnailDevelopedSourceFlights.removeValue(forKey: key) }
            } else {
                isCurrentFlight = developedSourceFlights[key]?.token == token
                if isCurrentFlight { developedSourceFlights.removeValue(forKey: key) }
            }
            if isCurrentFlight {
                cache.insert(
                    image, for: key,
                    cost: estimatedByteCost(extent: image.extent.integral, bytesPerPixel: 4)
                )
            }
            return image
        }

        return await Task.detached(priority: .userInitiated) { () -> CIImage? in
            guard !Task.isCancelled else { return nil }
            return RenderPipeline.developedSource(
                source, rawDevelop: rawDevelop, scale: scale, rotation: rotation
            )
        }.value
    }

    private struct MaskPayloadWork: Sendable {
        let key: LocalMaskCacheKey
        let component: MaskComponent
        let targetSize: PixelDimensions
        let definitionHash: String
        let request: LocalMaskResolveRequest
        let isSemantic: Bool
    }

    /// Resolve and compose only the layers that can affect pixels. The component cache is keyed by
    /// source and mask definition, never by the document's global look, so slider edits reuse the
    /// same bounded payloads. Core Image objects are created only after the value-only resolver
    /// returns and remain inside this actor.
    private func resolveMaskPayloads(
        for layers: [LocalAdjustmentLayer],
        source: ImageSource,
        extent: CGRect,
        quality: RenderQuality,
        transform: LocalMaskRenderTransform,
        assetID: PhotoAssetID?,
        requestRevision: UInt64,
        maskIdentity: String?,
        documentIdentity: String?,
        resolveSemanticMasks: Bool,
        includeIdentity: Bool,
        onlyComponentID: UUID?
    ) async throws -> ([LocalMaskCacheKey: LocalMaskPayload], Set<LocalMaskCacheKey>) {
        var payloads: [LocalMaskCacheKey: LocalMaskPayload] = [:]
        var pending: [MaskPayloadWork] = []
        var pendingKeys: Set<LocalMaskCacheKey> = []
        var duplicateKeys: Set<LocalMaskCacheKey> = []

        for layer in layers where includeIdentity ? layer.isEnabled : layer.hasVisibleLook {
            guard resolveSemanticMasks || layer.allowsDeferredSemanticPreview else { continue }
            for component in layer.components where component.isUsable
                && (onlyComponentID == nil || component.id == onlyComponentID) {
                if !resolveSemanticMasks, component.source.semanticDefinition != nil { continue }
                let definitionHash = RenderCacheHash.digest(component.source)
                let targetSize = maskTargetSize(for: component, extent: extent, quality: quality)
                let key = LocalMaskCacheKey(
                    source: RenderSourceFingerprint(source), definitionHash: definitionHash,
                    targetSize: targetSize, quality: quality, transform: transform,
                    rendererVersion: LocalMaskRenderer.version
                )
                guard pendingKeys.insert(key).inserted else {
                    duplicateKeys.insert(key)
                    continue
                }
                if let cached = localMaskCache.value(for: key) {
                    payloads[key] = cached
                    continue
                }
                pending.append(MaskPayloadWork(
                    key: key, component: component, targetSize: targetSize,
                    definitionHash: definitionHash,
                    request: LocalMaskResolveRequest(
                        source: source, assetID: assetID, component: component,
                        targetSize: targetSize, quality: quality, transform: transform
                    ),
                    isSemantic: component.source.semanticDefinition != nil
                ))
            }
        }

        guard !pending.isEmpty else { return (payloads, duplicateKeys) }
        let resolver = localMaskResolver
        try await withThrowingTaskGroup(of: (LocalMaskCacheKey, LocalMaskPayload).self) { group in
            for work in pending {
                group.addTask { [weak self] in
                    guard let self else { throw CancellationError() }
                    do {
                        let payload: LocalMaskPayload
                        if work.isSemantic, requestRevision > 0, let maskIdentity {
                            payload = try await self.resolveSemanticMask(
                                work.request, sourceKey: source.cacheFingerprint,
                                maskIdentity: maskIdentity
                            )
                        } else {
                            payload = try await resolver.resolve(work.request)
                        }
                        return (work.key, payload)
                    } catch is CancellationError {
                        throw CancellationError()
                    }
                }
            }
            for try await (key, payload) in group {
                try Task.checkCancellation()
                guard isCurrentMaskRequest(
                    source: source, revision: requestRevision,
                    maskIdentity: maskIdentity, documentIdentity: documentIdentity
                ) else { throw LocalMaskResolutionError.cancelled }
                localMaskCache.insert(payload, for: key, cost: payload.estimatedCostBytes)
                payloads[key] = payload
            }
        }
        return (payloads, duplicateKeys)
    }

    private func resolvedLocalMasks(
        for layers: [LocalAdjustmentLayer],
        source: ImageSource,
        extent: CGRect,
        maskExtent: CGRect? = nil,
        quality: RenderQuality,
        transform: LocalMaskRenderTransform,
        assetID: PhotoAssetID?,
        requestRevision: UInt64,
        maskIdentity: String? = nil,
        documentIdentity: String? = nil,
        resolveSemanticMasks: Bool = true,
        includeIdentity: Bool = false,
        onlyComponentID: UUID? = nil
    ) async throws -> ResolvedLocalMaskSet {
        guard !layers.isEmpty,
              extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0,
              extent.width <= CGFloat(Int.max), extent.height <= CGFloat(Int.max)
        else { return ResolvedLocalMaskSet(images: [:], cacheIdentity: nil) }

        // Mask definitions are normalized in the complete oriented source. An ROI changes the
        // upstream image extent, but it must not change the coordinate system used to resolve or
        // rasterize those definitions. Render the mask in the complete frame and clip it back to
        // the working extent only after its source-space coverage has been established.
        let renderExtent = maskExtent ?? extent
        let (payloads, duplicateKeys) = try await resolveMaskPayloads(
            for: layers, source: source, extent: renderExtent, quality: quality,
            transform: transform, assetID: assetID, requestRevision: requestRevision,
            maskIdentity: maskIdentity, documentIdentity: documentIdentity,
            resolveSemanticMasks: resolveSemanticMasks, includeIdentity: includeIdentity,
            onlyComponentID: onlyComponentID
        )
        var result: [UUID: CIImage] = [:]
        var composedKeys: Set<LocalMaskCacheKey> = []
        var payloadVersions: [String] = []
        let hasSemanticMask = layers.contains { layer in
            layer.hasVisibleLook && layer.components.contains {
                $0.isUsable && $0.source.semanticDefinition != nil
            }
        }
        for layer in layers where includeIdentity ? layer.isEnabled : layer.hasVisibleLook {
            try Task.checkCancellation()
            // The deferred first frame omits semantic components, which only stays a *refinement*
            // while the semantics-free mask is a subset of the resolved one. A layer that would
            // over-apply without its semantic components is left out of the base frame entirely,
            // so the refinement adds its look rather than retracting it.
            if !resolveSemanticMasks, !layer.allowsDeferredSemanticPreview { continue }
            guard isCurrentMaskRequest(
                source: source, revision: requestRevision,
                maskIdentity: maskIdentity, documentIdentity: documentIdentity
            ) else {
                throw LocalMaskResolutionError.cancelled
            }
            var effective: CIImage?
            for component in layer.components where component.isUsable
                && (onlyComponentID == nil || component.id == onlyComponentID) {
                if !resolveSemanticMasks, component.source.semanticDefinition != nil { continue }
                let definitionHash = RenderCacheHash.digest(component.source)
                let componentTargetSize = maskTargetSize(
                    for: component, extent: renderExtent, quality: quality
                )
                let key = LocalMaskCacheKey(
                    source: RenderSourceFingerprint(source), definitionHash: definitionHash,
                    targetSize: componentTargetSize, quality: quality, transform: transform,
                    rendererVersion: LocalMaskRenderer.version
                )
                guard let payload = payloads[key] else {
                    throw LocalMaskResolutionError.invalidPayload
                }
                if component.source.semanticDefinition != nil {
                    payloadVersions.append(component.id.uuidString + ":" + payload.cacheFingerprint)
                }
                if duplicateKeys.contains(key), !composedKeys.insert(key).inserted {
                    // Preserve the cache accounting/behavior of the old in-order resolver: a
                    // second identical component is a cache hit even when its first resolution
                    // was coalesced into the concurrent value phase above.
                    _ = localMaskCache.value(for: key)
                }

                // The resolver is allowed to suspend. A newer request for this source may have
                // superseded it while it was waiting; never turn that late value into a CI graph.
                guard isCurrentMaskRequest(
                    source: source, revision: requestRevision,
                    maskIdentity: maskIdentity, documentIdentity: documentIdentity
                ) else {
                    throw LocalMaskResolutionError.cancelled
                }

                guard (payload.assetID == nil
                       || payload.assetID == (assetID ?? PhotoAnalysisCoordinator.assetID(for: source))),
                      payload.sourceFingerprint == source.cacheFingerprint,
                      (payload.definitionHash.isEmpty || payload.definitionHash == definitionHash),
                      payload.targetSize == componentTargetSize,
                      payload.quality == quality,
                      !payload.providerVersion.isEmpty else {
                    throw LocalMaskResolutionError.sourceMismatch
                }

                guard let image = localMaskRenderer.image(
                    for: payload, extent: renderExtent, transform: transform
                ) else { throw LocalMaskResolutionError.invalidPayload }
                var componentImage = image.cropped(to: extent)
                if component.isInverted {
                    componentImage = localMaskRenderer.inverted(componentImage, extent: extent)
                }
                if let current = effective {
                    effective = localMaskRenderer.combined(
                        current, with: componentImage,
                        mode: onlyComponentID == nil ? component.mode : .replace, extent: extent
                    )
                } else {
                    // A first subtract/intersect component is defined against an empty mask, so
                    // composition remains deterministic regardless of component ordering.
                    effective = localMaskRenderer.combined(
                        localMaskRenderer.emptyMask(extent: extent), with: componentImage,
                        mode: onlyComponentID == nil ? component.mode : .replace, extent: extent
                    )
                }
            }
            guard var mask = effective else { continue }
            if layer.isInverted { mask = localMaskRenderer.inverted(mask, extent: extent) }
            result[layer.id] = mask
        }
        let cacheIdentity: MaskRasterCacheIdentity? = hasSemanticMask ? MaskRasterCacheIdentity(
            resolutionState: resolveSemanticMasks
                ? "resolved"
                : "deferred:\(requestRevision)",
            payloadVersion: RenderCacheHash.digest(payloadVersions.sorted())
        ) : nil
        return ResolvedLocalMaskSet(images: result, cacheIdentity: cacheIdentity)
    }

    private func maskTargetSize(
        for component: MaskComponent, extent: CGRect, quality: RenderQuality
    ) -> PixelDimensions {
        let fullSize = PixelDimensions(width: Int(extent.width), height: Int(extent.height))
        guard quality.maskQuality == .preview,
              case .semantic = component.source else { return fullSize }
        return SemanticMaskPreviewResolution.targetSize(
            for: fullSize, cap: semanticMaskPreviewCap
        )
    }

    private func noteMaskRequest(source: ImageSource, revision: UInt64) {
        revisionLedger.noteOverlayMaskRequest(sourceKey: source.cacheFingerprint, revision: revision)
    }

    private func beginRenderRequest(_ request: RenderRequest) {
        revisionLedger.beginRenderRequest(
            sourceKey: request.source.cacheFingerprint, revision: request.requestRevision
        )
    }

    private func endRenderRequest(_ request: RenderRequest) {
        revisionLedger.endRenderRequest(
            sourceKey: request.source.cacheFingerprint, revision: request.requestRevision
        )
    }

    private func isCurrentRenderRequest(_ request: RenderRequest) -> Bool {
        revisionLedger.isCurrentRenderRequest(
            sourceKey: request.source.cacheFingerprint, revision: request.requestRevision
        )
    }

    private func noteMaskRequest(
        source: ImageSource, revision: UInt64, maskIdentity: String, documentIdentity: String
    ) {
        guard revision > 0 else { return }
        let sourceKey = source.cacheFingerprint
        if activeRevisionedMaskSource != sourceKey {
            cancelSemanticMaskResolutions { $0.sourceKey != sourceKey }
            activeRevisionedMaskSource = sourceKey
        }
        let recipeChanged = revisionLedger.beginMaskRequest(
            sourceKey: sourceKey, revision: revision,
            maskIdentity: maskIdentity, documentIdentity: documentIdentity
        )
        if recipeChanged {
            cancelSemanticMaskResolutions {
                $0.sourceKey == sourceKey && $0.maskIdentity != maskIdentity
            }
        }
    }

    /// Run a revisioned semantic resolve in an explicitly cancellable waiter task. A global-look
    /// edit has the same `maskIdentity`, so it attaches another waiter to the coordinator's shared
    /// provider task instead of cancelling or restarting Vision. Source and recipe changes cancel
    /// the old waiter from `noteMaskRequest` above.
    private func resolveSemanticMask(
        _ request: LocalMaskResolveRequest, sourceKey: String, maskIdentity: String
    ) async throws -> LocalMaskPayload {
        let id = UUID()
        let resolver = localMaskResolver
        let task = Task { try await resolver.resolve(request) }
        inFlightSemanticMaskResolutions[id] = InFlightSemanticMaskResolution(
            sourceKey: sourceKey, maskIdentity: maskIdentity, task: task
        )
        defer { inFlightSemanticMaskResolutions.removeValue(forKey: id) }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func cancelSemanticMaskResolutions(
        where shouldCancel: (InFlightSemanticMaskResolution) -> Bool
    ) {
        for resolution in inFlightSemanticMaskResolutions.values where shouldCancel(resolution) {
            resolution.task.cancel()
        }
    }

    private func cancelAllSemanticMaskResolutions() {
        for resolution in inFlightSemanticMaskResolutions.values {
            resolution.task.cancel()
        }
        inFlightSemanticMaskResolutions.removeAll(keepingCapacity: true)
        activeRevisionedMaskSource = nil
    }

    /// Current bounded semantic-mask source keys retained by the renderer. This snapshot is
    /// intentionally value-only so diagnostics cannot expose renderer internals.
    var diagnosticsSnapshot: RenderEngineDiagnosticsSnapshot {
        RenderEngineDiagnosticsSnapshot(
            trackedMaskSourceKeys: revisionLedger.trackedMaskSourceKeys,
            trackedRenderSourceCount: revisionLedger.trackedRenderSourceCount,
            trackedMaskRequestCount: revisionLedger.trackedMaskRequestCount,
            cachedFilterCount: lutCache.count
        )
    }

    private func isCurrentMaskRequest(
        source: ImageSource, revision: UInt64,
        maskIdentity: String? = nil, documentIdentity: String? = nil
    ) -> Bool {
        let sourceKey = source.cacheFingerprint
        guard let maskIdentity, let documentIdentity else {
            return revisionLedger.isCurrentOverlayMaskRequest(sourceKey: sourceKey, revision: revision)
        }
        return revisionLedger.isCurrentMaskRequest(
            sourceKey: sourceKey, revision: revision,
            maskIdentity: maskIdentity, documentIdentity: documentIdentity
        )
    }

    private struct MaterializedImage {
        let image: CIImage
        let costBytes: Int
    }

    private struct PrefixMaterializationFlight {
        let task: Task<MaterializedImage?, Never>
        let token: UInt64
    }

    private struct DevelopedSourceFlight {
        let task: Task<CIImage?, Never>
        let token: UInt64
    }

    private struct MaterializationEstimate {
        let rowBytes: Int
        let cpuBytes: Int
        let gpuBytes: Int

        var workingSetBytes: Int {
            cpuBytes > Int.max - gpuBytes ? Int.max : cpuBytes + gpuBytes
        }
    }

    /// Complete a prefix directly into a private Metal texture. This is deliberately separate from
    /// `materializedImage`: the latter is the CPU fallback seam used by software/injected contexts,
    /// while this path never allocates a bitmap or calls `CIContext.render(toBitmap:)`.
    private func materializedPrefixImage(
        _ image: CIImage,
        space: WorkingSpace,
        maxWorkingSetBytes: Int
    ) async -> MaterializedImage? {
        let rect = image.extent.integral
        guard rect.isRasterizable,
              rect.width <= CGFloat(Int.max), rect.height <= CGFloat(Int.max),
              rect.width > 0, rect.height > 0 else { return nil }
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard let estimate = materializationEstimate(width: width, height: height) else {
            return nil
        }
        guard maxWorkingSetBytes > 0, estimate.workingSetBytes <= maxWorkingSetBytes else {
            // Keep the conservative working-set admission used by the existing cache. It avoids
            // admitting a prefix whose GPU allocation would leave no room for Core Image's
            // transient source-side work, while the retained cache cost below is texture-only.
            materializationBudgetSkipCount += 1
            return nil
        }

        guard let commandQueue, let texture = resources.makeProcessingTexture(
            width: width, height: height
        ) else {
            // The injected/software context has no renderer-owned Metal queue. Preserve the
            // established CPU fallback, including its working-space tag and origin.
            processingPrefixCPUReadbackCount += 1
            return materializedImage(
                image, space: space, maxWorkingSetBytes: maxWorkingSetBytes
            )
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return nil }
        processingPrefixTextureSubmissionCount += 1
        context.render(
            image, to: texture, commandBuffer: commandBuffer, bounds: rect,
            colorSpace: space.cgColorSpace
        )
        guard await commitAndWaitForCompletion(commandBuffer), !Task.isCancelled,
              let textureImage = CIImage(
                  mtlTexture: texture, options: [.colorSpace: space.cgColorSpace]
              ) else {
            return nil
        }
        let positioned = rect.origin == .zero
            ? textureImage
            : textureImage.transformed(by: CGAffineTransform(
                translationX: rect.minX, y: rect.minY
            ))
        // The cached value retains the private texture. Count only the retained GPU allocation;
        // the CPU bitmap path remains available only as a fallback.
        return MaterializedImage(image: positioned, costBytes: estimate.gpuBytes)
    }

    /// Complete a prefix at half-float precision so later graph construction cannot pull the RAW
    /// decoder or expensive spatial nodes back into the next LUT/grain evaluation. This is a
    /// bounded, preview-only boundary; full-resolution/export requests stay on the original fused
    /// graph and never pay for an intermediate readback.
    private func materializedImage(
        _ image: CIImage,
        space: WorkingSpace,
        maxWorkingSetBytes: Int
    ) -> MaterializedImage? {
        let rect = image.extent.integral
        guard rect.isRasterizable,
              rect.width <= CGFloat(Int.max), rect.height <= CGFloat(Int.max),
              rect.width > 0, rect.height > 0 else { return nil }
        let width = Int(rect.width)
        let height = Int(rect.height)
        guard let estimate = materializationEstimate(width: width, height: height) else {
            return nil
        }
        guard maxWorkingSetBytes > 0, estimate.workingSetBytes <= maxWorkingSetBytes else {
            // Above-budget images stay on the caller's lazy/fused path. In particular, do not
            // allocate the CPU bitmap just to let BoundedLRUCache reject it after the fact.
            materializationBudgetSkipCount += 1
            return nil
        }

        // `bounds` is the complete integral extent and `rowBytes` is exactly width * 8 for
        // RGBA16Float, so Core Image writes every byte in this allocation before the bitmap is
        // wrapped in a CIImage. Keep the pointer scoped to this actor-local render call; Data takes
        // ownership only after rendering has completed and releases it with `deallocate()`.
        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: estimate.cpuBytes, alignment: MemoryLayout<UInt16>.alignment
        )
        context.render(
            image, toBitmap: buffer, rowBytes: estimate.rowBytes, bounds: rect,
            format: .RGBAh, colorSpace: space.cgColorSpace
        )
        let data = Data(
            bytesNoCopy: buffer, count: estimate.cpuBytes,
            deallocator: .custom { pointer, _ in pointer.deallocate() }
        )
        let image = CIImage(
            bitmapData: data, bytesPerRow: estimate.rowBytes, size: rect.size,
            format: .RGBAh, colorSpace: space.cgColorSpace
        )
        let positioned = rect.origin == .zero
            ? image
            : image.transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return MaterializedImage(image: positioned, costBytes: estimate.workingSetBytes)
    }

    private func materializationEstimate(width: Int, height: Int) -> MaterializationEstimate? {
        guard width > 0, height > 0 else { return nil }
        let pixels = width.multipliedReportingOverflow(by: height)
        guard !pixels.overflow else { return nil }
        let rowBytes = width.multipliedReportingOverflow(by: 8)
        guard !rowBytes.overflow else { return nil }
        let cpuBytes = pixels.partialValue.multipliedReportingOverflow(by: 8)
        guard !cpuBytes.overflow else { return nil }
        let gpuBytes = pixels.partialValue.multipliedReportingOverflow(by: 8)
        guard !gpuBytes.overflow else {
            return MaterializationEstimate(
                rowBytes: rowBytes.partialValue, cpuBytes: cpuBytes.partialValue, gpuBytes: Int.max
            )
        }
        // The completed prefix is retained as an RGBA16Float CIImage and can be consumed by a
        // Metal-backed downstream render. Reserve the corresponding GPU footprint in the same
        // admission decision, with saturating arithmetic for hostile or synthetic dimensions.
        return MaterializationEstimate(
            rowBytes: rowBytes.partialValue,
            cpuBytes: cpuBytes.partialValue,
            gpuBytes: gpuBytes.partialValue
        )
    }

    private func processingPrefix(
        source: ImageSource,
        document: EditDocument,
        developed: CIImage,
        scale: RenderScale,
        sourceROI: CGRect?,
        spatialReferenceExtent: CGRect,
        space: WorkingSpace,
        includePostRenderWhiteBalance: Bool,
        quality: RenderQuality
    ) async -> CIImage? {
        let key = ProcessingPrefixCacheKey(
            source: RenderSourceFingerprint(source),
            developHash: RenderCacheHash.digest(document.rawDevelop),
            upstreamHash: prefixDocumentHash(
                document, includePostRenderWhiteBalance: includePostRenderWhiteBalance
            ),
            scale: RenderScaleKey(scale, nativeExtent: source.nativeExtent),
            sourceROI: sourceROI,
            space: space,
            includePostRenderWhiteBalance: includePostRenderWhiteBalance,
            pipelineVersion: RenderPipeline.cacheVersion
        )
        if let flight = processingPrefixFlights[key] {
            return await flight.task.value?.image
        }
        if let cached = processingPrefixCache.value(for: key) {
            KromoraObservability.event(.cacheHit, source: source, quality: quality,
                                    detail: "layer=processingPrefix")
            return cached
        }
        KromoraObservability.event(.cacheMiss, source: source, quality: quality,
                                detail: "layer=processingPrefix")

        let prefix = RenderPipeline.buildPreLUTImage(
            developed: developed, document: document, toneCurveCache: toneCurveCache,
            includePostRenderWhiteBalance: includePostRenderWhiteBalance,
            spatialReferenceExtent: spatialReferenceExtent
        )
        nextPrefixFlightToken &+= 1
        let token = nextPrefixFlightToken
        let task = Task { [self] in
            await materializedPrefixImage(
                prefix, space: space,
                maxWorkingSetBytes: resources.configuration.processingPrefixMaxCostBytes
            )
        }
        processingPrefixFlights[key] = PrefixMaterializationFlight(task: task, token: token)
        let completed = await task.value
        let completionHook = processingPrefixCompletionHook
        processingPrefixCompletionHook = nil
        await completionHook?()
        if processingPrefixFlights[key]?.token == token {
            processingPrefixFlights.removeValue(forKey: key)
            if let completed {
                processingPrefixMaterializationCount += 1
                processingPrefixCache.insert(completed.image, for: key, cost: completed.costBytes)
            }
        }
        return completed?.image
    }

    /// Materialize the graph after local adjustments when semantic masks participate in a
    /// preview. The payload identity is collected only after resolution, so a deferred frame can
    /// never occupy the settled-mask slot. Global edits remain in `upstreamHash`; the developed
    /// source and every resolved component can still be reused independently on the next tick.
    private func postLocalProcessingPrefix(
        source: ImageSource,
        document: EditDocument,
        localAdjusted: CIImage,
        scale: RenderScale,
        sourceROI: CGRect?,
        space: WorkingSpace,
        includePostRenderWhiteBalance: Bool,
        quality: RenderQuality,
        cacheIdentity: MaskRasterCacheIdentity
    ) async -> CIImage {
        let key = ProcessingPrefixCacheKey(
            source: RenderSourceFingerprint(source),
            developHash: RenderCacheHash.digest(document.rawDevelop),
            upstreamHash: prefixDocumentHash(
                document, includePostRenderWhiteBalance: includePostRenderWhiteBalance
            ),
            stage: .postLocal,
            localAdjustmentsHash: RenderCacheHash.digest(document.localAdjustments),
            maskResolutionState: cacheIdentity.resolutionState,
            maskPayloadVersion: cacheIdentity.payloadVersion,
            scale: RenderScaleKey(scale, nativeExtent: source.nativeExtent),
            sourceROI: sourceROI,
            space: space,
            includePostRenderWhiteBalance: includePostRenderWhiteBalance,
            pipelineVersion: RenderPipeline.cacheVersion
        )
        if let flight = processingPrefixFlights[key] {
            return await flight.task.value?.image ?? localAdjusted
        }
        if let cached = processingPrefixCache.value(for: key) {
            KromoraObservability.event(.cacheHit, source: source, quality: quality,
                                    detail: "layer=postLocalProcessingPrefix state=\(cacheIdentity.resolutionState)")
            return cached
        }
        KromoraObservability.event(.cacheMiss, source: source, quality: quality,
                                detail: "layer=postLocalProcessingPrefix state=\(cacheIdentity.resolutionState)")

        nextPrefixFlightToken &+= 1
        let token = nextPrefixFlightToken
        let task = Task { [self] in
            await materializedPrefixImage(
                localAdjusted, space: space,
                maxWorkingSetBytes: resources.configuration.processingPrefixMaxCostBytes
            )
        }
        processingPrefixFlights[key] = PrefixMaterializationFlight(task: task, token: token)
        let completed = await task.value
        let completionHook = processingPrefixCompletionHook
        processingPrefixCompletionHook = nil
        await completionHook?()
        if processingPrefixFlights[key]?.token == token {
            processingPrefixFlights.removeValue(forKey: key)
            if let completed {
                processingPrefixMaterializationCount += 1
                processingPrefixCache.insert(completed.image, for: key, cost: completed.costBytes)
            }
        }
        return completed?.image ?? localAdjusted
    }

    private func prefixDocumentHash(
        _ document: EditDocument,
        includePostRenderWhiteBalance: Bool
    ) -> String {
        let adjustments = includePostRenderWhiteBalance
            ? document.adjustments
            : document.adjustments.filter {
                if case .temperatureTint = $0 { return false }
                return true
            }
        return RenderCacheHash.digest(EditDocument(
            version: document.version, rawDevelop: .neutral, light: document.light,
            color: document.color,
            effects: EffectsAdjustments(
                texture: document.effects.texture, clarity: document.effects.clarity,
                dehaze: document.effects.dehaze
            ), crop: .neutral, adjustments: adjustments, lut: .none
        ))
    }

    // MARK: - The developed-source cache

    /// The source stage, cached for **preview** renders.
    ///
    /// This exists for one measured reason. Core Image caches decoded intermediates against the
    /// `CIImage` instance, so handing it a freshly-built source every render means re-decoding the
    /// file every render. Measured per preview render, rebuilding versus reusing:
    ///
    /// | source | rebuild | reuse |
    /// |---|---|---|
    /// | 30 MB DNG | 63 ms | 0.7 ms |
    /// | 6000×4000 | 156 ms | 0.6 ms |
    ///
    /// An intensity drag is many renders, so without this the cutover would be a plainly visible
    /// regression — the one thing Step 5 must not ship.
    ///
    /// **Only preview scales are memoized.** Export runs once per user action, so it has nothing to
    /// gain, and holding a full-resolution developed image between exports would pin Core Image's
    /// full-resolution intermediates for as long as the engine lives.
    ///
    /// Several entries are retained so stepping back through a folder can hit, but both a count and
    /// an estimated decoded-byte limit keep a long navigation session bounded.
    private func developedSource(
        _ source: ImageSource,
        _ rawDevelop: RAWDevelopSettings,
        _ scale: RenderScale,
        rotation: ImageRotation = .zero,
        space: WorkingSpace,
        interactive: Bool = false,
        thumbnail: Bool = false
    ) -> CIImage? {
        let canUsePreparedSession = source.kind == .raw && !scale.isFull &&
            (interactive || interactiveRAWSession?.fingerprint == source.decoderFingerprint)
        if canUsePreparedSession {
            let fingerprint = source.decoderFingerprint
            let reused = interactiveRAWSession?.fingerprint == fingerprint
            guard let session = session(for: source) else { return nil }
            KromoraObservability.event(
                reused ? .cacheHit : .cacheMiss, source: source, quality: .interactive,
                detail: "layer=interactiveRAWFilter reused=\(reused)"
            )
            let result = session.output(
                rawDevelop: rawDevelop, scale: scale, rotation: rotation,
                materialize: { [self] image in
                    materializedImage(
                        image, space: space,
                        maxWorkingSetBytes: resources.configuration.developedSourceMaxCostBytes
                    )?.image
                }
            )
            rawPropertyWriteCount += result.propertyWrites
            if result.requestedOutput { rawOutputRequestCount += 1 }
            return result.image
        }
        guard !scale.isFull else {
            return RenderPipeline.developedSource(
                source, rawDevelop: rawDevelop, scale: scale, rotation: rotation
            )
        }
        let key = DevelopedSourceCacheKey(
            source: RenderSourceFingerprint(source),
            developHash: RenderCacheHash.digest(rawDevelop),
            scale: RenderScaleKey(
                scale, nativeExtent: rotation.orientedExtent(source.nativeExtent)
            ),
            pipelineVersion: RenderPipeline.cacheVersion
        )
        let cache = thumbnail ? thumbnailDevelopedSourceCache : developedSourceCache
        var cacheInterval = KromoraObservability.begin(.cache, source: source, quality: .preview)
        let cachedImage = cache.value(for: key)
        cacheInterval.end()
        if let image = cachedImage {
            KromoraObservability.event(.cacheHit, source: source, quality: .preview,
                                    detail: "layer=developedSource")
            return image
        }

        KromoraObservability.event(.cacheMiss, source: source, quality: .preview,
                                detail: "layer=developedSource")

        var decodeInterval = KromoraObservability.begin(.decode, source: source, quality: .preview)
        defer { decodeInterval.end() }

        guard let image = RenderPipeline.developedSource(
            source, rawDevelop: rawDevelop, scale: scale, rotation: rotation
        ) else { return nil }

        // RAW output is mutable-filter-backed. Complete it before putting it in the settled cache,
        // otherwise a later render can ask Core Image to evaluate the same decoder graph again.
        if source.kind == .raw {
            if let completed = materializedImage(
                image, space: space,
                maxWorkingSetBytes: resources.configuration.developedSourceMaxCostBytes
            ) {
                cache.insert(completed.image, for: key, cost: completed.costBytes)
                return completed.image
            }
            // A lazy RAW output is backed by a decoder graph whose full working set is unknown to
            // this cache. If the completed half-float form did not fit, keep this request-local
            // output out of the settled cache rather than admitting it with an optimistic RGBA8
            // estimate.
            return image
        }

        let extent = image.extent.integral
        let byteCount = estimatedByteCost(extent: extent, bytesPerPixel: 4)
        cache.insert(image, for: key, cost: byteCount)
        return image
    }

    private func estimatedByteCost(extent: CGRect, bytesPerPixel: Int) -> Int {
        guard extent.width > 0, extent.height > 0,
              extent.width <= CGFloat(Int.max), extent.height <= CGFloat(Int.max) else {
            return Int.max
        }
        let width = Int(extent.width)
        let height = Int(extent.height)
        let row = width.multipliedReportingOverflow(by: max(0, bytesPerPixel))
        guard !row.overflow else { return Int.max }
        let total = row.partialValue.multipliedReportingOverflow(by: height)
        return total.overflow ? Int.max : total.partialValue
    }

    /// Drop the developed-source memo. Not needed for correctness — the key covers every input — but
    /// it lets a caller release the intermediates when no image is on screen.
    func invalidateSourceCache() {
        cancelAllSemanticMaskResolutions()
        cancelProcessingPrefixFlights()
        revisionLedger.removeAll()
        developedSourceCache.removeAll()
        thumbnailDevelopedSourceCache.removeAll()
        processingPrefixCache.removeAll()
        localMaskCache.removeAll()
        localMaskRenderer.removeAllCachedBrushStrokes()
        interactiveRAWSession = nil
        toneCurveCache.removeAll()
        toneCurveSource = nil
        toneCurveSpace = nil
    }

    /// A reusable actor-local RAW filter for the short-lived interactive tier. The baseline values
    /// are captured once because applying an optional setting cannot undo a value written on the
    /// previous tick (`nil` means decoder default, not "clear this mutable filter property").
    ///
    /// Not `private`: `RenderEngine+RAWCapabilities.swift` (KRMA-530) constructs and reads this
    /// type too, and `private` is file-scoped rather than type-scoped.
    final class InteractiveRAWFilterSession {
        struct OutputResult {
            let image: CIImage?
            let propertyWrites: Int
            let requestedOutput: Bool
        }

        private struct OutputKey: Equatable {
            let sourceRevision: String
            let developHash: String
            let scale: RenderScaleKey
        }

        // Not `private`: read from `RenderEngine+RAWCapabilities.swift`'s `session(for:)`.
        let fingerprint: String
        private let filter: CIRAWFilter
        private let baseline: RAWFilterBaseline
        private let capturedCapabilities: RAWCapabilities
        private let orientation: CGImagePropertyOrientation
        private var appliedSettings: RAWDevelopSettings?
        private var appliedScaleFactor: Float?
        private var cachedOutputKey: OutputKey?
        private var cachedOutput: CIImage?

        var nativeSize: CGSize { filter.nativeSize }
        /// Display dimensions: sensor size with the EXIF orientation's axis swap applied.
        var orientedNativeSize: CGSize {
            ImageDecoder.orientedDimensions(filter.nativeSize, for: orientation)
        }

        init?(source: ImageSource) {
            guard let filter = RenderPipeline.rawFilter(for: source.backing) else { return nil }
            let orientation = RenderPipeline.rawOrientation(for: source.backing)
            guard ImageDecoder.developedImage(from: filter, orientation: orientation) != nil else {
                return nil
            }
            self.fingerprint = source.decoderFingerprint
            self.filter = filter
            self.baseline = RAWFilterBaseline(filter: filter)
            self.capturedCapabilities = Self.captureCapabilities(filter)
            // The file fingerprint owns invalidation if the tag changes underneath us.
            self.orientation = orientation
        }

        func capabilities() -> RAWCapabilities {
            capturedCapabilities
        }

        private static func captureCapabilities(_ filter: CIRAWFilter) -> RAWCapabilities {
            var highlightRecovery = false
            if #available(macOS 26, *) {
                highlightRecovery = filter.isHighlightRecoverySupported
            }
            return RAWCapabilities(
                isSharpnessSupported: filter.isSharpnessSupported,
                isContrastSupported: filter.isContrastSupported,
                isDetailSupported: filter.isDetailSupported,
                isMoireReductionSupported: filter.isMoireReductionSupported,
                isLocalToneMapSupported: filter.isLocalToneMapSupported,
                isLuminanceNoiseReductionSupported: filter.isLuminanceNoiseReductionSupported,
                isColorNoiseReductionSupported: filter.isColorNoiseReductionSupported,
                isLensCorrectionSupported: filter.isLensCorrectionSupported,
                isHighlightRecoverySupported: highlightRecovery,
                asShotTemperature: Double(filter.neutralTemperature),
                asShotTint: Double(filter.neutralTint),
                baselineExposure: Double(filter.baselineExposure),
                shadowBias: Double(filter.shadowBias),
                sharpnessAmount: filter.isSharpnessSupported ? Double(filter.sharpnessAmount) : 0,
                contrastAmount: filter.isContrastSupported ? Double(filter.contrastAmount) : 0,
                detailAmount: filter.isDetailSupported ? Double(filter.detailAmount) : 0,
                moireReductionAmount:
                    filter.isMoireReductionSupported ? Double(filter.moireReductionAmount) : 0,
                localToneMapAmount:
                    filter.isLocalToneMapSupported ? Double(filter.localToneMapAmount) : 0,
                luminanceNoiseReductionAmount: filter.isLuminanceNoiseReductionSupported
                    ? Double(filter.luminanceNoiseReductionAmount) : 0,
                colorNoiseReductionAmount: filter.isColorNoiseReductionSupported
                    ? Double(filter.colorNoiseReductionAmount) : 0,
                lensCorrectionEnabled:
                    filter.isLensCorrectionSupported ? filter.isLensCorrectionEnabled : false
            )
        }

        func output(
            rawDevelop: RAWDevelopSettings,
            scale: RenderScale,
            rotation: ImageRotation = .zero,
            materialize: (CIImage) -> CIImage?
        ) -> OutputResult {
            // The scale factor is computed from the display size so a quarter-turned sensor
            // fits the preview box the same way the settled path does. The filter already
            // orients `outputImage`; a second bake would turn portrait RAWs back to landscape.
            let orientedSize = rotation.orientedExtent(
                ImageDecoder.orientedDimensions(filter.nativeSize, for: orientation)
            )
            let factor = scale.factor(for: orientedSize)
            let key = OutputKey(
                sourceRevision: fingerprint,
                developHash: RenderCacheHash.digest(rawDevelop),
                scale: RenderScaleKey(scale, nativeExtent: orientedSize)
            )
            if cachedOutputKey == key, let cachedOutput {
                return OutputResult(image: cachedOutput, propertyWrites: 0, requestedOutput: false)
            }

            let propertyWrites = baseline.apply(
                changedFrom: appliedSettings, to: rawDevelop, filter: filter
            )
            appliedSettings = rawDevelop
            let scaleFactor = Float(factor)
            if appliedScaleFactor != scaleFactor {
                filter.scaleFactor = scaleFactor
                appliedScaleFactor = scaleFactor
            }
            guard let rawOutput = filter.outputImage else {
                return OutputResult(image: nil, propertyWrites: propertyWrites, requestedOutput: true)
            }
            let output = ImageDecoder.displayOrientedRAWOutput(
                rawOutput, sensorSize: filter.nativeSize, orientation: orientation
            )
            guard let completed = materialize(output) else {
                // The mutable filter remains correctly configured, but do not retain its lazy
                // output: a later property write could otherwise change the image behind the cache.
                cachedOutputKey = nil
                cachedOutput = nil
                return OutputResult(image: output, propertyWrites: propertyWrites, requestedOutput: true)
            }
            cachedOutputKey = key
            cachedOutput = completed
            return OutputResult(image: completed, propertyWrites: propertyWrites, requestedOutput: true)
        }
    }

    /// All mutable develop values touched by `RAWDevelopSettings.apply`. Keeping this snapshot
    /// local to the renderer makes reset semantics explicit without sharing a `CIRAWFilter` across
    /// actors or changing the settled, deterministic pipeline.
    private struct RAWFilterBaseline {
        let exposure: Float
        let baselineExposure: Float
        let shadowBias: Float
        let boostAmount: Float
        let boostShadowAmount: Float
        let neutralTemperature: Float
        let neutralTint: Float
        let gamutMappingEnabled: Bool
        let extendedDynamicRangeAmount: Float
        let sharpnessAmount: Float
        let contrastAmount: Float
        let detailAmount: Float
        let moireReductionAmount: Float
        let localToneMapAmount: Float
        let luminanceNoiseReductionAmount: Float
        let colorNoiseReductionAmount: Float
        let lensCorrectionEnabled: Bool
        let highlightRecoveryEnabled: Bool?

        init(filter: CIRAWFilter) {
            exposure = filter.exposure; baselineExposure = filter.baselineExposure
            shadowBias = filter.shadowBias; boostAmount = filter.boostAmount
            boostShadowAmount = filter.boostShadowAmount
            neutralTemperature = filter.neutralTemperature; neutralTint = filter.neutralTint
            gamutMappingEnabled = filter.isGamutMappingEnabled
            extendedDynamicRangeAmount = filter.extendedDynamicRangeAmount
            sharpnessAmount = filter.sharpnessAmount; contrastAmount = filter.contrastAmount
            detailAmount = filter.detailAmount; moireReductionAmount = filter.moireReductionAmount
            localToneMapAmount = filter.localToneMapAmount
            luminanceNoiseReductionAmount = filter.luminanceNoiseReductionAmount
            colorNoiseReductionAmount = filter.colorNoiseReductionAmount
            lensCorrectionEnabled = filter.isLensCorrectionEnabled
            if #available(macOS 26, *), filter.isHighlightRecoverySupported {
                highlightRecoveryEnabled = filter.isHighlightRecoveryEnabled
            } else { highlightRecoveryEnabled = nil }
        }

        func apply(
            changedFrom previous: RAWDevelopSettings?,
            to next: RAWDevelopSettings,
            filter: CIRAWFilter
        ) -> Int {
            var writeCount = 0
            if previous?.exposure != next.exposure {
                writeCount += 1
                filter.exposure = next.exposure.map(Float.init) ?? exposure
            }
            if previous?.baselineExposure != next.baselineExposure {
                writeCount += 1
                filter.baselineExposure = next.baselineExposure.map(Float.init) ?? baselineExposure
            }
            if previous?.shadowBias != next.shadowBias {
                writeCount += 1
                filter.shadowBias = next.shadowBias.map(Float.init) ?? shadowBias
            }
            if previous?.boostAmount != next.boostAmount {
                writeCount += 1
                filter.boostAmount = next.boostAmount.map(Float.init) ?? boostAmount
            }
            if previous?.boostShadowAmount != next.boostShadowAmount {
                writeCount += 1
                filter.boostShadowAmount = next.boostShadowAmount.map(Float.init) ?? boostShadowAmount
            }
            if previous?.neutralTemperature != next.neutralTemperature {
                writeCount += 1
                filter.neutralTemperature = next.neutralTemperature.map(Float.init) ?? neutralTemperature
            }
            if previous?.neutralTint != next.neutralTint {
                writeCount += 1
                filter.neutralTint = next.neutralTint.map(Float.init) ?? neutralTint
            }
            if previous?.gamutMappingEnabled != next.gamutMappingEnabled {
                writeCount += 1
                filter.isGamutMappingEnabled = next.gamutMappingEnabled ?? gamutMappingEnabled
            }
            if previous?.extendedDynamicRangeAmount != next.extendedDynamicRangeAmount {
                writeCount += 1
                filter.extendedDynamicRangeAmount =
                    next.extendedDynamicRangeAmount.map(Float.init) ?? extendedDynamicRangeAmount
            }
            if filter.isSharpnessSupported, previous?.sharpnessAmount != next.sharpnessAmount {
                writeCount += 1
                filter.sharpnessAmount = next.sharpnessAmount.map(Float.init) ?? sharpnessAmount
            }
            if filter.isContrastSupported, previous?.contrastAmount != next.contrastAmount {
                writeCount += 1
                filter.contrastAmount = next.contrastAmount.map(Float.init) ?? contrastAmount
            }
            if filter.isDetailSupported, previous?.detailAmount != next.detailAmount {
                writeCount += 1
                filter.detailAmount = next.detailAmount.map(Float.init) ?? detailAmount
            }
            if filter.isMoireReductionSupported, previous?.moireReductionAmount != next.moireReductionAmount {
                writeCount += 1
                filter.moireReductionAmount = next.moireReductionAmount.map(Float.init) ?? moireReductionAmount
            }
            if filter.isLocalToneMapSupported, previous?.localToneMapAmount != next.localToneMapAmount {
                writeCount += 1
                filter.localToneMapAmount = next.localToneMapAmount.map(Float.init) ?? localToneMapAmount
            }
            if filter.isLuminanceNoiseReductionSupported,
               previous?.luminanceNoiseReductionAmount != next.luminanceNoiseReductionAmount {
                writeCount += 1
                filter.luminanceNoiseReductionAmount =
                    next.luminanceNoiseReductionAmount.map(Float.init) ?? luminanceNoiseReductionAmount
            }
            if filter.isColorNoiseReductionSupported,
               previous?.colorNoiseReductionAmount != next.colorNoiseReductionAmount {
                writeCount += 1
                filter.colorNoiseReductionAmount =
                    next.colorNoiseReductionAmount.map(Float.init) ?? colorNoiseReductionAmount
            }
            if filter.isLensCorrectionSupported,
               previous?.lensCorrectionEnabled != next.lensCorrectionEnabled {
                writeCount += 1
                filter.isLensCorrectionEnabled = next.lensCorrectionEnabled ?? lensCorrectionEnabled
            }
            if previous?.highlightRecoveryEnabled != next.highlightRecoveryEnabled,
               let baseline = highlightRecoveryEnabled,
               #available(macOS 26, *), filter.isHighlightRecoverySupported {
                writeCount += 1
                filter.isHighlightRecoveryEnabled = next.highlightRecoveryEnabled ?? baseline
            }
            return writeCount
        }
    }

    private func previewCacheKey(for request: RenderRequest, scale: RenderScale) -> PreviewCacheKey? {
        guard !scale.isFull, request.output == .raster else { return nil }
        guard request.quality == .thumbnail || request.quality == .interactive || request.quality == .preview else {
            return nil
        }
        // Semantic masks can be progressive: a resolver may replace a preview payload with a
        // refined one without changing the durable document. Do not cache the final raster around
        // that resolver state; the bounded component cache still avoids repeating valid work.
        guard !request.document.localAdjustments.contains(where: { layer in
            layer.components.contains { component in
                if case .semantic = component.source { return true }
                return false
            }
        }) else { return nil }
        return PreviewCacheKey(
            source: RenderSourceFingerprint(request.source),
            documentHash: RenderCacheHash.digest(request.document),
            lutFingerprint: request.lut?.cacheFingerprint ?? "none",
            targetScale: RenderScaleKey(scale, nativeExtent: request.source.nativeExtent),
            sourceROI: request.sourceROI,
            presentationROI: request.presentationROI,
            quality: request.quality,
            space: request.space,
            pipelineVersion: RenderPipeline.cacheVersion
        )
    }

    private func installMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler(handler: { [weak self] in
            Task { await self?.evictForMemoryPressure() }
        })
        source.resume()
        memoryPressureSource = source
    }
}
