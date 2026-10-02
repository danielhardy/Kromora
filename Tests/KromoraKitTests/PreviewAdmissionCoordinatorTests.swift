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

    func testLateNeighbourResolutionAfterNavigationCannotPublish() async throws {
        let urls = try ["a.png", "b.png", "c.png"].map {
            try Fixtures.writeGradientPNG(width: 16, height: 12, named: $0, in: tempDirectory)
        }
        let session = try PortableLibrarySession(
            at: tempDirectory.appendingPathComponent("NeighbourWarm.kromoralibrary"))
        _ = try session.importURLs(urls, duplicatePolicy: .importAnyway)
        let browsingAssets = try session.browsingAssets()
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        destination.admissionCollection.loadPortableAssets(browsingAssets)
        await destination.admissionCollection.scanCompletion()
        destination.admissionCollection.setSelection(at: 0)
        let activeItem = destination.admissionCollection.items[0]
        destination.assetID = activeItem.id
        destination.admissionNavigationIsEdit = true
        destination.admissionCanWarmAdjacentDocuments = true
        let neighbor = destination.admissionCollection.items[1]
        let resolvedNeighbor = try await session.materializedAsset(
            for: neighbor.asset.source.portableIdentity.assetID)

        let coordinator = makeCoordinator(destination: destination, engine: engine)
        coordinator.scheduleAdjacentPreviewPrefetch()
        try await waitUntil("the neighbour resolution to suspend") {
            destination.resolutionStarted
        }

        // Simulate a newer selection while the package record read is still in flight.
        destination.assetID = PhotoAssetID.imported(UUID())
        destination.admissionSourceRevision += 1
        coordinator.cancelAdjacentPreviewPrefetch()
        destination.pendingResolution?.resume(returning: resolvedNeighbor)
        destination.pendingResolution = nil
        try await Task.sleep(for: .milliseconds(50))

        let currentNeighbor = try XCTUnwrap(
            destination.admissionCollection.items.first { $0.id == neighbor.id })
        XCTAssertEqual(
            currentNeighbor.asset.source.portableIdentity.sourceFingerprint.decoderVersion,
            "browsing-v1"
        )
        coordinator.shutdown()
        await destination.scheduler.cancelAllAndWait()
        await session.shutdown()
    }

    func testStaleDisplayRevisionAndAssetDropStoredFrameHit() async throws {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        destination.admissionLastPresentedRequest = makeRequest(source: destination.source)
        destination.admissionLastPresentedImage = CIImage(color: .black)
        let request = makeRequest(source: destination.source)
        let coordinator = makeCoordinator(destination: destination, engine: engine)
        try await seedStoredFrame(destination, edit: request.document.editHash)

        // The selection moved on before the submission: the session no longer owns this
        // revision, so the stored frame must neither present nor suppress the render.
        destination.assetID = PhotoAssetID.imported(UUID())
        destination.admissionSourceRevision += 1
        coordinator.schedulePreview()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(destination.cachePublicationCount, 0)

        _ = try await engine.render(request)
        destination.admissionInspectorPresented = true
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

    func testROIRequestDoesNotAdoptCanonicalStoredFrame() async throws {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        destination.admissionPreviewBackingSize = CGSize(width: 12, height: 12)
        destination.admissionCanvasNavigation.setZoom(8)
        let coordinator = makeCoordinator(destination: destination, engine: engine)
        try await seedStoredFrame(destination, edit: EditDocument().editHash)

        coordinator.schedulePreview()
        try await waitUntil("ROI render admission") {
            await engine.renderRequests.count == 1
        }

        XCTAssertEqual(destination.cachePublicationCount, 0)
        let requests = await engine.renderRequests
        XCTAssertNotNil(requests.first?.sourceROI)
        await destination.scheduler.cancelAllAndWait()
    }

    func testExactStoredFrameSkipsTheRendererAndPresentsThroughTheConfirmedTail() async throws {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        let coordinator = makeCoordinator(destination: destination, engine: engine)
        try await seedStoredFrame(destination, edit: EditDocument().editHash)
        destination.admissionStoredEditsResolved = true

        coordinator.schedulePreview()

        XCTAssertEqual(destination.cachePublicationCount, 1)
        try await Task.sleep(for: .milliseconds(80))
        let renders = await engine.renderRequests.count + engine.previewRequests.count
        XCTAssertEqual(renders, 0, "an exact stored frame must not submit a preview render")
        coordinator.shutdown()
        await destination.scheduler.cancelAllAndWait()
    }

    func testStaleStoredFrameWaitsForStoredEditsThenRendersOnce() async throws {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        let coordinator = makeCoordinator(destination: destination, engine: engine)
        try await seedStoredFrame(destination, edit: "an-older-edit")
        destination.admissionStoredEditsResolved = false

        coordinator.schedulePreview()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(coordinator.hasDeferredSettledPreview)
        let deferredRenders = await engine.previewRequests.count
        XCTAssertEqual(deferredRenders, 0, "no speculative render while the stored frame can cover")
        XCTAssertEqual(destination.cachePublicationCount, 0)

        destination.admissionStoredEditsResolved = true
        coordinator.resumeDeferredSettledPreview()
        try await waitUntil("the single settled render") {
            await engine.previewRequests.count == 1
        }
        XCTAssertFalse(coordinator.hasDeferredSettledPreview)
        XCTAssertEqual(destination.cachePublicationCount, 0, "a stale frame never stands in")
        XCTAssertEqual(destination.staleRefinementPreparationCount, 1)
        coordinator.shutdown()
        await destination.scheduler.cancelAllAndWait()
    }

    func testPendingStoredFrameLookupDefersTheRenderUntilItFinishes() async throws {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        let coordinator = makeCoordinator(destination: destination, engine: engine)
        destination.admissionStoredEditsResolved = true
        let session = destination.beginSession()
        var finished = false
        destination.admissionPresentation.beginStoredFrameLookup(
            assetID: session.assetID, identity: session.identity, generation: session.generation
        ) { _ in finished = true }

        coordinator.schedulePreview()
        XCTAssertTrue(coordinator.hasDeferredSettledPreview)
        try await waitUntil("lookup completion") { finished }
        coordinator.resumeDeferredSettledPreview()
        try await waitUntil("render after a miss") { await engine.previewRequests.count == 1 }
        coordinator.shutdown()
        await destination.scheduler.cancelAllAndWait()
    }

    func testStoredLookIdentityMakesAWarmOpenExactBeforeTheLookScanFinishes() async throws {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        let coordinator = makeCoordinator(destination: destination, engine: engine)
        let lutID = LUTID(raw: "warm-look")
        destination.admissionDocument = EditDocument(lut: LUTSettings(lutID: lutID, intensity: 1))
        let look = LookSignature.resolved(id: lutID, contentHash: "bytes-1")
        try await seedStoredFrame(
            destination, edit: destination.admissionDocument.editHash, look: look
        )
        destination.admissionStoredEditsResolved = true
        // The Look browser has not resolved the table: the request itself is unresolved.
        XCTAssertNil(destination.admissionSelectedLook)

        destination.storedLookSignature = nil
        coordinator.schedulePreview()
        XCTAssertEqual(destination.cachePublicationCount, 0, "without the stored identity it renders")
        try await waitUntil("provisional render") { await engine.previewRequests.count == 1 }

        destination.storedLookSignature = look
        coordinator.schedulePreview()
        XCTAssertEqual(destination.cachePublicationCount, 1)
        coordinator.shutdown()
        await destination.scheduler.cancelAllAndWait()
    }

    func testStoredFrameOfAReplacedSourceIsNeverACandidate() async throws {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        let coordinator = makeCoordinator(destination: destination, engine: engine)
        let replaced = FrameFixtures.identity(
            asset: destination.source.portableIdentity.assetID, content: "the-old-source"
        )
        try await seedStoredFrame(
            destination, edit: EditDocument().editHash, identity: replaced, expectCandidate: false
        )
        destination.admissionStoredEditsResolved = true

        coordinator.schedulePreview()

        XCTAssertEqual(destination.cachePublicationCount, 0)
        try await waitUntil("render of the current source") {
            await engine.previewRequests.count == 1
        }
        coordinator.shutdown()
        await destination.scheduler.cancelAllAndWait()
    }

    func testComparisonAndCropFramesNeverConsultTheStoredFrame() async throws {
        let engine = FakeRenderEngine()
        let destination = makeDestination(engine: engine)
        let coordinator = makeCoordinator(destination: destination, engine: engine)
        try await seedStoredFrame(destination, edit: EditDocument().editHash)
        destination.admissionStoredEditsResolved = true
        destination.admissionIsShowingOriginal = true

        coordinator.schedulePreview()

        XCTAssertEqual(destination.cachePublicationCount, 0)
        try await waitUntil("original render") { await engine.previewRequests.count == 1 }
        coordinator.shutdown()
        await destination.scheduler.cancelAllAndWait()
    }

    /// Stores a preview for the destination's photo and runs the selection-time lookup, so the
    /// presentation coordinator holds it as the session's candidate.
    private func seedStoredFrame(
        _ destination: FakePreviewAdmissionDestination, edit: String,
        look: LookSignature = .none,
        identity: PortablePhotoIdentity? = nil, expectCandidate: Bool = true
    ) async throws {
        let frameIdentity = identity ?? destination.source.portableIdentity
        let store = destination.admissionPresentation.store
        await store.enqueueWrite(
            try FrameFixtures.frame(identity: frameIdentity, edit: edit, look: look)
        )
        await store.waitForPendingWrites()
        let session = destination.beginSession()
        var finished: Bool?
        destination.admissionPresentation.beginStoredFrameLookup(
            assetID: session.assetID, identity: session.identity, generation: session.generation
        ) { candidate in finished = candidate != nil }
        try await waitUntil("stored frame lookup") { finished != nil }
        XCTAssertEqual(finished, expectCandidate)
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
        let store = LatestPreviewFrameStore(
            directory: tempDirectory.appendingPathComponent("admission-frames-\(UUID().uuidString)"),
            capBytes: 10_000_000
        )
        let presentation = PreviewPresentationCoordinator(store: store, engine: engine)
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
    var admissionPortableLibrary: PortableLibrarySession? { nil }
    var admissionCanWarmAdjacentDocuments = false
    var admissionNavigationIsEdit = false
    var resolutionStarted = false
    var pendingResolution: CheckedContinuation<PhotoAsset, Error>?
    let admissionImageSource: ImageSource?
    var admissionSourceRevision: UInt64 = 1
    var admissionDisplayRevision: UInt64 { admissionPresentation.displayRevision }
    var admissionDisplayDocument: EditDocument {
        admissionLastPresentedRequest?.document ?? admissionDocument
    }
    var admissionDisplayLUT: CubeLUT? { admissionLastPresentedRequest?.lut ?? admissionSelectedLook }
    var assetID = PhotoAssetID.imported(UUID())
    var admissionActiveAssetID: PhotoAssetID? { assetID }
    var admissionLastPresentedRequest: RenderRequest?
    var admissionLastPresentedImage: CIImage?
    var admissionInspectorPresented = false
    var admissionHistogramLoading = false
    var admissionHistogram: HistogramData?
    var admissionOriginalPreviewImage: CIImage?
    var admissionHistogramErrorMessage: String?
    var admissionSourceName = "test"
    var admissionSourceSessionIsBusy = false
    var admissionPreviewDebouncing = false
    var admissionPreviewInteractionActive = false
    var admissionPreviewBackingSize = CGSize(width: 1600, height: 1200)
    var admissionStoredEditsResolved = false
    var storedLookSignature: LookSignature?
    func admissionStoredLookSignature(for lutID: LUTID?) -> LookSignature? {
        storedLookSignature?.lutID == lutID ? storedLookSignature : nil
    }
    var admissionDocument = EditDocument()
    var admissionComparisonBaselineDocument = EditDocument()
    var admissionComparisonRevision: UInt64 { admissionPresentation.comparisonRevision }
    var admissionActiveSourceReference: EditSourceReference? {
        EditSourceReference(assetID: assetID, url: nil)
    }
    var admissionIsShowingOriginal = false
    var admissionIsSideBySideVisible = false
    var admissionHasOriginalPreview = false
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
    var staleRefinementPreparationCount = 0
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

    func admissionResolveBrowsingAsset(for assetID: PortablePhotoAssetID) async throws -> PhotoAsset
    {
        _ = assetID
        resolutionStarted = true
        return try await withCheckedThrowingContinuation { continuation in
            pendingResolution = continuation
        }
    }

    /// Start the presentation session a real selection would have begun for this photo.
    func beginSession() -> (
        assetID: PhotoAssetID, identity: PortablePhotoIdentity, generation: UInt64
    ) {
        let identity = source.portableIdentity
        admissionPresentation.beginPresentationSession(
            assetID: assetID, identity: identity, generation: admissionSourceRevision
        )
        return (assetID, identity, admissionSourceRevision)
    }
    func admitSettledEditedThumbnail(_ assetID: PhotoAssetID) {}
    func admitDeferredEditedThumbnails() {}
    func admissionClearPreview() {}
    func admissionScheduleOriginalPreview() {}
    func admissionPresentCacheRaster(
        _ image: CIImage, request: RenderRequest, assetID: PhotoAssetID?,
        sourceRevision: UInt64, displayRevision: UInt64
    ) { cachePublicationCount += 1 }
    func admissionPrepareStaleRefinement(using digest: PerceptualDigest) {
        staleRefinementPreparationCount += 1
    }
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
