import XCTest
import CoreGraphics
import CoreImage
import Combine
@testable import KromoraKit

final class CanvasNavigationTests: XCTestCase {
    private let landscape = CGRect(x: 0, y: 0, width: 400, height: 200)
    private let viewport = CGSize(width: 300, height: 300)

    private func assertPoint(
        _ actual: CGPoint, equals expected: CGPoint, accuracy: CGFloat = 0.000_001,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
    }

    func testFitShowsTheWholeImageAndCentersIt() {
        let navigation = CanvasNavigation()
        let transform = navigation.transform(imageExtent: landscape, viewportSize: viewport)

        XCTAssertEqual(transform.scale, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(transform.imageSize, CGSize(width: 300, height: 150))
        XCTAssertEqual(transform.origin, CGPoint(x: 0, y: 75))
    }

    func testFillCoversTheViewport() {
        var navigation = CanvasNavigation()
        navigation.fill()
        let transform = navigation.transform(imageExtent: landscape, viewportSize: viewport)

        XCTAssertEqual(transform.scale, 1.5, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(transform.imageSize.width, viewport.width)
        XCTAssertGreaterThanOrEqual(transform.imageSize.height, viewport.height)
        XCTAssertEqual(transform.origin.y, 0, accuracy: 0.000_001)
    }

    func testFitCentersAPortraitImageInALandscapeViewport() {
        let navigation = CanvasNavigation()
        let portrait = CGRect(x: 0, y: 0, width: 200, height: 400)
        let viewport = CGSize(width: 400, height: 200)
        let transform = navigation.transform(imageExtent: portrait, viewportSize: viewport)

        XCTAssertEqual(transform.scale, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(transform.imageSize, CGSize(width: 100, height: 200))
        XCTAssertEqual(transform.origin.x, 150, accuracy: 0.000_001)
        XCTAssertEqual(transform.origin.y, 0, accuracy: 0.000_001)
    }

    func testFillCoversALandscapeViewportWithAPortraitImage() {
        var navigation = CanvasNavigation()
        navigation.fill()
        let portrait = CGRect(x: 0, y: 0, width: 200, height: 400)
        let viewport = CGSize(width: 400, height: 200)
        let transform = navigation.transform(imageExtent: portrait, viewportSize: viewport)

        XCTAssertEqual(transform.scale, 2, accuracy: 0.000_001)
        XCTAssertEqual(transform.imageSize.width, viewport.width, accuracy: 0.000_001)
        XCTAssertGreaterThan(transform.imageSize.height, viewport.height)
        XCTAssertEqual(transform.origin.x, 0, accuracy: 0.000_001)
        XCTAssertLessThan(transform.origin.y, 0)
    }

    func testPanIsClampedToKeepTheImageCoveringTheViewport() {
        var navigation = CanvasNavigation()
        navigation.setZoom(4)
        navigation.pan(by: CGSize(width: 10_000, height: -10_000),
                       imageExtent: landscape, viewportSize: viewport)
        let transform = navigation.transform(imageExtent: landscape, viewportSize: viewport)

        XCTAssertEqual(transform.origin.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(transform.origin.y, viewport.height - transform.imageSize.height,
                       accuracy: 0.000_001)
    }

    func testPanMovesTheImageInTheDirectionOfTheViewportDelta() {
        var navigation = CanvasNavigation()
        navigation.setZoom(4)
        let before = navigation.transform(imageExtent: landscape, viewportSize: viewport)

        let delta = CGSize(width: 24, height: 32)
        navigation.pan(by: delta, imageExtent: landscape, viewportSize: viewport)
        let after = navigation.transform(imageExtent: landscape, viewportSize: viewport)

        XCTAssertEqual(after.origin.x, before.origin.x + delta.width, accuracy: 0.000_001)
        XCTAssertEqual(after.origin.y, before.origin.y + delta.height, accuracy: 0.000_001)
    }

    func testInvalidZoomValuesAreSafeAndClamped() {
        var navigation = CanvasNavigation()
        navigation.setZoom(.infinity)
        XCTAssertEqual(navigation.zoom, 1)
        navigation.setZoom(.nan)
        XCTAssertEqual(navigation.zoom, 1)
        navigation.setZoom(-10)
        XCTAssertEqual(navigation.zoom, CanvasNavigation.minimumZoom)
        navigation.setZoom(100)
        XCTAssertEqual(navigation.zoom, CanvasNavigation.maximumZoom)
    }

    func testDoubleClickUsesDeterministicFallbackAndTogglesBackToFit() {
        var navigation = CanvasNavigation()

        navigation.toggleFitAndRememberedZoom()
        XCTAssertEqual(navigation.mode, .custom)
        XCTAssertEqual(navigation.zoom, CanvasNavigation.doubleClickFallbackZoom)
        XCTAssertEqual(navigation.rememberedZoom, CanvasNavigation.doubleClickFallbackZoom)

        navigation.toggleFitAndRememberedZoom()
        XCTAssertEqual(navigation.mode, .fit)
        XCTAssertEqual(navigation.zoom, 1)
        XCTAssertEqual(navigation.focalPoint, CanvasNavigation.center)
        XCTAssertEqual(navigation.rememberedZoom, CanvasNavigation.doubleClickFallbackZoom)

        navigation.toggleFitAndRememberedZoom()
        XCTAssertEqual(navigation.mode, .custom)
        XCTAssertEqual(navigation.zoom, CanvasNavigation.doubleClickFallbackZoom)
    }

    func testFitAndFillRetainTheLastChosenZoom() {
        var navigation = CanvasNavigation()
        navigation.setZoom(4)

        navigation.fit()
        XCTAssertEqual(navigation.rememberedZoom, 4)
        navigation.toggleFitAndRememberedZoom()
        XCTAssertEqual(navigation.zoom, 4)

        navigation.fill()
        navigation.toggleFitAndRememberedZoom()
        XCTAssertEqual(navigation.mode, .fit)
        XCTAssertEqual(navigation.rememberedZoom, 4)
        navigation.toggleFitAndRememberedZoom()
        XCTAssertEqual(navigation.mode, .custom)
        XCTAssertEqual(navigation.zoom, 4)
    }

    func testRememberedZoomIsUpdatedByGestureAndClampedSafely() {
        var navigation = CanvasNavigation()
        navigation.multiplyZoom(by: 3)
        XCTAssertEqual(navigation.rememberedZoom, 3)

        navigation.fit()
        navigation.toggleFitAndRememberedZoom()
        XCTAssertEqual(navigation.zoom, 3)

        navigation.setZoom(100)
        XCTAssertEqual(navigation.rememberedZoom, CanvasNavigation.maximumZoom)
        navigation.fit()
        navigation.toggleFitAndRememberedZoom()
        XCTAssertEqual(navigation.zoom, CanvasNavigation.maximumZoom)

        let clamped = CanvasNavigation(rememberedZoom: .infinity)
        XCTAssertEqual(clamped.rememberedZoom, 1)
        XCTAssertEqual(CanvasNavigation(rememberedZoom: -10).rememberedZoom,
                       CanvasNavigation.minimumZoom)
    }

    func testFocalPointSurvivesViewportResize() {
        var navigation = CanvasNavigation()
        navigation.setZoom(3)
        navigation.pan(by: CGSize(width: -40, height: 25),
                       imageExtent: landscape, viewportSize: viewport)
        let before = navigation.transform(imageExtent: landscape, viewportSize: viewport)
        let resized = navigation.transform(
            imageExtent: landscape, viewportSize: CGSize(width: 500, height: 240)
        )

        XCTAssertNotEqual(before.origin, resized.origin)
        XCTAssertGreaterThanOrEqual(resized.origin.x, 500 - resized.imageSize.width)
        XCTAssertLessThanOrEqual(resized.origin.x, 0)
    }

    func testRenderResolutionGrowsWithZoomButNeverRequestsMoreThanNativeExtent() {
        var navigation = CanvasNavigation()
        XCTAssertEqual(
            navigation.renderResolutionMultiplier(imageExtent: landscape.size, viewportSize: viewport),
            1,
            accuracy: 0.000_001
        )
        navigation.setZoom(4)
        let multiplier = navigation.renderResolutionMultiplier(
            imageExtent: landscape.size, viewportSize: viewport
        )
        XCTAssertEqual(multiplier, 4, accuracy: 0.000_001)

        navigation.setZoom(100)
        XCTAssertLessThanOrEqual(
            navigation.renderResolutionMultiplier(imageExtent: landscape.size, viewportSize: viewport),
            CanvasNavigation.maximumZoom
        )
    }

    func testMaskTransformRoundTripsOrientedPortraitAndBottomLeftCrop() {
        // ImageDecoder supplies the oriented size, so an EXIF-6 landscape source is represented
        // here as its upright portrait extent. The persisted crop is intentionally bottom-left;
        // mask points use upper-left coordinates.
        let sourceSize = CGSize(width: 300, height: 500)
        let crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.5)
        )
        var navigation = CanvasNavigation()
        navigation.fill()
        navigation.setZoom(2.25)
        navigation.pan(by: CGSize(width: -70, height: 35),
                       imageExtent: CGRect(origin: .zero, size: sourceSize),
                       viewportSize: CGSize(width: 420, height: 280))
        let transform = CanvasMaskTransform(
            sourceSize: sourceSize, crop: crop, navigation: navigation,
            viewportSize: CGSize(width: 420, height: 280), backingScale: 2
        )

        for point in [CGPoint(x: 0.1, y: 0.3), CGPoint(x: 0.45, y: 0.55), CGPoint(x: 0.8, y: 0.8)] {
            let viewportPoint = try! XCTUnwrap(transform.viewportPoint(forSourceNormalized: point))
            let roundTrip = try! XCTUnwrap(transform.sourceNormalizedPoint(forViewport: viewportPoint))
            XCTAssertEqual(roundTrip.x, point.x, accuracy: 0.000_001)
            XCTAssertEqual(roundTrip.y, point.y, accuracy: 0.000_001)
        }
        assertPoint(transform.cropRect.origin, equals: CGPoint(x: 0.1, y: 0.3))
        XCTAssertEqual(transform.cropRect.width, 0.7, accuracy: 0.000_001)
        XCTAssertEqual(transform.cropRect.height, 0.5, accuracy: 0.000_001)
    }

    func testMaskTransformIsRetinaScaleInvariant() throws {
        let sourceSize = CGSize(width: 1600, height: 900)
        var navigation = CanvasNavigation()
        navigation.setZoom(1.75)
        navigation.pan(by: CGSize(width: -90, height: 28),
                       imageExtent: CGRect(origin: .zero, size: sourceSize),
                       viewportSize: CGSize(width: 500, height: 320))
        let oneX = CanvasMaskTransform(
            sourceSize: sourceSize, navigation: navigation,
            viewportSize: CGSize(width: 500, height: 320), backingScale: 1
        )
        let twoX = CanvasMaskTransform(
            sourceSize: sourceSize, navigation: navigation,
            viewportSize: CGSize(width: 500, height: 320), backingScale: 2
        )
        let sourcePoint = CGPoint(x: 0.73, y: 0.18)
        let onePoint = try XCTUnwrap(oneX.viewportPoint(forSourceNormalized: sourcePoint))
        let twoPoint = try XCTUnwrap(twoX.viewportPoint(forSourceNormalized: sourcePoint))
        XCTAssertEqual(onePoint.x, twoPoint.x, accuracy: 0.000_001)
        XCTAssertEqual(onePoint.y, twoPoint.y, accuracy: 0.000_001)
        assertPoint(try XCTUnwrap(twoX.sourceNormalizedPoint(forViewport: twoPoint)), equals: sourcePoint)
    }

    func testMaskTransformConvertsViewportDeltaWithoutCropOrBackingAmplification() throws {
        let sourceSize = CGSize(width: 2400, height: 1200)
        let crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.15, y: 0.2, width: 0.65, height: 0.5)
        )
        var navigation = CanvasNavigation()
        navigation.fill()
        navigation.setZoom(3)
        navigation.pan(
            by: CGSize(width: -180, height: 44),
            imageExtent: CGRect(origin: .zero, size: sourceSize),
            viewportSize: CGSize(width: 640, height: 420)
        )
        let transform = CanvasMaskTransform(
            sourceSize: sourceSize, crop: crop, navigation: navigation,
            viewportSize: CGSize(width: 640, height: 420), backingScale: 2
        )
        let center = CGPoint(x: 0.52, y: 0.58)
        let start = try XCTUnwrap(transform.viewportPoint(forSourceNormalized: center))
        let viewportDelta = CGSize(width: 10, height: -6)
        let normalizedDelta = try XCTUnwrap(
            transform.sourceNormalizedDelta(forViewportDelta: viewportDelta)
        )
        let moved = CGPoint(x: center.x + normalizedDelta.x, y: center.y + normalizedDelta.y)
        let movedViewport = try XCTUnwrap(transform.viewportPoint(forSourceNormalized: moved))

        XCTAssertEqual(movedViewport.x - start.x, viewportDelta.width, accuracy: 0.000_001)
        XCTAssertEqual(movedViewport.y - start.y, viewportDelta.height, accuracy: 0.000_001)
        XCTAssertEqual(
            normalizedDelta.x,
            viewportDelta.width * 2 / transform.canvasTransform.scale / sourceSize.width,
            accuracy: 0.000_000_001
        )
        XCTAssertEqual(
            normalizedDelta.y,
            viewportDelta.height * 2 / transform.canvasTransform.scale / sourceSize.height,
            accuracy: 0.000_000_001
        )
    }

    func testMaskTransformFollowsFitFillZoomPanAndWindowResize() throws {
        let sourceSize = CGSize(width: 1200, height: 800)
        let sourcePoint = CGPoint(x: 0.25, y: 0.65)
        var navigation = CanvasNavigation()
        let fit = CanvasMaskTransform(
            sourceSize: sourceSize, navigation: navigation,
            viewportSize: CGSize(width: 600, height: 400)
        )
        let fitPoint = try XCTUnwrap(fit.viewportPoint(forSourceNormalized: sourcePoint))
        assertPoint(fitPoint, equals: CGPoint(x: 150, y: 260))

        navigation.fill()
        navigation.setZoom(2)
        navigation.pan(by: CGSize(width: -120, height: 40),
                       imageExtent: CGRect(origin: .zero, size: sourceSize),
                       viewportSize: CGSize(width: 600, height: 400))
        let zoomed = CanvasMaskTransform(
            sourceSize: sourceSize, navigation: navigation,
            viewportSize: CGSize(width: 600, height: 400)
        )
        let zoomedPoint = try XCTUnwrap(zoomed.viewportPoint(forSourceNormalized: sourcePoint))
        XCTAssertNotEqual(zoomedPoint, fitPoint)
        assertPoint(try XCTUnwrap(zoomed.sourceNormalizedPoint(forViewport: zoomedPoint)), equals: sourcePoint)

        let resized = CanvasMaskTransform(
            sourceSize: sourceSize, navigation: navigation,
            viewportSize: CGSize(width: 900, height: 540)
        )
        let resizedPoint = try XCTUnwrap(resized.viewportPoint(forSourceNormalized: sourcePoint))
        assertPoint(try XCTUnwrap(resized.sourceNormalizedPoint(forViewport: resizedPoint)), equals: sourcePoint)
    }
}

@MainActor
final class CanvasObservationTests: TempDirectoryTestCase {
    private func waitUntil(
        _ description: String, timeout: TimeInterval = 5,
        _ condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !(await condition()) {
            if Date() > deadline {
                throw TestSynchronizationError.timedOut(
                    description, "condition did not become true")
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func nextROIRequest(
        from fake: FakeRenderEngine, after count: Int
    ) async throws -> FakeRenderEngine.Request {
        try await waitUntil("the next viewport ROI request") {
            (await fake.previewRequests).dropFirst(count).contains { $0.sourceROI != nil }
        }
        let requests = await fake.previewRequests
        return try XCTUnwrap(requests.dropFirst(count).first { $0.sourceROI != nil })
    }

    private func assertContains(
        _ roi: CGRect, _ visible: CGRect,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let epsilon: CGFloat = 0.01
        XCTAssertLessThanOrEqual(roi.minX, visible.minX + epsilon, file: file, line: line)
        XCTAssertLessThanOrEqual(roi.minY, visible.minY + epsilon, file: file, line: line)
        XCTAssertGreaterThanOrEqual(roi.maxX + epsilon, visible.maxX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(roi.maxY + epsilon, visible.maxY, file: file, line: line)
    }

    func testPanCanvasPreservesPointerDirectionOnBothAxes() async throws {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let imageURL = try Fixtures.writeGradientPNG(
            width: 100, height: 80, named: "pan.png", in: tempDirectory
        )
        viewModel.openImage(url: imageURL)
        let deadline = Date().addingTimeInterval(5)
        while viewModel.sourceImage == nil {
            if Date() > deadline {
                XCTFail("timed out waiting for the image to load")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        viewModel.setCanvasZoom(4)

        let viewport = CGSize(width: 80, height: 60)
        let before = viewModel.canvasNavigation.transform(
            imageExtent: CGRect(origin: .zero, size: viewModel.sourceSize),
            viewportSize: viewport
        )

        let delta = CGSize(width: 10, height: 12)
        viewModel.panCanvas(by: delta, viewportSize: viewport)
        let after = viewModel.canvasNavigation.transform(
            imageExtent: CGRect(origin: .zero, size: viewModel.sourceSize),
            viewportSize: viewport
        )

        XCTAssertEqual(after.origin.x, before.origin.x + delta.width, accuracy: 0.000_001)
        XCTAssertEqual(after.origin.y, before.origin.y + delta.height, accuracy: 0.000_001)
    }

    func testPanAtDeepZoomRequestsROIsThatCoverEveryViewportEdge() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        let imageURL = try Fixtures.writeGradientPNG(
            width: 100, height: 80, named: "deep-pan.png", in: tempDirectory
        )
        viewModel.openImage(url: imageURL)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }

        let viewport = CGSize(width: 80, height: 60)
        viewModel.updatePreviewBackingSize(viewport)
        for zoom in [4.0, 8.0, CanvasNavigation.maximumZoom] {
            let beforeZoom = await fake.previewRequests.count
            viewModel.setCanvasZoom(zoom)
            _ = try await nextROIRequest(from: fake, after: beforeZoom)

            viewModel.beginCanvasInteraction()
            let edgeDeltas = [
                CGSize(width: 10_000, height: 10_000),   // top-left
                CGSize(width: -10_000, height: 0),       // top-right
                CGSize(width: 0, height: -10_000),       // bottom-right
                CGSize(width: 10_000, height: 0),        // bottom-left
            ]
            for delta in edgeDeltas {
                let before = await fake.previewRequests.count
                viewModel.panCanvas(by: delta, viewportSize: viewport)
                let request = try await nextROIRequest(from: fake, after: before)
                let plan = viewModel.resolutionPlan(
                    for: viewModel.document, nativeExtent: viewModel.sourceSize,
                    viewportSize: viewport, surface: .mainPreview
                )
                assertContains(
                    try XCTUnwrap(request.sourceROI), plan.visibleSourceRect,
                    file: #filePath, line: #line
                )
            }
            viewModel.endCanvasInteraction()
        }
    }

    func testEditTriggeredPreviewKeepsThePannedFocalPoint() async throws {
        let fake = FakeRenderEngine()
        let viewModel = makeAppViewModel(engine: fake)
        let imageURL = try Fixtures.writeGradientPNG(
            width: 100, height: 80, named: "edit-pan.png", in: tempDirectory
        )
        viewModel.openImage(url: imageURL)
        try await waitUntil("the image to load") { viewModel.sourceImage != nil }

        let viewport = CGSize(width: 80, height: 60)
        viewModel.updatePreviewBackingSize(viewport)
        viewModel.setCanvasZoom(8)
        _ = try await nextROIRequest(from: fake, after: 0)
        viewModel.panCanvas(by: CGSize(width: -12, height: 9), viewportSize: viewport)
        let focalBeforeEdit = viewModel.canvasNavigation.focalPoint

        let beforeEdit = await fake.previewRequests.count
        viewModel.setToneCurvePoint(
            LightCurvePoint(input: 0.5, output: 0.5), output: 0.8
        )
        try await waitUntil("the tone-curve preview") {
            (await fake.previewRequests).dropFirst(beforeEdit).contains {
                $0.document.light.toneCurve.value(at: 0.5) == 0.8
            }
        }

        XCTAssertEqual(viewModel.canvasNavigation.focalPoint, focalBeforeEdit)
        let renderRequests = await fake.renderRequests
        let request = try XCTUnwrap(renderRequests.last {
            $0.document.light.toneCurve.value(at: 0.5) == 0.8
        })
        XCTAssertEqual(
            request.presentationNavigation, viewModel.canvasNavigation,
            "an edit-triggered ROI must be planned for the current pan"
        )
    }

    func testHighFrequencyCanvasAndCropUpdatesBypassBroadModelPublisher() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = CIImage(color: .gray).cropped(
            to: CGRect(x: 0, y: 0, width: 100, height: 80)
        )

        var appChanges = 0
        var canvasChanges = 0
        var inspectorChanges = 0
        let appSubscription = viewModel.objectWillChange.sink { _ in appChanges += 1 }
        let canvasSubscription = viewModel.canvasState.objectWillChange.sink {
            _ in canvasChanges += 1
        }
        let inspectorSubscription = viewModel.inspectorState.objectWillChange.sink {
            _ in inspectorChanges += 1
        }

        // A wheel/pinch update is presentation-only and must not fan out through AppViewModel.
        viewModel.setCanvasZoom(2)
        XCTAssertEqual(appChanges, 0)
        XCTAssertGreaterThan(canvasChanges, 0)

        // Crop-handle movement has the same contract. The opening transition may update status,
        // so begin first and measure only the pointer-frequency draft mutation.
        viewModel.beginCrop()
        appChanges = 0
        canvasChanges = 0
        viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.7))
        XCTAssertEqual(appChanges, 0)
        XCTAssertGreaterThan(canvasChanges, 0)

        // Inspector chrome is independently observable and is not forwarded through the broad
        // model publisher either.
        appChanges = 0
        viewModel.inspectorState.tab = .effects
        XCTAssertEqual(appChanges, 0)
        XCTAssertGreaterThan(inspectorChanges, 0)

        withExtendedLifetime((appSubscription, canvasSubscription, inspectorSubscription)) {}
    }

    func testSourceResetClearsNavigationAndCropTransientState() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.sourceImage = CIImage(color: .gray).cropped(
            to: CGRect(x: 0, y: 0, width: 100, height: 80)
        )
        viewModel.setCanvasZoom(3)
        viewModel.beginCrop()
        viewModel.updateCropDraft(CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5))

        viewModel.canvasState.resetForSource()

        XCTAssertEqual(viewModel.canvasState.navigation, CanvasNavigation())
        XCTAssertFalse(viewModel.canvasState.isCropToolActive)
        XCTAssertNil(viewModel.canvasState.cropDraft)
    }

    func testCanvasDoubleClickToggleIsPresentationOnly() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let document = viewModel.document

        viewModel.toggleCanvasZoom()
        XCTAssertEqual(viewModel.canvasNavigation.mode, .custom)
        XCTAssertEqual(viewModel.canvasNavigation.zoom, CanvasNavigation.doubleClickFallbackZoom)
        XCTAssertEqual(viewModel.document, document)

        viewModel.toggleCanvasZoom()
        XCTAssertEqual(viewModel.canvasNavigation.mode, .fit)
        XCTAssertEqual(viewModel.document, document)
    }

    func testMaskOverlayStateBypassesBroadModelPublisher() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let state = MaskOverlayInteractionState()
        var appChanges = 0
        var overlayChanges = 0
        let appSubscription = viewModel.objectWillChange.sink { _ in appChanges += 1 }
        let overlaySubscription = state.objectWillChange.sink { _ in overlayChanges += 1 }

        state.activate()
        state.beginPointer(at: CGPoint(x: 0.2, y: 0.3), time: 1)
        state.dragPointer(to: CGPoint(x: 0.4, y: 0.5), time: 2)
        state.selectTool(.radial)

        XCTAssertGreaterThan(overlayChanges, 0)
        XCTAssertEqual(appChanges, 0)
        withExtendedLifetime((appSubscription, overlaySubscription)) {}
    }
}
