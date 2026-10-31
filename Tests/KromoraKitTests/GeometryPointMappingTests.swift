import CoreGraphics
import CoreImage
import XCTest
@testable import KromoraKit

final class GeometryPointMappingTests: XCTestCase {
    func testGeometryMappingsRoundTripThroughQuarterTurnsAndGeometry() throws {
        let samples = [CGPoint(x: 0.2, y: 0.25), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.78, y: 0.7)]
        for rotation in ImageRotation.allCases {
            for flipHorizontal in [false, true] {
                for flipVertical in [false, true] {
                    let crop = CropAdjustments(
                        straightenAngle: 7,
                        flipHorizontal: flipHorizontal,
                        flipVertical: flipVertical,
                        verticalPerspective: 0.12,
                        horizontalPerspective: -0.08
                    )
                    let mapping = GeometryPointMapping(
                        sourceSize: CGSize(width: 1600, height: 1000),
                        rotation: rotation,
                        crop: crop
                    )
                    for source in samples {
                        let presented = try XCTUnwrap(mapping.forward(source))
                        let restored = try XCTUnwrap(mapping.inverse(presented))
                        XCTAssertEqual(restored.x, source.x, accuracy: 1e-8)
                        XCTAssertEqual(restored.y, source.y, accuracy: 1e-8)
                    }
                }
            }
        }
    }

    /// KRMA-1149: the rendered straighten geometry must be the true rotated bounding box (no
    /// filter zoom or stretch), so a marker lands where the crop workspace's mapping says it does.
    func testRenderedStraightenMatchesPointMapping() throws {
        let size = CGSize(width: 1000, height: 600)
        let base = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        let marker = CIImage(color: .white).cropped(to: CGRect(x: 700, y: 400, width: 100, height: 100))
        let crop = CropAdjustments(straightenAngle: -17)
        let geometry = RenderPipeline.applyingGeometry(crop, to: marker.composited(over: base))
        let expectedSize = RenderPipeline.geometryExtent(of: size, for: crop)
        XCTAssertEqual(geometry.extent.width, expectedSize.width, accuracy: 2.5)
        XCTAssertEqual(geometry.extent.height, expectedSize.height, accuracy: 2.5)

        let bounds = geometry.extent.integral
        let width = Int(bounds.width), height = Int(bounds.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        CIContext().render(geometry, toBitmap: &bytes, rowBytes: width * 4, bounds: bounds,
                           format: .RGBA8, colorSpace: nil)
        var sumX = 0.0, sumY = 0.0, count = 0.0
        for y in 0..<height {
            for x in 0..<width where bytes[(y * width + x) * 4] > 128 {
                sumX += Double(x); sumY += Double(y); count += 1
            }
        }
        XCTAssertGreaterThan(count, 0, "the marker must survive straighten (no corner clipping)")
        // Bitmap rows are top-down; the mapping uses top-left normalized coordinates.
        let rendered = CGPoint(x: sumX / count / Double(width), y: sumY / count / Double(height))
        let mapping = GeometryPointMapping(sourceSize: size, crop: crop)
        let predicted = try XCTUnwrap(mapping.forward(CGPoint(x: 0.75, y: 0.25)))
        XCTAssertEqual(rendered.x, predicted.x, accuracy: 0.01)
        XCTAssertEqual(rendered.y, predicted.y, accuracy: 0.01)
    }

    func testIdentityAndQuarterTurnMapping() throws {
        let point = CGPoint(x: 0.2, y: 0.7)
        let identity = GeometryPointMapping(sourceSize: CGSize(width: 400, height: 300))
        XCTAssertEqual(try XCTUnwrap(identity.forward(point)), point)

        let rotated = GeometryPointMapping(
            sourceSize: CGSize(width: 400, height: 300), rotation: .clockwise90
        )
        let expected = CGPoint(x: 0.3, y: 0.2)
        let actual = try XCTUnwrap(rotated.forward(point))
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-12)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-12)
    }

    func testRetouchSourcePointMapsThroughViewportAndBack() throws {
        let mapping = GeometryPointMapping(
            sourceSize: CGSize(width: 1600, height: 1000), rotation: .clockwise90,
            crop: CropAdjustments(straightenAngle: 4, flipHorizontal: true)
        )
        let source = CGPoint(x: 0.31, y: 0.64)
        let viewport = try XCTUnwrap(mapping.viewportPoint(
            forRetouchPoint: source, navigation: CanvasNavigation(),
            viewportSize: CGSize(width: 900, height: 700), backingScale: 2
        ))
        let restored = try XCTUnwrap(mapping.retouchPoint(
            forViewport: viewport, navigation: CanvasNavigation(),
            viewportSize: CGSize(width: 900, height: 700), backingScale: 2
        ))
        XCTAssertEqual(restored.x, source.x, accuracy: 1e-8)
        XCTAssertEqual(restored.y, source.y, accuracy: 1e-8)
    }
}
