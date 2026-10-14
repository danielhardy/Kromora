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
}
