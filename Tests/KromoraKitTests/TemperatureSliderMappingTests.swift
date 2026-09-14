import Foundation
import XCTest

@testable import KromoraKit

final class TemperatureSliderMappingTests: XCTestCase {
    func testRAWMappingUsesTheUsefulRangeForHalfTheTrack() {
        let mapping = TemperatureSliderMapping(kelvinRange: 2000...50000)

        XCTAssertEqual(mapping.sliderPosition(for: 2000), 0, accuracy: 1e-12)
        XCTAssertEqual(mapping.sliderPosition(for: 10000), 0.5, accuracy: 1e-12)
        XCTAssertEqual(mapping.sliderPosition(for: 50000), 1, accuracy: 1e-12)
        XCTAssertGreaterThan(
            mapping.sliderPosition(for: 10000),
            (10000.0 - 2000.0) / (50000.0 - 2000.0),
            "the practical range must receive more travel than a linear Kelvin scale"
        )
    }

    func testRepresentativeKelvinValuesRoundTripExactlyEnoughForEditing() {
        let mapping = TemperatureSliderMapping(kelvinRange: 2000...50000)

        for kelvin in [2000.0, 2000.25, 6500.0, 10000.0, 49999.75, 50000.0] {
            let position = mapping.sliderPosition(for: kelvin)
            XCTAssertTrue((0...1).contains(position))
            XCTAssertEqual(
                mapping.kelvinValue(for: position), kelvin, accuracy: 1e-9, "\(kelvin) K"
            )
        }
    }

    func testMappingIsMonotonicAndContinuousAtThePracticalBoundary() {
        let mapping = TemperatureSliderMapping(kelvinRange: 2000...50000)
        let values = [2000.0, 6499.0, 6500.0, 10000.0, 10000.001, 50000.0]
        let positions = values.map(mapping.sliderPosition(for:))

        for pair in zip(positions, positions.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }
        XCTAssertLessThan(
            positions[4] - positions[3],
            0.000001,
            "the mapping must not jump at 10,000 K"
        )
    }

    func testStandardImageRangeSharesTheMappingWithoutChangingItsUpperBound() {
        let mapping = TemperatureSliderMapping(kelvinRange: AdjustmentControl.temperature.range)

        XCTAssertEqual(mapping.kelvinRange.upperBound, 11000)
        XCTAssertEqual(
            mapping.kelvinValue(for: mapping.sliderPosition(for: 6500)), 6500, accuracy: 1e-9)
        XCTAssertEqual(mapping.sliderPosition(for: 10000), log(5) / log(5.5), accuracy: 1e-12)
    }

    func testColorReadoutsRoundTemperatureAndTintWithoutChangingTheValues() {
        XCTAssertEqual(ColorSettingFormatting.temperature(5842.2), "5842 K")
        XCTAssertEqual(ColorSettingFormatting.tint(14.04), "+14")
        XCTAssertEqual(LocalAdjustmentControl.temperature.readout(6500.4), "6500 K")
    }
}
