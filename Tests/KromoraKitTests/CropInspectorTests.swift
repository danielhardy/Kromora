import XCTest

@testable import KromoraKit

@MainActor
final class CropInspectorTests: XCTestCase {
    func testCropResetButtonUsesSharedAccessibilityAndInvokesReset() {
        var resetCount = 0
        let button = CropInspectorView.resetButton { resetCount += 1 }

        XCTAssertEqual(button.title, "Reset")
        XCTAssertEqual(button.appearance, .semanticLink)
        XCTAssertEqual(button.accessibilityPresentation.label, "Reset crop")
        XCTAssertEqual(
            button.accessibilityPresentation.hint,
            "Return the crop frame to the full image"
        )

        button.action()
        XCTAssertEqual(resetCount, 1)
    }

    func testSharedResetButtonDefaultsAccessibilityToItsTitle() {
        let button = ResetIconButton("Reset test") {}

        XCTAssertEqual(button.accessibilityPresentation.label, "Reset test")
        XCTAssertEqual(button.accessibilityPresentation.hint, "")
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
