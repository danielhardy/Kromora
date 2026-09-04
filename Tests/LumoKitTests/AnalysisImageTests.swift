import Foundation
import XCTest

@testable import LumoKit

final class AnalysisImageTests: XCTestCase {
    func testFactoryUsesOneCanonicalLongestEdge() throws {
        let source = ImageSource(
            backing: .data(Data([0, 1, 2])), kind: .standard,
            nativeExtent: CGSize(width: 4000, height: 2000)
        )
        let image = try AnalysisImageFactory.make(
            from: source, configuration: AnalysisConfiguration(maximumDimension: 768)
        )

        XCTAssertEqual(image.dimensions.width, 768)
        XCTAssertEqual(image.dimensions.height, 384)
        XCTAssertEqual(image.source, source)
    }

    func testVisionCoordinatesConvertToUpperLeftExactlyOnce() {
        let point = NormalizedPoint.fromVision(CGPoint(x: 0.25, y: 0.2))
        let rect = NormalizedRect.fromVision(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))

        XCTAssertEqual(point, NormalizedPoint(x: 0.25, y: 0.8))
        XCTAssertEqual(rect, NormalizedRect(x: 0.1, y: 0.4, width: 0.3, height: 0.4))
    }
}
