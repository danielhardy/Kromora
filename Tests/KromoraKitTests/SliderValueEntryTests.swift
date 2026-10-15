import XCTest
@testable import KromoraKit

final class SliderValueEntryTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")

    private func value(_ result: Result<Double, SliderValueEntry.Failure>) -> Double? {
        if case .success(let v) = result { return v }
        return nil
    }

    func testValidValuesIncludingSignAndUnit() {
        let entry = SliderValueEntry(range: -5...5, fractionDigits: 2, unit: "EV", locale: us)
        XCTAssertEqual(value(entry.parse("1.25")), 1.25)
        XCTAssertEqual(value(entry.parse("+1.25")), 1.25)
        XCTAssertEqual(value(entry.parse("-2")), -2)
        XCTAssertEqual(value(entry.parse(" 0.5 EV ")), 0.5)
        XCTAssertEqual(value(entry.parse("0.5ev")), 0.5)
    }

    func testBoundsAreInclusiveAndOutsideIsRejectedNotClamped() {
        let entry = SliderValueEntry(range: -100...100, locale: us)
        XCTAssertEqual(value(entry.parse("100")), 100)
        XCTAssertEqual(value(entry.parse("-100")), -100)
        XCTAssertEqual(
            entry.parse("101"), .failure(.outOfRange(lower: "-100", upper: "100")))
        XCTAssertEqual(
            entry.parse("-100.5"), .failure(.outOfRange(lower: "-100", upper: "100")))
        XCTAssertEqual(
            entry.parse("100.00000001"), .failure(.outOfRange(lower: "-100", upper: "100")))
        XCTAssertEqual(
            entry.parse("-100.00000001"), .failure(.outOfRange(lower: "-100", upper: "100")))
        XCTAssertEqual(SliderValueEntry.Failure.outOfRange(lower: "-100", upper: "100").message,
                       "Enter -100 to 100")
    }

    func testNonNumericAndEmptyTextAreRejected() {
        let entry = SliderValueEntry(range: 0...100, unit: "%", locale: us)
        for text in ["abc", "1x", "1 2", "--5", "+-5", "nan", "inf", "5%%"] {
            XCTAssertEqual(entry.parse(text), .failure(.notANumber), text)
        }
        XCTAssertEqual(entry.parse(""), .failure(.empty))
        XCTAssertEqual(entry.parse("   "), .failure(.empty))
        XCTAssertEqual(entry.parse("+"), .failure(.empty))
    }

    func testLocaleDecimalSeparator() {
        let german = SliderValueEntry(range: -5...5, fractionDigits: 2, locale: de)
        XCTAssertEqual(value(german.parse("1,5")), 1.5)
        XCTAssertEqual(german.editingText(for: 1.5), "1,5")
        XCTAssertEqual(german.parse("abc"), .failure(.notANumber))
    }

    func testStepSnapping() {
        let entry = SliderValueEntry(range: -45...45, step: 0.1, fractionDigits: 1, locale: us)
        XCTAssertEqual(value(entry.parse("1.26")), 1.3)
        XCTAssertEqual(value(entry.parse("0.04")), 0)
        let whole = SliderValueEntry(range: 2000...50000, step: 50, locale: us)
        XCTAssertEqual(value(whole.parse("5520")), 5500)
    }

    func testContinuousControlDoesNotSnapTypedValues() {
        let entry = SliderValueEntry(range: 0...1, displayScale: 100, unit: "%", locale: us)
        XCTAssertEqual(value(entry.parse("55.25%")), 0.5525)
    }

    func testDisplayScaleAndOrigin() {
        let percent = SliderValueEntry(range: 0...1, step: 0.01, displayScale: 100, unit: "%", locale: us)
        XCTAssertEqual(value(percent.parse("55%")), 0.55)
        XCTAssertEqual(percent.parse("101"), .failure(.outOfRange(lower: "0", upper: "100")))
        XCTAssertEqual(percent.editingText(for: 0.25), "25")

        let offset = SliderValueEntry(
            range: 0.01...1, displayScale: 100 / 0.99, displayOrigin: 0.01, unit: "%", locale: us)
        XCTAssertEqual(value(offset.parse("0")), 0.01)
        XCTAssertEqual(value(offset.parse("100")) ?? 0, 1, accuracy: 1e-9)
    }

    func testAnnouncementIncludesUnit() {
        let entry = SliderValueEntry(range: -5...5, fractionDigits: 2, unit: "EV", locale: us)
        XCTAssertEqual(entry.announcement(for: 1.5), "1.5 EV")
    }
}
