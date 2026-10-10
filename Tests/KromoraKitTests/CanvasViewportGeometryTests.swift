import CoreGraphics
import XCTest
@testable import KromoraKit

final class CanvasViewportGeometryTests: XCTestCase {
    func testVisibleViewportUsesTheDrawablesBackingScaleWithoutMovingItsOrigin() {
        let geometry = CanvasViewportGeometry(
            surfaceSize: CGSize(width: 900, height: 700),
            viewportSize: CGSize(width: 900, height: 570))
        XCTAssertEqual(geometry.viewportSize, CGSize(width: 900, height: 570))
        XCTAssertEqual(
            geometry.backingSize(drawableSize: CGSize(width: 1800, height: 1400)),
            CGSize(width: 1800, height: 1140))
        XCTAssertEqual(
            geometry.backingSize(drawableSize: CGSize(width: 900, height: 700)),
            geometry.viewportSize)
    }

    func testViewportClampsToTheSurfaceAndMissingViewportUsesAllOfIt() {
        let size = CGSize(width: 320, height: 240)
        XCTAssertEqual(CanvasViewportGeometry(surfaceSize: size, viewportSize: nil).viewportSize, size)
        XCTAssertEqual(
            CanvasViewportGeometry(surfaceSize: size, viewportSize: CGSize(width: 500, height: -20)).viewportSize,
            CGSize(width: 320, height: 1))
        XCTAssertEqual(
            CanvasViewportGeometry(surfaceSize: size, viewportSize: CGSize(width: CGFloat.nan, height: CGFloat.infinity)).viewportSize,
            size)
        XCTAssertEqual(
            CanvasViewportGeometry(surfaceSize: .zero, viewportSize: size).backingSize(drawableSize: size),
            .zero)
    }
}
