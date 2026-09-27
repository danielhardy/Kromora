import CoreImage
import CoreGraphics
import XCTest

@testable import KromoraKit

/// Deterministic, image-quality oracle for the small-defect retouch lane. This is deliberately
/// separate from renderer timing tests; it compares rendered pixels with known clean references.
final class RetouchQualityEvaluationTests: XCTestCase {
    private struct Metrics {
        let deltaE2000: Double
        let gradientError: Double
        let varianceRatio: Double
        let luminanceShift: Double

        func failures(against limit: Limits) -> [String] {
            var result: [String] = []
            if deltaE2000 > limit.deltaE { result.append("ΔE") }
            if gradientError > limit.gradient { result.append("gradient") }
            if !(limit.variance.lowerBound...limit.variance.upperBound).contains(varianceRatio) { result.append("variance") }
            if abs(luminanceShift) > limit.luminance { result.append("luminance") }
            return result
        }
    }

    private struct Limits {
        let deltaE: Double
        let gradient: Double
        let variance: ClosedRange<Double>
        let luminance: Double
    }

    // Phase-0 starting limits. They are intentionally conservative but reject visible remnants,
    // broad halos, broken edges, and strongly smoothed grain. Tighten only with recorded evidence.
    private let limits: [String: Limits] = [
        "sky": Limits(deltaE: 3.0, gradient: 28, variance: 0.55...1.65, luminance: 0.025),
        "cloud": Limits(deltaE: 3.5, gradient: 32, variance: 0.50...1.75, luminance: 0.03),
        "foliage": Limits(deltaE: 4.5, gradient: 38, variance: 0.48...1.8, luminance: 0.035),
        "water": Limits(deltaE: 3.5, gradient: 30, variance: 0.50...1.7, luminance: 0.03),
        "brick": Limits(deltaE: 4.0, gradient: 34, variance: 0.48...1.8, luminance: 0.03),
        "skin": Limits(deltaE: 3.0, gradient: 28, variance: 0.55...1.65, luminance: 0.025),
    ]

    func testGroundTruthGateReportsCurrentHealAndRemoveFailures() throws {
        var table: [(String, String, String, Metrics, [String])] = []
        var healFailuresByDefect: [String: Int] = [:]
        var removeFailuresByDefect: [String: Int] = [:]
        var automaticHealPasses = 0

        for background in RetouchQualityFixtures.backgrounds {
            for defect in RetouchQualityFixtures.defects {
                let fixture = RetouchQualityFixtures.make(background: background, defect: defect)
                let clean = try Pixels.bytes(of: fixture.clean)
                let damaged = try Pixels.bytes(of: fixture.damaged)
                let input = CIImage(cgImage: fixture.damaged)
                let radius = fixture.radius
                let samples = fixture.stroke.isEmpty
                    ? [BrushSample(point: fixture.center)] : fixture.stroke.map { BrushSample(point: $0) }
                let spotRadius = radius
                let actualModes: [(String, RetouchMode?)] = [
                    ("Remove (no path)", nil), ("Heal", .heal), ("Heal (auto)", .heal), ("Clone", .clone),
                    ("Current", .heal),
                ]
                for (label, mode) in actualModes {
                    let output: [UInt8]
                    if let mode {
                        var spot = RetouchSpot(
                            mode: mode,
                            region: RetouchRegion(samples: samples, radius: spotRadius),
                            source: .manual(offset: fixture.sourceOffset)
                        )
                        if label == "Heal (auto)" {
                            let proxy = RetouchAnalysisProxy.fromRGBA8(
                                Data(damaged), width: fixture.width, height: fixture.height
                            )
                            spot.source = RetouchSourcePicker.source(for: spot, among: [spot], in: proxy)
                        }
                        let rendered = RetouchRenderer.apply(
                            RetouchSettings(spots: [spot]), to: input,
                            sourceSize: CGSize(width: fixture.width, height: fixture.height),
                            maskRenderer: LocalMaskRenderer()
                        )
                        output = try Pixels.bytes(of: rendered)
                    } else {
                        // Remove is prospective. Measuring the unchanged damaged image makes the
                        // absent inpainting path visible as a threshold failure, not a false pass.
                        output = damaged
                    }
                    let values = measure(clean: clean, output: output, fixture: fixture)
                    let failed = values.failures(against: limits[background]!)
                    table.append((background, defect, label, values, failed))
                    if label == "Heal (auto)" && failed.isEmpty { automaticHealPasses += 1 }
                    if label == "Heal" && !failed.isEmpty { healFailuresByDefect[defect, default: 0] += 1 }
                    if label == "Remove (no path)" && !failed.isEmpty { removeFailuresByDefect[defect, default: 0] += 1 }
                }
            }
        }

        let header = "BACKGROUND / DEFECT | MODE | ΔE2000 | GRADIENT | VAR RATIO | LUMA SHIFT | RESULT"
        print("\nRETOUCH QUALITY — limits: ΔE / gradient RGB levels / variance ratio / abs luma shift\n\(header)")
        for row in table {
            let result = row.4.isEmpty ? "PASS" : "FAIL: " + row.4.joined(separator: ",")
            print(String(format: "%@ / %@ | %@ | %.2f | %.2f | %.2f | %+.4f | %@",
                row.0, row.1, row.2, row.3.deltaE2000, row.3.gradientError,
                row.3.varianceRatio, row.3.luminanceShift, result))
        }
        print("Automatic Heal quality rows passing: \(automaticHealPasses)/\(RetouchQualityFixtures.backgrounds.count * RetouchQualityFixtures.defects.count)")

        // These are behavior assertions about the current renderer, not XCTest expected failures:
        // Heal and the missing Remove implementation must continue to be exposed by the oracle.
        for defect in RetouchQualityFixtures.defects {
            XCTAssertGreaterThan(healFailuresByDefect[defect, default: 0], 0,
                "current Heal must miss at least one (defect) case")
            XCTAssertEqual(removeFailuresByDefect[defect], RetouchQualityFixtures.backgrounds.count,
                "prospective Remove no-op must fail all (defect) backgrounds")
        }
        XCTAssertGreaterThan(automaticHealPasses, 0, "automatic source picks should clear some KRMA-658 heal rows")
        XCTAssertEqual(table.count, RetouchQualityFixtures.backgrounds.count * RetouchQualityFixtures.defects.count * 5)
    }

    func testSyntheticFixtureGenerationIsRepeatable() throws {
        let first = RetouchQualityFixtures.make(background: "cloud", defect: "wire straight")
        let second = RetouchQualityFixtures.make(background: "cloud", defect: "wire straight")
        XCTAssertEqual(try Pixels.bytes(of: first.clean), try Pixels.bytes(of: second.clean))
        XCTAssertEqual(try Pixels.bytes(of: first.damaged), try Pixels.bytes(of: second.damaged))
        XCTAssertEqual(first.mask, second.mask)
    }

    func testPatchMatchRemoveQualityAcrossGroundTruthCorpus() throws {
        var table: [(String, String, Metrics, [String])] = []
        for background in RetouchQualityFixtures.backgrounds {
            for defect in RetouchQualityFixtures.defects {
                let fixture = RetouchQualityFixtures.make(background: background, defect: defect)
                let clean = try Pixels.bytes(of: fixture.clean)
                let damaged = try Pixels.bytes(of: fixture.damaged)
                let proxy = RetouchAnalysisProxy.fromRGBA8(Data(damaged), width: fixture.width, height: fixture.height)
                let hole = fixture.mask.map { $0 ? UInt8(1) : 0 }
                let samples = fixture.stroke.isEmpty ? [fixture.center] : fixture.stroke
                let spot = RetouchSpot(mode: .remove, region: RetouchRegion(
                    samples: samples.map { BrushSample(point: $0) }, radius: fixture.radius
                ))
                let pickedOffset: CGVector
                if case .auto(let offset, _)? = RetouchSourcePicker.source(for: spot, among: [spot], in: proxy) {
                    pickedOffset = offset
                } else {
                    pickedOffset = fixture.sourceOffset
                }
                let field = try PatchMatchInpainter.solve(.init(
                    image: .init(width: fixture.width, height: fixture.height, lab: proxy.pixels),
                    holeMask: hole, exclusionMask: [UInt8](repeating: 0, count: hole.count), seed: 658,
                    initialOffset: SIMD2(Int((pickedOffset.dx * Double(fixture.width)).rounded()),
                                         -Int((pickedOffset.dy * Double(fixture.height)).rounded()))
                ))
                let output = compositeRemove(damaged: damaged, field: field, fixture: fixture, sourceOffset: pickedOffset)
                let metrics = measure(clean: clean, output: output, fixture: fixture)
                let failures = metrics.failures(against: limits[background]!)
                table.append((background, defect, metrics, failures))
            }
        }
        print("\nPATCHMATCH REMOVE QUALITY — BG / DEFECT | ΔE2000 | GRADIENT | VAR RATIO | LUMA SHIFT | RESULT")
        for row in table {
            print(String(format: "%@ / %@ | %.2f | %.2f | %.2f | %+.4f | %@", row.0, row.1,
                row.2.deltaE2000, row.2.gradientError, row.2.varianceRatio, row.2.luminanceShift,
                row.3.isEmpty ? "PASS" : "FAIL: " + row.3.joined(separator: ",")))
        }
        XCTAssertEqual(table.count, RetouchQualityFixtures.backgrounds.count * RetouchQualityFixtures.defects.count)
        XCTAssertTrue(table.allSatisfy { $0.3.isEmpty }, "PatchMatch Remove must pass every KRMA-658 case")
    }

    /// Test-only live-image sampling followed by an exterior-ring membrane colour correction.
    private func compositeRemove(damaged: [UInt8], field: PatchMatchInpainter.Field,
                                 fixture: RetouchQualityFixtures.Case, sourceOffset: CGVector) -> [UInt8] {
        let w = fixture.width, h = fixture.height
        var output = damaged
        // Estimate the membrane's local offset exclusively from the one-pixel exterior ring.
        var correction = [Double](repeating: 0, count: 3), count = 0.0
        for y in max(0, field.y - 1)..<min(h, field.y + field.height + 1) {
            for x in max(0, field.x - 1)..<min(w, field.x + field.width + 1) {
                guard fixture.mask[y * w + x] == false else { continue }
                let dx = Int((sourceOffset.dx * Double(w)).rounded())
                let dy = -Int((sourceOffset.dy * Double(h)).rounded())
                let sx = x + dx, sy = y + dy
                guard sx >= 0, sy >= 0, sx < w, sy < h else { continue }
                for c in 0..<3 {
                    correction[c] += Double(Int(damaged[(y * w + x) * 4 + c]) - Int(damaged[(sy * w + sx) * 4 + c]))
                }
                count += 1
            }
        }
        if count > 0 { correction = correction.map { $0 / count } }
        for y in 0..<h { for x in 0..<w where fixture.mask[y * w + x] {
            guard let p = field[x, y], p.x >= 0 else { continue }
            let sx = Int(p.x), sy = Int(p.y), destination = (y * w + x) * 4, source = (sy * w + sx) * 4
            for c in 0..<3 {
                output[destination + c] = UInt8(min(255, max(0, Double(damaged[source + c]) + correction[c].rounded())))
            }
        } }
        return output
    }

    private func measure(clean: [UInt8], output: [UInt8], fixture: RetouchQualityFixtures.Case) -> Metrics {
        let w = fixture.width, h = fixture.height
        var selected = fixture.mask
        for y in 0..<h { for x in 0..<w where !selected[y * w + x] {
            let near = (-4...4).contains { dy in (-4...4).contains { dx in
                abs(dx) + abs(dy) <= 4 && x + dx >= 0 && x + dx < w && y + dy >= 0 && y + dy < h
                    && fixture.mask[(y + dy) * w + x + dx]
            }}
            if near { selected[y * w + x] = true }
        }}
        let indices = selected.indices.filter { selected[$0] }
        var delta = 0.0, lumaShift = 0.0
        for i in indices {
            let a = lab(clean, i * 4), b = lab(output, i * 4)
            delta += deltaE2000(a, b)
            lumaShift += luminance(output, i * 4) - luminance(clean, i * 4)
        }
        let gradientIndices = indices.filter { i in
            let x = i % w, y = i / w
            return x + 1 < w && y + 1 < h
        }
        var gradient = 0.0
        for i in gradientIndices {
            for neighbor in [i + 1, i + w] {
                for c in 0..<3 {
                    let actual = Double(Int(output[neighbor * 4 + c]) - Int(output[i * 4 + c]))
                    let expected = Double(Int(clean[neighbor * 4 + c]) - Int(clean[i * 4 + c]))
                    gradient += abs(actual - expected)
                }
            }
        }
        let cleanVariance = localVariance(clean, indices: indices, width: w, height: h)
        let outputVariance = localVariance(output, indices: indices, width: w, height: h)
        return Metrics(
            deltaE2000: delta / Double(max(1, indices.count)),
            gradientError: gradient / Double(max(1, gradientIndices.count * 6)),
            varianceRatio: cleanVariance > 1e-10 ? outputVariance / cleanVariance : 1,
            luminanceShift: lumaShift / Double(max(1, indices.count))
        )
    }

    private func localVariance(_ pixels: [UInt8], indices: [Int], width: Int, height: Int) -> Double {
        var varianceSum = 0.0
        for index in indices {
            let x = index % width, y = index / width
            var values: [Double] = []
            for dy in -1...1 { for dx in -1...1 {
                let nx = x + dx, ny = y + dy
                if nx >= 0 && nx < width && ny >= 0 && ny < height { values.append(luminance(pixels, (ny * width + nx) * 4)) }
            }}
            let mean = values.reduce(0, +) / Double(values.count)
            varianceSum += values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        }
        return indices.isEmpty ? 0 : varianceSum / Double(indices.count)
    }

    private func luminance(_ p: [UInt8], _ i: Int) -> Double {
        (0.2126 * Double(p[i]) + 0.7152 * Double(p[i + 1]) + 0.0722 * Double(p[i + 2])) / 255
    }

    private func lab(_ p: [UInt8], _ i: Int) -> (Double, Double, Double) {
        func linear(_ byte: UInt8) -> Double {
            let v = Double(byte) / 255
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = linear(p[i]), g = linear(p[i + 1]), b = linear(p[i + 2])
        let x = (r * 0.4124564 + g * 0.3575761 + b * 0.1804375) / 0.95047
        let y = (r * 0.2126729 + g * 0.7151522 + b * 0.0721750)
        let z = (r * 0.0193339 + g * 0.1191920 + b * 0.9503041) / 1.08883
        func f(_ value: Double) -> Double { value > 0.008856451679 ? pow(value, 1 / 3) : 7.787037 * value + 16 / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// CIEDE2000, Sharma et al. This keeps the reported colour error perceptual rather than RGB-only.
    private func deltaE2000(_ lhs: (Double, Double, Double), _ rhs: (Double, Double, Double)) -> Double {
        let (l1, a1, b1) = lhs, (l2, a2, b2) = rhs
        let c1 = hypot(a1, b1), c2 = hypot(a2, b2), cBar = (c1 + c2) / 2
        let g = 0.5 * (1 - sqrt(pow(cBar, 7) / (pow(cBar, 7) + pow(25.0, 7))))
        let ap1 = (1 + g) * a1, ap2 = (1 + g) * a2
        let cp1 = hypot(ap1, b1), cp2 = hypot(ap2, b2)
        func hue(_ a: Double, _ b: Double) -> Double { (atan2(b, a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360) }
        let hp1 = hue(ap1, b1), hp2 = hue(ap2, b2)
        let dL = l2 - l1, dC = cp2 - cp1
        var dh = hp2 - hp1
        if cp1 * cp2 == 0 { dh = 0 } else if dh > 180 { dh -= 360 } else if dh < -180 { dh += 360 }
        let dH = 2 * sqrt(cp1 * cp2) * sin(dh * .pi / 360)
        let lBar = (l1 + l2) / 2, cpBar = (cp1 + cp2) / 2
        var hpBar = hp1 + hp2
        if cp1 * cp2 == 0 { hpBar = hp1 + hp2 }
        else if abs(hp1 - hp2) > 180 { hpBar += hpBar < 360 ? 360 : -360 }
        hpBar /= 2
        let t = 1 - 0.17 * cos((hpBar - 30) * .pi / 180) + 0.24 * cos(2 * hpBar * .pi / 180)
            + 0.32 * cos((3 * hpBar + 6) * .pi / 180) - 0.20 * cos((4 * hpBar - 63) * .pi / 180)
        let sl = 1 + 0.015 * pow(lBar - 50, 2) / sqrt(20 + pow(lBar - 50, 2))
        let sc = 1 + 0.045 * cpBar, sh = 1 + 0.015 * cpBar * t
        let deltaTheta = 30 * exp(-pow((hpBar - 275) / 25, 2))
        let rc = 2 * sqrt(pow(cpBar, 7) / (pow(cpBar, 7) + pow(25.0, 7)))
        let rt = -rc * sin(2 * deltaTheta * .pi / 180)
        let x = dL / sl, y = dC / sc, z = dH / sh
        return sqrt(max(0, x * x + y * y + z * z + rt * y * z))
    }
}
