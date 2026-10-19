import CoreImage
import CoreGraphics
import XCTest
@testable import KromoraKit

/// KRMA-1042: the stored first-frame raster is the durable post-crop frame painted first on the
/// next open. Its edges must be fully photo-covered or the canvas flashes a light line until the
/// settled render replaces it.
final class CanonicalPreviewRasterEdgeCoverageTests: XCTestCase {
    func testCanonicalRasterIsFullyOpaqueAtEveryEdge() throws {
        // Dimensions and long edges chosen so extent * scale is fractional on at least one axis.
        let cases: [(CGSize, Int)] = [
            (CGSize(width: 429, height: 272), 2048),
            (CGSize(width: 429, height: 272), 1000),
            (CGSize(width: 517, height: 255), 333),
            (CGSize(width: 149, height: 202), 97),
            (CGSize(width: 3001, height: 1687), 2048),
        ]
        for (size, longEdge) in cases {
            let gradient = CIImage(color: CIColor(red: 0.2, green: 0.5, blue: 0.7))
                .cropped(to: CGRect(origin: .zero, size: size))
            let raster = try XCTUnwrap(RenderEngineResources.canonicalPreviewRaster(
                from: gradient, space: .current, longEdge: longEdge
            ), "\(size) @ \(longEdge)")
            let bytes = try Pixels.bytes(of: CIImage(cgImage: raster))
            let w = raster.width, h = raster.height
            func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * w + x) * 4 + 3] }
            func assertPhotoColorAtEdge(_ x: Int, _ y: Int, matches ix: Int, _ iy: Int,
                                        file: StaticString = #filePath, line: UInt = #line) {
                let edge = (y * w + x) * 4
                let interior = (iy * w + ix) * 4
                for channel in 0..<3 {
                    XCTAssertEqual(bytes[edge + channel], bytes[interior + channel],
                                   "\(size)@\(longEdge) edge color at (\(x), \(y))",
                                   file: file, line: line)
                }
            }
            for x in 0..<w {
                XCTAssertEqual(alpha(x, 0), 255, "\(size)@\(longEdge) top x=\(x)")
                XCTAssertEqual(alpha(x, h - 1), 255, "\(size)@\(longEdge) bottom x=\(x)")
                assertPhotoColorAtEdge(x, 0, matches: x, 1)
                assertPhotoColorAtEdge(x, h - 1, matches: x, h - 2)
            }
            for y in 0..<h {
                XCTAssertEqual(alpha(0, y), 255, "\(size)@\(longEdge) left y=\(y)")
                XCTAssertEqual(alpha(w - 1, y), 255, "\(size)@\(longEdge) right y=\(y)")
                assertPhotoColorAtEdge(0, y, matches: 1, y)
                assertPhotoColorAtEdge(w - 1, y, matches: w - 2, y)
            }
        }
    }
}
