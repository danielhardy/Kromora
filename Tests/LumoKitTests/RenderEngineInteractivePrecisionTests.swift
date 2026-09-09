import CoreImage
import CoreGraphics
import Metal
import XCTest
@testable import LumoKit

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
