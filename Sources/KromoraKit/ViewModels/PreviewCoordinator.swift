import Foundation
import CoreGraphics
import CoreImage

/// Coordinates the display render, which has a different lifecycle from the render actor.
///
/// A slider produces a burst of edit values. During that burst the coordinator asks for a
/// viewport-sized `.interactive` result and keeps only the newest request. When the burst ends it
/// promotes that request to `.preview`, so the last interactive frame is always replaced by the
/// normal settled preview. The renderer remains an actor concerned only with executing requests;
/// this type owns cancellation, revisions, and the policy for what is allowed onto the screen.
@MainActor
final class PreviewCoordinator {

    enum Phase: Sendable, Equatable {
        case interactive
        case settled
    }

    struct Publication {
        let request: RenderRequest
        let image: CGImage?
        let gpuImage: CIImage?
        let revision: UInt64
        /// The caller's navigation generations. The coordinator's own revision protects its
        /// queue, while these protect the owning view model when equal-valued sources are selected
        /// by different photo assets.
        let assetID: PhotoAssetID?
        let sourceRevision: UInt64
        let displayRevision: UInt64
        let phase: Phase
    }

    typealias PublicationHandler = @MainActor (Publication) -> Void
    typealias FailureHandler = @MainActor (RenderRequest) -> Void

    /// The semantic mask work a published refined frame has already warmed.
    ///
    /// The two-phase publish only pays for itself while the refined render can still suspend on
    /// Vision. Once a resolved frame for this photo and mask recipe has reached the screen, the
    /// renderer's component cache answers the next render without suspending, and a base frame
    /// would just be a second full-graph render for every pointer tick. Mask resolution is keyed
    /// by the component definitions, the mask quality tier and the requested box — not by the
    /// document's global look — so a slider drag keeps the warm identity while adding or editing a
    /// smart mask correctly loses it.
    private struct SemanticWarmth: Equatable {
        let source: ImageSource
        let assetID: PhotoAssetID?
        let components: [MaskSource]
        let maskQuality: MaskQuality
        let targetSize: CGSize?
    }

    private struct Token: Equatable {
        let source: ImageSource
        let assetID: PhotoAssetID?
        let sourceRevision: UInt64
        let displayRevision: UInt64
        let revision: UInt64
    }

    private let engine: any RenderEngining
    private let scheduler: ImageWorkScheduler
    private let interactiveDelay: Duration
    private let settleDelay: Duration
    private var interactiveTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    /// True only after an interactive task has entered the renderer. A renderer actor may still be
    /// finishing a non-cancellable Core Image operation after its caller is cancelled; tracking
    /// that boundary prevents every pointer tick from becoming another actor message.
    private var interactiveRenderInFlight = false
    private var pendingInteractive: (request: RenderRequest, token: Token)?
    private var interactiveJobID: ImageWorkScheduler.JobID?
    private var settledJobID: ImageWorkScheduler.JobID?
    /// Settled predecessors left running by `submitCorrective` instead of being cancelled (see
    /// `admit`). They are not tracked by `settledJobID` once superseded, so without this set the
    /// next `cancelSettledJob` would leak them: still occupying the scheduler's single editor-lane
    /// slot, they would block every later editor job — including the next photo's preview — until
    /// they happened to finish on their own.
    private var abandonedSettledJobIDs: Set<ImageWorkScheduler.JobID> = []
    private var latestRequest: RenderRequest?
    private var latestToken: Token?
    private var nextRevision: UInt64 = 0
    private var isInteracting = false
    private var isShutdown = false
    private var warmSemanticMasks: SemanticWarmth?

    var onPublication: PublicationHandler?
    var onFailure: FailureHandler?
    let telemetry = LiveEditTelemetry()

    init(
        engine: any RenderEngining,
        scheduler: ImageWorkScheduler = ImageWorkScheduler(),
        interactiveDelay: Duration = .zero,
        settleDelay: Duration = .milliseconds(60)
    ) {
        self.engine = engine
        self.scheduler = scheduler
        self.interactiveDelay = interactiveDelay
        self.settleDelay = settleDelay
    }

    /// Start a gesture. The coordinator will not settle until `endInteraction()` is called.
    func beginInteraction() {
        isInteracting = true
        settleTask?.cancel()
        settleTask = nil
    }

    /// End a gesture and immediately request the final preview-quality result.
    func endInteraction() {
        guard isInteracting else { return }
        isInteracting = false
        settleTask?.cancel()
        settleTask = nil
        settleLatest()
    }

    /// Submit a complete display request. The request is value state, so a caller can safely create
    /// it on the main actor and the renderer can evaluate it elsewhere.
    ///
    /// A new submission preempts any admitted predecessor so a stuck render can never hold the
    /// visible lane hostage; see `submitCorrective` for the one path that intentionally opts out.
    func submit(
        _ request: RenderRequest,
        phase: Phase = .settled,
        assetID: PhotoAssetID? = nil,
        sourceRevision: UInt64 = 0,
        displayRevision: UInt64 = 0
    ) {
        admit(
            request, phase: phase, assetID: assetID, sourceRevision: sourceRevision,
            displayRevision: displayRevision, cancelSettledPredecessor: true
        )
    }

    /// Submit the stored-edit corrective render for a speculative open.
    ///
    /// Unlike `submit`, this never cancels an admitted settled predecessor: the predecessor is
    /// the speculative identity render submitted moments earlier for the same source, and
    /// cancelling it before its scheduler task first runs coalesces both submissions into the
    /// corrective request — first pixels then wait on persistence after all (LUMO-317). The
    /// predecessor is left to reach the engine and the revision fence retires it as stale, while
    /// the corrective queues behind it on the single-editor lane, so both renders are observed
    /// in order. The predecessor's job handle is intentionally not cancelled here (see `admit`);
    /// it can no longer publish once the corrective advances the revision, and it is tracked in
    /// `abandonedSettledJobIDs` so a later cancellation still reclaims the editor lane from it
    /// instead of leaking it as a permanently running job.
    func submitCorrective(
        _ request: RenderRequest,
        assetID: PhotoAssetID? = nil,
        sourceRevision: UInt64 = 0,
        displayRevision: UInt64 = 0
    ) {
        admit(
            request, phase: .settled, assetID: assetID, sourceRevision: sourceRevision,
            displayRevision: displayRevision, cancelSettledPredecessor: false
        )
    }

    private func admit(
        _ request: RenderRequest,
        phase: Phase,
        assetID: PhotoAssetID?,
        sourceRevision: UInt64,
        displayRevision: UInt64,
        cancelSettledPredecessor: Bool
    ) {
        guard !isShutdown else { return }
        let hadPendingWork = interactiveTask != nil || settleTask != nil
            || (interactiveJobID.map(scheduler.contains) ?? false)
            || (settledJobID.map(scheduler.contains) ?? false)
        if hadPendingWork {
            KromoraObservability.event(.cancellation, source: request.source, quality: request.quality,
                                    detail: "superseded")
        }
        // A previous settled request is not a coalesced edit. Only count a new interactive value
        // replacing another interactive task in the same burst.
        if phase == .interactive, interactiveTask != nil {
            KromoraObservability.event(.coalesced, source: request.source, quality: .interactive,
                                    detail: "interactive-burst")
        }

        nextRevision &+= 1
        let token = Token(
            source: request.source, assetID: assetID, sourceRevision: sourceRevision,
            displayRevision: displayRevision, revision: nextRevision
        )
        telemetry.input(source: request.source, request: request, revision: token.revision)
        KromoraObservability.liveEdit(.pointerInput, source: request.source, quality: request.quality,
                                   revision: token.revision)
        if phase == .interactive, interactiveTask != nil { telemetry.coalesced(token.revision) }
        latestRequest = request
        latestToken = token

        cancelInteractiveJob(pump: false)
        interactiveTask?.cancel()
        interactiveTask = nil
        if cancelSettledPredecessor {
            cancelSettledJob(pump: false)
        } else if let settledJobID {
            // Left running so it can still win the revision race and publish first (LUMO-317);
            // tracked so a later cancellation can still reclaim the lane instead of leaking it.
            abandonedSettledJobIDs.insert(settledJobID)
        }
        settleTask?.cancel()
        settleTask = nil
        pendingInteractive = nil

        switch phase {
        case .interactive:
            let interactiveRequest = Self.request(request, quality: .interactive)
            latestRequest = interactiveRequest
            scheduleInteractive(interactiveRequest, token: token)

            // Tests and non-Slider callers do not have editing callbacks. They still get the same
            // gesture behavior through the quiet-period fallback; an explicit interaction keeps
            // this timer from firing until the control reports that it ended.
            if !isInteracting {
                let delay = settleDelay
                settleTask = Task { [weak self] in
                    try? await Task.sleep(for: delay)
                    guard !Task.isCancelled else { return }
                    self?.settleLatest()
                }
            }

        case .settled:
            scheduleSettled(request, token: token)
        }
    }

    /// Invalidate every in-flight publication, including one for a source that happens to compare
    /// equal to the next source. This is the source-generation boundary used by navigation.
    func cancel() {
        if interactiveTask != nil || settleTask != nil {
            KromoraObservability.event(.cancellation, source: latestRequest?.source,
                                    quality: latestRequest?.quality, detail: "navigation")
        }
        nextRevision &+= 1
        latestRequest = nil
        latestToken = nil
        interactiveTask?.cancel()
        interactiveTask = nil
        cancelInteractiveJob(pump: false)
        cancelSettledJob(pump: false)
        settleTask?.cancel()
        settleTask = nil
        pendingInteractive = nil
        isInteracting = false
        // Navigation is also the renderer's source boundary: nothing about the next photo's mask
        // work may be assumed warm from this one.
        warmSemanticMasks = nil
    }

    /// Cancel display scheduling and wait for any admitted render operation to leave the shared
    /// scheduler. This is the teardown barrier used when the source backing a request is temporary.
    func shutdown() async {
        guard !isShutdown else { return }
        isShutdown = true
        cancel()
        await scheduler.cancelAllAndWait()
    }

    private func settleLatest() {
        guard let request = latestRequest else { return }
        let sourceRevision = latestToken?.sourceRevision ?? 0
        let displayRevision = latestToken?.displayRevision ?? 0
        let originatingRevision = latestToken?.revision
        nextRevision &+= 1
        let token = Token(
            source: request.source, assetID: latestToken?.assetID, sourceRevision: sourceRevision,
            displayRevision: displayRevision, revision: nextRevision
        )
        latestToken = token
        interactiveTask?.cancel()
        interactiveTask = nil
        cancelInteractiveJob(pump: false)
        settleTask = nil
        pendingInteractive = nil
        let settledRequest = Self.request(request, quality: .preview)
        if let originatingRevision {
            telemetry.promote(from: originatingRevision, to: token.revision,
                              source: settledRequest.source, request: settledRequest)
        } else {
            telemetry.input(source: settledRequest.source, request: settledRequest, revision: token.revision)
        }
        scheduleSettled(settledRequest, token: token)
    }

    private func scheduleInteractive(_ request: RenderRequest, token: Token) {
        if interactiveRenderInFlight {
            // Keep only value state while the renderer finishes the one operation already in
            // flight. This is latest-wins coalescing without building an actor/task queue.
            pendingInteractive = (request, token)
            return
        }

        interactiveTask = Task { [weak self, engine] in
            // No debounce belongs before the first interactive frame. The in-flight/pending
            // state below is the frame pacer: it permits one render and retains only the latest
            // document while Core Image finishes the non-cancellable operation.
            if self?.interactiveDelay != .zero {
                try? await Task.sleep(for: self?.interactiveDelay ?? .zero)
            }
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let jobID = ImageWorkScheduler.JobID("visible-preview-interactive-\(token.revision)")
            self.interactiveJobID = jobID
            self.scheduler.enqueue(id: jobID, lane: .editor, priority: .activeEditor) {
                [weak self, engine] in
                guard !Task.isCancelled, let self else { return }
                self.interactiveRenderInFlight = true
                await self.render(request, token: token, phase: .interactive, engine: engine)
                self.interactiveRenderFinished(token: token)
            }
        }
    }

    private func interactiveRenderFinished(token: Token) {
        guard interactiveRenderInFlight else { return }
        interactiveRenderInFlight = false

        // A settled request supersedes this work when a gesture ended, so only continue an
        // interactive burst that is still active.
        guard isInteracting, let pending = pendingInteractive else {
            pendingInteractive = nil
            return
        }
        pendingInteractive = nil
        scheduleInteractive(pending.request, token: pending.token)
    }

    private func scheduleSettled(_ request: RenderRequest, token: Token) {
        interactiveTask?.cancel()
        interactiveTask = nil
        cancelInteractiveJob(pump: false)
        let jobID = ImageWorkScheduler.JobID("visible-preview-settled-\(token.revision)")
        // Overwriting here leaves a still-running predecessor's handle out of `settledJobID` when
        // the submission opted out of preemption (see `submitCorrective`); `admit` records that
        // predecessor in `abandonedSettledJobIDs` before this runs; so it is still reclaimed by a
        // later cancellation.
        settledJobID = jobID
        scheduler.enqueue(id: jobID, lane: .editor, priority: .activeEditor) {
            [weak self, engine] in
            guard !Task.isCancelled, let self else { return }
            await self.render(request, token: token, phase: .settled, engine: engine)
        }
    }

    private func cancelInteractiveJob(pump: Bool = true) {
        guard let interactiveJobID else { return }
        scheduler.cancel(id: interactiveJobID, pump: pump)
        self.interactiveJobID = nil
    }

    private func cancelSettledJob(pump: Bool = true) {
        var ids = abandonedSettledJobIDs
        abandonedSettledJobIDs.removeAll()
        if let settledJobID {
            ids.insert(settledJobID)
            self.settledJobID = nil
        }
        guard !ids.isEmpty else { return }
        if pump {
            scheduler.cancel(ids: ids)
        } else {
            for id in ids { scheduler.cancel(id: id, pump: false) }
        }
    }

    private func render(
        _ request: RenderRequest,
        token: Token,
        phase: Phase,
        engine: any RenderEngining
    ) async {
        // Semantic masks are the only display stage that can suspend on Vision. Publish the
        // already-available source/global/procedural graph first, then refine the same visible
        // revision once the mask resolver returns. A newer request cancels this scheduler job and
        // the renderer's request revision fence prevents a late refinement from being published.
        guard request.maskResolution == .resolved, request.document.hasSemanticMasks else {
            await renderSingle(request, token: token, phase: phase, engine: engine)
            return
        }
        let warmth = Self.semanticWarmth(for: request, assetID: token.assetID)
        if warmth != warmSemanticMasks {
            let baseRequest = Self.request(
                request, quality: request.quality, maskResolution: .deferSemantic
            )
            let publishedBase = await renderSingle(
                baseRequest, token: token, phase: phase, engine: engine
            )
            guard !Task.isCancelled, isCurrent(token) else { return }
            // Pointer-to-pixel latency is a property of the frame the user actually saw, and both
            // phases share this revision. Once the base frame has been published, the refinement
            // must not overwrite its timings with its own, later ones.
            if await renderSingle(
                request, token: token, phase: phase, engine: engine,
                tracksLatency: !publishedBase
            ) {
                warmSemanticMasks = warmth
            }
            return
        }
        // Only a frame that actually reached the screen proves the renderer resolved and cached
        // this recipe's masks. A cancelled or failed refinement leaves the next submit two-phase.
        if await renderSingle(request, token: token, phase: phase, engine: engine) {
            warmSemanticMasks = warmth
        }
    }

    private static func semanticWarmth(
        for request: RenderRequest, assetID: PhotoAssetID?
    ) -> SemanticWarmth {
        SemanticWarmth(
            source: request.source,
            assetID: request.assetID ?? assetID,
            components: request.document.localAdjustments.flatMap { layer in
                layer.isEnabled
                    ? layer.components.filter {
                        $0.isUsable && $0.source.semanticDefinition != nil
                    }.map(\.source)
                    : []
            },
            maskQuality: request.quality.maskQuality,
            targetSize: request.targetSize
        )
    }

    /// Renders one request and publishes it if it is still current. Returns whether it published.
    @discardableResult
    private func renderSingle(
        _ request: RenderRequest,
        token: Token,
        phase: Phase,
        engine: any RenderEngining,
        tracksLatency: Bool = true
    ) async -> Bool {
        let maskDetail = request.maskResolution == .deferSemantic ? "masks=deferred" : ""
        if tracksLatency { telemetry.mark(token.revision, renderStart: LiveEditTelemetryClock.now) }
        KromoraObservability.liveEdit(.renderStart, source: request.source, quality: request.quality,
                                   revision: token.revision, detail: maskDetail)
        let gpuImage = await engine.makeCIImage(request)
        // Test doubles and non-GPU conformers retain the old raster seam. Once a GPU image exists,
        // the persistent presentation surface owns display for both phases, so rasterizing the
        // same request would rebuild the graph and perform a redundant second render pass.
        let image = gpuImage == nil ? await engine.makeCGImage(request) : nil
        if tracksLatency { telemetry.mark(token.revision, renderEnd: LiveEditTelemetryClock.now) }
        KromoraObservability.liveEdit(.renderEnd, source: request.source, quality: request.quality,
                                   revision: token.revision, detail: maskDetail)
        guard !Task.isCancelled else { return false }
        guard isCurrent(token) else {
            let age = nextRevision >= token.revision ? nextRevision - token.revision : 0
            telemetry.stale(token.revision, age: age)
            KromoraObservability.liveEdit(.staleRevision, source: request.source, quality: request.quality,
                                       revision: token.revision, detail: "age=\(age)")
            return false
        }
        guard image != nil || gpuImage != nil else {
            telemetry.discard(token.revision)
            onFailure?(request)
            return false
        }
        onPublication?(Publication(
            request: request, image: image, gpuImage: gpuImage,
            revision: token.revision, assetID: token.assetID,
            sourceRevision: token.sourceRevision,
            displayRevision: token.displayRevision, phase: phase
        ))
        return true
    }

    private func isCurrent(_ token: Token) -> Bool {
        latestToken == token && latestRequest?.source == token.source
    }

    private static func request(_ request: RenderRequest, quality: RenderQuality) -> RenderRequest {
        Self.request(request, quality: quality, maskResolution: request.maskResolution)
    }

    private static func request(
        _ request: RenderRequest,
        quality: RenderQuality,
        maskResolution: MaskResolutionPolicy
    ) -> RenderRequest {
        RenderRequest(
            source: request.source,
            assetID: request.assetID,
            document: request.document,
            lut: request.lut,
            targetSize: request.targetSize,
            sourceROI: request.sourceROI,
            presentationImageExtent: request.presentationImageExtent,
            presentationNavigation: request.presentationNavigation,
            quality: quality,
            frameBudgetMilliseconds: request.frameBudgetMilliseconds,
            output: .raster,
            space: request.space,
            maskResolution: maskResolution,
            requestRevision: request.requestRevision
        )
    }
}
