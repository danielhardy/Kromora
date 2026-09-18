import CoreImage
import MetalKit
import SwiftUI

/// GPU-owned presentation state for one preview. It is separate from AppViewModel so an
/// interactive frame does not invalidate the application's broad observation graph.
struct PreviewFrameIdentity: Equatable, Sendable {
    let sourceToken: String
    let documentHash: String
    let space: WorkingSpace
}

@MainActor
final class PreviewSurface: ObservableObject {
    /// Diagnostic count used by the presentation acceptance tests. A publication is expected to
    /// perform one Core Image materialization; retained-texture redraws must not increment it.
    @MainActor static private(set) var presentationCoreImageEvaluationCount = 0

    @MainActor static func resetPresentationCoreImageEvaluationCount() {
        presentationCoreImageEvaluationCount = 0
    }

    @MainActor static func notePresentationCoreImageEvaluation() {
        presentationCoreImageEvaluationCount += 1
    }

    @Published private(set) var revision: UInt64 = 0
    private(set) var image: CIImage?
    private(set) var presentationImageExtent: CGRect?
    /// When true, a smaller texture is a stand-in for the whole `presentationImageExtent`
    /// (a camera JPEG first frame, or a cropped fit preview whose ROI is the committed crop).
    /// Fit/Fill then fill the canvas instead of treating the texture as a top-left ROI of a
    /// larger virtual frame. Viewport-fragment ROI previews leave this false.
    private(set) var coversPresentationExtent = false
    /// Planner-space rectangle for an uncovered ROI fragment. Interactive frames can decode
    /// below the planner `targetSize`, so this is not always `image.extent`.
    private(set) var layoutImageExtent: CGRect?
    private(set) var space: WorkingSpace = .current
    /// The last image known to have made it through the presentation command buffer. Production
    /// frames are already completed texture-backed images; the confirmation still matters because
    /// drawable acquisition/presentation can fail independently of processing.
    private var lastValidImage: CIImage?
    /// The display-ready copy of `image`. It is materialized once when a new render revision is
    /// published and sampled directly by the Metal presenter for every drawable thereafter.
    private(set) var presentationTexture: MTLTexture?
    private(set) var presentationTextureExtent: CGRect?
    private(set) var presentationTextureGeneration: UInt64 = 0
    private var lastValidPresentationTexture: MTLTexture?
    private var lastValidPresentationTextureExtent: CGRect?
    private var lastValidPresentationImageExtent: CGRect?
    private var lastValidLayoutImageExtent: CGRect?
    private var lastValidCoversPresentationExtent = false
    private var lastValidSpace: WorkingSpace = .current
    /// The detail level of a published frame, plus whether that frame is the complete photo.
    /// Coverage is part of the record because a partial ROI frame is not interchangeable with a
    /// whole-photo frame of the same source and document, however sharp it is.
    private struct PublishedDetail {
        let identity: PreviewFrameIdentity
        let factor: CGFloat
        let coversPresentationExtent: Bool
    }
    private var lastValidDetail: PublishedDetail?
    private var currentDetail: PublishedDetail?
    private var pendingPresentationMaterializationRevision: UInt64?
    private var pendingPresentationMaterialization: (texture: MTLTexture, extent: CGRect)?
    private var pendingDisplayID: UInt64?
    private var pendingGPURevision: UInt64?
    /// The paused MTKView does not continuously redraw. Keep the active destination weakly so a
    /// completed publication can invalidate it immediately, even when SwiftUI does not schedule
    /// an NSViewRepresentable update for the nested surface object.
    private weak var displayView: MTKView?
    private struct PendingTelemetry {
        let telemetry: LiveEditTelemetry
        let source: ImageSource?
        let quality: RenderQuality
    }
    private var telemetryByRevision: [UInt64: PendingTelemetry] = [:]
    private var submittedTelemetryRevisions: Set<UInt64> = []
    private var skippedTelemetryRevisions: Set<UInt64> = []
    private var presentationConfirmations: [UInt64: () -> Void] = [:]
    private var hasManagedPresentationLifecycle = false
    var onPresentationFailure: (() -> Void)?

    /// Capture-host seam for hardware benchmarks: when the WindowServer reports no scan-out
    /// (`presentedTime == 0`, e.g. screen sharing or a headless capture session), a real drawable
    /// still went through the presentation lifecycle and the capture needs a timestamp. When set,
    /// such drawables are marked with this clock instead of being dropped as skipped frames.
    /// Production leaves it nil, so Metal's zero-means-skipped contract is unchanged.
    var zeroPresentedTimeFallback: (() -> TimeInterval)?

    /// The Metal view calls this when a real presentation lifecycle exists. Headless/test callers
    /// have no drawable to confirm, so `present` confirms immediately for that compatibility seam.
    /// Called by the Metal view, and by lifecycle tests that model a drawable-managed surface.
    func attachPresentationLifecycle() {
        hasManagedPresentationLifecycle = true
    }

    /// Bind the current Metal destination and request its first draw. A render can complete before
    /// SwiftUI creates the representable, so attaching the view must replay the already-published
    /// frame as well as future publications.
    func attachDisplayView(_ view: MTKView) {
        displayView = view
        view.setNeedsDisplay(view.bounds)
    }

    func detachDisplayView(_ view: MTKView) {
        if displayView === view {
            displayView = nil
        }
    }

    private func requestDisplay() {
        displayView?.setNeedsDisplay(displayView?.bounds ?? .zero)
    }

    @discardableResult
    func present(
        _ image: CIImage?, space: WorkingSpace = .current, revision: UInt64? = nil,
        telemetry: LiveEditTelemetry? = nil, source: ImageSource? = nil,
        quality: RenderQuality = .interactive,
        detailIdentity: PreviewFrameIdentity? = nil,
        detailFactor: CGFloat? = nil,
        presentationImageExtent: CGRect? = nil,
        coversPresentationExtent: Bool = false,
        layoutImageExtent: CGRect? = nil,
        onPresented: (() -> Void)? = nil
    ) -> Bool {
        guard let image,
            image.extent.width > 0, image.extent.height > 0,
            image.extent.width.isFinite, image.extent.height.isFinite
        else {
            // A failed render must not turn the surface into a blank candidate. The coordinator
            // reports the failure separately; retaining the current image keeps the drawable's
            // last confirmed frame available while that path recovers.
            return false
        }
        if let detailIdentity, let detailFactor, detailFactor.isFinite,
            let current = currentDetail,
            current.identity == detailIdentity,
            detailFactor + 0.000001 < current.factor,
            // A retained ROI frame only holds pixels for the region the user was zoomed into, so
            // refusing the complete photo for being less detailed would leave the rest of the
            // canvas showing that fragment — which is what made zooming back out look stuck.
            !(coversPresentationExtent && !current.coversPresentationExtent)
        {
            // Navigation can legitimately request a cheaper interactive level, but it must not
            // replace an already valid sharper frame for the same source/document. The settled
            // request will still be accepted when it reaches the coordinator.
            return false
        }
        self.image = image
        self.presentationImageExtent = Self.presentationExtentMatchingPixelAxes(
            planned: presentationImageExtent, pixels: image.extent,
            covers: coversPresentationExtent
        )
        self.coversPresentationExtent = coversPresentationExtent
        self.layoutImageExtent = layoutImageExtent
        self.space = space
        // The new publication must not sample the previous frame's texture. Until the async
        // materialization completes, draw() intentionally takes the CI fallback path for this
        // image, which keeps the first drawable responsive and preserves the non-GPU seam.
        presentationTexture = nil
        presentationTextureExtent = nil
        pendingPresentationMaterialization = nil
        if let detailIdentity, let detailFactor, detailFactor.isFinite {
            currentDetail = PublishedDetail(
                identity: detailIdentity, factor: detailFactor,
                coversPresentationExtent: coversPresentationExtent
            )
        } else {
            currentDetail = nil
        }
        self.revision &+= 1
        pendingDisplayID = self.revision
        if let revision, let telemetry {
            // A skipped publication has been submitted but never reached a visible drawable.
            // A newer publication supersedes it, so release its callback and diagnostic state.
            if let previous = pendingGPURevision,
                skippedTelemetryRevisions.contains(previous)
            {
                telemetryByRevision.removeValue(forKey: previous)
                submittedTelemetryRevisions.remove(previous)
                skippedTelemetryRevisions.remove(previous)
                presentationConfirmations.removeValue(forKey: previous)
            }
            // A pending value that has not reached a drawable is obsolete once a newer value is
            // presented. Submitted values remain until Metal reports their completion/display.
            if let previous = pendingGPURevision,
                !submittedTelemetryRevisions.contains(previous)
            {
                telemetryByRevision.removeValue(forKey: previous)
            }
            pendingGPURevision = revision
            telemetryByRevision[revision] = PendingTelemetry(
                telemetry: telemetry, source: source,
                quality: quality)
            if let onPresented {
                presentationConfirmations[revision] = onPresented
            }
            trimTelemetry()
        } else {
            pendingGPURevision = nil
        }
        let surfaceRevision = self.revision
        pendingPresentationMaterializationRevision = surfaceRevision
        beginPresentationTextureMaterialization(
            image: image, space: space, surfaceRevision: surfaceRevision,
            telemetryRevision: revision
        )
        if let revision, let onPresented, !hasManagedPresentationLifecycle {
            presentationConfirmations.removeValue(forKey: revision)
            onPresented()
        }
        requestDisplay()
        return true
    }
    /// A complete frame must keep the pixels' landscape/portrait axes. Stretching a 4000×6000
    /// photo onto a 3:2 planner rectangle fills the window by distorting, and Fill then has no
    /// tall frame left to zoom into.
    fileprivate static func presentationExtentMatchingPixelAxes(
        planned: CGRect?, pixels: CGRect, covers: Bool
    ) -> CGRect? {
        guard covers, let planned,
            planned.width > 1, planned.height > 1,
            pixels.width > 1, pixels.height > 1,
            planned.width.isFinite, planned.height.isFinite,
            pixels.width.isFinite, pixels.height.isFinite
        else {
            return planned
        }
        let plannedLandscape = planned.width >= planned.height
        let pixelsLandscape = pixels.width >= pixels.height
        if plannedLandscape != pixelsLandscape {
            return CGRect(origin: .zero, size: pixels.size)
        }
        return planned
    }

    fileprivate func pendingPresentationRevision() -> UInt64? { pendingGPURevision }
    func pendingDisplayRevision() -> UInt64? { pendingDisplayID }

    /// The quad/layout rectangle for the current texture. A first-frame JPEG is mapped onto
    /// the native presentation extent; an ROI preview keeps its source-space texture rectangle
    /// unless the request supplied a planner-space layout (interactive frames can decode smaller
    /// than that planner size).
    fileprivate func layoutExtent(forTextureExtent textureExtent: CGRect) -> CGRect {
        if coversPresentationExtent, let presentationImageExtent,
            presentationImageExtent.width > 0, presentationImageExtent.height > 0
        {
            return presentationImageExtent
        }
        if let layoutImageExtent,
            layoutImageExtent.width > 0, layoutImageExtent.height > 0,
            layoutImageExtent.width.isFinite, layoutImageExtent.height.isFinite
        {
            return layoutImageExtent
        }
        return textureExtent
    }

    fileprivate func mappedImageForPresentation(_ image: CIImage) -> CIImage {
        if coversPresentationExtent, let presentationImageExtent,
            presentationImageExtent.width > 0, presentationImageExtent.height > 0
        {
            return Self.imageMapped(image, onto: presentationImageExtent)
        }
        if let layoutImageExtent,
            layoutImageExtent.width > 0, layoutImageExtent.height > 0,
            layoutImageExtent.width.isFinite, layoutImageExtent.height.isFinite
        {
            return Self.imageMapped(image, onto: layoutImageExtent)
        }
        return image
    }

    fileprivate static func imageMapped(_ image: CIImage, onto target: CGRect) -> CIImage {
        let src = image.extent
        guard src.width > 0, src.height > 0,
            target.width > 0, target.height > 0,
            src.width.isFinite, src.height.isFinite,
            target.width.isFinite, target.height.isFinite
        else {
            return image
        }
        let scale = min(target.width / src.width, target.height / src.height)
        guard scale.isFinite, scale > 0 else { return image }
        let fitted = CGSize(width: src.width * scale, height: src.height * scale)
        let origin = CGPoint(
            x: target.minX + (target.width - fitted.width) / 2,
            y: target.minY + (target.height - fitted.height) / 2
        )
        return image.transformed(
            by: CGAffineTransform(
                a: scale, b: 0, c: 0, d: scale,
                tx: origin.x - src.minX * scale,
                ty: origin.y - src.minY * scale
            ))
    }

    func markPresentationSucceeded(displayRevision: UInt64) {
        guard pendingDisplayID == displayRevision else { return }
        lastValidImage = image
        lastValidPresentationTexture = presentationTexture
        lastValidPresentationTextureExtent = presentationTextureExtent
        lastValidPresentationImageExtent = presentationImageExtent
        lastValidLayoutImageExtent = layoutImageExtent
        lastValidCoversPresentationExtent = coversPresentationExtent
        lastValidSpace = space
        lastValidDetail = currentDetail
        pendingDisplayID = nil
    }

    func rejectPresentation(displayRevision: UInt64) {
        guard pendingDisplayID == displayRevision else { return }
        pendingDisplayID = nil
        image = lastValidImage
        presentationTexture = lastValidPresentationTexture
        presentationTextureExtent = lastValidPresentationTextureExtent
        presentationImageExtent = lastValidPresentationImageExtent
        layoutImageExtent = lastValidLayoutImageExtent
        coversPresentationExtent = lastValidCoversPresentationExtent
        space = lastValidSpace
        currentDetail = lastValidDetail
        pendingPresentationMaterializationRevision = nil
        pendingPresentationMaterialization = nil
        revision &+= 1
        requestDisplay()
        onPresentationFailure?()
    }

    fileprivate func markPresentationSubmitted(revision: UInt64) {
        guard telemetryByRevision[revision] != nil else { return }
        submittedTelemetryRevisions.insert(revision)
        if pendingGPURevision == revision { pendingGPURevision = nil }
    }

    fileprivate func setEffectiveDimensions(revision: UInt64, width: Int, height: Int) {
        telemetryByRevision[revision]?.telemetry.setEffectiveDimensions(
            revision, width: width, height: height)
    }

    fileprivate func markPresentationEncoded(
        revision: UInt64, drawableAcquisitionMS: Double,
        presentationEncodingMS: Double
    ) {
        telemetryByRevision[revision]?.telemetry.markPresentationTimings(
            revision, drawableAcquisitionMS: drawableAcquisitionMS,
            presentationEncodingMS: presentationEncodingMS
        )
        if let pending = telemetryByRevision[revision], let source = pending.source {
            KromoraObservability.event(
                .presentationEncoded, source: source, quality: pending.quality,
                detail: "drawable_ms=\(drawableAcquisitionMS) encode_ms=\(presentationEncodingMS)"
            )
        }
    }

    private func beginPresentationTextureMaterialization(
        image: CIImage, space: WorkingSpace, surfaceRevision: UInt64,
        telemetryRevision: UInt64?
    ) {
        let started = LiveEditTelemetryClock.now
        guard let submission = Self.makePresentationTexture(image: image, space: space) else {
            pendingPresentationMaterializationRevision = nil
            return
        }
        pendingPresentationMaterialization = (submission.texture, submission.extent)

        submission.commandBuffer.addCompletedHandler { [weak self] commandBuffer in
            let gpuMS: Double?
            if commandBuffer.gpuStartTime > 0, commandBuffer.gpuEndTime > 0 {
                gpuMS = max(0, (commandBuffer.gpuEndTime - commandBuffer.gpuStartTime) * 1_000)
            } else {
                gpuMS = nil
            }
            let succeeded = commandBuffer.status == .completed
            Task { @MainActor in
                self?.presentationTextureMaterializationCompleted(
                    surfaceRevision: surfaceRevision, telemetryRevision: telemetryRevision,
                    succeeded: succeeded, gpuMS: gpuMS
                )
            }
        }
        submission.commandBuffer.commit()
        let submitMS = max(0, (LiveEditTelemetryClock.now - started) * 1_000)
        if let telemetryRevision {
            telemetryByRevision[telemetryRevision]?.telemetry
                .markPresentationMaterializationSubmitted(telemetryRevision, submitMS: submitMS)
        }
    }

    private func presentationTextureMaterializationCompleted(
        surfaceRevision: UInt64,
        telemetryRevision: UInt64?, succeeded: Bool, gpuMS: Double?
    ) {
        if let telemetryRevision {
            telemetryByRevision[telemetryRevision]?.telemetry
                .markPresentationMaterializationCompleted(telemetryRevision, gpuMS: gpuMS)
            if let pending = telemetryByRevision[telemetryRevision], let source = pending.source {
                KromoraObservability.event(
                    .presentationMaterialized, source: source, quality: pending.quality,
                    detail: "gpu_ms=\(gpuMS ?? 0)"
                )
            }
        }
        guard pendingPresentationMaterializationRevision == surfaceRevision,
            revision == surfaceRevision
        else { return }
        pendingPresentationMaterializationRevision = nil
        let materialization = pendingPresentationMaterialization
        pendingPresentationMaterialization = nil
        if succeeded, let materialization {
            presentationTexture = materialization.texture
            presentationTextureExtent = materialization.extent
            presentationTextureGeneration &+= 1
            // The fallback drawable can complete before this callback's main-actor hop. Keep the
            // retained texture in rollback state if the publication was already confirmed.
            if pendingDisplayID == nil {
                lastValidPresentationTexture = materialization.texture
                lastValidPresentationTextureExtent = materialization.extent
            }
            requestDisplay()
        }
    }

    private func trimTelemetry() {
        guard telemetryByRevision.count > LiveEditTelemetry.maximumRetainedSamples else { return }
        let revisions = telemetryByRevision.keys.sorted()
        for revision in revisions.prefix(
            telemetryByRevision.count - LiveEditTelemetry.maximumRetainedSamples)
        {
            telemetryByRevision.removeValue(forKey: revision)
            submittedTelemetryRevisions.remove(revision)
            skippedTelemetryRevisions.remove(revision)
        }
    }

    fileprivate func markGPUCompletion(revision: UInt64, time: TimeInterval) {
        guard let pending = telemetryByRevision[revision] else { return }
        pending.telemetry.mark(revision, gpuCompletion: time)
        if let source = pending.source {
            KromoraObservability.liveEdit(
                .gpuComplete, source: source, quality: pending.quality,
                revision: revision)
        }
    }

    fileprivate func markPresentationFailed(revision: UInt64) {
        presentationConfirmations.removeValue(forKey: revision)
        telemetryByRevision.removeValue(forKey: revision)
        submittedTelemetryRevisions.remove(revision)
        skippedTelemetryRevisions.remove(revision)
        if pendingGPURevision == revision { pendingGPURevision = nil }
    }

    /// Returns `true` when Metal skipped this drawable and the caller should request another draw.
    /// A skipped drawable remains pending: it is a valid render candidate, but it has not reached
    /// visible pixels, so the producer's visible-frame confirmation must wait for a real retry.
    @discardableResult
    func markDrawablePresented(revision: UInt64, time: TimeInterval) -> Bool {
        guard let pending = telemetryByRevision[revision] else { return false }
        if time > 0 {
            pending.telemetry.mark(revision, drawablePresentation: time)
        } else if let fallback = zeroPresentedTimeFallback {
            // Capture host without drawable scan-out (screen sharing/headless session). A real
            // drawable still went through the presentation lifecycle and the capture needs a
            // timestamp; this is the same fallback clock the MetalPresentationBenchmark capture
            // procedure uses.
            pending.telemetry.mark(revision, drawablePresentation: fallback())
        } else {
            // Metal reports zero when a drawable was skipped. Do not turn a skipped frame into a
            // false presentation sample. Keep the candidate and its confirmation pending so the
            // producer does not mistake an occluded frame for pixels the user received. Re-arm
            // the revision for the next drawable; the coordinator bounds how often that happens.
            pending.telemetry.markSkippedDrawable(revision)
            skippedTelemetryRevisions.insert(revision)
            pendingGPURevision = revision
            return true
        }
        if let source = pending.source {
            KromoraObservability.liveEdit(
                .drawablePresented, source: source, quality: pending.quality,
                revision: revision, detail: "displayed")
        }
        telemetryByRevision.removeValue(forKey: revision)
        submittedTelemetryRevisions.remove(revision)
        skippedTelemetryRevisions.remove(revision)
        let confirmation = presentationConfirmations.removeValue(forKey: revision)
        confirmation?()
        return false
    }
    func clear() {
        image = nil
        presentationImageExtent = nil
        coversPresentationExtent = false
        layoutImageExtent = nil
        space = .current
        lastValidImage = nil
        presentationTexture = nil
        presentationTextureExtent = nil
        presentationTextureGeneration &+= 1
        lastValidPresentationTexture = nil
        lastValidPresentationTextureExtent = nil
        lastValidPresentationImageExtent = nil
        lastValidLayoutImageExtent = nil
        lastValidCoversPresentationExtent = false
        lastValidSpace = .current
        lastValidDetail = nil
        currentDetail = nil
        revision &+= 1
        pendingDisplayID = nil
        // A source switch invalidates any telemetry attached to the previous drawable. Its
        // command buffer may still complete, but it must not be attributed to the next source.
        pendingGPURevision = nil
        telemetryByRevision.removeAll()
        submittedTelemetryRevisions.removeAll()
        skippedTelemetryRevisions.removeAll()
        presentationConfirmations.removeAll()
        pendingPresentationMaterializationRevision = nil
        pendingPresentationMaterialization = nil
    }

    private struct MaterializationSubmission {
        let texture: MTLTexture
        let extent: CGRect
        let commandBuffer: MTLCommandBuffer
    }

    /// Convert a completed preview image to the drawable's display format once per publication.
    /// The returned texture is deliberately separate from the source CIImage: the latter may
    /// retain a private render texture, while this copy owns the exact color-space conversion
    /// needed at the presentation boundary and can be sampled without Core Image evaluation.
    private static func makePresentationTexture(
        image: CIImage, space: WorkingSpace
    ) -> MaterializationSubmission? {
        let extent = image.extent.integral
        guard extent.width > 0, extent.height > 0,
            extent.width.isFinite, extent.height.isFinite,
            extent.width <= CGFloat(Int32.max), extent.height <= CGFloat(Int32.max),
            let width = Int(exactly: extent.width), let height = Int(exactly: extent.height),
            width > 0, height > 0
        else { return nil }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .private
        guard let texture = RenderEngine.presentationDevice.makeTexture(descriptor: descriptor)
        else {
            return nil
        }

        let translated = image.transformed(
            by: CGAffineTransform(
                translationX: -extent.minX, y: -extent.minY
            ))
        guard let commandBuffer = RenderEngine.presentationQueue.makeCommandBuffer() else {
            return nil
        }
        RenderEngine.presentationContext.render(
            translated, to: texture, commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: extent.size),
            colorSpace: space.cgColorSpace
        )
        Self.notePresentationCoreImageEvaluation()
        return MaterializationSubmission(
            texture: texture, extent: extent,
            commandBuffer: commandBuffer)
    }
}

/// Persistent CAMetalLayer/MTKView destination for the completed preview texture.
struct PreviewSurfaceView: NSViewRepresentable {
    @ObservedObject var surface: PreviewSurface
    var navigation: CanvasNavigation = CanvasNavigation()
    var onScrollZoom: ((CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?
    /// The drawable reports backing pixels, which is the only reliable size across mixed-DPI
    /// windows and side-by-side panels. SwiftUI point geometry is not sufficient here.
    var onDrawableSizeChange: ((CGSize) -> Void)?
    /// When true, the MTKView declines AppKit hit testing so an overlay (crop) can own pointer
    /// input. SwiftUI `allowsHitTesting(false)` is not enough on its own because the representable
    /// still participates in the NSView hit-test walk.
    var ignoresHits: Bool = false

    func makeNSView(context: Context) -> MTKView {
        let view = PreviewMTKView(frame: .zero, device: context.coordinator.device)
        surface.attachPresentationLifecycle()
        surface.attachDisplayView(view)
        context.coordinator.surface = surface
        context.coordinator.navigation = navigation
        context.coordinator.onDrawableSizeChange = onDrawableSizeChange
        view.onScrollZoom = onScrollZoom
        view.onDoubleClick = onDoubleClick
        view.ignoresHits = ignoresHits
        view.delegate = context.coordinator
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.framebufferOnly = false
        view.colorPixelFormat = .bgra8Unorm
        view.autoResizeDrawable = true
        view.onEffectiveAppearanceChange = { [weak coordinator = context.coordinator] appearance in
            coordinator?.appearanceDidChange(appearance)
        }
        context.coordinator.startDisplayObservation()
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        if context.coordinator.surface !== surface {
            context.coordinator.surface?.detachDisplayView(view)
            surface.attachDisplayView(view)
        }
        context.coordinator.surface = surface
        context.coordinator.navigation = navigation
        context.coordinator.onDrawableSizeChange = onDrawableSizeChange
        if let view = view as? PreviewMTKView {
            view.onScrollZoom = onScrollZoom
            view.onDoubleClick = onDoubleClick
            view.ignoresHits = ignoresHits
        }
        // SwiftUI may call updateNSView before the MTKView has a drawable (notably while a
        // NavigationSplitView is replacing the selected image). The delegate will retry when the
        // view is laid out and when it receives its next drawable instead of losing this revision.
        view.setNeedsDisplay(view.bounds)
    }

    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        coordinator.stopDisplayObservation()
        coordinator.surface?.detachDisplayView(view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator: NSObject, MTKViewDelegate {
        let context: CIContext = RenderEngine.presentationContext
        let device: MTLDevice = RenderEngine.presentationDevice
        let commandQueue: MTLCommandQueue = RenderEngine.presentationQueue
        weak var surface: PreviewSurface?
        weak var view: MTKView?
        var navigation = CanvasNavigation()
        var onDrawableSizeChange: ((CGSize) -> Void)?
        private var lastDrawnRevision: UInt64?
        private var lastDrawnNavigation: CanvasNavigation?
        private var lastDrawnTextureGeneration: UInt64?
        private var lastDrawableSize: (width: Int, height: Int)?
        /// A drawable can be skipped after its command buffer has been submitted. Remember which
        /// draw needs replaying so the completion handler cannot mark the skipped revision as the
        /// settled frame and suppress the retry.
        private var skippedDrawNeedsRetry = false
        /// A paused MTKView is explicitly invalidated for each retry. Keep that invalidation
        /// coalesced and paced to the next main-runloop turn; otherwise an occluded view can
        /// manufacture an unbounded stream of drawable submissions.
        private var retryTask: Task<Void, Never>?
        private var retryScheduled = false
        private var skippedPresentationRevision: UInt64?
        private var consecutiveSkippedDraws = 0
        private var skippedDrawRetriesSuppressed = false
        fileprivate static let maximumConsecutiveSkippedDraws = 3
        /// Keep one drawable submission in flight and redraw only the newest surface state when it
        /// completes. Processing has already completed on RenderEngine's queue; this pacer bounds
        /// only the small transform/compositing pass and drawable submissions.
        private var isDrawing = false
        private var needsDisplayAfterInFlightDraw = false
        private var displayNotificationTokens: [NSObjectProtocol] = []
        private let pipeline: MTLRenderPipelineState?
        private let samplerState: MTLSamplerState?

        private struct Vertex {
            var position: SIMD2<Float>
            var texcoord: SIMD2<Float>
        }

        private struct Uniforms {
            var transformOrigin: SIMD2<Float>
            var imageOrigin: SIMD2<Float>
            var imageSize: SIMD2<Float>
            var scale: Float
            var viewportSize: SIMD2<Float>
        }

        override init() {
            let library: MTLLibrary?
            if let url = KromoraKitResourceBundle.bundle.url(
                forResource: "PreviewSurface", withExtension: "metal"),
                let source = try? String(contentsOf: url, encoding: .utf8)
            {
                library = try? RenderEngine.presentationDevice.makeLibrary(
                    source: source, options: nil)
            } else {
                library = RenderEngine.presentationDevice.makeDefaultLibrary()
            }

            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library?.makeFunction(name: "preview_quad_vertex")
            descriptor.fragmentFunction = library?.makeFunction(name: "preview_quad_fragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try? RenderEngine.presentationDevice.makeRenderPipelineState(
                descriptor: descriptor)

            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToEdge
            samplerDescriptor.tAddressMode = .clampToEdge
            samplerState = RenderEngine.presentationDevice.makeSamplerState(
                descriptor: samplerDescriptor)
            super.init()
        }

        /// A screen move can change the drawable's backing/color space without changing the
        /// published image. Repaint the retained texture into the new drawable, while keeping the
        /// settled-frame confirmation attached to the publication rather than to each repaint.
        func startDisplayObservation() {
            guard displayNotificationTokens.isEmpty else { return }
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didChangeScreenNotification,
                NSWindow.didChangeBackingPropertiesNotification,
                NSApplication.didChangeScreenParametersNotification,
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didBecomeKeyNotification,
            ]
            displayNotificationTokens = names.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.displayConfigurationChanged() }
                }
            }
        }

        func stopDisplayObservation() {
            retryTask?.cancel()
            retryTask = nil
            retryScheduled = false
            let center = NotificationCenter.default
            displayNotificationTokens.forEach(center.removeObserver)
            displayNotificationTokens.removeAll()
        }

        private func displayConfigurationChanged() {
            resetSkippedDrawBackoff()
            lastDrawableSize = nil
            if isDrawing {
                needsDisplayAfterInFlightDraw = true
            } else {
                lastDrawnRevision = nil
                lastDrawnNavigation = nil
                lastDrawnTextureGeneration = nil
            }
            view?.setNeedsDisplay(view?.bounds ?? .zero)
        }

        /// Explicit seam for a visibility/occlusion observer. Notification-driven display
        /// changes use the same path, and tests can model a restore without requiring a window.
        func visibilityDidChange() {
            displayConfigurationChanged()
        }

        func draw(in view: MTKView) {
            self.view = view
            guard !isDrawing else { return }
            guard let surface, let image = surface.image else { return }
            let drawableAcquisitionStart = LiveEditTelemetryClock.now
            guard let drawable = view.currentDrawable,
                let commandBuffer = commandQueue.makeCommandBuffer()
            else { return }

            let drawableAcquisitionMS = max(
                0, (LiveEditTelemetryClock.now - drawableAcquisitionStart) * 1_000
            )

            let drawableSize = (drawable.texture.width, drawable.texture.height)
            onDrawableSizeChange?(CGSize(width: drawableSize.0, height: drawableSize.1))
            let sameDrawableSize =
                lastDrawableSize?.width == drawableSize.0
                && lastDrawableSize?.height == drawableSize.1
            let sameTextureGeneration =
                lastDrawnTextureGeneration == surface.presentationTextureGeneration
            // A pan/zoom/fit change does not bump `surface.revision` — it is presentation-only
            // and deliberately does not wait for a new render — so it must independently trigger
            // a redraw here, or dragging the image would have no visible effect until some other
            // change (an edit, a settled render) happened to bump the revision.
            guard
                surface.revision != lastDrawnRevision || !sameDrawableSize
                    || navigation != lastDrawnNavigation || !sameTextureGeneration
            else {
                return
            }

            let destination = CGRect(
                x: 0, y: 0,
                width: CGFloat(drawable.texture.width),
                height: CGFloat(drawable.texture.height)
            )
            guard destination.width > 0, destination.height > 0,
                image.extent.width > 0, image.extent.height > 0,
                image.extent.width.isFinite, image.extent.height.isFinite
            else { return }

            let presentationRevision = surface.pendingPresentationRevision()
            if let presentationRevision {
                surface.setEffectiveDimensions(
                    revision: presentationRevision,
                    width: drawableSize.0, height: drawableSize.1)
            }
            let displayRevision = surface.pendingDisplayRevision()
            let drawRevision = surface.revision
            let drawNavigation = navigation
            let drawTextureGeneration = surface.presentationTextureGeneration
            isDrawing = true
            let presentationEncodingStart = LiveEditTelemetryClock.now
            let renderPass = view.currentRenderPassDescriptor
            let appearance = view.effectiveAppearance
            let clearColor = Self.canvasBackgroundClearColor(for: appearance)
            renderPass?.colorAttachments[0].clearColor = clearColor
            renderPass?.colorAttachments[0].loadAction = .clear
            renderPass?.colorAttachments[0].storeAction = .store

            if let texture = surface.presentationTexture,
                let textureExtent = surface.presentationTextureExtent,
                let pipeline, let samplerState,
                var geometry = Self.quadGeometry(
                    imageExtent: surface.layoutExtent(forTextureExtent: textureExtent),
                    navigation: navigation,
                    destination: destination, virtualExtent: surface.presentationImageExtent
                ),
                let vertexBuffer = geometry.vertices.withUnsafeBytes({ rawBuffer in
                    device.makeBuffer(
                        bytes: rawBuffer.baseAddress!,
                        length: rawBuffer.count, options: .storageModeShared)
                }),
                let uniformBuffer = device.makeBuffer(
                    bytes: &geometry.uniforms,
                    length: MemoryLayout<Uniforms>.stride,
                    options: .storageModeShared),
                let encoder = renderPass.flatMap({
                    commandBuffer.makeRenderCommandEncoder(descriptor: $0)
                })
            {
                encoder.setRenderPipelineState(pipeline)
                encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.setFragmentSamplerState(samplerState, index: 0)
                encoder.drawPrimitives(
                    type: .triangleStrip, vertexStart: 0,
                    vertexCount: geometry.vertices.count)
                encoder.endEncoding()
            } else if let output = Self.presentationImage(
                surface.mappedImageForPresentation(image), navigation: navigation,
                destination: destination,
                virtualExtent: surface.presentationImageExtent,
                appearance: appearance
            ) {
                // Compatibility seam for a host without a usable Metal texture/pipeline. The
                // production path above never evaluates this graph on presentation-only redraws.
                context.render(
                    output, to: drawable.texture, commandBuffer: commandBuffer,
                    bounds: destination, colorSpace: surface.space.cgColorSpace)
                PreviewSurface.notePresentationCoreImageEvaluation()
            } else {
                isDrawing = false
                return
            }

            // Presenting the drawable is on us. The drawable is submitted only after the complete
            // fitted frame is encoded, so a new frame cannot expose intermediate tiles.
            commandBuffer.present(drawable)
            let presentationEncodingMS = max(
                0, (LiveEditTelemetryClock.now - presentationEncodingStart) * 1_000
            )
            if let presentationRevision {
                surface.markPresentationEncoded(
                    revision: presentationRevision,
                    drawableAcquisitionMS: drawableAcquisitionMS,
                    presentationEncodingMS: presentationEncodingMS
                )
            }
            commandBuffer.addCompletedHandler { [weak self, weak surface] commandBuffer in
                let succeeded = commandBuffer.status == .completed
                let gpuCompletion =
                    commandBuffer.gpuEndTime > 0
                    ? commandBuffer.gpuEndTime : LiveEditTelemetryClock.now
                Task { @MainActor in
                    if let surface {
                        if succeeded, let displayRevision {
                            surface.markPresentationSucceeded(displayRevision: displayRevision)
                        } else if let displayRevision {
                            // A failed Core Image command buffer must not poison the drawable's
                            // last valid frame. Reject only the candidate this draw attempted;
                            // a newer publication may already be waiting behind it.
                            surface.rejectPresentation(displayRevision: displayRevision)
                        }
                        if let revision = presentationRevision {
                            if !succeeded { surface.markPresentationFailed(revision: revision) }
                            surface.markGPUCompletion(revision: revision, time: gpuCompletion)
                        }
                    }
                    self?.drawingFinished(
                        drawRevision: drawRevision, navigation: drawNavigation,
                        drawableSize: drawableSize, textureGeneration: drawTextureGeneration,
                        succeeded: succeeded
                    )
                }
            }
            if let revision = presentationRevision {
                drawable.addPresentedHandler { [weak self, weak surface] drawable in
                    let presentationTime = drawable.presentedTime
                    Task { @MainActor in
                        let skipped =
                            surface?.markDrawablePresented(
                                revision: revision, time: presentationTime
                            ) == true
                        if skipped {
                            self?.handleSkippedDrawable(revision: revision)
                        }
                    }
                }
            }
            commandBuffer.commit()
            if let revision = presentationRevision {
                surface.markPresentationSubmitted(revision: revision)
            }
        }

        /// Build the bounded image graph sent to the drawable.
        ///
        /// A native-resolution candidate can be much larger than the drawable once navigation
        /// passes 100%. Leaving that transformed extent attached to the source-over graph makes
        /// Core Image's Metal destination evaluate an unnecessarily large working extent and can
        /// fail the command buffer on large sources. Clip before compositing the letterbox and
        /// clip the final result as a second explicit destination contract. The source image is
        /// never downscaled here; only pixels outside the current viewport are discarded.
        static func presentationImage(
            _ image: CIImage, navigation: CanvasNavigation, destination: CGRect,
            virtualExtent: CGRect? = nil, appearance: NSAppearance? = nil
        ) -> CIImage? {
            guard destination.width > 0, destination.height > 0,
                destination.width.isFinite, destination.height.isFinite,
                image.extent.width > 0, image.extent.height > 0,
                image.extent.width.isFinite, image.extent.height.isFinite
            else { return nil }

            let extent = image.extent
            let transformExtent = virtualExtent ?? extent
            let transform = navigation.transform(
                imageExtent: transformExtent, viewportSize: destination.size)
            guard transform.scale.isFinite, transform.scale > 0,
                transform.imageSize.width.isFinite, transform.imageSize.height.isFinite
            else {
                return nil
            }
            let displayed =
                image
                .transformed(by: transform.affineTransform(for: transformExtent))
                .cropped(to: destination)
            // Resolve the dedicated canvas color against the editor view's effective appearance.
            // Resolving without that appearance is not reliable at the native presentation
            // boundary: a dark window can otherwise produce a light letterbox.
            let clear = canvasBackgroundClearColor(for: appearance)
            let background = CIImage(
                color: CIColor(
                    red: CGFloat(clear.red), green: CGFloat(clear.green),
                    blue: CGFloat(clear.blue), alpha: 1)
            ).cropped(to: destination)
            return displayed.composited(over: background).cropped(to: destination)
        }

        static func canvasBackgroundClearColor(for appearance: NSAppearance? = nil) -> MTLClearColor
        {
            let color = KromoraTheme.resolvedCanvasBackgroundColor(for: appearance)
            return MTLClearColor(
                red: Double(color.redComponent),
                green: Double(color.greenComponent),
                blue: Double(color.blueComponent), alpha: 1)
        }

        private static func quadGeometry(
            imageExtent: CGRect, navigation: CanvasNavigation, destination: CGRect,
            virtualExtent: CGRect?
        ) -> (vertices: [Vertex], uniforms: Uniforms)? {
            let transformExtent = virtualExtent ?? imageExtent
            let transform = navigation.transform(
                imageExtent: transformExtent, viewportSize: destination.size
            )
            guard transform.scale.isFinite, transform.scale > 0,
                transform.origin.x.isFinite, transform.origin.y.isFinite,
                imageExtent.width > 0, imageExtent.height > 0,
                imageExtent.width.isFinite, imageExtent.height.isFinite,
                destination.width > 0, destination.height > 0,
                destination.width.isFinite, destination.height.isFinite
            else { return nil }

            let origin = CGPoint(
                x: transform.origin.x + (imageExtent.minX - transformExtent.minX) * transform.scale,
                y: transform.origin.y + (imageExtent.minY - transformExtent.minY) * transform.scale
            )
            let size = CGSize(
                width: imageExtent.width * transform.scale,
                height: imageExtent.height * transform.scale)
            let values = [
                origin.x, origin.y, size.width, size.height,
                transform.scale, destination.width, destination.height,
            ]
            guard values.allSatisfy({ $0.isFinite }) else { return nil }
            return (
                vertices: [
                    Vertex(position: SIMD2(0, 0), texcoord: SIMD2(0, 0)),
                    Vertex(position: SIMD2(1, 0), texcoord: SIMD2(1, 0)),
                    Vertex(position: SIMD2(0, 1), texcoord: SIMD2(0, 1)),
                    Vertex(position: SIMD2(1, 1), texcoord: SIMD2(1, 1)),
                ],
                uniforms: Uniforms(
                    transformOrigin: SIMD2(Float(transform.origin.x), Float(transform.origin.y)),
                    imageOrigin: SIMD2(
                        Float(imageExtent.minX - transformExtent.minX),
                        Float(imageExtent.minY - transformExtent.minY)),
                    imageSize: SIMD2(Float(imageExtent.width), Float(imageExtent.height)),
                    scale: Float(transform.scale),
                    viewportSize: SIMD2(Float(destination.width), Float(destination.height))
                )
            )
        }

        private func drawingFinished(
            drawRevision: UInt64, navigation: CanvasNavigation,
            drawableSize: (width: Int, height: Int), textureGeneration: UInt64,
            succeeded: Bool
        ) {
            let retry = skippedDrawNeedsRetry
            skippedDrawNeedsRetry = false
            isDrawing = false
            let displayChanged = needsDisplayAfterInFlightDraw
            needsDisplayAfterInFlightDraw = false
            // Do not record a draw as complete until its command buffer completed successfully.
            // The surface may also have advanced while the buffer evaluated; in that case this
            // completion only frees the pacer and the newest revision is redrawn below.
            let surfaceAdvanced = surface?.revision != drawRevision
            if retry || displayChanged || surfaceAdvanced || !succeeded {
                lastDrawnRevision = nil
                lastDrawnNavigation = nil
                lastDrawnTextureGeneration = nil
                lastDrawableSize = nil
            } else if succeeded, let surface, surface.revision == drawRevision, surface.image != nil
            {
                lastDrawnRevision = drawRevision
                lastDrawnNavigation = navigation
                lastDrawnTextureGeneration = textureGeneration
                lastDrawableSize = drawableSize
            } else {
                lastDrawnRevision = nil
                lastDrawnNavigation = nil
                lastDrawnTextureGeneration = nil
                lastDrawableSize = nil
            }
            // The surface may have advanced while this buffer evaluated. One redraw now consumes
            // that latest revision rather than replaying every superseded pointer update. A
            // skipped drawable uses the paced scheduler; ordinary presentation completion can
            // request the newest publication immediately.
            if retry {
                scheduleSkippedDrawRetry()
            } else if displayChanged || surfaceAdvanced || !succeeded {
                view?.setNeedsDisplay(view?.bounds ?? .zero)
            }
        }

        // Internal (not private) so PreviewSurfaceTests can drive the bounded-retry
        // contract directly without requiring a live drawable.
        func handleSkippedDrawable(revision: UInt64) {
            if skippedPresentationRevision != revision {
                skippedPresentationRevision = revision
                consecutiveSkippedDraws = 0
                skippedDrawRetriesSuppressed = false
            }
            consecutiveSkippedDraws += 1
            guard consecutiveSkippedDraws < Self.maximumConsecutiveSkippedDraws,
                !skippedDrawRetriesSuppressed
            else {
                skippedDrawRetriesSuppressed = true
                skippedDrawNeedsRetry = false
                retryTask?.cancel()
                retryTask = nil
                retryScheduled = false
                return
            }

            if isDrawing {
                // The presented handler and command-buffer completion can arrive in either order.
                // Let drawingFinished preserve the retry when completion is still pending.
                skippedDrawNeedsRetry = true
            } else {
                // Completion already recorded this revision as drawn; invalidate that marker so
                // the paused view does not reject the fresh-draw request as redundant.
                lastDrawnRevision = nil
                lastDrawnNavigation = nil
                lastDrawableSize = nil
                scheduleSkippedDrawRetry()
            }
        }

        private func scheduleSkippedDrawRetry() {
            guard !retryScheduled, !skippedDrawRetriesSuppressed else { return }
            retryScheduled = true
            retryTask = Task { @MainActor [weak self] in
                // Yield once so multiple presented handlers/completion callbacks in the same
                // turn coalesce into this single invalidation.
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                self.retryScheduled = false
                self.retryTask = nil
                self.view?.setNeedsDisplay(self.view?.bounds ?? .zero)
            }
        }

        private func resetSkippedDrawBackoff() {
            retryTask?.cancel()
            retryTask = nil
            retryScheduled = false
            skippedDrawNeedsRetry = false
            skippedPresentationRevision = nil
            consecutiveSkippedDraws = 0
            skippedDrawRetriesSuppressed = false
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            lastDrawableSize = nil
            onDrawableSizeChange?(
                CGSize(width: size.width.rounded(.down), height: size.height.rounded(.down)))
            view.setNeedsDisplay(view.bounds)
        }

        /// Render one retained presentation texture into an offscreen target using the same
        /// pipeline as the drawable path. This is an acceptance-test seam for geometry and
        /// repaint behavior on hosts without a logged-in display; it never evaluates Core Image.
        func renderRetainedTextureForTesting(
            surface: PreviewSurface, navigation: CanvasNavigation, destinationSize: CGSize,
            appearance: NSAppearance? = nil
        ) -> MTLTexture? {
            guard destinationSize.width > 0, destinationSize.height > 0,
                destinationSize.width.isFinite, destinationSize.height.isFinite,
                let texture = surface.presentationTexture,
                let textureExtent = surface.presentationTextureExtent,
                let pipeline, let samplerState
            else { return nil }

            let width = Int(destinationSize.width.rounded())
            let height = Int(destinationSize.height.rounded())
            guard width > 0, height > 0 else { return nil }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false
            )
            descriptor.usage = [.shaderRead, .renderTarget]
            descriptor.storageMode = .shared
            guard let target = device.makeTexture(descriptor: descriptor),
                var geometry = Self.quadGeometry(
                    imageExtent: surface.layoutExtent(forTextureExtent: textureExtent),
                    navigation: navigation,
                    destination: CGRect(x: 0, y: 0, width: width, height: height),
                    virtualExtent: surface.presentationImageExtent
                ),
                let commandBuffer = commandQueue.makeCommandBuffer()
            else { return nil }

            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].clearColor = Self.canvasBackgroundClearColor(for: appearance)
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            guard
                let vertexBuffer = geometry.vertices.withUnsafeBytes({ rawBuffer in
                    device.makeBuffer(
                        bytes: rawBuffer.baseAddress!, length: rawBuffer.count,
                        options: .storageModeShared)
                }),
                let uniformBuffer = device.makeBuffer(
                    bytes: &geometry.uniforms,
                    length: MemoryLayout<Uniforms>.stride,
                    options: .storageModeShared
                ),
                let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
            else {
                return nil
            }
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            encoder.drawPrimitives(
                type: .triangleStrip, vertexStart: 0,
                vertexCount: geometry.vertices.count)
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()
            return commandBuffer.status == .completed ? target : nil
        }

        func appearanceDidChange(_ _: NSAppearance) {
            displayConfigurationChanged()
        }
    }
}

/// A paused MTKView still needs a display request after it first enters a window. This subclass
/// covers the case where SwiftUI's update arrived before the view had a drawable.
private final class PreviewMTKView: MTKView {
    var onScrollZoom: ((CGFloat) -> Void)?
    var onDoubleClick: (() -> Void)?
    var onEffectiveAppearanceChange: ((NSAppearance) -> Void)?
    var ignoresHits = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        ignoresHits ? nil : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        if delta.isFinite, abs(delta) > 0.001 {
            onScrollZoom?(pow(1.01, delta))
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onEffectiveAppearanceChange?(effectiveAppearance)
        setNeedsDisplay(bounds)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?(effectiveAppearance)
        setNeedsDisplay(bounds)
    }

    override func layout() {
        super.layout()
        setNeedsDisplay(bounds)
    }
}
