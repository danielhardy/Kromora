import XCTest
@testable import KromoraKit

final class LookNavigationTests: XCTestCase {
    func testCycleIncludesNoneBeforeTheFirstLook() {
        XCTAssertEqual(
            LookNavigation.adjacentIndex(currentIndex: nil, count: 3, direction: .next),
            0,
            "Down from None should select the first Look"
        )
        XCTAssertNil(
            LookNavigation.adjacentIndex(currentIndex: 0, count: 3, direction: .previous),
            "Up from the first Look should return to None"
        )
        XCTAssertNil(
            LookNavigation.adjacentIndex(currentIndex: nil, count: 3, direction: .previous),
            "Up from None is an intentional no-op"
        )
    }

    func testCycleWalksLibraryOrderAndStopsAtTheLastLook() {
        XCTAssertEqual(
            LookNavigation.adjacentIndex(currentIndex: 0, count: 3, direction: .next),
            1
        )
        XCTAssertEqual(
            LookNavigation.adjacentIndex(currentIndex: 1, count: 3, direction: .previous),
            0
        )
        XCTAssertEqual(
            LookNavigation.adjacentIndex(currentIndex: 2, count: 3, direction: .next),
            2,
            "Down at the last Look is a silent no-op"
        )
        XCTAssertEqual(
            LookNavigation.adjacentIndex(currentIndex: 1, count: 3, direction: .next),
            2
        )
    }

    func testEmptyLibraryStaysOnNone() {
        XCTAssertNil(LookNavigation.adjacentIndex(currentIndex: nil, count: 0, direction: .next))
        XCTAssertNil(LookNavigation.adjacentIndex(currentIndex: nil, count: 0, direction: .previous))
        XCTAssertNil(LookNavigation.adjacentIndex(currentIndex: 0, count: 0, direction: .next))
    }
}
