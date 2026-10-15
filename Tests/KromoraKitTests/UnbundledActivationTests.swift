import XCTest
@testable import KromoraKit

final class UnbundledActivationTests: XCTestCase {
    func testUnbundledLaunchNeedsActivationWorkaround() {
        XCTAssertTrue(KromoraAppDelegate.needsUnbundledActivation(bundleIdentifier: nil))
    }

    func testBundledLaunchSkipsActivationWorkaround() {
        XCTAssertFalse(KromoraAppDelegate.needsUnbundledActivation(bundleIdentifier: "com.example.Kromora"))
    }
}
