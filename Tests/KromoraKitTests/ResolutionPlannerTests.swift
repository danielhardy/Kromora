import CoreGraphics
import XCTest
@testable import KromoraKit

@MainActor
final class ResolutionPlannerTests: TempDirectoryTestCase {
    private let native = CGSize(width: 6_000, height: 4_000)

    func testQuarterCropRequestsNativeDetailWhenItWouldOtherwiseUpscale() {
        var planner = ResolutionPlanner()
        let plan = planner.plan(
            nativeExtent: native,
            crop: CropAdjustments(normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25)),
            viewportSize: CGSize(width: 1_600, height: 1_200)
        )

        XCTAssertEqual(plan.sourceSize, native)
        XCTAssertTrue(plan.isNativeResolution)
        XCTAssertEqual(plan.cropRect, CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
    }

    func testFitDetailIsDiscreteAndHysteresisBoundsResizeTransitions() {
        var planner = ResolutionPlanner()
        let initial = planner.plan(nativeExtent: native, viewportSize: CGSize(width: 1_620, height: 1_080))
        XCTAssertEqual(initial.scale, 0.5, "the first adequate level should be reusable")
        XCTAssertEqual(initial.sourceSize, CGSize(width: 3_000, height: 2_000))

        let nearBoundary = planner.plan(nativeExtent: native, viewportSize: CGSize(width: 1_500, height: 1_000))
        XCTAssertEqual(nearBoundary.level, initial.level,
                       "small resize changes must not thrash the selected level")

        let lower = planner.plan(nativeExtent: native, viewportSize: CGSize(width: 1_200, height: 800))
        XCTAssertEqual(lower.scale, 0.25)

        let upgrade = planner.plan(nativeExtent: native, viewportSize: CGSize(width: 1_560, height: 1_040))
        XCTAssertEqual(upgrade.scale, 0.5)
    }

    func testPanelBackingPixelsAndZoomDriveThePlanWithoutExceedingNativeBounds() {
        var planner = ResolutionPlanner()
        let sideBySide = planner.plan(
            nativeExtent: native, viewportSize: CGSize(width: 800, height: 1_200)
        )
        XCTAssertEqual(sideBySide.sourceSize, CGSize(width: 1_500, height: 1_000))

        var navigation = CanvasNavigation()
        navigation.setZoom(8)
        let deep = planner.plan(
            nativeExtent: native, viewportSize: CGSize(width: 800, height: 1_200), navigation: navigation
        )
        XCTAssertEqual(deep.sourceSize, native)
        XCTAssertLessThanOrEqual(deep.sourceSize.width, native.width)
        XCTAssertLessThanOrEqual(deep.sourceSize.height, native.height)
        XCTAssertGreaterThan(deep.visibleSourceRect.width, 0)
        XCTAssertLessThan(deep.visibleSourceRect.width, native.width)
    }

    func testZoomInThenFitReturnsToFreshCompletePhotoPlanAndCacheIdentity() {
        let source = ImageSource(data: Data("zoom-round-trip".utf8), nativeExtent: native)
        let document = EditDocument()
        let viewport = CGSize(width: 1_600, height: 1_200)
        var navigation = CanvasNavigation()
        var planner = ResolutionPlanner()

        navigation.setZoom(8)
        let zoomed = planner.plan(
            nativeExtent: native, viewportSize: viewport, navigation: navigation
        )
        let zoomedRequest = RenderRequest(
            source: source, document: document, targetSize: zoomed.sourceSize,
            sourceROI: zoomed.previewSourceROI(nativeExtent: native), quality: .preview
        )
        XCTAssertNotNil(zoomedRequest.sourceROI)

        navigation.fit()
        let zoomedOut = planner.plan(
            nativeExtent: native, viewportSize: viewport, navigation: navigation
        )
        var freshPlanner = ResolutionPlanner()
        let fresh = freshPlanner.plan(
            nativeExtent: native, viewportSize: viewport, navigation: navigation
        )
        let zoomedOutRequest = RenderRequest(
            source: source, document: document, targetSize: zoomedOut.sourceSize,
            sourceROI: zoomedOut.previewSourceROI(nativeExtent: native), quality: .preview
        )
        let freshRequest = RenderRequest(
            source: source, document: document, targetSize: fresh.sourceSize,
            sourceROI: fresh.previewSourceROI(nativeExtent: native), quality: .preview
        )

        XCTAssertNil(zoomedOutRequest.sourceROI, "fit must request a complete source frame")
        XCTAssertEqual(zoomedOut, fresh, "fit after deep zoom must match a fresh planner")
        XCTAssertEqual(
            Self.previewCacheKey(for: zoomedOutRequest),
            Self.previewCacheKey(for: freshRequest),
            "the recovered fit request must address the same cache entry as a fresh render"
        )
    }

    func testAppViewModelDoesNotShareHysteresisBetweenRenderingSurfaces() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let quarterCrop = EditDocument(crop: CropAdjustments(
            normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25)
        ))
        let uncropped = EditDocument()
        let viewport = CGSize(width: 1_600, height: 1_200)

        let mainHighDetail = viewModel.resolutionPlan(
            for: quarterCrop, nativeExtent: native, viewportSize: viewport, surface: .mainPreview
        )
        XCTAssertTrue(mainHighDetail.isNativeResolution)

        // A shared planner would still be at native detail here and would only step down to .75
        // because of downgrade hysteresis. A comparison surface starts from its own adequate .5
        // level, so the high-detail main-preview request cannot pollute this request.
        let comparison = viewModel.resolutionPlan(
            for: uncropped, nativeExtent: native, viewportSize: viewport,
            surface: .comparisonBaseline
        )
        XCTAssertEqual(comparison.scale, 0.5)

        let histogram = viewModel.resolutionPlan(
            for: uncropped, nativeExtent: native, viewportSize: viewport, surface: .histogram
        )
        XCTAssertEqual(histogram.scale, 0.5)
    }

    func testThumbnailScalePlansDetailForTheCroppedOutput() {
        let source = ImageSource(data: Data(), nativeExtent: native)
        let request = RenderRequest(
            source: source,
            document: EditDocument(crop: CropAdjustments(normalizedRect: CGRect(
                x: 0.25, y: 0.25, width: 0.25, height: 0.25
            ))),
            targetSize: CGSize(width: 240, height: 240),
            quality: .thumbnail,
            output: .raster
        )

        XCTAssertEqual(
            request.renderScale,
            .preview(maxSize: CGSize(width: 960, height: 960)),
            "thumbnail source planning must reserve pixels for the committed crop"
        )
    }

    private static func previewCacheKey(for request: RenderRequest) -> PreviewCacheKey {
        PreviewCacheKey(
            source: RenderSourceFingerprint(request.source),
            documentHash: RenderCacheHash.digest(request.document),
            lutFingerprint: request.lut?.cacheFingerprint ?? "none",
            targetScale: RenderScaleKey(
                request.renderScale, nativeExtent: request.source.nativeExtent),
            sourceROI: request.sourceROI,
            quality: request.quality,
            space: request.space,
            pipelineVersion: RenderPipeline.cacheVersion
        )
    }

    func testThumbnailScalePreservesChangingCropAspectRatio() {
        let source = ImageSource(data: Data(), nativeExtent: native)
        let request = RenderRequest(
            source: source,
            document: EditDocument(crop: CropAdjustments(normalizedRect: CGRect(
                x: 0.1, y: 0.1, width: 0.8, height: 0.3
            ))),
            targetSize: CGSize(width: 240, height: 240),
            quality: .thumbnail,
            output: .raster
        )

        guard case .preview(let size) = request.renderScale else {
            return XCTFail("thumbnail requests must use preview scaling")
        }
        XCTAssertEqual(size.width, 300, accuracy: 0.000_001)
        XCTAssertEqual(
            size.height, 800, accuracy: 0.000_001,
            "the source box must account for both crop dimensions, not only its area"
        )
    }
}
