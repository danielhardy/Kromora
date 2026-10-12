import Foundation
import XCTest

@testable import KromoraKit

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

    func testDecodingNormalizesPointsAndRectangles() throws {
        let rectJSON = Data(#"{"x":-5,"y":2,"width":10,"height":-4}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(NormalizedRect.self, from: rectJSON),
                       NormalizedRect(x: -5, y: 2, width: 10, height: -4))
        let contained = try JSONDecoder().decode(
            NormalizedRect.self, from: Data(#"{"x":0.75,"y":0.5,"width":3,"height":3}"#.utf8))
        XCTAssertEqual(contained.maxX, 1)
        XCTAssertEqual(contained.maxY, 1)
        for (x, y) in [(-1.0, 3.0), (2.0, -2.0)] {
            let point = try JSONDecoder().decode(
                NormalizedPoint.self, from: Data(#"{"x":\#(x),"y":\#(y)}"#.utf8))
            XCTAssertEqual(point, NormalizedPoint(x: x, y: y))
            XCTAssertTrue((0...1).contains(point.x) && (0...1).contains(point.y))
        }
    }
}
