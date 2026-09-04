import Foundation
import XCTest

@testable import LumoKit

final class AnalysisValueTypesTests: XCTestCase {
    func testToneAndColorStatisticsRoundTrip() throws {
        let tone = ToneStatistics(
            variant: .perceptual, minimum: 0.01, maximum: 0.99, mean: 0.5,
            p01: 0.02, p05: 0.05, p10: 0.1, p25: 0.25, p50: 0.5,
            p75: 0.75, p90: 0.9, p95: 0.95, p99: 0.99,
            shadowClippingFraction: 0.02, highlightClippingFraction: 0.03
        )
        let values = LuminanceDistribution(linear: .neutral, perceptual: tone)
        let color = ColorStatistics(
            meanRGB: SIMD3(0.2, 0.4, 0.6), medianRGB: SIMD3(0.1, 0.3, 0.5),
            saturationMedian: 0.4, saturationP95: 0.8,
            channelClipping: ChannelClipping(red: 0.01, green: 0.02, blue: 0.03),
            estimatedNeutrality: 0.7, colorfulness: 0.6
        )

        XCTAssertEqual(try roundTrip(values), values)
        XCTAssertEqual(try roundTrip(color), color)
        XCTAssertEqual(ToneStatistics(variant: .perceptual).variant, .perceptual)
    }

    func testQualityAndTimingsRoundTrip() throws {
        let quality = AnalysisQuality(
            globalToneAvailable: true, attentionAvailable: true,
            foregroundAvailable: false, faceAnalysisAvailable: true,
            peopleAnalysisAvailable: false, overallConfidence: 0.75
        )
        let timings = AnalysisTimings(
            imagePreparation: .milliseconds(2), globalTone: .milliseconds(3),
            faceDetection: .milliseconds(4), saliency: .milliseconds(5),
            foregroundMasking: .milliseconds(6), personSegmentation: .milliseconds(7),
            regionalAnalysis: .milliseconds(8), total: .milliseconds(35)
        )

        XCTAssertEqual(try roundTrip(quality), quality)
        XCTAssertEqual(try roundTrip(timings), timings)
        XCTAssertEqual(AnalysisQuality.globalOnly.globalToneAvailable, true)
    }

    func testVersionClampsToTheSupportedRange() {
        XCTAssertEqual(AnalysisVersion(-10), AnalysisVersion.current)
        XCTAssertEqual(AnalysisVersion(100), AnalysisVersion.current)
        XCTAssertEqual(AnalysisVersion.current.rawValue, 1)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
