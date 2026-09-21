import CoreGraphics
import XCTest

@testable import KromoraKit

final class CropROITests: TempDirectoryTestCase {
    private let native = CGSize(width: 6_000, height: 4_000)

    func testROIExtentTestSmallCommittedCropAtFitUsesOnlyTheCropPixels() {
        var planner = ResolutionPlanner()
        let plan = planner.plan(
            nativeExtent: native,
            crop: CropAdjustments(
                normalizedRect: CGRect(x: 0.375, y: 0.375, width: 0.25, height: 0.25)),
            viewportSize: CGSize(width: 1_600, height: 1_200)
        )

        let idealROI = plan.visibleSourceRect.width * plan.visibleSourceRect.height
        let developedROI = CGFloat(
            Int((plan.visibleSourceRect.width * plan.scale).rounded(.toNearestOrAwayFromZero))
                * Int(
                    (plan.visibleSourceRect.height * plan.scale).rounded(.toNearestOrAwayFromZero))
        )

        XCTAssertEqual(
            plan.visibleSourceRect, CGRect(x: 2_250, y: 1_500, width: 1_500, height: 1_000))
        XCTAssertLessThanOrEqual(developedROI, idealROI * 1.5)
        XCTAssertLessThan(developedROI, CGFloat(Int(native.width * native.height)) / 4)
        XCTAssertTrue(
            plan.coversPresentedPhoto(nativeExtent: native),
            "a fit crop's visible rectangle is the complete presented photo"
        )
    }

    func testResolutionPlannerFullImageFitIsANoOpROI() {
        var planner = ResolutionPlanner()
        let plan = planner.plan(
            nativeExtent: native,
            viewportSize: CGSize(width: 1_600, height: 1_200)
        )

        XCTAssertEqual(plan.visibleSourceRect, CGRect(origin: .zero, size: native))
    }

    func testResolutionPlannerDeepZoomRequestsNativeDetailOnlyForVisibleROI() {
        var planner = ResolutionPlanner()
        var navigation = CanvasNavigation()
        navigation.setZoom(8)
        let plan = planner.plan(
            nativeExtent: native,
            crop: CropAdjustments(
                normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)),
            viewportSize: CGSize(width: 800, height: 600),
            navigation: navigation
        )

        XCTAssertTrue(plan.isNativeResolution)
        XCTAssertEqual(plan.sourceSize, native)
        XCTAssertLessThan(
            plan.visibleSourceRect.width * plan.visibleSourceRect.height,
            native.width * native.height / 16)
        XCTAssertGreaterThan(plan.visibleSourceRect.minX, 0)
    }

    func testFitCropCoversThePresentedPhotoAndZoomedCropDoesNot() {
        var planner = ResolutionPlanner()
        let crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        let fit = planner.plan(
            nativeExtent: native,
            crop: crop,
            viewportSize: CGSize(width: 1_600, height: 1_200)
        )
        XCTAssertNotNil(
            fit.previewSourceROI(nativeExtent: native),
            "a cropped fit still has a source ROI so discarded pixels are skipped")
        XCTAssertTrue(
            fit.coversPresentedPhoto(nativeExtent: native),
            "that ROI is the complete cropped photo and must fill the canvas")

        var navigation = CanvasNavigation()
        navigation.setZoom(8)
        let zoomed = planner.plan(
            nativeExtent: native,
            crop: crop,
            viewportSize: CGSize(width: 800, height: 600),
            navigation: navigation
        )
        XCTAssertFalse(
            zoomed.coversPresentedPhoto(nativeExtent: native),
            "a viewport fragment of the crop must stay an ROI on the virtual canvas")
    }

    func testCroppedFitRequestCoversPresentationExtentWhileAZoomFragmentDoesNot() throws {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "roi-cover.png", in: tempDirectory)
        let native = CGSize(width: 96, height: 64)
        let source = ImageSource(url: url, nativeExtent: native)
        let document = EditDocument(
            crop: CropAdjustments(
                normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
            ))
        let cropNative = CGRect(x: 24, y: 16, width: 48, height: 32)
        let fit = RenderRequest(
            source: source, document: document, targetSize: native,
            sourceROI: cropNative, quality: .preview, output: .raster
        )
        XCTAssertTrue(fit.coversPresentationExtent)

        let fragment = RenderRequest(
            source: source, document: document, targetSize: native,
            sourceROI: CGRect(x: 30, y: 20, width: 20, height: 16),
            quality: .preview, output: .raster
        )
        XCTAssertFalse(fragment.coversPresentationExtent)
        XCTAssertEqual(
            fragment.presentationLayoutExtent,
            CGRect(x: 30, y: 28, width: 20, height: 16),
            "a same-scale fragment's layout is the ROI in y-down planner pixels"
        )
        XCTAssertNil(
            fit.presentationLayoutExtent,
            "a covering crop ROI is stretched onto the presentation extent; it has no fragment layout"
        )
    }

    func testInteractiveZoomFragmentLayoutStaysInPlannerSpace() {
        let native = CGSize(width: 3_000, height: 2_000)
        let source = ImageSource(
            url: URL(fileURLWithPath: "/tmp/layout-roi.png"), nativeExtent: native)
        let roi = CGRect(x: 600, y: 400, width: 1_200, height: 800)
        let plannerSize = CGSize(width: 2_400, height: 1_600)
        let request = RenderRequest(
            source: source, document: EditDocument(), targetSize: plannerSize,
            sourceROI: roi, quality: .interactive, output: .raster
        )

        XCTAssertFalse(request.coversPresentationExtent)
        XCTAssertEqual(
            request.renderScale.factor(for: native) * native.width, 1_500, accuracy: 0.5,
            "the 1.5 MP interactive budget must actually decode below the planner size"
        )
        XCTAssertEqual(
            request.presentationLayoutExtent,
            CGRect(x: 480, y: 640, width: 960, height: 640),
            "layout must use y-down planner pixels, not the reduced interactive decode origin"
        )
    }

    func testPresentationLayoutPutsATopSourceStripAtTheTopOfTheCanvas() {
        let native = CGSize(width: 1_000, height: 800)
        let source = ImageSource(
            url: URL(fileURLWithPath: "/tmp/layout-y.png"), nativeExtent: native)
        let top = RenderRequest(
            source: source, document: EditDocument(), targetSize: native,
            sourceROI: CGRect(x: 0, y: 600, width: 1_000, height: 200),
            quality: .preview, output: .raster
        )
        let bottom = RenderRequest(
            source: source, document: EditDocument(), targetSize: native,
            sourceROI: CGRect(x: 0, y: 0, width: 1_000, height: 200),
            quality: .preview, output: .raster
        )

        XCTAssertEqual(top.presentationLayoutExtent?.minY, 0)
        XCTAssertEqual(bottom.presentationLayoutExtent?.minY, 600)
    }

    func testPanCacheHitTestRepeatedROIRenderDoesNotRedevelopTheSource() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "roi-cache.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        let document = EditDocument(
            crop: CropAdjustments(
                normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
            ))
        let request = RenderRequest(
            source: source,
            document: document,
            targetSize: CGSize(width: 96, height: 64),
            sourceROI: CGRect(x: 24, y: 16, width: 48, height: 32),
            quality: .preview,
            output: .raster
        )
        let engine = RenderEngine()

        _ = await engine.makeCGImage(request)
        _ = await engine.makeCGImage(request)

        let stats = await engine.cacheStatistics()
        XCTAssertEqual(stats.developedSource.misses, 1)
        XCTAssertEqual(stats.developedSource.hits, 1)
    }

    func testCropExportParityTestVisibleROIMatchesFullExportCrop() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "roi-parity.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        let document = EditDocument(
            effects: EffectsAdjustments(
                texture: 35,
                clarity: 20,
                dehaze: 15,
                vignette: VignetteAdjustments(amount: 25),
                grain: GrainAdjustments(amount: 18, size: 60, roughness: 30)
            ),
            crop: CropAdjustments(normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        )
        let roi = CGRect(x: 24, y: 16, width: 48, height: 32)
        let engine = RenderEngine()
        let preview = try await engine.render(
            RenderRequest(
                source: source, document: document, targetSize: source.nativeExtent,
                sourceROI: roi, quality: .preview, output: .raster
            ))
        let export = try await engine.render(
            RenderRequest(
                source: source, document: document, quality: .export, output: .raster
            ))

        XCTAssertEqual(preview.extent, export.extent)
        assertPixelsEqual(
            try Pixels.bytes(of: try Pixels.decode(preview.data)),
            try Pixels.bytes(of: try Pixels.decode(export.data)), tolerance: 2,
            "the committed-crop ROI must match the same visible export crop")
    }

    func testGeometryViewportROIRendersThePostGeometryFragment() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "geometry-roi.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        let document = EditDocument(crop: CropAdjustments(straightenAngle: 35))
        var navigation = CanvasNavigation()
        navigation.setZoom(8)
        var planner = ResolutionPlanner()
        let plan = planner.plan(
            nativeExtent: source.nativeExtent, crop: document.crop,
            viewportSize: CGSize(width: 48, height: 36), navigation: navigation
        )
        let request = RenderRequest(
            source: source, document: document, targetSize: plan.sourceSize,
            sourceROI: try XCTUnwrap(plan.previewSourceROI(nativeExtent: source.nativeExtent)),
            presentationROI: plan.visiblePresentationRect,
            presentationImageExtent: plan.presentationImageExtent,
            presentationNavigation: navigation, quality: .preview, output: .raster
        )
        XCTAssertFalse(request.coversPresentationExtent)
        XCTAssertNotNil(request.presentationLayoutExtent)

        let rendered = await RenderEngine().makeCIImage(request)
        let image = try XCTUnwrap(rendered)
        XCTAssertGreaterThan(image.extent.width, 0)
        XCTAssertGreaterThan(image.extent.height, 0)
        XCTAssertTrue(image.extent.isRasterizable)
    }
}
