import XCTest
import simd
import CoreGraphics
@testable import KromoraKit

/// Covers the parts of the derive pipeline that can be tested without a RAW
/// fixture: the cube assembly (which decides what every unsampled color in the
/// image maps to) and the working-resolution cap.
final class RecipeExtractorTests: XCTestCase {

    // MARK: - buildCube

    private func identityValue(_ i: Int, size: Int) -> SIMD3<Float> {
        SIMD3(Float(i % size), Float((i / size) % size), Float(i / (size * size))) / Float(size - 1)
    }

    /// A cell holding many samples should come out close to their mean, and a cell with a single
    /// sample should move far less: confidence scales with the count.
    func testCellsAreWeightedByConfidence() {
        let size = 9
        let count = size * size * size
        let target = SIMD3<Float>(0.9, 0.2, 0.2)
        let dense = 2 + 2 * size + 2 * size * size
        let sparse = 7 + 7 * size + 7 * size * size

        var sums = [SIMD3<Float>](repeating: .zero, count: count)
        var counts = [Int32](repeating: 0, count: count)
        // A well-sampled 3×3×3 neighborhood around `dense`; a smooth fit needs support, not one spike.
        for b in 1...3 { for g in 1...3 { for r in 1...3 {
            let i = r + g * size + b * size * size
            counts[i] = 5000
            sums[i] = target * 5000
        } } }
        counts[sparse] = 1
        sums[sparse] = target

        let cube = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size)
        let denseMove = simd_length(cube[dense] - identityValue(dense, size: size))
        let sparseMove = simd_length(cube[sparse] - identityValue(sparse, size: size))
        let fullMove = simd_length(target - identityValue(dense, size: size))
        XCTAssertGreaterThan(denseMove, 0.6 * fullMove, "a well-sampled cell should follow its mean")
        XCTAssertLessThan(sparseMove, 0.05 * simd_length(target - identityValue(sparse, size: size)) + 0.01,
                          "a lone sample must not be trusted: it moved \(sparseMove)")
    }

    /// No samples at all means no information: every cell stays at identity.
    func testNoSamplesIsIdentity() {
        let size = 5
        let count = size * size * size
        let cube = RecipeExtractor.buildCube(
            sums: [SIMD3<Float>](repeating: .zero, count: count),
            counts: [Int32](repeating: 0, count: count),
            size: size
        )
        for i in 0..<count {
            XCTAssertEqual(simd_length(cube[i] - identityValue(i, size: size)), 0, accuracy: 1e-6)
        }
    }

    /// A uniformly dense, uniformly offset cube is reproduced (shrunk only by the weak prior), and
    /// the shrink is the same at the border as in the middle: edge replication must not fade the
    /// cube's outer cells.
    func testUniformOffsetSurvivesSmoothingIncludingBorders() {
        let size = 9
        let count = size * size * size
        var sums = [SIMD3<Float>](repeating: .zero, count: count)
        let counts = [Int32](repeating: 400, count: count)
        let offset = SIMD3<Float>(0.05, -0.02, 0.03)
        for i in 0..<count { sums[i] = (identityValue(i, size: size) + offset) * 400 }

        let cube = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size)
        let middle = 4 + 4 * size + 4 * size * size
        let corner = 1 + 1 * size + 1 * size * size
        let middleShift = cube[middle] - identityValue(middle, size: size)
        let cornerShift = cube[corner] - identityValue(corner, size: size)
        XCTAssertEqual(middleShift.x, offset.x, accuracy: 0.01)
        XCTAssertEqual(cornerShift.x, offset.x, accuracy: 0.01)
        XCTAssertEqual(cornerShift.z, offset.z, accuracy: 0.01)
    }

    /// The influence of a sampled region must fade gradually and reach identity: no jump larger
    /// than a fraction of the offset between neighbors, and the far side of the cube is untouched.
    func testOffsetFadesToIdentityWithoutACliff() {
        let size = 33
        let count = size * size * size
        var sums = [SIMD3<Float>](repeating: .zero, count: count)
        var counts = [Int32](repeating: 0, count: count)
        // A saturated blob in the low corner, shifted by a large amount.
        for b in 0..<6 { for g in 0..<6 { for r in 0..<6 {
            let i = r + g * size + b * size * size
            counts[i] = 300
            sums[i] = (identityValue(i, size: size) + SIMD3(0.4, 0.3, -0.1)) * 300
        } } }

        let cube = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size)
        let far = (size - 1) + (size - 1) * size + (size - 1) * size * size
        XCTAssertEqual(simd_length(cube[far] - identityValue(far, size: size)), 0, accuracy: 1e-6)

        // Walk the diagonal out of the blob: the offset shrinks monotonically in small steps.
        var previous = Float.greatestFiniteMagnitude
        var largestStep: Float = 0
        for t in 0..<size {
            let i = t + t * size + t * size * size
            let move = simd_length(cube[i] - identityValue(i, size: size))
            if t > 3 { XCTAssertLessThanOrEqual(move, previous + 1e-5, "offset grew again at \(t)") }
            if t > 0 { largestStep = max(largestStep, abs(previous - move)) }
            previous = move
        }
        XCTAssertLessThan(largestStep, 0.2, "offset collapsed in one cell: \(largestStep)")
    }

    func testBuiltCubeIsAlwaysFullyPopulatedAndFinite() {
        let size = 6
        let count = size * size * size
        var sums = [SIMD3<Float>](repeating: .zero, count: count)
        var counts = [Int32](repeating: 0, count: count)

        // Sparse, realistic-ish coverage: a handful of scattered cells.
        for i in stride(from: 0, to: count, by: 37) {
            sums[i] = SIMD3(0.5, 0.5, 0.5)
            counts[i] = 1
        }

        let cube = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size)
        XCTAssertEqual(cube.count, count)
        for (i, v) in cube.enumerated() {
            XCTAssertTrue(v.x.isFinite && v.y.isFinite && v.z.isFinite, "cell \(i) is not finite: \(v)")
            XCTAssertTrue(v.x >= 0 && v.x <= 1 && v.y >= 0 && v.y <= 1 && v.z >= 0 && v.z <= 1)
        }
    }

    // MARK: - Narrow-gamut pair (generated, no RAW)

    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// The grade the generated "JPG" applies: contrast, a warm cast and a saturation cut, all
    /// nonlinear enough that an unsampled color has no obvious right answer.
    private func grade(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let luma = (c.x + c.y + c.z) / 3
        let curved = c * c * (SIMD3<Float>(repeating: 3) - 2 * c)
        let desaturated = SIMD3(repeating: luma) + (curved - SIMD3(repeating: luma)) * 0.42
        return simd_clamp(desaturated + SIMD3(0.03, 0.0, -0.04), .zero, .one)
    }

    /// Draw `count` 8-bit samples of warm tans and neutral grays (a desert street) and accumulate
    /// them the way `accumulateSamples` does: nearest cell of the neutral value, sum of the graded one.
    private func narrowGamutAccumulation(size: Int, samples: Int = 200_000)
        -> (sums: [SIMD3<Float>], counts: [Int32])
    {
        var rng = SeededGenerator(state: 42)
        var sums = [SIMD3<Float>](repeating: .zero, count: size * size * size)
        var counts = [Int32](repeating: 0, count: size * size * size)
        for n in 0..<samples {
            let luma = Float.random(in: 0.08...0.95, using: &rng)
            // Even draws are grays, odd ones tans (red > green > blue), with sensor-ish noise.
            let tint: SIMD3<Float> = n.isMultiple(of: 2) ? .zero : SIMD3(0.10, 0.03, -0.09)
            var neutral = SIMD3(repeating: luma) + tint * luma
            neutral += SIMD3(Float.random(in: -0.01...0.01, using: &rng),
                             Float.random(in: -0.01...0.01, using: &rng),
                             Float.random(in: -0.01...0.01, using: &rng))
            neutral = simd_clamp(neutral, .zero, .one)
            let input = quantized(neutral)
            let out = quantized(grade(input))
            let scaled = input * Float(size - 1) + SIMD3<Float>(repeating: 0.5)
            let r = Int(scaled.x), g = Int(scaled.y), b = Int(scaled.z)
            let idx = r + g * size + b * size * size
            sums[idx] += out
            counts[idx] += 1
        }
        return (sums, counts)
    }

    private func quantized(_ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3((v.x * 255).rounded() / 255, (v.y * 255).rounded() / 255, (v.z * 255).rounded() / 255)
    }

    private func neighborSteps(_ cube: [SIMD3<Float>], size: Int) -> [Float] {
        var steps: [Float] = []
        let perChannel = Float(3).squareRoot()
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            let i = r + g * size + b * size * size
            if r + 1 < size { steps.append(simd_length(cube[i] - cube[i + 1]) / perChannel) }
            if g + 1 < size { steps.append(simd_length(cube[i] - cube[i + size]) / perChannel) }
            if b + 1 < size { steps.append(simd_length(cube[i] - cube[i + size * size]) / perChannel) }
        } } }
        return steps
    }

    /// Trilinear lookup in a cube, matching how the render path interpolates it.
    private func lookup(_ cube: [SIMD3<Float>], size: Int, _ c: SIMD3<Float>) -> SIMD3<Float> {
        let p = simd_clamp(c, .zero, .one) * Float(size - 1)
        let base = SIMD3<Int>(Int(min(p.x, Float(size - 2))), Int(min(p.y, Float(size - 2))), Int(min(p.z, Float(size - 2))))
        let f = p - SIMD3<Float>(Float(base.x), Float(base.y), Float(base.z))
        func at(_ dr: Int, _ dg: Int, _ db: Int) -> SIMD3<Float> {
            cube[(base.x + dr) + (base.y + dg) * size + (base.z + db) * size * size]
        }
        let c00 = at(0, 0, 0) * (1 - f.x) + at(1, 0, 0) * f.x
        let c10 = at(0, 1, 0) * (1 - f.x) + at(1, 1, 0) * f.x
        let c01 = at(0, 0, 1) * (1 - f.x) + at(1, 0, 1) * f.x
        let c11 = at(0, 1, 1) * (1 - f.x) + at(1, 1, 1) * f.x
        return (c00 * (1 - f.y) + c10 * f.y) * (1 - f.z) + (c01 * (1 - f.y) + c11 * f.y) * f.z
    }

    /// The cube derived from tans and grays only must be smooth everywhere, including the
    /// colors it never saw. The pre-KRMA-1154 cube had a p99 neighbor step of ~0.55 (per channel,
    /// 0…1) and a maximum of ~0.77.
    func testNarrowGamutCubeHasBoundedNeighborSteps() {
        let size = 33
        let (sums, counts) = narrowGamutAccumulation(size: size)
        let cube = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size)

        let steps = neighborSteps(cube, size: size).sorted()
        let p99 = steps[Int(Float(steps.count) * 0.99)]
        let worst = steps.last ?? 0
        // Measured on this fixture: p99 0.022, max 0.029 (RMS per channel); thresholds keep ~2x margin.
        XCTAssertLessThan(p99, 0.05, "p99 neighbor step \(p99)")
        XCTAssertLessThan(worst, 0.07, "max neighbor step \(worst)")
    }

    /// Far from the sampled tans and grays, the Look must leave colors alone rather than
    /// reinterpret them.
    func testNarrowGamutCubeLeavesUnsampledGreensNearIdentity() {
        let size = 33
        let (sums, counts) = narrowGamutAccumulation(size: size)
        let cube = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size)

        for green in [SIMD3<Float>(0.1, 0.6, 0.1), SIMD3(0.3, 0.8, 0.2), SIMD3(0.6, 1.0, 0.1), SIMD3(0.05, 0.35, 0.05)] {
            let out = lookup(cube, size: size, green)
            XCTAssertLessThan(simd_length(out - green), 0.12, "\(green) -> \(out)")
            XCTAssertGreaterThan(out.y, out.x, "green \(green) lost its hue: \(out)")
            XCTAssertGreaterThan(out.y, out.z, "green \(green) lost its hue: \(out)")
        }
    }

    /// A smooth green ramp through the narrow-gamut Look must come out without banding or a hue
    /// flip: the output is monotone in the ramp parameter and its total variation is close to the
    /// ramp's own.
    func testNarrowGamutLookKeepsAGreenGradientSmooth() {
        let size = 33
        let (sums, counts) = narrowGamutAccumulation(size: size)
        let cube = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size)

        let steps = 512
        var previous = SIMD3<Float>.zero
        var variation: Float = 0
        for s in 0...steps {
            let t = Float(s) / Float(steps)
            let input = SIMD3<Float>(0.04 + 0.2 * t, 0.15 + 0.8 * t, 0.03 + 0.1 * t)
            let out = lookup(cube, size: size, input)
            if s > 0 {
                XCTAssertGreaterThanOrEqual(out.y, previous.y - 0.002, "green channel reversed at t=\(t)")
                variation += simd_length(out - previous)
            }
            XCTAssertGreaterThan(out.y, out.x, "hue flipped at t=\(t): \(out)")
            XCTAssertGreaterThan(out.y, out.z, "hue flipped at t=\(t): \(out)")
            previous = out
        }
        let inputLength = simd_length(SIMD3<Float>(0.2, 0.8, 0.1))
        XCTAssertLessThan(variation, inputLength * 1.35, "total variation \(variation) vs ramp \(inputLength)")
    }

    /// Sampled colors still get the grade: the fix must not just flatten everything to identity.
    func testNarrowGamutLookStillAppliesToSampledColors() {
        let size = 33
        let (sums, counts) = narrowGamutAccumulation(size: size)
        let cube = RecipeExtractor.buildCube(sums: sums, counts: counts, size: size)

        for luma: Float in [0.25, 0.5, 0.75] {
            let gray = SIMD3(repeating: luma)
            let out = lookup(cube, size: size, gray)
            XCTAssertLessThan(simd_length(out - grade(gray)), 0.06, "gray \(luma): \(out) vs \(grade(gray))")
        }
    }

    // MARK: - Working resolution

    func testWorkingSizeCapsLongEdgeAndKeepsAspect() {
        let capped = RecipeExtractor.workingSize(
            for: CGSize(width: 9000, height: 6000), longEdge: 3000
        )
        XCTAssertEqual(capped.width, 3000)
        XCTAssertEqual(capped.height, 2000)
    }

    func testWorkingSizeCapsPortraitOnItsLongEdge() {
        let capped = RecipeExtractor.workingSize(
            for: CGSize(width: 6000, height: 9000), longEdge: 3000
        )
        XCTAssertEqual(capped.height, 3000)
        XCTAssertEqual(capped.width, 2000)
    }

    func testWorkingSizeLeavesSmallImagesAlone() {
        let size = CGSize(width: 1200, height: 800)
        XCTAssertEqual(RecipeExtractor.workingSize(for: size, longEdge: 3000), size,
                       "an image already under the cap should not be upscaled")
    }

    func testWorkingSizeZeroMeansNative() {
        let size = CGSize(width: 9000, height: 6000)
        XCTAssertEqual(RecipeExtractor.workingSize(for: size, longEdge: 0), size)
        XCTAssertEqual(RecipeExtractor.workingSize(for: size, longEdge: -1), size)
    }

    // MARK: - Coverage note

    func testLowCoverageThresholdFlagsNarrowPairs() {
        func report(coverage: Float) -> RecipeReport {
            RecipeReport(
                toneCurve: [], saturationRatio: 1, sharpeningRatio: 1, sampleCount: 1,
                cubeCoveragePercent: coverage, alignmentShift: (dx: 0, dy: 0), cameraInfo: nil
            )
        }
        XCTAssertTrue(report(coverage: 2.9).hasLowCoverage)
        XCTAssertFalse(report(coverage: 25).hasLowCoverage)
    }

    // MARK: - Errors

    func testGeometryMismatchErrorNamesBothSizes() throws {
        let error = RecipeExtractor.ExtractorError.geometryMismatch(
            raw: CGSize(width: 4928, height: 3288),
            jpg: CGSize(width: 533, height: 800)
        )
        let message = try XCTUnwrap(error.errorDescription)
        XCTAssertTrue(message.contains("4928×3288"), "should name the RAW size: \(message)")
        XCTAssertTrue(message.contains("533×800"), "should name the JPG size: \(message)")
    }
}
