import XCTest
@testable import KromoraKit

final class GamutTallyTests: XCTestCase {
    /// Encode an sRGB color as Display P3 bytes (what the histogram sample holds), independently of
    /// the production tally: sRGB-decode, sRGB->XYZ->P3 matrices, sRGB-encode, round to 8 bits.
    private func p3Bytes(fromSRGB c: (Double, Double, Double)) -> [UInt8] {
        func dec(_ e: Double) -> Double { e <= 0.04045 ? e / 12.92 : pow((e + 0.055) / 1.055, 2.4) }
        func enc(_ l: Double) -> Double { l <= 0.0031308 ? l * 12.92 : 1.055 * pow(l, 1 / 2.4) - 0.055 }
        let (r, g, b) = (dec(c.0), dec(c.1), dec(c.2))
        let x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b
        let pr = 2.4934969 * x - 0.9313836 * y - 0.4027108 * z
        let pg = -0.8294890 * x + 1.7626641 * y + 0.0236247 * z
        let pb = 0.0358458 * x - 0.0761724 * y + 0.9568845 * z
        return [pr, pg, pb].map { UInt8((min(1, max(0, enc($0))) * 255).rounded()) }
    }

    func testSRGBPatchesReadZeroOutside() {
        let colors: [(Double, Double, Double)] = [
            (1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0), (0, 1, 1), (1, 0, 1),
            (0, 0, 0), (1, 1, 1), (0.5, 0.5, 0.5), (0.8, 0.4, 0.2), (0.1, 0.7, 0.3),
        ]
        let tally = GamutTally(displayP3Samples: colors.flatMap(p3Bytes(fromSRGB:)))
        XCTAssertEqual(tally.pixelCount, colors.count)
        XCTAssertEqual(tally.outsideSRGBCount, 0)
        XCTAssertEqual(tally.outsideSRGBFraction, 0)
    }

    func testP3SaturatedGreenAreaIsExact() {
        // 3 of 12 pixels are P3 green (0,255,0); the rest are mid-gray.
        var samples: [UInt8] = []
        for i in 0..<12 { samples += i < 3 ? [0, 255, 0] : [128, 128, 128] }
        let tally = GamutTally(displayP3Samples: samples)
        XCTAssertEqual(tally.outsideSRGBCount, 3)
        XCTAssertEqual(tally.outsideSRGBFraction, 0.25, accuracy: 1e-12)
        XCTAssertFalse(tally.measuresBeyondP3)
        XCTAssertEqual(tally.outsideP3Count, 0)
    }

    func testP3EdgePrimariesAreOutsideSRGBButInsideP3() {
        let samples: [UInt8] = [255, 0, 0, 0, 255, 0, 0, 0, 255]
        let tally = GamutTally(displayP3Samples: samples)
        XCTAssertEqual(tally.outsideSRGBCount, 3)
        let linear = GamutTally(linearDisplayP3: [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
        XCTAssertEqual(linear.outsideSRGBCount, 3)
        XCTAssertEqual(linear.outsideP3Count, 0)
    }

    func testExtendedRangeBeyondP3IsCounted() {
        let tally = GamutTally(linearDisplayP3: [
            [0.2, 0.3, 0.4],      // in sRGB
            [0, 1, 0],            // P3 edge
            [-0.1, 1.1, 0],       // beyond P3
            [0.5, 0.5, 1.5],      // above range
        ])
        XCTAssertTrue(tally.measuresBeyondP3)
        XCTAssertEqual(tally.pixelCount, 4)
        XCTAssertEqual(tally.outsideP3Count, 2)
        XCTAssertEqual(tally.outsideSRGBCount, 3)
        XCTAssertEqual(tally.outsideP3Fraction, 0.5, accuracy: 1e-12)
    }

    func testFloatSamplesCountSmallOutOfGamutValues() {
        let tally = GamutTally(linearDisplayP3: [
            [-0.005, 0.4, 0.4],
            [1.005, 0.4, 0.4],
        ])
        XCTAssertEqual(tally.outsideP3Count, 2)
        XCTAssertEqual(tally.outsideSRGBCount, 2)
    }

    func testDensityHoldsEveryNonBlackPixel() {
        let tally = GamutTally(displayP3Samples: [0, 0, 0, 255, 255, 255, 255, 255, 255, 0, 255, 0])
        XCTAssertEqual(tally.density.count, GamutTally.gridSize * GamutTally.gridSize)
        // Black has no chromaticity; it counts toward the total but not the density.
        XCTAssertEqual(tally.density.reduce(0, +), 3)
        XCTAssertEqual(tally.densityPeak, 2) // two whites share the D65 cell
    }

    func testEmptySampleIsZero() {
        let tally = GamutTally(displayP3Samples: [])
        XCTAssertEqual(tally.pixelCount, 0)
        XCTAssertEqual(tally.outsideSRGBFraction, 0)
    }

    func testPrimariesAreOrderedP3WiderThanSRGB() {
        func area(_ p: [CGPoint]) -> Double {
            abs((p[1].x - p[0].x) * (p[2].y - p[0].y) - (p[2].x - p[0].x) * (p[1].y - p[0].y)) / 2
        }
        XCTAssertEqual(GamutTally.sRGBPrimaries.count, 3)
        XCTAssertEqual(GamutTally.displayP3Primaries.count, 3)
        XCTAssertGreaterThan(area(GamutTally.displayP3Primaries), area(GamutTally.sRGBPrimaries))
        // Known sRGB red in u'v'.
        XCTAssertEqual(GamutTally.sRGBPrimaries[0].x, 0.4507, accuracy: 0.001)
        XCTAssertEqual(GamutTally.sRGBPrimaries[0].y, 0.5229, accuracy: 0.001)
    }
}
