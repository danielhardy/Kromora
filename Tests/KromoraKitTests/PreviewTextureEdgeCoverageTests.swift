import CoreImage
import CoreGraphics
import Metal
import XCTest
@testable import KromoraKit

/// KRMA-689: a fractional crop or straighten extent is rasterized into a whole-pixel texture
/// (`extent.integral` rounds outward), so the outermost top row and right column used to hold
/// pixels the photo never covered. Those transparent/partial edge pixels showed as a thin light
/// stroke on the top and right of the presented photo.
@MainActor
final class PreviewTextureEdgeCoverageTests: TempDirectoryTestCase {

    func testCompletedTextureHasNoPartiallyCoveredPerimeter() async throws {
        try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "Metal is unavailable on this host")

        let url = try Fixtures.writeGradientPNG(
            width: 517, height: 331, named: "edge-source.png", in: tempDirectory
        )
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 517, height: 331))
        let cases: [(String, CropAdjustments)] = [
            ("fractional crop", CropAdjustments(
                normalizedRect: CGRect(x: 0.0613, y: 0.0471, width: 0.8317, height: 0.8249))),
            ("crop + straighten", CropAdjustments(
                normalizedRect: CGRect(x: 0.0613, y: 0.0471, width: 0.8317, height: 0.8249),
                straightenAngle: 1.3)),
            ("straighten only", CropAdjustments(straightenAngle: 0.7)),
        ]
        for (name, crop) in cases {
            let engine = RenderEngine()
            let candidate = await engine.makeCIImage(RenderRequest(
                source: source,
                document: EditDocument(crop: crop),
                targetSize: source.nativeExtent,
                quality: .preview,
                output: .raster,
                space: .current
            ))
            let image = try XCTUnwrap(candidate, name)
            let width = Int(image.extent.integral.width)
            let height = Int(image.extent.integral.height)
            let bytes = try Pixels.bytes(of: image)
            func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * width + x) * 4 + 3] }
            // Straighten only fills the inscribed region of the rotated frame, so only the
            // crop-without-rotation cases must be fully opaque to the edge.
            guard crop.straightenAngle == 0 || crop.normalizedRect != nil else { continue }
            for x in 0..<width {
                XCTAssertEqual(alpha(x, 0), 255, "\(name): top row alpha at x=\(x)")
                XCTAssertEqual(alpha(x, height - 1), 255, "\(name): bottom row alpha at x=\(x)")
            }
            for y in 0..<height {
                XCTAssertEqual(alpha(width - 1, y), 255, "\(name): right column alpha at y=\(y)")
                XCTAssertEqual(alpha(0, y), 255, "\(name): left column alpha at y=\(y)")
            }
        }
    }
}
