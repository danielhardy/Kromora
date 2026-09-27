import XCTest
@testable import KromoraKit

final class WhiteBalancePresetTests: XCTestCase {
    func testPresetTargetsCoverPhotographicSourcesAndCustomLeavesValuesEditable() {
        XCTAssertEqual(WhiteBalancePreset.allCases.map(\.rawValue), [
            "As Shot", "Auto", "Daylight", "Cloudy", "Shade", "Tungsten",
            "Fluorescent", "Flash", "Custom",
        ])
        XCTAssertEqual(WhiteBalancePreset.daylight.temperature, 5500)
        XCTAssertEqual(WhiteBalancePreset.cloudy.temperature, 6500)
        XCTAssertEqual(WhiteBalancePreset.shade.temperature, 7500)
        XCTAssertEqual(WhiteBalancePreset.tungsten.temperature, 3200)
        XCTAssertEqual(WhiteBalancePreset.fluorescent.temperature, 4000)
        XCTAssertNil(WhiteBalancePreset.custom.temperature)
    }

    func testNeutralSampleCentersAndWarmAndCoolSamplesMoveOppositeWays() {
        let neutral = WhiteBalanceEstimator.correction(red: 1, green: 1, blue: 1)
        let warm = WhiteBalanceEstimator.correction(red: 1, green: 0.5, blue: 0.25)
        let cool = WhiteBalanceEstimator.correction(red: 0.25, green: 0.5, blue: 1)

        XCTAssertEqual(neutral.temperature, 6500, accuracy: 300)
        XCTAssertLessThan(warm.temperature, neutral.temperature)
        XCTAssertGreaterThan(cool.temperature, neutral.temperature)
        XCTAssertTrue((-150...150).contains(warm.tint))
        XCTAssertTrue((-150...150).contains(cool.tint))
    }

    func testGreenSampleProducesMagentaCorrection() {
        let estimate = WhiteBalanceEstimator.correction(red: 0.35, green: 0.8, blue: 0.35)
        XCTAssertGreaterThan(estimate.tint, 0)
    }

    func testWhiteBalanceValuesRoundTripInBothDocumentStoragePaths() throws {
        var document = EditDocument()
        document.adjustments = [.temperatureTint(temp: 9200, tint: -18)]
        document.rawDevelop.neutralTemperature = 3450
        document.rawDevelop.neutralTint = 22

        let restored = try JSONDecoder().decode(
            EditDocument.self, from: JSONEncoder().encode(document))

        XCTAssertEqual(restored, document)
    }
}
