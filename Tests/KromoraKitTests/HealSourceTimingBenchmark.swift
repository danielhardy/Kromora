import CoreGraphics
import XCTest

@testable import KromoraKit

/// KRMA-1094: opt-in, window-independent measurement of what automatic Heal source resolution costs
/// a real RAW. A photo with source-less Heal spots used to repeat the whole picker search on every
/// histogram, preview and thumbnail build; `RenderEngine` now caches the resolved set. This reports
/// the cold cost (what every build paid before the cache), the warm cost, and a spot-free baseline
/// for the same photo, without a machine-specific threshold.
///
/// Run with `KROMORA_HEAL_TIMING=1 KROMORA_RAW_FIXTURE_DIR=<folder with one ARW>`. The photo is read
/// in place; the test writes nothing next to it.
final class HealSourceTimingBenchmark: XCTestCase {
    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// Two spots at the default centre and two close together, like the photo that prompted the ticket.
    private func healDocument() -> EditDocument {
        func spot(_ x: Double, _ y: Double) -> RetouchSpot {
            RetouchSpot(
                mode: .heal,
                region: RetouchRegion(samples: [BrushSample(point: CGPoint(x: x, y: y))], radius: 0.01))
        }
        var document = EditDocument()
        document.retouch = RetouchSettings(spots: [
            spot(0.5, 0.5), spot(0.5, 0.5), spot(0.569, 0.336), spot(0.558, 0.355),
        ])
        return document
    }

    func testAutomaticHealSourceCostOnARealRAW() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["KROMORA_HEAL_TIMING"] != nil, "opt-in benchmark")
        let url = try XCTUnwrap(
            Fixtures.localRAWURLs.first, "set KROMORA_RAW_FIXTURE_DIR to a folder holding one RAW")
        let source = ImageSource(url: url, nativeExtent: .zero)
        let scale = RenderScale.preview(maxSize: CGSize(width: 1_600, height: 1_600))
        let plain = EditDocument()
        let heal = healDocument()
        let clock = ContinuousClock()

        func histogramTime(_ engine: RenderEngine, _ document: EditDocument) async throws -> Double {
            var result: HistogramData?
            let elapsed = await clock.measure {
                result = await engine.histogram(
                    source: source, document: document, lut: nil, scale: scale, space: .sRGB)
            }
            XCTAssertNotNil(result, "the engine could not produce a histogram")
            return milliseconds(elapsed)
        }

        // Baseline: same photo, no spots, fresh engine (decode session included).
        let baselineEngine = RenderEngine(maskResolver: DefaultLocalMaskResolver())
        let baselineCold = try await histogramTime(baselineEngine, plain)
        let baselineWarm = try await histogramTime(baselineEngine, plain)

        // Heal: the first build pays the search; later builds reuse it.
        let engine = RenderEngine(maskResolver: DefaultLocalMaskResolver())
        let healCold = try await histogramTime(engine, heal)
        let picks = await engine.retouchPickCount
        var warm: [Double] = []
        for _ in 0..<5 { warm.append(try await histogramTime(engine, heal)) }
        let picksAfter = await engine.retouchPickCount

        // Pre-cache behavior: every build starts with no remembered picks, which a fresh engine
        // reproduces. Reusing one decode session isn't possible across engines, so this also pays
        // decode; subtract the baseline cold time for the search itself.
        var uncached: [Double] = []
        for _ in 0..<3 {
            uncached.append(try await histogramTime(RenderEngine(maskResolver: DefaultLocalMaskResolver()), heal))
        }

        let spotPick = await { () -> Double in
            let probe = RenderEngine(maskResolver: DefaultLocalMaskResolver())
            _ = await probe.histogram(source: source, document: plain, lut: nil, scale: scale, space: .sRGB)
            var picked: RetouchSource?
            let elapsed = await clock.measure {
                picked = await probe.pickRetouchSource(
                    source: source, settings: heal.retouch, spotID: heal.retouch.spots[2].id, rank: 0)
            }
            XCTAssertNotNil(picked)
            return milliseconds(elapsed)
        }()

        // The crop render inside a pick: a neutral full-resolution develop of a region around the
        // spot and a few candidates. The rest of a pick is the 1024 px proxy, the CPU scan and the refine.
        let cropMS = await { () -> Double in
            let probe = RenderEngine(maskResolver: DefaultLocalMaskResolver())
            _ = await probe.histogram(source: source, document: plain, lut: nil, scale: scale, space: .sRGB)
            let resolved = await probe.sourceWithResolvedExtent(source)
            let extent = resolved.nativeExtent
            let bounds = CGRect(x: extent.width * 0.5, y: extent.height * 0.5, width: 900, height: 900)
            var region: RetouchAnalysisRegion?
            let elapsed = await clock.measure { region = await probe.retouchAnalysisCrop(source: resolved, bounds: bounds) }
            XCTAssertNotNil(region)
            return milliseconds(elapsed)
        }()

        func fmt(_ values: [Double]) -> String { values.map { String(format: "%.0f", $0) }.joined(separator: ", ") }
        print("""

            === KRMA-1094 automatic Heal source timing: \(url.lastPathComponent) ===
            no spots   histogram cold \(String(format: "%.0f", baselineCold)) ms, warm \(String(format: "%.0f", baselineWarm)) ms
            4 spots    histogram cold \(String(format: "%.0f", healCold)) ms (\(picks) picks)
            4 spots    histogram warm [\(fmt(warm))] ms (picks after: \(picksAfter))
            4 spots    fresh engine each time [\(fmt(uncached))] ms
            one pickRetouchSource on a warm decode session: \(String(format: "%.0f", spotPick)) ms
            of which one crop render (neutral full-res develop of ~900 px): \(String(format: "%.0f", cropMS)) ms
            """)
        XCTAssertEqual(picksAfter, picks, "warm builds must not re-run the picker")
    }
}
