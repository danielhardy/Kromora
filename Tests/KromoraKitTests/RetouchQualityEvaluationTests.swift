import CoreImage
import CoreGraphics
import XCTest

@testable import KromoraKit

/// Deterministic, image-quality oracle for the small-defect retouch lane. This is deliberately
/// separate from renderer timing tests; it compares rendered pixels with known clean references.
/// Fixtures are authored in sRGB and the floors were calibrated on sRGB-encoded bytes, so the
/// comparison pins `space: .sRGB` rather than following `WorkingSpace.current`.
final class RetouchQualityEvaluationTests: TempDirectoryTestCase {
    /// Defect families the v1 product supports. Wires and broad removal (the 60 px dust case) are
    /// stress-corpus rows only; they are reported but never gate shipping.
    private static let shippingClasses: [String: [String]] = [
        "dust/speck": ["soft dust 5px", "hard speck"],
        "hair/fibre": ["hair/fibre"],
    ]

    /// Minimum passing rows (of `backgrounds × defects in the class`) per shipping class and mode.
    /// Initialised at the KRMA-1003 passing counts and raised by KRMA-1004 (dust/speck 5/5/5 → 10/11/10,
    /// hair/fibre Heal and Clone 1 → 2) and KRMA-1062 (automatic hair/fibre Heal 0 → 3). Raise a floor when a repair improves it; never lower one.
    private static let shippingFloors: [String: [String: Int]] = [
        "dust/speck": ["Heal": 10, "Heal (auto)": 11, "Clone": 10],
        "hair/fibre": ["Heal": 2, "Heal (auto)": 3, "Clone": 2],
    ]

    private static let shippingModes = ["Heal", "Heal (auto)", "Clone"]

    private struct Row {
        let background: String, defect: String, label: String
        let metrics: RetouchQualityMetrics.Metrics
        let failed: [String]
    }

    /// Runs the whole synthetic corpus once and returns every mode row.
    private func evaluateCorpus() throws -> [Row] {
        var table: [Row] = []

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
                    ("Heal", .heal), ("Heal (auto)", .heal), ("Clone", .clone),
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
                        output = try Pixels.bytes(of: rendered, space: .sRGB)
                    } else { continue }
                    let values = RetouchQualityMetrics.measure(clean: clean, output: output, mask: fixture.mask, width: fixture.width, height: fixture.height)
                    let failed = values.failures(against: RetouchQualityMetrics.limits[background]!)
                    table.append(Row(background: background, defect: defect, label: label,
                                     metrics: values, failed: failed))
                }
            }
        }

        return table
    }

    /// Stress report: prints every row and the corpus-wide pass counts. It asserts only that the
    /// corpus ran completely; it never requires a family to fail, so a real improvement stays green.
    func testStressCorpusReportsCurrentHealAndCloneResults() throws {
        let table = try evaluateCorpus()
        let header = "BACKGROUND / DEFECT | MODE | ΔE2000 | GRADIENT | VAR RATIO | LUMA SHIFT | RESULT"
        print("\nRETOUCH STRESS CORPUS — limits: ΔE / gradient RGB levels / variance ratio / abs luma shift\n\(header)")
        for row in table {
            let result = row.failed.isEmpty ? "PASS" : "FAIL: " + row.failed.joined(separator: ",")
            print(String(format: "%@ / %@ | %@ | %.2f | %.2f | %.2f | %+.4f | %@",
                row.background, row.defect, row.label, row.metrics.deltaE2000, row.metrics.gradientError,
                row.metrics.varianceRatio, row.metrics.luminanceShift, result))
        }
        let perMode = RetouchQualityFixtures.backgrounds.count * RetouchQualityFixtures.defects.count
        for label in ["Heal", "Heal (auto)", "Clone", "Current"] {
            let passes = table.filter { $0.label == label && $0.failed.isEmpty }.count
            print("STRESS \(label) rows passing: \(passes)/\(perMode)")
        }
        XCTAssertEqual(table.count, perMode * 4)
    }

    /// Shipping gate: supported classes must not drop below their floors. Synthetic fixtures only;
    /// passing is not camera-scale sign-off (see KRMA-1016).
    func testShippingGateHoldsSupportedClassFloors() throws {
        let table = try evaluateCorpus()
        XCTAssertEqual(Set(Self.shippingFloors.keys), Set(Self.shippingClasses.keys),
            "every supported shipping class must define floors")
        for (name, defects) in Self.shippingClasses.sorted(by: { $0.key < $1.key }) {
            XCTAssertTrue(defects.allSatisfy(RetouchQualityFixtures.defects.contains),
                "shipping class \(name) must name corpus defects")
            let floors = Self.shippingFloors[name, default: [:]]
            XCTAssertEqual(Set(floors.keys), Set(Self.shippingModes),
                "shipping class \(name) must define a floor for every shipping mode")
            let total = RetouchQualityFixtures.backgrounds.count * defects.count
            for (label, floor) in floors.sorted(by: { $0.key < $1.key }) {
                let passes = table.filter {
                    $0.label == label && defects.contains($0.defect) && $0.failed.isEmpty
                }.count
                print("SHIPPING \(name) \(label): \(passes)/\(total) (floor \(floor))")
                XCTAssertGreaterThanOrEqual(passes, floor,
                    "shipping class \(name) / \(label) fell below its floor")
            }
        }
    }

    func testSyntheticFixtureGenerationIsRepeatable() throws {
        let first = RetouchQualityFixtures.make(background: "cloud", defect: "wire straight")
        let second = RetouchQualityFixtures.make(background: "cloud", defect: "wire straight")
        XCTAssertEqual(try Pixels.bytes(of: first.clean), try Pixels.bytes(of: second.clean))
        XCTAssertEqual(try Pixels.bytes(of: first.damaged), try Pixels.bytes(of: second.damaged))
        XCTAssertEqual(first.mask, second.mask)
    }

    func testHandBuiltTextureSynthesisCanRepairStraightWireOnEveryBackground() throws {
        for background in RetouchQualityFixtures.backgrounds {
            let fixture = RetouchQualityFixtures.make(background: background, defect: "wire straight")
            let clean = try Pixels.bytes(of: fixture.clean)
            var output = try Pixels.bytes(of: fixture.damaged)
            let w = fixture.width, h = fixture.height
            func synthesizedGrain(_ x: Int, _ y: Int) -> Double {
                var n = UInt32(truncatingIfNeeded: x &* 1_103_515_245 &+ y &* 12_345) ^ 9191
                n = (n ^ (n >> 16)) &* 0x7feb352d
                n = (n ^ (n >> 15)) &* 0x846ca68b
                n ^= n >> 16
                return Double(n & 0xffff) / 65535 - 0.5
            }
            for index in fixture.mask.indices where fixture.mask[index] {
                let x = index % w, y = index / w
                var estimate = [Double](repeating: 0, count: 3)
                var weightSum = 0.0
                // Inverse-square interpolation from a 2–5 px neighborhood, excluding the defect.
                for dy in -5...5 { for dx in -5...5 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < w, ny >= 0, ny < h,
                          !fixture.mask[ny * w + nx], dx * dx + dy * dy >= 4,
                          dx * dx + dy * dy <= 25 else { continue }
                    let weight = 1.0 / Double(dx * dx + dy * dy)
                    for c in 0..<3 { estimate[c] += Double(output[(ny * w + nx) * 4 + c]) * weight }
                    weightSum += weight
                }}
                guard weightSum > 0 else { continue }
                for c in 0..<3 {
                    // Recreate grain statistically with an independent deterministic seed.
                    let value = estimate[c] / weightSum + synthesizedGrain(x, y) * 0.055 * 255
                    output[index * 4 + c] = UInt8(min(max(value.rounded(), 0), 255))
                }
            }
            let metrics = RetouchQualityMetrics.measure(clean: clean, output: output, mask: fixture.mask, width: fixture.width, height: fixture.height)
            XCTAssertTrue(metrics.failures(against: RetouchQualityMetrics.limits[background]!).isEmpty,
                "hand-built interpolation and texture synthesis should pass for \(background)")
        }
    }

    /// KRMA-1077: a manual source brighter than the destination ring used to be corrected with an
    /// additive offset, which pushed the source's own shadow structure below black and left a dark
    /// blob inside the repair. The tone match must scale, not subtract.
    func testHealFromBrighterSourceDoesNotClipShadowStructureToBlack() throws {
        let width = 400, height = 300
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            // Mid-dark destination ring; bright source area on the right with a dark stripe that is
            // as dark as the destination, which an additive correction drives to zero.
            var value: UInt8 = 64
            if x >= 230 { value = 180 }
            if (258...266).contains(x), (96...140).contains(y) { value = 64 }
            let o = (y * width + x) * 4
            rgba[o] = value; rgba[o + 1] = value; rgba[o + 2] = value; rgba[o + 3] = 255
        }}
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        let cgImage = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let spot = RetouchSpot(
            mode: .heal,
            region: RetouchRegion(samples: [BrushSample(point: CGPoint(x: 100.0 / 400, y: 118.0 / 300))],
                                  radius: 30.0 / 300),
            source: .manual(offset: CGVector(dx: 160.0 / 400, dy: 0))
        )
        let rendered = RetouchRenderer.apply(
            RetouchSettings(spots: [spot]), to: CIImage(cgImage: cgImage),
            sourceSize: CGSize(width: width, height: height), maskRenderer: LocalMaskRenderer()
        )
        let output = try Pixels.bytes(of: rendered, space: .sRGB)
        var darkest = 255
        for y in 96...140 { for x in 98...106 {
            darkest = min(darkest, Int(output[(y * width + x) * 4]))
        }}
        XCTAssertGreaterThanOrEqual(darkest, 12, "healed shadow structure must not clip to black")
    }

}
