import CoreGraphics
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
}
