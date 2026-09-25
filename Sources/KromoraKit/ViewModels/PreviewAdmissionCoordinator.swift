import AppKit
import CoreImage
import Foundation

/// The narrow values and publication hooks used by preview admission. The application model
/// remains the owner of its document, collection, and preview surfaces.
@MainActor
protocol PreviewAdmissionDestination: AnyObject {
    var admissionIsShuttingDown: Bool { get }
    var admissionImageSource: ImageSource? { get }
    var admissionSourceRevision: UInt64 { get }
    var admissionDisplayRevision: UInt64 { get }
    var admissionActiveAssetID: PhotoAssetID? { get }
    var admissionLastPresentedRequest: RenderRequest? { get }
    var admissionLastPresentedImage: CIImage? { get }
    var admissionInspectorPresented: Bool { get }
    var admissionHistogramLoading: Bool { get }
    var admissionHistogram: HistogramData? { get }
    var admissionHistogramErrorMessage: String? { get }
    var admissionSourceName: String { get }
    var admissionCollection: ImageCollection { get }
    var admissionEditStore: EditDocumentStore { get }
    var admissionPresentation: PreviewPresentationCoordinator { get }
    var admissionSourceSessionIsBusy: Bool { get }
    var admissionPreviewDebouncing: Bool { get }
    var admissionPreviewInteractionActive: Bool { get }
    var admissionPreviewBackingSize: CGSize { get }
    var admissionDocument: EditDocument { get }
    var admissionComparisonBaselineDocument: EditDocument { get }
    var admissionComparisonRevision: UInt64 { get }
    var admissionActiveSourceReference: EditSourceReference? { get }
    var admissionIsShowingOriginal: Bool { get }
    var admissionIsSideBySideVisible: Bool { get }
    var admissionHasOriginalPreview: Bool { get }
    var admissionHasComparisonPreviewCandidate: Bool { get }
    var admissionSelectedLook: CubeLUT? { get }
    var admissionCropToolActive: Bool { get }
    var admissionCanvasNavigation: CanvasNavigation { get }
    var admissionCropRotation: ImageRotation { get }
    var admissionCropFlipHorizontal: Bool { get }
    var admissionCropFlipVertical: Bool { get }
    var admissionCropVerticalPerspective: Double { get }
    var admissionCropHorizontalPerspective: Double { get }
    var admissionPreviewCoordinator: PreviewCoordinator { get }
    var pendingEditedThumbnailAssetID: PhotoAssetID? { get }
    func admitSettledEditedThumbnail(_ assetID: PhotoAssetID)
    func admissionClearPreview()
    func admissionPresentCacheRaster(
        _ image: CIImage, request: RenderRequest, assetID: PhotoAssetID?,
        sourceRevision: UInt64, displayRevision: UInt64
    )
    func admissionDocument(for assetID: PhotoAssetID) -> EditDocument?
    func admissionSourceReference(for item: ImageCollection.Item) -> EditSourceReference
    func admissionResolvedLUT(_ id: LUTID?) -> CubeLUT?
    func admissionAdjacentPlan(for document: EditDocument, nativeExtent: CGSize) -> ResolutionPlan
    func admissionCanonicalPlan(for document: EditDocument, nativeExtent: CGSize) -> ResolutionPlan
    func admissionSettledRequest(
        source: ImageSource, assetID: PhotoAssetID?, document: EditDocument, lut: CubeLUT?,
        plan: ResolutionPlan, canonical: Bool
    ) -> RenderRequest
    func publishAdmissionHistogram(_ histogram: HistogramData?)
    func publishAdmissionHistogramLoading(_ isLoading: Bool)
    func publishAdmissionHistogramError(_ message: String?)
    func publishAdmissionStatus(_ message: String)
    func admissionPresentOriginalPreview(_ image: CIImage, request: RenderRequest) -> Bool
    func admissionClearOriginalPreview()
}

/// Admission policy for preview and supporting work. Render execution remains in
/// `PreviewCoordinator`, and request generations/cache state remain in
/// `PreviewPresentationCoordinator`.
@MainActor
final class PreviewAdmissionCoordinator {
    private var histogramTaskRevision: UInt64?
    private var histogramTaskRequest: RenderRequest?
    private var histogramTaskAssetID: PhotoAssetID?
    private let histogramJobID = ImageWorkScheduler.JobID("histogram")
    private struct AdjacentPreviewCandidate: Sendable {
        let source: ImageSource
        let inMemoryDocument: EditDocument?
        let reference: EditSourceReference
    }
    private struct IdlePreviewCandidate: Sendable {
        let index: Int
        let source: ImageSource
        let inMemoryDocument: EditDocument?
        let reference: EditSourceReference
    }
    private struct IdlePreviewWorkItem: Sendable {
        let cursor: Int
        let request: RenderRequest?
    }
    let idlePreviewBuildJobID = ImageWorkScheduler.JobID("idle-preview-build")
    let adjacentPreviewPrefetchJobID = ImageWorkScheduler.JobID("adjacent-preview-prefetch")
    private var idleBuildTask: Task<Void, Never>?
    private var idleBuildGeneration: UInt64 = 0
    private var idleBuildCursor: Int?
    private static let maxItemsPerIdleSession = 20
    private var prefetchDelayTask: Task<Void, Never>?
    private var pendingPreviewCacheLookup:
        (request: RenderRequest, assetID: PhotoAssetID?, sourceRevision: UInt64, displayRevision: UInt64)?
    private var previewScheduledSourceRevision: UInt64?
    private let comparisonPreviewJobID = ImageWorkScheduler.JobID("comparison-preview")
    private var comparisonPreviewScheduledRevision: UInt64?
    private var comparisonPreviewRetriedRevision: UInt64?
    private var comparisonPreviewRetryTask: Task<Void, Never>?
    var previewBackingSize = CGSize(width: 1600, height: 1200)
    private static let intensityDebounceMs = 60
    private var previewDebounceTask: Task<Void, Never>?
    private var previewDebounceGeneration: UInt64 = 0
    var isPreviewInteractionActive = false

    private let workScheduler: ImageWorkScheduler
    private let engine: any RenderEngining
    weak var destination: (any PreviewAdmissionDestination)?

    init(
        workScheduler: ImageWorkScheduler,
        engine: any RenderEngining,
        destination: (any PreviewAdmissionDestination)? = nil
    ) {
        self.workScheduler = workScheduler
        self.engine = engine
        self.destination = destination
    }

    /// Recompute the histogram from the frame that was actually presented. It never rebuilds the
    /// source graph, so the pinned chart describes the same comparison or edited request on screen.
    func updateHistogram(
        for displayedRequest: RenderRequest? = nil,
        presentedImage: CIImage? = nil
    ) {
        guard let destination else { return }
        guard destination.admissionInspectorPresented else {
            cancelHistogram(clear: true)
            return
        }
        guard let imageSource = destination.admissionImageSource else {
            cancelHistogram(clear: true)
            return
        }
        guard let lastPresentedRequest = destination.admissionLastPresentedRequest else { return }
        let request = displayedRequest ?? lastPresentedRequest
        guard request.source == imageSource else {
            cancelHistogram(clear: true)
            return
        }
        guard let image = presentedImage ?? destination.admissionLastPresentedImage else { return }

        let sourceRevision = destination.admissionSourceRevision
        let displayRevision = destination.admissionDisplayRevision
        let assetID = destination.admissionActiveAssetID
        if workScheduler.contains(histogramJobID),
            histogramTaskAssetID == assetID,
            histogramTaskRevision == displayRevision,
            histogramTaskRequest == request
        {
            return
        }
        cancelHistogram(clear: false)
        histogramTaskRevision = displayRevision
        histogramTaskRequest = request
        histogramTaskAssetID = assetID
        destination.publishAdmissionHistogramLoading(true)
        destination.publishAdmissionHistogramError(nil)
        let engine = self.engine
        workScheduler.enqueue(id: histogramJobID, lane: .editor, priority: .histogram) {
            [weak destination, engine] in
            guard !Task.isCancelled, let destination,
                !destination.admissionIsShuttingDown
            else { return }
            let result = await engine.histogram(
                presentedImage: image, space: request.space, maxDimension: 512
            )
            guard !Task.isCancelled, !destination.admissionIsShuttingDown,
                destination.admissionInspectorPresented,
                assetID == destination.admissionActiveAssetID,
                sourceRevision == destination.admissionSourceRevision,
                displayRevision == destination.admissionDisplayRevision,
                destination.admissionImageSource == request.source
            else { return }
            destination.publishAdmissionHistogram(result)
            destination.publishAdmissionHistogramLoading(false)
            if result == nil {
                let message = "Histogram unavailable for \(destination.admissionSourceName)."
                destination.publishAdmissionHistogramError(message)
                destination.publishAdmissionStatus(message)
            } else {
                destination.publishAdmissionHistogramError(nil)
            }
        }
    }

    func cancelHistogram(clear: Bool, pump: Bool = true) {
        workScheduler.cancel(id: histogramJobID, pump: pump)
        histogramTaskRevision = nil
        histogramTaskRequest = nil
        histogramTaskAssetID = nil
        guard let destination else { return }
        if destination.admissionHistogramLoading {
            destination.publishAdmissionHistogramLoading(false)
        }
        if destination.admissionHistogramErrorMessage != nil {
            destination.publishAdmissionHistogramError(nil)
        }
        if clear, destination.admissionHistogram != nil {
            destination.publishAdmissionHistogram(nil)
        }
    }

    func shutdown() {
        cancelHistogram(clear: false, pump: false)
        cancelIdlePreviewBuild(resetCursor: true)
        workScheduler.cancel(id: adjacentPreviewPrefetchJobID, pump: false)
        prefetchDelayTask?.cancel()
        prefetchDelayTask = nil
        idleBuildTask?.cancel()
        idleBuildTask = nil
        previewDebounceGeneration &+= 1
        previewDebounceTask?.cancel()
        previewDebounceTask = nil
        pendingPreviewCacheLookup = nil
        comparisonPreviewRetryTask?.cancel()
        comparisonPreviewRetryTask = nil
        destination = nil
    }

    func cancelComparisonRetry() {
        comparisonPreviewRetryTask?.cancel()
        comparisonPreviewRetryTask = nil
    }

    func resetComparisonPreviewAdmission() {
        comparisonPreviewScheduledRevision = nil
        cancelComparisonRetry()
    }

    func scheduleOriginalPreview(
        allowHiddenPreparation: Bool = false,
        allowBeforePresentationConfirmation: Bool = false
    ) {
        guard let destination else { return }
        let hasCurrentPreviewCandidate = allowBeforePresentationConfirmation
            && destination.admissionHasComparisonPreviewCandidate
        guard destination.admissionLastPresentedRequest != nil || hasCurrentPreviewCandidate,
            destination.admissionIsSideBySideVisible || allowHiddenPreparation,
            let imageSource = destination.admissionImageSource
        else {
            comparisonPreviewScheduledRevision = nil
            cancelComparisonPreview()
            destination.admissionClearOriginalPreview()
            return
        }
        let comparisonRevision = destination.admissionComparisonRevision
        guard comparisonPreviewScheduledRevision != comparisonRevision else { return }
        let baseline = destination.admissionComparisonBaselineDocument
        let plan = destination.admissionPresentation.plan(
            for: baseline,
            nativeExtent: imageSource.nativeExtent,
            viewportSize: destination.admissionPreviewBackingSize,
            surface: .comparisonBaseline,
            navigation: destination.admissionCanvasNavigation
        )
        let sourceRevision = destination.admissionSourceRevision
        let assetID = destination.admissionActiveAssetID
        let sourceReference = destination.admissionActiveSourceReference
        comparisonPreviewScheduledRevision = comparisonRevision

        let accepted = workScheduler.enqueue(
            id: comparisonPreviewJobID, lane: .editor, priority: .comparison,
            onTerminal: { [weak self, weak destination] outcome in
                guard outcome != .completed, let self, let destination,
                    assetID == destination.admissionActiveAssetID,
                    sourceReference == destination.admissionActiveSourceReference,
                    sourceRevision == destination.admissionSourceRevision,
                    comparisonRevision == destination.admissionComparisonRevision,
                    self.comparisonPreviewScheduledRevision == comparisonRevision
                else { return }
                // An already displayed baseline remains correct when a redundant request is
                // evicted. Keep this revision admitted so a later Adjusted publication cannot
                // enqueue the same Original render again.
                if destination.admissionHasOriginalPreview { return }
                // A queued comparison can be evicted by a newer active-editor render. Leave the
                // revision retryable so the next settled publication can re-admit it.
                self.comparisonPreviewScheduledRevision = nil
            },
            operation: { [weak self, weak destination, engine] in
                guard !Task.isCancelled, let self, let destination,
                    assetID == destination.admissionActiveAssetID,
                    sourceReference == destination.admissionActiveSourceReference,
                    sourceRevision == destination.admissionSourceRevision,
                    comparisonRevision == destination.admissionComparisonRevision,
                    destination.admissionImageSource == imageSource
                else { return }
                let request = destination.admissionSettledRequest(
                    source: imageSource, assetID: assetID, document: baseline, lut: nil,
                    plan: plan, canonical: false
                )
                let gpuImage = await engine.makeCIImage(request)
                if let gpuImage {
                    guard !Task.isCancelled,
                        assetID == destination.admissionActiveAssetID,
                        sourceReference == destination.admissionActiveSourceReference,
                        sourceRevision == destination.admissionSourceRevision,
                        comparisonRevision == destination.admissionComparisonRevision,
                        destination.admissionImageSource == imageSource
                    else { return }
                    if !destination.admissionPresentOriginalPreview(gpuImage, request: request) {
                        self.comparisonPreviewDidFail(
                            sourceReference: sourceReference,
                            sourceRevision: sourceRevision, comparisonRevision: comparisonRevision
                        )
                    }
                    return
                }
                let cgImage = await engine.makeCGImage(request)
                guard !Task.isCancelled,
                    assetID == destination.admissionActiveAssetID,
                    sourceReference == destination.admissionActiveSourceReference,
                    sourceRevision == destination.admissionSourceRevision,
                    comparisonRevision == destination.admissionComparisonRevision,
                    destination.admissionImageSource == imageSource,
                    let cgImage
                else { return }
                if !destination.admissionPresentOriginalPreview(CIImage(cgImage: cgImage), request: request) {
                    self.comparisonPreviewDidFail(
                        sourceReference: sourceReference,
                        sourceRevision: sourceRevision, comparisonRevision: comparisonRevision
                    )
                }
            }
        )
        if !accepted, comparisonPreviewScheduledRevision == comparisonRevision {
            comparisonPreviewScheduledRevision = nil
        }
    }

    func comparisonPreviewDidFail(
        sourceReference: EditSourceReference?,
        sourceRevision: UInt64, comparisonRevision: UInt64
    ) {
        guard let destination, destination.admissionActiveAssetID != nil,
            sourceReference == destination.admissionActiveSourceReference,
            sourceRevision == destination.admissionSourceRevision,
            comparisonRevision == destination.admissionComparisonRevision,
            destination.admissionIsSideBySideVisible,
            comparisonPreviewScheduledRevision == comparisonRevision
        else { return }
        if destination.admissionHasOriginalPreview {
            // The current baseline is still displayed. A failed redundant refresh must not blank
            // it or create a retry loop for pixels that have not changed.
            return
        }
        comparisonPreviewScheduledRevision = nil
        destination.admissionClearOriginalPreview()
        destination.publishAdmissionStatus("Could not display the comparison preview. Retrying…")
        guard comparisonPreviewRetriedRevision != comparisonRevision else { return }
        comparisonPreviewRetriedRevision = comparisonRevision
        comparisonPreviewRetryTask?.cancel()
        comparisonPreviewRetryTask = Task { [weak self, weak destination] in
            try? await Task.sleep(for: .milliseconds(25))
            guard !Task.isCancelled, let self, let destination,
                sourceReference == destination.admissionActiveSourceReference,
                sourceRevision == destination.admissionSourceRevision,
                comparisonRevision == destination.admissionComparisonRevision,
                destination.admissionIsSideBySideVisible,
                self.comparisonPreviewScheduledRevision != comparisonRevision
            else { return }
            self.comparisonPreviewRetryTask = nil
            self.scheduleOriginalPreview(allowBeforePresentationConfirmation: true)
        }
    }

    func cancelComparisonPreview(pump: Bool = true) {
        workScheduler.cancel(id: comparisonPreviewJobID, pump: pump)
    }

    var isPreviewDebouncing: Bool { previewDebounceTask != nil }
    var scheduledSourceRevision: UInt64? { previewScheduledSourceRevision }

    func resetScheduledSourceRevision() { previewScheduledSourceRevision = nil }

    func cancelPreviewDebounce() {
        previewDebounceGeneration &+= 1
        previewDebounceTask?.cancel()
        previewDebounceTask = nil
    }

    func cancelPendingPreviewWork() {
        cancelPreviewDebounce()
        destination?.admissionPresentation.cancelCacheLookup()
        pendingPreviewCacheLookup = nil
        destination?.admissionPreviewCoordinator.cancel()
    }

    var displayRequest: (document: EditDocument, lut: CubeLUT?) {
        guard let destination else { return (EditDocument(), nil) }
        var requested = destination.admissionIsShowingOriginal
            ? destination.admissionComparisonBaselineDocument : destination.admissionDocument
        if destination.admissionCropToolActive {
            requested.rotation = requested.rotation.addingClockwiseQuarterTurns(
                destination.admissionCropRotation.rawValue / 90
            )
            requested.crop = CropAdjustments(
                straightenAngle: 0,
                flipHorizontal: destination.admissionCropFlipHorizontal,
                flipVertical: destination.admissionCropFlipVertical,
                verticalPerspective: destination.admissionCropVerticalPerspective,
                horizontalPerspective: destination.admissionCropHorizontalPerspective
            )
        }
        return destination.admissionIsShowingOriginal ? (requested, nil)
            : (requested, destination.admissionSelectedLook)
    }

    func schedulePreview() {
        cancelIdlePreviewBuild()
        submitSettledPreview(preemptsPredecessor: true)
    }

    func scheduleCropEntryPreview() {
        cancelIdlePreviewBuild()
        scheduleInteractivePreview()
    }

    func scheduleCorrectivePreview() {
        cancelIdlePreviewBuild()
        submitSettledPreview(preemptsPredecessor: false)
    }

    private func submitSettledPreview(preemptsPredecessor: Bool) {
        guard let destination else { return }
        cancelIdlePreviewBuild()
        guard !destination.admissionIsShuttingDown,
            let source = destination.admissionImageSource
        else { destination.admissionClearPreview(); return }
        let supersededLookup = pendingPreviewCacheLookup
        destination.admissionPresentation.advanceDisplayRevision()
        cancelHistogram(clear: false, pump: false)
        let (requested, look) = displayRequest
        let plan = destination.admissionPresentation.plan(
            for: requested, nativeExtent: source.nativeExtent, viewportSize: previewBackingSize,
            surface: .mainPreview, navigation: destination.admissionCanvasNavigation
        )
        previewScheduledSourceRevision = destination.admissionSourceRevision
        let request = makeSettledRequest(
            source: source, assetID: destination.admissionActiveAssetID,
            document: requested, lut: look, plan: plan,
            cropInteractionActive: destination.admissionCropToolActive,
            requestRevision: destination.admissionDisplayRevision
        )
        let assetID = destination.admissionActiveAssetID
        let sourceRevision = destination.admissionSourceRevision
        let displayRevision = destination.admissionDisplayRevision
        if !preemptsPredecessor, let supersededLookup,
            supersededLookup.sourceRevision == sourceRevision, supersededLookup.assetID == assetID
        {
            destination.admissionPresentation.cancelCacheLookup()
            destination.admissionPreviewCoordinator.submit(
                supersededLookup.request, phase: .settled, assetID: assetID,
                sourceRevision: sourceRevision, displayRevision: supersededLookup.displayRevision
            )
        }
        if request.sourceROI != nil {
            destination.admissionPresentation.cancelCacheLookup()
            pendingPreviewCacheLookup = nil
            submit(request, preemptsPredecessor: preemptsPredecessor,
                assetID: assetID, sourceRevision: sourceRevision, displayRevision: displayRevision)
            return
        }
        let key = destination.admissionPresentation.cacheKey(for: request)
        destination.admissionPresentation.lookupCache(for: key) { [weak self, weak destination] cached in
            guard let self, let destination, !destination.admissionIsShuttingDown,
                destination.admissionSourceRevision == sourceRevision,
                destination.admissionDisplayRevision == displayRevision,
                destination.admissionActiveAssetID == assetID,
                destination.admissionImageSource == request.source,
                self.displayRequest.document == request.document
            else { return }
            self.pendingPreviewCacheLookup = nil
            if let cached {
                destination.admissionPreviewCoordinator.cancel()
                destination.admissionPresentCacheRaster(
                    CIImage(cgImage: cached), request: request, assetID: assetID,
                    sourceRevision: sourceRevision, displayRevision: displayRevision
                )
            } else {
                self.submit(request, preemptsPredecessor: preemptsPredecessor,
                    assetID: assetID, sourceRevision: sourceRevision, displayRevision: displayRevision)
            }
        }
        pendingPreviewCacheLookup = (request, assetID, sourceRevision, displayRevision)
    }

    private func submit(
        _ request: RenderRequest, preemptsPredecessor: Bool, assetID: PhotoAssetID?,
        sourceRevision: UInt64, displayRevision: UInt64
    ) {
        guard let destination else { return }
        if preemptsPredecessor {
            destination.admissionPreviewCoordinator.submit(
                request, phase: .settled, assetID: assetID,
                sourceRevision: sourceRevision, displayRevision: displayRevision
            )
        } else {
            destination.admissionPreviewCoordinator.submitCorrective(
                request, assetID: assetID, sourceRevision: sourceRevision,
                displayRevision: displayRevision
            )
        }
    }

    private func makeSettledRequest(
        source: ImageSource, assetID: PhotoAssetID?, document: EditDocument, lut: CubeLUT?,
        plan: ResolutionPlan, canonical: Bool = false, cropInteractionActive: Bool = false,
        requestRevision: UInt64 = 0
    ) -> RenderRequest {
        RenderRequest(
            source: source, assetID: assetID, document: document, lut: lut,
            targetSize: plan.sourceSize,
            sourceROI: canonical || cropInteractionActive ? nil : plan.previewSourceROI(
                nativeExtent: document.rotation.orientedExtent(source.nativeExtent)
            ),
            presentationROI: canonical || cropInteractionActive ? nil : plan.visiblePresentationRect,
            presentationImageExtent: plan.presentationImageExtent,
            presentationNavigation: destination?.admissionCanvasNavigation ?? CanvasNavigation(),
            quality: .preview, output: .raster, space: .current, requestRevision: requestRevision
        )
    }

    func scheduleInteractivePreview() {
        guard let destination, let source = destination.admissionImageSource else { return }
        cancelIdlePreviewBuild()
        if !isPreviewInteractionActive { destination.admissionPresentation.advanceDisplayRevision() }
        cancelHistogram(clear: false, pump: false)
        let (requested, lut) = displayRequest
        let plan = destination.admissionPresentation.plan(
            for: requested, nativeExtent: source.nativeExtent, viewportSize: previewBackingSize,
            surface: .mainPreview, navigation: destination.admissionCanvasNavigation
        )
        let request = RenderRequest(
            source: source, assetID: destination.admissionActiveAssetID, document: requested,
            lut: lut, targetSize: plan.sourceSize,
            sourceROI: destination.admissionCropToolActive ? nil : plan.previewSourceROI(
                nativeExtent: requested.rotation.orientedExtent(source.nativeExtent)
            ),
            presentationROI: destination.admissionCropToolActive ? nil : plan.visiblePresentationRect,
            presentationImageExtent: plan.presentationImageExtent,
            presentationNavigation: destination.admissionCanvasNavigation,
            quality: .interactive, output: .raster, space: .current,
            requestRevision: destination.admissionDisplayRevision
        )
        destination.admissionPreviewCoordinator.submit(
            request, phase: .interactive, assetID: destination.admissionActiveAssetID,
            sourceRevision: destination.admissionSourceRevision,
            displayRevision: destination.admissionDisplayRevision
        )
    }

    func updatePreviewBackingSize(_ size: CGSize) {
        guard let destination else { return }
        let width = size.width.rounded(.down), height = size.height.rounded(.down)
        guard width >= 1, height >= 1, width.isFinite, height.isFinite,
            abs(width - previewBackingSize.width) > 1 || abs(height - previewBackingSize.height) > 1
        else { return }
        previewBackingSize = CGSize(width: width, height: height)
        guard destination.admissionImageSource != nil else { return }
        if isPreviewInteractionActive { scheduleInteractivePreview() } else { schedulePreview() }
    }

    func scheduleSettledPreviewAfterDebounce() {
        guard let destination else { return }
        cancelIdlePreviewBuild()
        previewDebounceTask?.cancel()
        previewDebounceGeneration &+= 1
        let generation = previewDebounceGeneration
        let revision = destination.admissionSourceRevision
        previewDebounceTask = Task { [weak self, weak destination] in
            try? await Task.sleep(for: .milliseconds(Self.intensityDebounceMs))
            guard !Task.isCancelled, let self, let destination,
                self.previewDebounceGeneration == generation,
                destination.admissionSourceRevision == revision
            else { return }
            self.previewDebounceTask = nil
            self.schedulePreview()
            if let assetID = destination.pendingEditedThumbnailAssetID {
                destination.admitSettledEditedThumbnail(assetID)
            }
        }
    }

    func beginInteraction() {
        cancelIdlePreviewBuild()
        destination?.admissionPresentation.advanceDisplayRevision()
        isPreviewInteractionActive = true
        destination?.admissionPreviewCoordinator.beginInteraction()
    }

    func endInteraction() {
        isPreviewInteractionActive = false
        previewDebounceTask?.cancel()
        previewDebounceTask = nil
        destination?.admissionPreviewCoordinator.endInteraction()
    }

    func cancelIdlePreviewBuild(resetCursor: Bool = false) {
        idleBuildGeneration &+= 1
        idleBuildTask?.cancel()
        idleBuildTask = nil
        workScheduler.cancel(id: idlePreviewBuildJobID, pump: false)
        if resetCursor { idleBuildCursor = nil }
    }

    func cancelAdjacentPreviewPrefetch() {
        workScheduler.cancel(id: adjacentPreviewPrefetchJobID, pump: false)
        prefetchDelayTask?.cancel()
        prefetchDelayTask = nil
    }

    func scheduleAdjacentPreviewPrefetch() {
        guard let destination else { return }
        let collection = destination.admissionCollection
        workScheduler.cancel(id: adjacentPreviewPrefetchJobID)
        prefetchDelayTask?.cancel()
        prefetchDelayTask = nil
        guard collection.isActive else { return }
        let selected = collection.selectedIndex
        let candidates = collection.filteredIndices
            .filter { $0 != selected && abs($0 - selected) <= 2 }
            .sorted { abs($0 - selected) < abs($1 - selected) }
            .prefix(2)
            .compactMap { index -> AdjacentPreviewCandidate? in
                let item = collection.items[index]
                guard let dimensions = item.asset.dimensions,
                    dimensions.width > 0, dimensions.height > 0
                else { return nil }
                let extent = CGSize(width: dimensions.width, height: dimensions.height)
                let source: ImageSource
                if let url = item.url {
                    source = ImageSource(url: url, nativeExtent: extent,
                        portableIdentity: item.asset.source.portableIdentity)
                } else if let data = item.imageData {
                    source = ImageSource(data: data, nativeExtent: extent,
                        dataFingerprint: item.dataFingerprint,
                        portableIdentity: item.asset.source.portableIdentity)
                } else { return nil }
                return AdjacentPreviewCandidate(
                    source: source, inMemoryDocument: destination.admissionDocument(for: item.id),
                    reference: destination.admissionSourceReference(for: item)
                )
            }
        guard !candidates.isEmpty else { return }
        let revision = destination.admissionSourceRevision
        let assetID = destination.admissionActiveAssetID
        let editStore = destination.admissionEditStore
        prefetchDelayTask = Task { [weak self, weak destination, candidates] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, let destination,
                destination.admissionActiveAssetID == assetID,
                destination.admissionSourceRevision == revision
            else { return }
            let coldCandidates = candidates.filter { $0.inMemoryDocument == nil }
            let storedResults = await editStore.load(for: coldCandidates.map(\.reference))
            guard !Task.isCancelled,
                destination.admissionActiveAssetID == assetID,
                destination.admissionSourceRevision == revision
            else { return }
            var storedResultIndex = 0
            var requests: [RenderRequest] = []
            requests.reserveCapacity(candidates.count)
            for candidate in candidates {
                let document: EditDocument
                if let inMemory = candidate.inMemoryDocument { document = inMemory }
                else {
                    let stored = storedResults[storedResultIndex]
                    storedResultIndex += 1
                    guard stored.isUsableForPrefetch else { continue }
                    document = stored.document
                }
                requests.append(destination.admissionSettledRequest(
                    source: candidate.source, assetID: candidate.reference.assetID,
                    document: document, lut: destination.admissionResolvedLUT(document.lut.lutID),
                    plan: destination.admissionAdjacentPlan(
                        for: document, nativeExtent: candidate.source.nativeExtent
                    ), canonical: false
                ))
            }
            guard !requests.isEmpty, !Task.isCancelled,
                destination.admissionActiveAssetID == assetID,
                destination.admissionSourceRevision == revision
            else { return }
            let engine = self.engine
            self.workScheduler.enqueue(
                id: self.adjacentPreviewPrefetchJobID, lane: .editor, priority: .background
            ) { [weak destination, engine] in
                guard !Task.isCancelled, let destination,
                    destination.admissionActiveAssetID == assetID,
                    destination.admissionSourceRevision == revision
                else { return }
                for request in requests {
                    guard !Task.isCancelled,
                        destination.admissionActiveAssetID == assetID,
                        destination.admissionSourceRevision == revision
                    else { return }
                    _ = await engine.makeCIImage(request)
                }
            }
        }
    }

    func scheduleIdlePreviewBuild() {
        guard let destination, idleBuildTask == nil else { return }
        cancelIdlePreviewBuild()
        let collection = destination.admissionCollection
        guard collection.isActive, !collection.isScanning,
            !destination.admissionSourceSessionIsBusy,
            !destination.admissionPreviewDebouncing,
            !destination.admissionPreviewInteractionActive,
            NSApplication.shared.isActive
        else { return }
        let candidates = collection.filteredIndices
            .filter { $0 != collection.selectedIndex }
            .sorted { abs($0 - collection.selectedIndex) < abs($1 - collection.selectedIndex) }
            .compactMap { index -> IdlePreviewCandidate? in
                let item = collection.items[index]
                guard let dimensions = item.asset.dimensions,
                    dimensions.width > 0, dimensions.height > 0
                else { return nil }
                let extent = CGSize(width: dimensions.width, height: dimensions.height)
                let source: ImageSource
                if let url = item.url {
                    source = ImageSource(url: url, nativeExtent: extent,
                        portableIdentity: item.asset.source.portableIdentity)
                } else if let data = item.imageData {
                    source = ImageSource(data: data, nativeExtent: extent,
                        dataFingerprint: item.dataFingerprint,
                        portableIdentity: item.asset.source.portableIdentity)
                } else { return nil }
                return IdlePreviewCandidate(
                    index: index, source: source,
                    inMemoryDocument: destination.admissionDocument(for: item.id),
                    reference: destination.admissionSourceReference(for: item)
                )
            }
        guard !candidates.isEmpty else { return }
        let generation = idleBuildGeneration
        let revision = destination.admissionSourceRevision
        let selectedAssetID = destination.admissionActiveAssetID
        idleBuildTask = Task { [weak self, weak destination, candidates] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self, let destination,
                !destination.admissionIsShuttingDown,
                self.idleBuildGeneration == generation,
                destination.admissionSourceRevision == revision,
                destination.admissionActiveAssetID == selectedAssetID,
                destination.admissionCollection.isActive,
                !destination.admissionCollection.isScanning,
                !destination.admissionSourceSessionIsBusy,
                !destination.admissionPreviewDebouncing,
                !destination.admissionPreviewInteractionActive,
                NSApplication.shared.isActive
            else {
                if let self, self.idleBuildGeneration == generation { self.idleBuildTask = nil }
                return
            }
            await self.runIdlePreviewBuild(
                candidates: candidates, generation: generation, sourceRevision: revision,
                selectedAssetID: selectedAssetID
            )
            if self.idleBuildGeneration == generation { self.idleBuildTask = nil }
        }
    }

    private func runIdlePreviewBuild(
        candidates: [IdlePreviewCandidate], generation: UInt64, sourceRevision: UInt64,
        selectedAssetID: PhotoAssetID?
    ) async {
        guard let destination else { return }
        let start = min(idleBuildCursor ?? 0, candidates.count)
        guard start < candidates.count else { return }
        let sessionCandidates = Array(candidates[start..<candidates.count].prefix(Self.maxItemsPerIdleSession))
        let coldCandidates = sessionCandidates.filter { $0.inMemoryDocument == nil }
        let storedResults = await destination.admissionEditStore.load(for: coldCandidates.map(\.reference))
        guard !Task.isCancelled, idleBuildGeneration == generation,
            destination.admissionSourceRevision == sourceRevision,
            destination.admissionActiveAssetID == selectedAssetID,
            !destination.admissionCollection.isScanning, NSApplication.shared.isActive
        else { return }
        var storedResultIndex = 0
        var workItems: [IdlePreviewWorkItem] = []
        for (offset, candidate) in sessionCandidates.enumerated() {
            let cursor = start + offset
            let document: EditDocument
            if let inMemory = candidate.inMemoryDocument { document = inMemory }
            else if storedResults.indices.contains(storedResultIndex) {
                let stored = storedResults[storedResultIndex]
                storedResultIndex += 1
                guard stored.isUsableForPrefetch else {
                    workItems.append(IdlePreviewWorkItem(cursor: cursor, request: nil)); continue
                }
                document = stored.document
            } else {
                storedResultIndex += 1
                workItems.append(IdlePreviewWorkItem(cursor: cursor, request: nil)); continue
            }
            let plan = destination.admissionCanonicalPlan(
                for: document, nativeExtent: candidate.source.nativeExtent
            )
            let request = destination.admissionSettledRequest(
                source: candidate.source, assetID: candidate.reference.assetID, document: document,
                lut: destination.admissionResolvedLUT(document.lut.lutID), plan: plan, canonical: true
            )
            let key = destination.admissionPresentation.cacheKey(for: request)
            workItems.append(IdlePreviewWorkItem(
                cursor: cursor,
                request: destination.admissionPresentation.cache.contains(key) ? nil : request
            ))
        }
        guard !workItems.isEmpty, !Task.isCancelled else { return }
        let engine = self.engine
        let cache = destination.admissionPresentation.cache
        let presentation = destination.admissionPresentation
        let scheduler = workScheduler
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            scheduler.enqueue(
                id: idlePreviewBuildJobID, lane: .editor, priority: .background,
                onTerminal: { _ in continuation.resume() }
            ) { [weak self, weak destination, engine, cache, presentation, workItems,
                generation, sourceRevision, selectedAssetID] in
                guard let self, let destination else { return }
                for item in workItems {
                    guard !Task.isCancelled,
                        self.idleBuildGeneration == generation,
                        destination.admissionSourceRevision == sourceRevision,
                        destination.admissionActiveAssetID == selectedAssetID,
                        !destination.admissionCollection.isScanning,
                        NSApplication.shared.isActive
                    else { return }
                    guard let request = item.request else {
                        self.idleBuildCursor = item.cursor + 1; continue
                    }
                    let key = presentation.cacheKey(for: request)
                    guard !cache.contains(key) else {
                        self.idleBuildCursor = item.cursor + 1; continue
                    }
                    let image = await engine.makeCIImage(request)
                    guard !Task.isCancelled,
                        self.idleBuildGeneration == generation,
                        destination.admissionSourceRevision == sourceRevision,
                        destination.admissionActiveAssetID == selectedAssetID
                    else { return }
                    if let image { presentation.writeCanonical(image, for: request) }
                    self.idleBuildCursor = item.cursor + 1
                }
            }
        }
    }
}
