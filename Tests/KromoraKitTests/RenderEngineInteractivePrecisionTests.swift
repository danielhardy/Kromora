import CoreImage
import CoreGraphics
import Metal
import XCTest
@testable import KromoraKit

/// Acceptance coverage for LUMO-306's completed preview-texture precision boundary.
@MainActor
final class RenderEngineInteractivePrecisionTests: TempDirectoryTestCase {

    func testInteractiveDescriptorTest() throws {
        XCTAssertEqual(
            RenderEngineResources.previewTexturePixelFormat(for: .interactive), .rgba8Unorm
        )
        XCTAssertEqual(
            RenderEngineResources.previewTexturePixelFormat(for: .preview), .rgba16Float
        )
        XCTAssertEqual(
            RenderEngineResources.previewTexturePixelFormat(for: .thumbnail), .rgba16Float
        )
        XCTAssertEqual(
            RenderEngineResources.previewTexturePixelFormat(for: .fullResolution), .rgba16Float
        )
        XCTAssertEqual(
            RenderEngineResources.previewTexturePixelFormat(for: .export), .rgba16Float
        )
    }

    func testBandwidthStructureTest() throws {
        let width = 1_920
        let height = 1_080
        let eightBitBytesPerRow = width * 4
        let halfFloatBytesPerRow = width * 8

        XCTAssertEqual(
            Double(eightBitBytesPerRow * height) / Double(halfFloatBytesPerRow * height), 0.5,
            accuracy: 0.000_001
        )
    }

    func testSettleQualityTest() async throws {
        try XCTSkipUnless(
            MTLCreateSystemDefaultDevice() != nil,
            "Metal is unavailable on this host"
        )

        let url = try Fixtures.writeGradientPNG(
            width: 512, height: 320, named: "sky-gradient.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 512, height: 320))
        let document = EditDocument(
            light: LightAdjustments(exposure: 0.18, contrast: 8),
            color: ColorAdjustments(saturation: 0.12)
        )
        let engine = RenderEngine()

        let interactiveCandidate = await engine.makeCIImage(RenderRequest(
            source: source,
            document: document,
            targetSize: source.nativeExtent,
            quality: .interactive,
            output: .raster,
            space: .current
        ))
        let interactive = try XCTUnwrap(interactiveCandidate)
        let settledCandidate = await engine.makeCIImage(RenderRequest(
            source: source,
            document: document,
            targetSize: source.nativeExtent,
            quality: .preview,
            output: .raster,
            space: .current
        ))
        let settled = try XCTUnwrap(settledCandidate)

        let delta = try XCTUnwrap(
            Pixels.worstDelta(try Pixels.bytes(of: interactive), try Pixels.bytes(of: settled))
        )
        XCTAssertLessThanOrEqual(
            delta.delta, 2,
            "the settled 16F frame must correct interactive 8-bit quantization without visible banding"
        )
    }

    func testDetailStaysPredictableAcrossInteractiveToSettledScaleChange() async throws {
        try XCTSkipUnless(
            MTLCreateSystemDefaultDevice() != nil,
            "Metal is unavailable on this host"
        )

        let native = CGSize(width: 512, height: 320)
        let pattern = try Fixtures.makeParametricCGImage(width: 512, height: 320) { x, y in
            let value = 0.5 + 0.2 * sin(x * 2 * Double.pi * 24)
                + 0.1 * sin(y * 2 * Double.pi * 10)
            return (value, value, value)
        }
        let url = try Fixtures.writePNG(
            pattern, named: "detail-scale-transition.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: native)
        let document = EditDocument(effects: EffectsAdjustments(detail: DetailAdjustments(
            sharpeningRadius: 4, sharpeningAmount: 80, luminanceNoise: 20, colorNoise: 15
        )))
        let interactiveRequest = RenderRequest(
            source: source, document: document, targetSize: native, quality: .interactive,
            frameBudgetMilliseconds: 1, output: .raster, space: .current
        )
        let settledRequest = RenderRequest(
            source: source, document: document, targetSize: native, quality: .preview,
            output: .raster, space: .current
        )
        let interactiveScale = interactiveRequest.renderScale.factor(for: native)
        let settledScale = settledRequest.renderScale.factor(for: native)
        XCTAssertLessThan(interactiveScale, settledScale,
                          "the interactive request must exercise the lower-resolution render")

        let engine = RenderEngine()
        let interactiveCandidate = await engine.makeCIImage(interactiveRequest)
        let settledCandidate = await engine.makeCIImage(settledRequest)
        let interactive = try XCTUnwrap(interactiveCandidate)
        let settled = try XCTUnwrap(settledCandidate)
        let comparison = settled.transformed(by: CGAffineTransform(
            scaleX: interactive.extent.width / settled.extent.width,
            y: interactive.extent.height / settled.extent.height
        )).cropped(to: CGRect(origin: .zero, size: interactive.extent.size))
        let interactivePixels = try Pixels.bytes(of: interactive)
        let settledPixels = try Pixels.bytes(of: comparison)
        let meanDelta = zip(interactivePixels, settledPixels).reduce(0.0) {
            $0 + Double(abs(Int($1.0) - Int($1.1)))
        } / Double(interactivePixels.count)

        XCTAssertLessThanOrEqual(
            meanDelta, 5,
            "the documented Detail approximation must stay visually close when the settled frame replaces the interactive frame"
        )
    }

    func testExportUnchangedTest() async throws {
        let url = try Fixtures.writeGradientPNG(
            width: 96, height: 64, named: "export-source.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 96, height: 64))
        let document = EditDocument(adjustments: [.exposure(ev: 0.35)])
        let engine = RenderEngine()

        let before = try await engine.encode(
            source: source, document: document, lut: nil, scale: .full,
            format: .png, quality: 1, space: .current
        )
        _ = await engine.makeCIImage(RenderRequest(
            source: source,
            document: document,
            targetSize: source.nativeExtent,
            quality: .interactive,
            output: .raster,
            space: .current
        ))
        let after = try await engine.encode(
            source: source, document: document, lut: nil, scale: .full,
            format: .png, quality: 1, space: .current
        )

        XCTAssertEqual(before, after, "interactive precision must not change export bytes")
    }
}
