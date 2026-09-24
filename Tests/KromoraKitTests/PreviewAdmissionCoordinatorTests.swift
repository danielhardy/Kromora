import CoreImage
import XCTest

@testable import KromoraKit

@MainActor
final class PreviewAdmissionCoordinatorTests: TempDirectoryTestCase {
    func testIdleAndAdjacentPrefetchJobsHaveIndependentCancellationIDs() async {
        let scheduler = ImageWorkScheduler()
        let coordinator = PreviewAdmissionCoordinator(
            workScheduler: scheduler, engine: RenderEngine.shared
        )
        XCTAssertNotEqual(coordinator.idlePreviewBuildJobID, coordinator.adjacentPreviewPrefetchJobID)

        let wait: ImageWorkScheduler.Operation = {
            try? await Task.sleep(for: .seconds(30))
        }
        scheduler.enqueue(
            id: coordinator.idlePreviewBuildJobID, lane: .editor, priority: .background,
            operation: wait
        )
        scheduler.enqueue(
            id: coordinator.adjacentPreviewPrefetchJobID, lane: .editor, priority: .background,
            operation: wait
        )
        coordinator.cancelIdlePreviewBuild()
        XCTAssertTrue(scheduler.contains(coordinator.adjacentPreviewPrefetchJobID))
        XCTAssertFalse(scheduler.contains(coordinator.idlePreviewBuildJobID))

        coordinator.cancelAdjacentPreviewPrefetch()
        await scheduler.cancelAllAndWait()
    }

    func testStaleDisplayRevisionAndAssetDropCacheHit() async throws {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        destination.admissionLastPresentedRequest = makeRequest(source: destination.source)
        destination.admissionLastPresentedImage = CIImage(color: .black)
        let request = makeRequest(source: destination.source)
        let key = destination.admissionPresentation.cacheKey(for: request)
        destination.admissionPresentation.cache.write(
            try Fixtures.makeCGImage(width: 32, height: 24), for: key
        )
        let coordinator = makeCoordinator(destination: destination, engine: engine)

        coordinator.schedulePreview()
        destination.assetID = PhotoAssetID.imported(UUID())
        destination.admissionPresentation.advanceDisplayRevision()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(destination.cachePublicationCount, 0)

        _ = try await engine.render(request)
        destination.admissionInspectorPresented = true
        destination.admissionInspectorTabIsInfo = true
        await engine.gateHistogram()
        coordinator.updateHistogram(
            for: request, presentedImage: destination.admissionLastPresentedImage
        )
        try await waitUntil("histogram renderer admission") {
            await engine.histogramRequests.count == 1
        }
        destination.admissionPresentation.advanceDisplayRevision()
        destination.assetID = PhotoAssetID.imported(UUID())
        await engine.releaseHistograms()
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(destination.histogramPublicationCount, 0)
        coordinator.shutdown()
        await destination.scheduler.cancelAllAndWait()
    }

    func testIdleAdmissionNeverCallsPreviewPublication() async {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        let coordinator = makeCoordinator(destination: destination, engine: engine)

        coordinator.scheduleIdlePreviewBuild()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(destination.cachePublicationCount, 0)
        XCTAssertEqual(destination.histogramPublicationCount, 0)
        coordinator.shutdown()
    }

    func testComparisonRetryRunsOncePerComparisonRevision() async throws {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        destination.admissionLastPresentedRequest = makeRequest(source: destination.source)
        destination.admissionIsSideBySideVisible = true
        destination.admissionHasComparisonPreviewCandidate = true
        let coordinator = makeCoordinator(destination: destination, engine: engine)

        coordinator.scheduleOriginalPreview()
        coordinator.comparisonPreviewDidFail(
            sourceReference: destination.admissionActiveSourceReference,
            sourceRevision: destination.admissionSourceRevision,
            comparisonRevision: destination.admissionComparisonRevision
        )
        try await Task.sleep(for: .milliseconds(50))
        coordinator.scheduleOriginalPreview()
        coordinator.comparisonPreviewDidFail(
            sourceReference: destination.admissionActiveSourceReference,
            sourceRevision: destination.admissionSourceRevision,
            comparisonRevision: destination.admissionComparisonRevision
        )
        try await Task.sleep(for: .milliseconds(60))

        let requests = await engine.renderRequests
        XCTAssertEqual(requests.filter { $0.document == destination.admissionComparisonBaselineDocument }.count, 2)
        coordinator.cancelComparisonRetry()
        await destination.scheduler.cancelAllAndWait()
    }

    func testROIRequestDoesNotAdoptCanonicalCacheHit() async throws {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        destination.admissionPreviewBackingSize = CGSize(width: 12, height: 12)
        destination.admissionCanvasNavigation.setZoom(8)
        let coordinator = makeCoordinator(destination: destination, engine: engine)
        let canonical = makeRequest(source: destination.source)
        let key = destination.admissionPresentation.cacheKey(for: canonical)
        destination.admissionPresentation.cache.write(
            try Fixtures.makeCGImage(width: 32, height: 24), for: key
        )

        coordinator.schedulePreview()
        try await waitUntil("ROI render admission") {
            await engine.renderRequests.count == 1
        }

        XCTAssertEqual(destination.cachePublicationCount, 0)
        let requests = await engine.renderRequests
        XCTAssertNotNil(requests.first?.sourceROI)
        await destination.scheduler.cancelAllAndWait()
    }

    private func makeCoordinator(
        destination: FakePreviewAdmissionDestination,
        engine: FakeRenderEngine
    ) -> PreviewAdmissionCoordinator {
        PreviewAdmissionCoordinator(
            workScheduler: destination.scheduler,
            engine: engine,
            destination: destination
        )
    }

    private func makeDestination(engine: FakeRenderEngine) -> FakePreviewAdmissionDestination {
        let scheduler = ImageWorkScheduler()
        let cache = PreviewDiskCache(
            directory: tempDirectory.appendingPathComponent("admission-cache-\(UUID().uuidString)"),
            capBytes: 10_000_000
        )
        let presentation = PreviewPresentationCoordinator(cache: cache, engine: engine)
        let renderCoordinator = PreviewCoordinator(engine: engine, scheduler: scheduler)
        return FakePreviewAdmissionDestination(
            scheduler: scheduler,
            engine: engine,
            presentation: presentation,
            renderCoordinator: renderCoordinator
        )
    }

    private func makeRequest(source: ImageSource) -> RenderRequest {
        RenderRequest(source: source, document: EditDocument(), quality: .preview)
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(5),
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !(await condition()) {
            if ContinuousClock.now >= deadline {
                throw TestSynchronizationError.timedOut(description, "condition did not settle")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class FakePreviewAdmissionDestination: PreviewAdmissionDestination {
    let scheduler: ImageWorkScheduler
    let admissionPreviewCoordinator: PreviewCoordinator
    let admissionPresentation: PreviewPresentationCoordinator
    let admissionCollection = ImageCollection()
    let admissionEditStore = EditDocumentStore.makeInMemoryProjectionStore()
    let admissionImageSource: ImageSource?
    var admissionSourceRevision: UInt64 = 1
    var admissionDisplayRevision: UInt64 { admissionPresentation.displayRevision }
    var assetID = PhotoAssetID.imported(UUID())
    var admissionActiveAssetID: PhotoAssetID? { assetID }
    var admissionLastPresentedRequest: RenderRequest?
    var admissionLastPresentedImage: CIImage?
    var admissionInspectorPresented = false
    var admissionInspectorTabIsInfo = false
    var admissionHistogramLoading = false
    var admissionHistogram: HistogramData?
    var admissionHistogramErrorMessage: String?
    var admissionSourceName = "test"
    var admissionSourceSessionIsBusy = false
    var admissionPreviewDebouncing = false
    var admissionPreviewInteractionActive = false
    var admissionPreviewBackingSize = CGSize(width: 1600, height: 1200)
    var admissionDocument = EditDocument()
    var admissionComparisonBaselineDocument = EditDocument()
    var admissionComparisonRevision: UInt64 { admissionPresentation.comparisonRevision }
    var admissionActiveSourceReference: EditSourceReference? {
        EditSourceReference(assetID: assetID, url: nil)
    }
    var admissionIsShowingOriginal = false
    var admissionIsSideBySideVisible = false
    var admissionHasComparisonPreviewCandidate = false
    var admissionSelectedLook: CubeLUT?
    var admissionCropToolActive = false
    var admissionCanvasNavigation = CanvasNavigation()
    var admissionCropRotation = ImageRotation(rawValue: 0)!
    var admissionCropFlipHorizontal = false
    var admissionCropFlipVertical = false
    var admissionCropVerticalPerspective = 0.0
    var admissionCropHorizontalPerspective = 0.0
    var pendingEditedThumbnailAssetID: PhotoAssetID?
    var admissionIsShuttingDown = false
    var cachePublicationCount = 0
    var histogramPublicationCount = 0
    var statusMessage: String?

    init(
        scheduler: ImageWorkScheduler,
        engine: FakeRenderEngine,
        presentation: PreviewPresentationCoordinator,
        renderCoordinator: PreviewCoordinator
    ) {
        self.scheduler = scheduler
        self.admissionPresentation = presentation
        self.admissionPreviewCoordinator = renderCoordinator
        admissionImageSource = ImageSource(
            backing: .data(Data("preview-admission-test".utf8)),
            kind: .standard,
            nativeExtent: CGSize(width: 32, height: 24)
        )
    }

    var source: ImageSource { admissionImageSource! }
    func admitSettledEditedThumbnail(_ assetID: PhotoAssetID) {}
    func admissionClearPreview() {}
    func admissionPresentCacheRaster(
        _ image: CIImage, request: RenderRequest, assetID: PhotoAssetID?,
        sourceRevision: UInt64, displayRevision: UInt64
    ) { cachePublicationCount += 1 }
    func admissionDocument(for assetID: PhotoAssetID) -> EditDocument? { nil }
    func admissionSourceReference(for item: ImageCollection.Item) -> EditSourceReference {
        EditSourceReference(assetID: item.id, url: item.url)
    }
    func admissionResolvedLUT(_ id: LUTID?) -> CubeLUT? { nil }
    func admissionAdjacentPlan(for document: EditDocument, nativeExtent: CGSize) -> ResolutionPlan {
        admissionPresentation.plan(
            for: document, nativeExtent: nativeExtent,
            viewportSize: admissionPreviewBackingSize, surface: .mainPreview,
            navigation: admissionCanvasNavigation
        )
    }
    func admissionCanonicalPlan(for document: EditDocument, nativeExtent: CGSize) -> ResolutionPlan {
        admissionAdjacentPlan(for: document, nativeExtent: nativeExtent)
    }
    func admissionSettledRequest(
        source: ImageSource, assetID: PhotoAssetID?, document: EditDocument, lut: CubeLUT?,
        plan: ResolutionPlan, canonical: Bool
    ) -> RenderRequest {
        RenderRequest(
            source: source, assetID: assetID, document: document, lut: lut,
            targetSize: plan.sourceSize,
            sourceROI: canonical ? nil : plan.previewSourceROI(
                nativeExtent: document.rotation.orientedExtent(source.nativeExtent)
            ),
            presentationROI: canonical ? nil : plan.visiblePresentationRect,
            presentationImageExtent: plan.presentationImageExtent,
            quality: .preview, output: .raster
        )
    }
    func publishAdmissionHistogram(_ histogram: HistogramData?) {
        histogramPublicationCount += 1
        self.admissionHistogram = histogram
    }
    func publishAdmissionHistogramLoading(_ isLoading: Bool) { admissionHistogramLoading = isLoading }
    func publishAdmissionHistogramError(_ message: String?) { admissionHistogramErrorMessage = message }
    func publishAdmissionStatus(_ message: String) { statusMessage = message }
    func admissionPresentOriginalPreview(_ image: CIImage, request: RenderRequest) -> Bool { true }
    func admissionClearOriginalPreview() {}
}
