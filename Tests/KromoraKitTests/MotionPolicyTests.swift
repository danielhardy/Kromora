import SwiftUI
import XCTest

@testable import KromoraKit

final class MotionPolicyTests: XCTestCase {
    func testReduceMotionRemovesAnimation() {
        XCTAssertNil(Animation.easeInOut(duration: 0.2).respectingReduceMotion(true))
    }

    func testAnimationIsKeptWhenReduceMotionIsOff() {
        let animation = Animation.easeInOut(duration: 0.2)
        XCTAssertEqual(animation.respectingReduceMotion(false), animation)
    }

    func testFilmstripCentersEntryItemIncludingEdges() {
        let ids = ["a", "b", "c"]
        XCTAssertEqual(FilmstripLayout.centeredItemID(ids: ids, selectedIndex: 0), "a")
        XCTAssertEqual(FilmstripLayout.centeredItemID(ids: ids, selectedIndex: 2), "c")
        XCTAssertNil(FilmstripLayout.centeredItemID(ids: ids, selectedIndex: 3))
        XCTAssertNil(FilmstripLayout.centeredItemID(ids: [String](), selectedIndex: 0))
    }
}
