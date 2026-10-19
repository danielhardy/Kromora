import CoreImage
import CoreGraphics
import XCTest

@testable import KromoraKit

/// KRMA-1061: camera-scale diagnostics for the supported small-defect Heal/Clone lane. Real Core
/// Image evaluation, so this class belongs to the serial lane. It reports, per generated case, the
/// manual (known-clean) source against automatic sources chosen at declared proxy scales, and the
/// quality metrics for each, so the first failing boundary is visible. Generated-fixture results
/// only: not camera-image sign-off (KRMA-1063).
final class RetouchCameraScaleDiagnosticsTests: XCTestCase {
    private typealias Fixture = RetouchCameraScaleFixtures.Case

    /// Proxy scales: 1.0 is a native-resolution proxy (isolates ranking from resolution); 0.57 is the
    /// production 1024 px proxy of this 1800 px crop used as a whole frame; 0.17 is the same crop as a
    /// 1:1 region of a 6000 px frame, which the production proxy reduces by 1024 / 6000.
    private static let proxyScales: [Double] = [1.0, 0.57, 0.17]

    private struct Outcome {
        let label: String
        /// `nil` when the picker produced no candidate, so the spot renders with no source.
        let offset: CGPoint?
        let sourceTouchesDefect: Bool
        let metrics: RetouchQualityMetrics.Metrics
        let failed: [String]
    }

    // MARK: Fixture sanity

    func testCameraScaleFixturesAreRepeatable() {
        // Three representative cases keep generation cost bounded; the report test asserts that every
        // manual source is defect-free for all sixteen.
        for (background, defect) in [("sky", "hair"), ("edge", "long hair"), ("foliage", "soft dust")] {
            let first = RetouchCameraScaleFixtures.make(background: background, defect: defect)
            let second = RetouchCameraScaleFixtures.make(background: background, defect: defect)
            XCTAssertEqual(first.clean, second.clean)
            XCTAssertEqual(first.damaged, second.damaged)
            XCTAssertEqual(first.mask, second.mask)
            XCTAssertNotEqual(first.clean, first.damaged, "\(first.name) must contain a defect")
            XCTAssertTrue(first.mask.contains(true))
        }
    }

    // MARK: Diagnostic report

    /// Prints one row per case and mode, then summary counts. Asserts only the harness invariants
    /// and no-regression floors on the manual rows; automatic-source targets are reported, and
    /// KRMA-1062 turns the corrected ones into enforced acceptance.
    func testCameraScaleReportCompareManualAndAutomaticSources() throws {
        var rows: [(Fixture, Outcome)] = []
        var oracle: [String] = []
        print("\nRETOUCH CAMERA-SCALE DIAGNOSTICS — \(RetouchCameraScaleFixtures.width)×\(RetouchCameraScaleFixtures.height) crops")
        print("CASE | MODE | OFFSET px (dx,dy) | SRC TOUCHES DEFECT | ΔE2000 | GRADIENT | VAR | LUMA | RESULT")
        for background in RetouchCameraScaleFixtures.backgrounds {
            for defect in RetouchCameraScaleFixtures.defects {
                let fixture = RetouchCameraScaleFixtures.make(background: background, defect: defect)
                let input = CIImage(cgImage: Self.image(fixture.damaged, width: fixture.width, height: fixture.height))
                var outcomes: [Outcome] = []
                outcomes.append(try render(fixture, input, label: "Manual Heal", mode: .heal,
                                           pixelOffset: fixture.manualPixelOffset))
                outcomes.append(try render(fixture, input, label: "Manual Clone", mode: .clone,
                                           pixelOffset: fixture.manualPixelOffset))
                for scale in Self.proxyScales {
                    let proxy = Self.proxy(of: fixture, scale: scale)
                    let spot = Self.spot(for: fixture)
                    // Production snaps the proxy pick to whole source pixels before refinement.
                    let coarse = RetouchSourcePicker.snapped(
                        RetouchSourcePicker.candidates(for: spot, among: [spot], in: proxy, limit: 24),
                        sourceWidth: fixture.width, sourceHeight: fixture.height)
                    guard let top = coarse.first else {
                        // No candidate: the spot keeps no source and the defect is left in place.
                        let labels = scale < 1
                            ? ["coarse", "coarse snapped", "refined (shipped origin)"]
                            : ["coarse"]
                        for label in labels {
                            outcomes.append(try render(fixture, input, label: "Auto s=\(scale) \(label)",
                                                       mode: .heal, pixelOffset: nil))
                        }
                        continue
                    }
                    outcomes.append(try render(fixture, input, label: "Auto s=\(scale) coarse", mode: .heal,
                                               pixelOffset: Self.pixels(top.offset, fixture)))
                    guard scale < 1 else { continue }
                    // Same coarse winner with its offset rounded to whole source pixels.
                    let snapped = CGPoint(x: Self.pixels(top.offset, fixture).x.rounded(),
                                          y: Self.pixels(top.offset, fixture).y.rounded())
                    outcomes.append(try render(fixture, input, label: "Auto s=\(scale) coarse snapped",
                                               mode: .heal, pixelOffset: snapped))
                    for (name, topDown) in [("shipped origin", true)] {
                        let refined = Self.refine(coarse, fixture: fixture, spot: spot, topDownOrigin: topDown)
                        guard let best = refined.first else { continue }
                        outcomes.append(try render(fixture, input, label: "Auto s=\(scale) refined (\(name))",
                                                   mode: .heal, pixelOffset: Self.pixels(best.offset, fixture)))
                        if scale == 0.57 && !topDown && defect != "long hair" {
                            let sweep = try refined.map {
                                try render(fixture, input, label: "rank", mode: .heal,
                                           pixelOffset: Self.pixels($0.offset, fixture))
                            }
                            let firstPass = sweep.firstIndex { $0.failed.isEmpty }
                            let clean = sweep.filter { !$0.sourceTouchesDefect }.count
                            oracle.append("\(fixture.name): ranked candidates \(sweep.count), defect-free sources \(clean), passing \(sweep.filter { $0.failed.isEmpty }.count), first passing rank \(firstPass.map(String.init) ?? "none")")
                        }
                    }
                }
                for outcome in outcomes {
                    let offsetText = outcome.offset.map { String(format: "(%.1f,%.1f)", $0.x, $0.y) } ?? "none (no candidate)"
                    print(String(format: "%@ | %@ | %@ | %@ | %.2f | %.2f | %.2f | %+.4f | %@",
                        fixture.name, outcome.label, offsetText,
                        outcome.sourceTouchesDefect ? "YES" : "no",
                        outcome.metrics.deltaE2000, outcome.metrics.gradientError,
                        outcome.metrics.varianceRatio, outcome.metrics.luminanceShift,
                        outcome.failed.isEmpty ? "PASS" : "FAIL: " + outcome.failed.joined(separator: ",")))
                    rows.append((fixture, outcome))
                }
            }
        }
        print("CANDIDATE SWEEP (production-shaped list at s=0.57, Heal):")
        oracle.forEach { print("  \($0)") }
        for defect in RetouchCameraScaleFixtures.defects {
            let subset = rows.filter { $0.0.defect == defect }
            for label in Set(subset.map(\.1.label)).sorted() {
                let matching = subset.filter { $0.1.label == label }
                print("CAMERA \(defect) \(label): \(matching.filter { $0.1.failed.isEmpty }.count)/\(matching.count) pass")
            }
        }
        for label in Set(rows.map(\.1.label)).sorted() {
            let matching = rows.filter { $0.1.label == label }
            print("CAMERA TOTAL \(label): \(matching.filter { $0.1.failed.isEmpty }.count)/\(matching.count) pass")
        }
        // KRMA-1062 acceptance: the shipped automatic path (whole-pixel coarse pick, then top-down
        // full-resolution refinement) repairs every supported case at both declared proxy scales.
        for (fixture, outcome) in rows where outcome.label.hasPrefix("Auto s=0.") && outcome.label.hasSuffix("(shipped origin)") {
            XCTAssertTrue(outcome.failed.isEmpty, "\(fixture.name) \(outcome.label): \(outcome.failed.joined(separator: ","))")
            XCTAssertFalse(outcome.sourceTouchesDefect, "\(fixture.name) \(outcome.label)")
        }

        let perCase = Set(rows.map(\.1.label)).count
        XCTAssertEqual(rows.count, RetouchCameraScaleFixtures.backgrounds.count
            * RetouchCameraScaleFixtures.defects.count * perCase, "every case must report every mode")
        for (fixture, outcome) in rows where outcome.label.hasPrefix("Manual") {
            XCTAssertFalse(outcome.sourceTouchesDefect, "\(fixture.name) \(outcome.label)")
        }
        for (mode, floor) in Self.manualFloors {
            let passes = rows.filter { $0.1.label == mode && $0.1.failed.isEmpty }.count
            XCTAssertGreaterThanOrEqual(passes, floor, "\(mode) fell below its recorded floor")
        }
    }

    /// Recorded no-regression floors, out of 16 generated cases (raise, never lower).
    /// The two `shipped origin` rows record the production path (coarse proxy pick plus full-resolution
    /// refinement) at each declared scale.
    private static let manualFloors: [String: Int] = [
        "Manual Heal": 13, "Manual Clone": 14,
        "Auto s=0.57 refined (shipped origin)": 16, "Auto s=0.17 refined (shipped origin)": 16,
    ]

    // MARK: Helpers

    private static func spot(for fixture: Fixture) -> RetouchSpot {
        RetouchSpot(mode: .heal, region: RetouchRegion(
            samples: fixture.stroke.map { BrushSample(point: $0) }, radius: fixture.radius))
    }

    private static func pixels(_ offset: CGVector, _ fixture: Fixture) -> CGPoint {
        CGPoint(x: offset.dx * CGFloat(fixture.width), y: -offset.dy * CGFloat(fixture.height))
    }

    private func render(
        _ fixture: Fixture, _ input: CIImage, label: String, mode: RetouchMode, pixelOffset: CGPoint?
    ) throws -> Outcome {
        var spot = Self.spot(for: fixture)
        spot.mode = mode
        spot.source = pixelOffset.map {
            .manual(offset: CGVector(dx: $0.x / CGFloat(fixture.width), dy: -$0.y / CGFloat(fixture.height)))
        }
        let rendered = RetouchRenderer.apply(
            RetouchSettings(spots: [spot]), to: input,
            sourceSize: CGSize(width: fixture.width, height: fixture.height), maskRenderer: LocalMaskRenderer())
        let window = fixture.window
        let ciWindow = CGRect(x: window.minX, y: CGFloat(fixture.height) - window.maxY,
                              width: window.width, height: window.height)
        let output = try Pixels.bytes(of: rendered.cropped(to: ciWindow))
        let metrics = RetouchQualityMetrics.measure(
            clean: Self.slice(fixture.clean, fixture: fixture, window: window), output: output,
            mask: Self.sliceMask(fixture.mask, fixture: fixture, window: window),
            width: Int(window.width), height: Int(window.height))
        return Outcome(label: label, offset: pixelOffset,
                       sourceTouchesDefect: pixelOffset.map { sourceTouchesDefect(fixture, offset: $0) } ?? false,
                       metrics: metrics, failed: metrics.failures(against: RetouchQualityMetrics.limits[fixture.limitKey]!))
    }

    /// True when any defect pixel falls inside the translated brush (including its outward feather),
    /// i.e. the fill would be sampled from the defect itself.
    private func sourceTouchesDefect(_ fixture: Fixture, offset: CGPoint) -> Bool {
        let stroke = fixture.stroke.map { CGPoint(x: $0.x * CGFloat(fixture.width), y: $0.y * CGFloat(fixture.height)) }
        let reach = fixture.radiusPixels * 1.35
        func distance(_ p: CGPoint) -> Double {
            if stroke.count == 1 { return hypot(Double(p.x - stroke[0].x), Double(p.y - stroke[0].y)) }
            return zip(stroke, stroke.dropFirst()).map { a, b in
                let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
                let length = dx * dx + dy * dy
                let t = min(max((Double(p.x - a.x) * dx + Double(p.y - a.y) * dy) / length, 0), 1)
                return hypot(Double(p.x - a.x) - t * dx, Double(p.y - a.y) - t * dy)
            }.min() ?? .infinity
        }
        let window = fixture.window.insetBy(dx: -Double(abs(offset.x)), dy: -Double(abs(offset.y)))
            .intersection(CGRect(x: 0, y: 0, width: fixture.width, height: fixture.height))
        for y in Int(window.minY)..<Int(window.maxY) { for x in Int(window.minX)..<Int(window.maxX)
            where fixture.mask[y * fixture.width + x] {
            if distance(CGPoint(x: CGFloat(x) - offset.x, y: CGFloat(y) - offset.y)) <= reach { return true }
        }}
        return false
    }

    private static func slice(_ bytes: [UInt8], fixture: Fixture, window: CGRect) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(Int(window.width * window.height) * 4)
        for y in Int(window.minY)..<Int(window.maxY) {
            let start = (y * fixture.width + Int(window.minX)) * 4
            out.append(contentsOf: bytes[start..<start + Int(window.width) * 4])
        }
        return out
    }

    private static func sliceMask(_ mask: [Bool], fixture: Fixture, window: CGRect) -> [Bool] {
        var out: [Bool] = []
        for y in Int(window.minY)..<Int(window.maxY) {
            let start = y * fixture.width + Int(window.minX)
            out.append(contentsOf: mask[start..<start + Int(window.width)])
        }
        return out
    }

    private static func image(_ bytes: [UInt8], width: Int, height: Int) -> CGImage {
        CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Lab proxy of the damaged crop reduced by `scale`, as `RenderEngine.retouchProxy` would build it.
    private static func proxy(of fixture: Fixture, scale: Double) -> RetouchAnalysisProxy {
        let width = max(1, Int((Double(fixture.width) * scale).rounded()))
        let height = max(1, Int((Double(fixture.height) * scale).rounded()))
        guard scale < 1 else {
            return .fromRGBA8(Data(fixture.damaged), width: width, height: height)
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .high
            context.draw(image(fixture.damaged, width: fixture.width, height: fixture.height),
                         in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return .fromRGBA8(Data(bytes), width: width, height: height)
    }

    /// Mirrors `RenderEngine.pickRetouchSource`'s full-resolution refinement: the crop is chosen in
    /// Core Image (y-up) coordinates by `analysisCropBounds`, rendered top row first, and wrapped in a
    /// `RetouchAnalysisRegion`. `topDownOrigin` selects the y origin: the shipped code (KRMA-1062)
    /// passes the top-down row index of the crop's first row.
    private static func refine(
        _ coarse: [RetouchSourceCandidate], fixture: Fixture, spot: RetouchSpot, topDownOrigin: Bool
    ) -> [RetouchSourceCandidate] {
        let width = CGFloat(fixture.width), height = CGFloat(fixture.height)
        let radius = CGFloat(spot.region.radius) * min(width, height)
        let limit = Double(radius * 8)
        let near = coarse.filter { hypot(Double($0.offset.dx * width), Double($0.offset.dy * height)) <= limit }
        let points = spot.region.samples.map { CGPoint(x: $0.point.x * width, y: (1 - $0.point.y) * height) }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return coarse }
        let destination = CGRect(x: minX - radius, y: minY - radius,
                                 width: maxX - minX + radius * 2, height: maxY - minY + radius * 2)
        var bounds = destination
        for candidate in near.prefix(4) {
            bounds = bounds.union(destination.offsetBy(dx: candidate.offset.dx * width, dy: candidate.offset.dy * height))
        }
        let padding = max(4, radius * 0.5)
        let crop = bounds.insetBy(dx: -padding, dy: -padding)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        guard !crop.isNull, crop.width > 0, crop.height > 0 else { return coarse }
        let top = fixture.height - Int(crop.maxY)
        var bytes: [UInt8] = []
        for row in top..<top + Int(crop.height) {
            let start = (row * fixture.width + Int(crop.minX)) * 4
            bytes.append(contentsOf: fixture.damaged[start..<start + Int(crop.width) * 4])
        }
        let region = RetouchAnalysisRegion(
            sourceWidth: fixture.width, sourceHeight: fixture.height,
            originX: Int(crop.minX), originY: topDownOrigin ? top : Int(crop.minY),
            proxy: .fromRGBA8(Data(bytes), width: Int(crop.width), height: Int(crop.height)))
        return RetouchSourcePicker.refining(coarse, for: spot, among: [spot], in: region)
    }
}

// MARK: Existing 96 × 72 hair rows

extension RetouchCameraScaleDiagnosticsTests {
    /// Per-row trace of the generated 96 × 72 hair/fibre rows, where manual Heal repairs some
    /// backgrounds but automatic Heal repairs none: automatic versus manual source, whether either
    /// source overlaps the hair, and a sweep of every ranked candidate through the same renderer.
    func testSmallFixtureHairRowsTraceAutomaticVersusManualSource() throws {
        print("\nRETOUCH 96×72 HAIR TRACE")
        print("BACKGROUND | SOURCE | OFFSET px | TOUCHES HAIR | ΔE2000 | GRADIENT | VAR | LUMA | RESULT")
        for background in RetouchQualityFixtures.backgrounds {
            let fixture = RetouchQualityFixtures.make(background: background, defect: "hair/fibre")
            let clean = try Pixels.bytes(of: CIImage(cgImage: fixture.clean))
            let damaged = try Pixels.bytes(of: CIImage(cgImage: fixture.damaged))
            let input = CIImage(cgImage: fixture.damaged)
            let samples = fixture.stroke.map { BrushSample(point: $0) }
            let w = fixture.width, h = fixture.height
            let pixelStroke = fixture.stroke.map { CGPoint(x: $0.x * CGFloat(w), y: $0.y * CGFloat(h)) }
            let brush = fixture.radius * Double(min(w, h))
            func touches(_ offset: CGVector) -> Bool {
                let dx = offset.dx * CGFloat(w), dy = -offset.dy * CGFloat(h)
                for index in fixture.mask.indices where fixture.mask[index] {
                    let q = CGPoint(x: CGFloat(index % w) - dx, y: CGFloat(index / w) - dy)
                    let d = zip(pixelStroke, pixelStroke.dropFirst()).map { a, b -> Double in
                        let ex = Double(b.x - a.x), ey = Double(b.y - a.y)
                        let t = min(max((Double(q.x - a.x) * ex + Double(q.y - a.y) * ey) / (ex * ex + ey * ey), 0), 1)
                        return hypot(Double(q.x - a.x) - t * ex, Double(q.y - a.y) - t * ey)
                    }.min()!
                    if d <= brush * 1.35 { return true }
                }
                return false
            }
            func grade(_ offset: CGVector) throws -> (RetouchQualityMetrics.Metrics, [String]) {
                let spot = RetouchSpot(mode: .heal, region: RetouchRegion(samples: samples, radius: fixture.radius),
                                       source: .manual(offset: offset))
                let rendered = RetouchRenderer.apply(
                    RetouchSettings(spots: [spot]), to: input, sourceSize: CGSize(width: w, height: h),
                    maskRenderer: LocalMaskRenderer())
                let metrics = RetouchQualityMetrics.measure(
                    clean: clean, output: try Pixels.bytes(of: rendered), mask: fixture.mask, width: w, height: h)
                return (metrics, metrics.failures(against: RetouchQualityMetrics.limits[background]!))
            }
            func report(_ label: String, _ offset: CGVector) throws -> Bool {
                let (m, failed) = try grade(offset)
                print(String(format: "%@ | %@ | (%.1f,%.1f) | %@ | %.2f | %.2f | %.2f | %+.4f | %@", background, label,
                    offset.dx * CGFloat(w), -offset.dy * CGFloat(h), touches(offset) ? "YES" : "no",
                    m.deltaE2000, m.gradientError, m.varianceRatio, m.luminanceShift,
                    failed.isEmpty ? "PASS" : "FAIL: " + failed.joined(separator: ",")))
                return failed.isEmpty
            }
            _ = try report("manual", fixture.sourceOffset)
            let proxy = RetouchAnalysisProxy.fromRGBA8(Data(damaged), width: w, height: h)
            let spot = RetouchSpot(mode: .heal, region: RetouchRegion(samples: samples, radius: fixture.radius))
            let ranked = RetouchSourcePicker.candidates(for: spot, among: [spot], in: proxy)
            if let top = ranked.first { _ = try report("auto rank 0", top.offset) }
            var passing: [Int] = []
            var clean_ = 0
            for (rank, candidate) in ranked.enumerated() {
                if !touches(candidate.offset) { clean_ += 1 }
                let (_, failed) = try grade(candidate.offset)
                if failed.isEmpty { passing.append(rank) }
            }
            print("\(background) | picker sweep: \(ranked.count) candidates, \(clean_) defect-free, passing ranks \(passing)")
            // Oracle: every defect-free whole-pixel placement (6 px grid) whose translated brush stays
            // inside the frame, rendered through the same Heal path, to show repairable sources exist.
            var placements = 0, repairing = 0
            for dy in stride(from: -(h - 1), to: h, by: 6) { for dx in stride(from: -(w - 1), to: w, by: 6) {
                let margin = brush * 1.35 + 2
                let moved = pixelStroke.map { CGPoint(x: $0.x + CGFloat(dx), y: $0.y + CGFloat(dy)) }
                guard moved.allSatisfy({ $0.x >= margin && $0.x < CGFloat(w) - margin
                    && $0.y >= margin && $0.y < CGFloat(h) - margin }) else { continue }
                let offset = CGVector(dx: CGFloat(dx) / CGFloat(w), dy: -CGFloat(dy) / CGFloat(h))
                guard !touches(offset) else { continue }
                placements += 1
                if try grade(offset).1.isEmpty { repairing += 1 }
            }}
            print("\(background) | geometry-aware oracle: \(placements) defect-free in-frame placements, \(repairing) pass all limits")
        }
    }
}
