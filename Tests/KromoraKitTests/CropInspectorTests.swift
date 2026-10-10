import XCTest

@testable import KromoraKit

@MainActor
final class CropInspectorTests: XCTestCase {
    func testCropResetButtonUsesSharedAccessibilityAndInvokesReset() {
        var resetCount = 0
        let button = CropInspectorView.resetButton { resetCount += 1 }

        XCTAssertEqual(button.resolvedAccessibilityLabel, "Reset crop")
        XCTAssertEqual(
            button.resolvedAccessibilityHint,
            "Return the crop frame to the full image"
        )

        button.action()
        XCTAssertEqual(resetCount, 1)
    }

    func testSharedResetButtonDefaultsAccessibilityToItsTitle() {
        let button = ResetIconButton("Reset test") {}

        XCTAssertEqual(button.resolvedAccessibilityLabel, "Reset test")
        XCTAssertEqual(button.resolvedAccessibilityHint, "")
    }

    /// A missing SF Symbol draws nothing, so the button looks blank. `rectangle.landscape` was one.
    @MainActor
    func testOrientationButtonsUseSymbolsThatExist() {
        for name in [
            CropInspectorView.landscapeOrientationSymbol,
            CropInspectorView.portraitOrientationSymbol,
        ] {
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "\(name) is not an SF Symbol"
            )
        }
    }
}
