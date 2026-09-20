import XCTest
@testable import KromoraKit

final class ColorSettingFormattingTests: XCTestCase {
    func testWholeNumberFormatRemovesFractionalTails() {
        XCTAssertEqual(ColorSettingFormatting.wholeNumberFormat.format(10.16310), "10")
        XCTAssertEqual(ColorSettingFormatting.wholeNumberFormat.format(-12.89409), "-13")
        XCTAssertEqual(ColorSettingFormatting.signedWholeNumberFormat.format(12.89409), "+13")
        XCTAssertEqual(ColorSettingFormatting.signedWholeNumberFormat.format(0), "0")
    }

    func testPhotographerReadoutsRoundToWholeNumbers() {
        XCTAssertEqual(ColorSettingFormatting.temperature(5317.88), "5318 K")
        XCTAssertEqual(ColorSettingFormatting.tint(12.89409), "+13")
    }
}
