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

    /// The stored frame must be whole pixels of the same uniform scale as the settled render, not
    /// a raster stretched to a rounded size (a sub-pixel shift when the settled frame replaces it).
    func testCanonicalRasterKeepsUniformScaleWithWholePixelSize() throws {
        let cases: [(CGSize, Int)] = [
            (CGSize(width: 149, height: 202), 97),
            (CGSize(width: 517, height: 255), 333),
            (CGSize(width: 3001, height: 1687), 2048),
        ]
        for (size, longEdge) in cases {
            let ramp = try TestImages.gradient(width: Int(size.width), height: Int(size.height))
            let scale = CGFloat(longEdge) / max(size.width, size.height)
            let raster = try XCTUnwrap(RenderEngineResources.canonicalPreviewRaster(
                from: ramp, space: .current, longEdge: longEdge
            ))
            let width = Int((size.width * scale + 1e-4).rounded(.down))
            let height = Int((size.height * scale + 1e-4).rounded(.down))
            XCTAssertEqual(raster.width, width, "\(size)")
            XCTAssertEqual(raster.height, height, "\(size)")
            XCTAssertLessThanOrEqual(Double(raster.width), Double(size.width * scale) + 1e-3)
            XCTAssertLessThanOrEqual(Double(raster.height), Double(size.height * scale) + 1e-3)
            XCTAssertEqual(max(raster.width, raster.height), longEdge, "\(size)")

            let extent = ramp.extent.integral
            let expectedImage = ramp
                .transformed(by: CGAffineTransform(
                    translationX: -extent.minX, y: -extent.minY
                ))
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let context = RenderEngineResources.makeOneShotContext(
                workingColorSpace: WorkingSpace.current.cgColorSpace
            )
            let expected = try XCTUnwrap(context.createCGImage(
                expectedImage,
                from: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8,
                colorSpace: WorkingSpace.current.cgColorSpace
            ))
            XCTAssertEqual(
                try Pixels.bytes(of: CIImage(cgImage: raster)),
                try Pixels.bytes(of: CIImage(cgImage: expected)),
                "the raster must use the same uniform scale as the settled image (\(size))"
            )
        }
    }

    func testCanonicalRasterCoverageForFractional16By9Crop() throws {
        let sourceSize = CGSize(width: 517, height: 331)
        let source = try TestImages.gradient(
            width: Int(sourceSize.width), height: Int(sourceSize.height)
        )
        let crop = CropAdjustments(
            normalizedRect: CGRect(x: 0.103, y: 0.117, width: 0.797, height: 0.7),
            aspectRatio: .sixteenToNine,
            orientation: .landscape
        )
        let rawCrop = CGRect(
            x: crop.normalizedRect!.minX * sourceSize.width,
            y: crop.normalizedRect!.minY * sourceSize.height,
            width: crop.normalizedRect!.width * sourceSize.width,
            height: crop.normalizedRect!.height * sourceSize.height
        )
        XCTAssertNotEqual(rawCrop.minX, rawCrop.minX.rounded())
        XCTAssertNotEqual(rawCrop.minY, rawCrop.minY.rounded())
        XCTAssertNotEqual(rawCrop.maxX, rawCrop.maxX.rounded())
        XCTAssertNotEqual(rawCrop.maxY, rawCrop.maxY.rounded())

        let cropped = RenderPipeline.applyCrop(crop, to: source)
        XCTAssertEqual(cropped.extent.width / cropped.extent.height, 16.0 / 9.0, accuracy: 0.01)
        let raster = try XCTUnwrap(RenderEngineResources.canonicalPreviewRaster(
            from: cropped, space: .current, longEdge: 1001
        ))
        XCTAssertEqual(raster.width, 1001)
        XCTAssertEqual(raster.height, 562)

        let bytes = try Pixels.bytes(of: CIImage(cgImage: raster))
        let width = raster.width
        let height = raster.height
        func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[(y * width + x) * 4 + 3] }
        for x in 0..<width {
            XCTAssertEqual(alpha(x, 0), 255, "top edge x=\(x)")
            XCTAssertEqual(alpha(x, height - 1), 255, "bottom edge x=\(x)")
        }
        for y in 0..<height {
            XCTAssertEqual(alpha(0, y), 255, "left edge y=\(y)")
            XCTAssertEqual(alpha(width - 1, y), 255, "right edge y=\(y)")
        }
    }
}
