import CoreGraphics
import XCTest
@testable import KromoraKit

final class CropROITests: TempDirectoryTestCase {
    private let native = CGSize(width: 6_000, height: 4_000)

    func testROIExtentTestSmallCommittedCropAtFitUsesOnlyTheCropPixels() {
        var planner = ResolutionPlanner()
        let plan = planner.plan(
            nativeExtent: native,
            crop: CropAdjustments(normalizedRect: CGRect(x: 0.375, y: 0.375, width: 0.25, height: 0.25)),
            viewportSize: CGSize(width: 1_600, height: 1_200)
        )

        let idealROI = plan.visibleSourceRect.width * plan.visibleSourceRect.height
        let developedROI = CGFloat(
            Int((plan.visibleSourceRect.width * plan.scale).rounded(.toNearestOrAwayFromZero))
                * Int((plan.visibleSourceRect.height * plan.scale).rounded(.toNearestOrAwayFromZero))
        )

        XCTAssertEqual(plan.visibleSourceRect, CGRect(x: 2_250, y: 1_500, width: 1_500, height: 1_000))
        XCTAssertLessThanOrEqual(developedROI, idealROI * 1.5)
        XCTAssertLessThan(developedROI, CGFloat(Int(native.width * native.height)) / 4)
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
            crop: CropAdjustments(normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)),
            viewportSize: CGSize(width: 800, height: 600),
            navigation: navigation
        )

        XCTAssertTrue(plan.isNativeResolution)
        XCTAssertEqual(plan.sourceSize, native)
        XCTAssertLessThan(plan.visibleSourceRect.width * plan.visibleSourceRect.height,
                          native.width * native.height / 16)
        XCTAssertGreaterThan(plan.visibleSourceRect.minX, 0)
    }

    func testPanCacheHitTestRepeatedROIRenderDoesNotRedevelopTheSource() async throws {
        let url = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "roi-cache.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        let document = EditDocument(crop: CropAdjustments(
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
        let url = try Fixtures.writeGradientPNG(width: 96, height: 64, named: "roi-parity.png", in: tempDirectory)
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
        let preview = try await engine.render(RenderRequest(
            source: source, document: document, targetSize: source.nativeExtent,
            sourceROI: roi, quality: .preview, output: .raster
        ))
        let export = try await engine.render(RenderRequest(
            source: source, document: document, quality: .export, output: .raster
        ))

        XCTAssertEqual(preview.extent, export.extent)
        assertPixelsEqual(try Pixels.bytes(of: try Pixels.decode(preview.data)),
                          try Pixels.bytes(of: try Pixels.decode(export.data)), tolerance: 2,
                          "the committed-crop ROI must match the same visible export crop")
    }
}
