import XCTest
@testable import KromoraKit

/// The chart plots `animatableData` directly, so interpolation is checked on the vector SwiftUI
/// drives: intermediate fractions must differ from both endpoints and the terminal value is exact.
@MainActor
final class HistogramPlotAnimationTests: XCTestCase {
    private func histogram(peak: Int, samples: [UInt8] = []) -> HistogramData {
        var bins = [Int](repeating: 0, count: 256)
        bins[peak] = 1000
        return HistogramData(
            red: bins, green: bins, blue: bins, luma: bins,
            samples: samples, sampleWidth: samples.isEmpty ? 0 : 1, sampleHeight: samples.isEmpty ? 0 : 1)
    }

    private func interpolate(
        _ from: HistogramPlotValues, _ to: HistogramPlotValues, _ fraction: Double
    ) -> HistogramPlotValues {
        var delta = to - from
        delta.scale(by: fraction)
        return from + delta
    }

    func testIntermediateFractionDiffersFromBothEndpointsAndTerminalEqualsTarget() {
        let from = HistogramPlotValues(data: histogram(peak: 20))
        let to = HistogramPlotValues(data: histogram(peak: 230))

        let middle = interpolate(from, to, 0.5)
        XCTAssertNotEqual(middle, from)
        XCTAssertNotEqual(middle, to)
        XCTAssertEqual(interpolate(from, to, 0), from)
        XCTAssertEqual(interpolate(from, to, 1), to)
    }

    func testChartPlotsTheValueSwiftUIWritesThroughAnimatableData() {
        let from = HistogramPlotValues(data: histogram(peak: 20))
        let to = HistogramPlotValues(data: histogram(peak: 230))
        var chart = HistogramChart(data: histogram(peak: 230), channel: .rgb)
        XCTAssertEqual(chart.animatableData, to)
        let middle = interpolate(from, to, 0.5)
        chart.animatableData = middle
        XCTAssertEqual(chart.animatableData, middle)
    }

    func testSampleIdentityChangesOnlyWithSamples() {
        let a = histogram(peak: 1, samples: [1, 2, 3])
        XCTAssertEqual(a.sampleIdentity, histogram(peak: 9, samples: [1, 2, 3]).sampleIdentity)
        XCTAssertNotEqual(a.sampleIdentity, histogram(peak: 1, samples: [9, 8, 7]).sampleIdentity)
    }

    func testSampleBasedModes() {
        let sampleModes = HistogramChart.Mode.allCases.filter(\.isSampleBased)
        XCTAssertEqual(Set(sampleModes), [.waveform, .parade, .vectorscope])
    }
}
