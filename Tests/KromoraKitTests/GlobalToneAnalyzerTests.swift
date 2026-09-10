import Foundation
import XCTest

@testable import KromoraKit

final class GlobalToneAnalyzerTests: XCTestCase {
    func testStatisticsUsePercentilesAndClippingFromOneHistogram() throws {
        var bins = [Int](repeating: 0, count: 256)
        bins[0] = 2
        bins[64] = 2
        bins[128] = 4
        bins[255] = 2
        let histogram = HistogramData(red: bins, green: bins, blue: bins, luma: bins)

        let result = try GlobalToneAnalyzer.statistics(from: histogram)
        XCTAssertEqual(result.tone.perceptual.p50, 128.0 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(result.tone.perceptual.shadowClippingFraction, 0.2, accuracy: 0.0001)
        XCTAssertEqual(result.tone.perceptual.highlightClippingFraction, 0.2, accuracy: 0.0001)
        XCTAssertLessThan(result.tone.linear.p50, result.tone.perceptual.p50)
        XCTAssertEqual(result.color.meanRGB.x, result.color.meanRGB.y, accuracy: 0.0001)
    }

    func testMalformedAndEmptyHistogramsAreTypedFailures() {
        XCTAssertThrowsError(try GlobalToneAnalyzer.statistics(from: HistogramData(
            red: [], green: [], blue: [], luma: []
        ))) { error in
            XCTAssertEqual(error as? GlobalToneAnalysisError, .malformedHistogram)
        }
        var bins = [Int](repeating: 0, count: 256)
        XCTAssertThrowsError(try GlobalToneAnalyzer.statistics(from: HistogramData(
            red: bins, green: bins, blue: bins, luma: bins
        ))) { error in
            XCTAssertEqual(error as? GlobalToneAnalysisError, .malformedHistogram)
        }
    }
}
