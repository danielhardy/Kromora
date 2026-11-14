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

    func testInteractiveZoomFragmentLayoutStaysInPlannerSpaceWithinROIShapedBudget() {
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
            request.renderScale.factor(for: native) * native.width, plannerSize.width,
            accuracy: 0.5,
            "the planner box fits under the absolute ceiling and the ROI-specific budget"
        )
        let decodedROIArea = roi.width * roi.height
            * pow(request.renderScale.factor(for: native), 2)
        XCTAssertLessThanOrEqual(decodedROIArea, 4_000_000)
        XCTAssertEqual(
            request.presentationLayoutExtent,
            CGRect(x: 480, y: 640, width: 960, height: 640),
            "layout must use y-down planner pixels, not the reduced interactive decode origin"
        )
    }

    func testInteractiveROIBudgetKeepsAbsoluteDecodeCeiling() {
        let native = CGSize(width: 12_000, height: 8_000)
        let scale = RenderScale.interactive(
            maxSize: native,
            budgetAreaFraction: 0.01
        )

        XCTAssertEqual(
            native.width * native.height * pow(scale.factor(for: native), 2),
            36_000_000,
            accuracy: 1
        )
    }

    func testZoomedInteractiveDecodeKeepsViewportScaleVisiblePixels() {
        let native = CGSize(width: 6_000, height: 4_000)
        // A zoomed retina canvas: the visible ROI is 1/8 of the source area.
        let scale = RenderScale.interactive(maxSize: native, budgetAreaFraction: 1.0 / 8)
        let visiblePixels = native.width * native.height / 8
            * pow(scale.factor(for: native), 2)

        XCTAssertGreaterThanOrEqual(
            visiblePixels, 1_500_000 * 2,
            "a zoomed drag frame must not be upscaled ~2x from the 1.5 MP fit budget")
        XCTAssertEqual(
            RenderScale.interactive(maxSize: native).factor(for: native),
            sqrt(1_500_000 / (native.width * native.height)), accuracy: 0.0001,
            "fit views keep the historical 1.5 MP budget")
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

    func testDetailNativeROIParityMatchesFullExportCrop() async throws {
        let url = try Fixtures.writeClarityPNG(
            width: 512, height: 320, named: "detail-roi-parity.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 512, height: 320))
        let document = EditDocument(
            effects: EffectsAdjustments(detail: DetailAdjustments(
                sharpeningRadius: 4, sharpeningAmount: 80,
                luminanceNoise: 25, colorNoise: 20
            )),
            crop: CropAdjustments(
                normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        )
        let roi = CGRect(x: 128, y: 80, width: 256, height: 160)
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
            "native-scale ROI Detail must match the same region of a full export")
    }

    func testLocalSpatialROIWithFeatheredMaskMatchesFullExportCrop() async throws {
        let url = try Fixtures.writeClarityPNG(
            width: 512, height: 320, named: "local-spatial-roi-parity.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 512, height: 320))
        let mask = RadialGradientDefinition(
            center: CGPoint(x: 0.46, y: 0.52), horizontalRadius: 0.38,
            verticalRadius: 0.42, feather: 0.7)
        let localLayer = LocalAdjustmentLayer(
            name: "Feathered local clarity",
            components: [MaskComponent(source: .radial(mask))],
            adjustments: LocalAdjustments(clarity: 80))
        let document = EditDocument(
            effects: EffectsAdjustments(detail: DetailAdjustments(
                sharpeningRadius: 2, sharpeningAmount: 60)),
            localAdjustments: [localLayer])
        let roi = CGRect(x: 128, y: 80, width: 256, height: 160)
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

        XCTAssertEqual(preview.extent, roi.size)
        let exportImage = try Pixels.decode(export.data)
        let exportROI = try XCTUnwrap(exportImage.cropping(to: roi))
        let detailOnly = EditDocument(effects: document.effects)
        let detailPreview = try await engine.render(
            RenderRequest(
                source: source, document: detailOnly, targetSize: source.nativeExtent,
                sourceROI: roi, quality: .preview, output: .raster
            ))
        let detailExport = try await engine.render(
            RenderRequest(
                source: source, document: detailOnly, quality: .export, output: .raster
            ))
        assertPixelsEqual(
            try Pixels.bytes(of: try Pixels.decode(detailPreview.data)),
            try Pixels.bytes(of: XCTUnwrap(Pixels.decode(detailExport.data).cropping(to: roi))),
            tolerance: 2, "global Detail ROI baseline")
        assertPixelsEqual(
            try Pixels.bytes(of: try Pixels.decode(preview.data)),
            try Pixels.bytes(of: exportROI), tolerance: 2,
            "zoomed local spatial output with a feathered mask must match the full export crop")
    }

    func testGeometryROIWithFeatheredLocalSpatialLayerMatchesFullExportCrop() async throws {
        let url = try Fixtures.writeClarityPNG(
            width: 512, height: 320, named: "geometry-local-spatial-roi.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 512, height: 320))
        let localLayer = LocalAdjustmentLayer(
            name: "Feathered local clarity",
            components: [MaskComponent(source: .radial(RadialGradientDefinition(
                center: CGPoint(x: 0.5, y: 0.5), horizontalRadius: 0.4,
                verticalRadius: 0.4, feather: 0.7)))],
            adjustments: LocalAdjustments(exposure: 0.6, clarity: 80))
        let document = EditDocument(
            effects: EffectsAdjustments(detail: DetailAdjustments(
                sharpeningRadius: 2, sharpeningAmount: 60)),
            crop: CropAdjustments(straightenAngle: 10),
            localAdjustments: [localLayer])
        let presentationROI = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let engine = RenderEngine()
        let preview = try await engine.render(
            RenderRequest(
                source: source, document: document, targetSize: source.nativeExtent,
                sourceROI: CGRect(x: 128, y: 80, width: 256, height: 160),
                presentationROI: presentationROI, quality: .preview, output: .raster
            ))
        let export = try await engine.render(
            RenderRequest(
                source: source, document: document, quality: .export, output: .raster
            ))
        let exportImage = try Pixels.decode(export.data)
        let crop = CGRect(
            x: presentationROI.minX * CGFloat(exportImage.width),
            y: presentationROI.minY * CGFloat(exportImage.height),
            width: presentationROI.width * CGFloat(exportImage.width),
            height: presentationROI.height * CGFloat(exportImage.height)
        ).integral
        XCTAssertEqual(preview.extent, crop.size)
        assertPixelsEqual(
            try Pixels.bytes(of: try Pixels.decode(preview.data)),
            try Pixels.bytes(of: XCTUnwrap(exportImage.cropping(to: crop))), tolerance: 2,
            "geometry ROI with a feathered local spatial layer must match the full export crop")
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

    func testGeometryROIWithoutPresentationROIFallsBackToTheCompleteFrame() {
        let source = ImageSource(
            url: URL(fileURLWithPath: "/tmp/geometry-plan.png"),
            nativeExtent: CGSize(width: 96, height: 64)
        )
        let document = EditDocument(crop: CropAdjustments(straightenAngle: 20))
        let roi = CGRect(x: 10, y: 10, width: 30, height: 20)
        let legacy = RenderBuildPlan.make(
            source: source, document: document, identity: RenderDocumentIdentity(document),
            scale: .preview(maxSize: CGSize(width: 48, height: 32)),
            sourceROI: roi, presentationROI: nil
        )
        XCTAssertNil(legacy.sourceROI, "a native ROI cannot be applied after geometry on its own")
        XCTAssertFalse(legacy.hasEarlyCrop)

        let aware = RenderBuildPlan.make(
            source: source, document: document, identity: RenderDocumentIdentity(document),
            scale: .preview(maxSize: CGSize(width: 48, height: 32)),
            sourceROI: roi, presentationROI: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3)
        )
        XCTAssertNotNil(aware.sourceROI)
        XCTAssertTrue(aware.hasEarlyCrop)
    }
}
