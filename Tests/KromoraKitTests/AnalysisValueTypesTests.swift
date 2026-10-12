import Foundation
import XCTest

@testable import KromoraKit

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

    // MARK: Decoding enforces construction invariants

    private func mutated<T: Codable>(
        _ value: T, as type: T.Type = T.self, _ mutate: (inout [String: Any]) -> Void
    ) throws -> T {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
        )
        mutate(&object)
        return try JSONDecoder().decode(
            T.self, from: JSONSerialization.data(withJSONObject: object)
        )
    }

    func testToneStatisticsDecodeClampsOutOfRangeScalars() throws {
        let keys = ["minimum", "maximum", "mean", "p01", "p05", "p10", "p25", "p50", "p75",
                    "p90", "p95", "p99", "shadowClippingFraction", "highlightClippingFraction"]
        let base = ToneStatistics(variant: .perceptual, mean: 0.5)
        for key in keys {
            for (input, expected) in [(7.0, Float(1)), (-2.0, Float(0))] {
                let decoded = try mutated(base) { $0[key] = input }
                let direct = ToneStatistics(
                    variant: .perceptual,
                    minimum: key == "minimum" ? Float(input) : 0,
                    maximum: key == "maximum" ? Float(input) : 0,
                    mean: key == "mean" ? Float(input) : 0.5,
                    p01: key == "p01" ? Float(input) : 0,
                    p05: key == "p05" ? Float(input) : 0,
                    p10: key == "p10" ? Float(input) : 0,
                    p25: key == "p25" ? Float(input) : 0,
                    p50: key == "p50" ? Float(input) : 0,
                    p75: key == "p75" ? Float(input) : 0,
                    p90: key == "p90" ? Float(input) : 0,
                    p95: key == "p95" ? Float(input) : 0,
                    p99: key == "p99" ? Float(input) : 0,
                    shadowClippingFraction: key == "shadowClippingFraction" ? Float(input) : 0,
                    highlightClippingFraction: key == "highlightClippingFraction" ? Float(input) : 0
                )
                XCTAssertEqual(decoded, direct, key)
                XCTAssertEqual(try XCTUnwrap(
                    JSONSerialization.jsonObject(
                        with: JSONEncoder().encode(decoded)) as? [String: Any])[key] as? Double,
                    Double(expected), key)
            }
        }
    }

    func testLuminanceDistributionDecodeCannotSwapVariants() throws {
        let value = LuminanceDistribution(
            linear: ToneStatistics(mean: 0.2), perceptual: ToneStatistics(variant: .perceptual, mean: 0.6)
        )
        let decoded = try mutated(value) { object in
            var linear = object["linear"] as? [String: Any] ?? [:]
            var perceptual = object["perceptual"] as? [String: Any] ?? [:]
            linear["variant"] = "perceptual"
            perceptual["variant"] = "linear"
            object["linear"] = linear
            object["perceptual"] = perceptual
        }
        XCTAssertEqual(decoded.linear.variant, .linear)
        XCTAssertEqual(decoded.perceptual.variant, .perceptual)
        XCTAssertEqual(decoded, value)
    }

    func testColorStatisticsAndClippingDecodeClampVectorsAndScalars() throws {
        let decoded = try mutated(ColorStatistics()) { object in
            object["meanRGB"] = [-1.0, 0.5, 4.0]
            object["medianRGB"] = [2.0, -3.0, 0.25]
            object["saturationMedian"] = 9.0
            object["saturationP95"] = -9.0
            object["estimatedNeutrality"] = 1.5
            object["colorfulness"] = -0.5
            object["channelClipping"] = ["red": 3.0, "green": -1.0, "blue": 0.5]
        }
        XCTAssertEqual(decoded, ColorStatistics(
            meanRGB: SIMD3(-1, 0.5, 4), medianRGB: SIMD3(2, -3, 0.25),
            saturationMedian: 9, saturationP95: -9,
            channelClipping: ChannelClipping(red: 3, green: -1, blue: 0.5),
            estimatedNeutrality: 1.5, colorfulness: -0.5
        ))
        XCTAssertEqual(decoded.meanRGB, SIMD3<Float>(0, 0.5, 1))
        XCTAssertEqual(decoded.channelClipping, ChannelClipping(red: 1, green: 0, blue: 0.5))
    }

    func testAnalysisQualityDecodeClampsConfidence() throws {
        XCTAssertEqual(try mutated(AnalysisQuality.globalOnly) { $0["overallConfidence"] = 5.0 }
            .overallConfidence, 1)
        XCTAssertEqual(try mutated(AnalysisQuality.globalOnly) { $0["overallConfidence"] = -5.0 }
            .overallConfidence, 0)
    }

    func testMalformedShapeStillThrows() throws {
        let data = Data(#"{"red":"x","green":0,"blue":0}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ChannelClipping.self, from: data))
        let missing = Data(#"{"x":0.5}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(NormalizedPoint.self, from: missing))
    }

    func testRegionAndSelectionConfidenceDecodeClamps() throws {
        let selection = try mutated(PrimarySubjectSelection(primaryRegionID: nil, confidence: 0.5)) {
            $0["confidence"] = 12.0
        }
        XCTAssertEqual(selection.confidence, 1)
        let key = MaskCacheKey(
            assetID: PhotoAssetID.data(Data([1])), sourceFingerprint: .data(Data([1])),
            kind: .subject, quality: .analysis, providerVersion: "vision-1"
        )
        let mask = RegionMask(
            kind: .subject, bounds: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
            quality: .analysis,
            reference: RegionMaskReference(cacheKey: key, size: PixelDimensions(width: 2, height: 2)),
            confidence: 0.5, coverage: 0.5
        )
        let decoded = try mutated(mask) {
            $0["confidence"] = -4.0
            $0["coverage"] = 4.0
            $0["bounds"] = ["x": -5.0, "y": 2.0, "width": 10.0, "height": -4.0]
        }
        XCTAssertEqual(decoded.confidence, 0)
        XCTAssertEqual(decoded.coverage, 1)
        XCTAssertEqual(decoded.bounds, NormalizedRect(x: -5, y: 2, width: 10, height: -4))
    }
}
