import XCTest

@testable import KromoraKit

/// Opt-in, window-independent `RenderEngine` interaction latency for the RGB Light controls on a
/// RAW (KRMA-1182). `RAWHighlightHeadroomBenchmark` times one cold pass per control; this measures
/// what the app does: a first interactive frame, warm-up ticks, then many interactive ticks through
/// one engine, and a settled `.preview` render at a value no tick used. For each file and control it
/// prints first / tick p50 / tick p95 / settled / cached-settled milliseconds and, over the measured
/// ticks only, the decoder output requests, filter constructions, developed-source cache hits and
/// misses, and processing-prefix materializations, so a tick that re-develops the RAW is visible.
/// Exposure (decoder-routed since KRMA-1174) is included as the known-routed reference row. It
/// asserts nothing about wall-clock time. Needs `KROMORA_RAW_FIXTURE_DIR` or `realworldtest/`.
final class RAWHighlightInteractionBenchmark: XCTestCase {
    private let box = CGSize(width: 1024, height: 1024)
    private let warmupTicks = 4
    private let measuredTicks = 40

    private struct Control {
        let name: String
        let light: (Double) -> LightAdjustments
    }

    private let controls: [Control] = [
        Control(name: "highlights", light: { LightAdjustments(highlights: -$0) }),
        Control(name: "shadows", light: { LightAdjustments(shadows: $0) }),
        Control(name: "whites", light: { LightAdjustments(whites: -$0) }),
        Control(name: "blacks", light: { LightAdjustments(blacks: -$0) }),
        Control(name: "contrast", light: { LightAdjustments(contrast: $0) }),
        // Decoder-routed reference (EV, so a smaller travel than the -100...100 sliders).
        Control(name: "exposure*", light: { LightAdjustments(exposure: $0 / 50) }),
    ]

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
    }

    private func measure<Value>(
        _ body: () async -> Value
    ) async -> (value: Value, milliseconds: Double) {
        let clock = ContinuousClock()
        let start = clock.now
        let value = await body()
        let d = clock.now - start
        let elapsedMilliseconds =
            Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        return (value, elapsedMilliseconds)
    }

    private struct Run {
        var first = 0.0
        var tickP50 = 0.0
        var tickP95 = 0.0
        var tickMax = 0.0
        var settled = 0.0
        var settledRevisit = 0.0
        var tickOutputRequests = 0
        var tickConstructions = 0
        var tickDevelopHits = 0
        var tickDevelopMisses = 0
        var tickPrefixMaterializations = 0
        var firstOutputRequests = 0
        var firstConstructions = 0
        var firstDevelopMisses = 0
        var settledOutputRequests = 0
        var settledDevelopMisses = 0
    }

    private func run(_ source: ImageSource, control: Control) async -> Run {
        let engine = RenderEngine()
        func request(_ amount: Double, _ quality: RenderQuality) -> RenderRequest {
            RenderRequest(
                source: source, document: EditDocument(light: control.light(amount)),
                targetSize: box, quality: quality)
        }
        var result = Run()
        let first = await measure { await engine.makeCGImage(request(10, .interactive)) }
        XCTAssertNotNil(first.value, "The first interactive frame must render for \(control.name)")
        result.first = first.milliseconds
        let workFirst = await engine.workStatistics()
        let cacheFirst = await engine.cacheStatistics()
        result.firstOutputRequests = workFirst.rawOutputRequests
        result.firstConstructions = workFirst.rawFilterConstructions
        result.firstDevelopMisses = cacheFirst.developedSource.misses
        // Amounts walk 12...(12 + 2.1 * n) so no two ticks (or tick and settled value) repeat.
        for i in 1...warmupTicks {
            let warmup = await engine.makeCGImage(request(10 + Double(i) * 2.1, .interactive))
            XCTAssertNotNil(warmup, "Warm-up tick \(i) must render for \(control.name)")
        }
        let work0 = await engine.workStatistics()
        let cache0 = await engine.cacheStatistics()
        var samples: [Double] = []
        for i in 1...measuredTicks {
            let amount = 10 + Double(warmupTicks + i) * 2.1
            let tick = await measure { await engine.makeCGImage(request(amount, .interactive)) }
            XCTAssertNotNil(tick.value, "Measured tick \(i) must render for \(control.name)")
            samples.append(tick.milliseconds)
        }
        let work1 = await engine.workStatistics()
        let cache1 = await engine.cacheStatistics()
        result.tickP50 = percentile(samples, 0.5)
        result.tickP95 = percentile(samples, 0.95)
        result.tickMax = samples.max() ?? 0
        result.tickOutputRequests = work1.rawOutputRequests - work0.rawOutputRequests
        result.tickConstructions = work1.rawFilterConstructions - work0.rawFilterConstructions
        result.tickDevelopHits = cache1.developedSource.hits - cache0.developedSource.hits
        result.tickDevelopMisses = cache1.developedSource.misses - cache0.developedSource.misses
        result.tickPrefixMaterializations =
            work1.processingPrefixMaterializations - work0.processingPrefixMaterializations

        // A value no tick rendered, so the settled frame cannot ride on an interactive output.
        let settled = await measure { await engine.makeCGImage(request(97.3, .preview)) }
        XCTAssertNotNil(settled.value, "The settled frame must render for \(control.name)")
        result.settled = settled.milliseconds
        let work2 = await engine.workStatistics()
        let cache2 = await engine.cacheStatistics()
        result.settledOutputRequests = work2.rawOutputRequests - work1.rawOutputRequests
        result.settledDevelopMisses = cache2.developedSource.misses - cache1.developedSource.misses
        let settledRevisit = await measure {
            await engine.makeCGImage(request(97.3, .preview))
        }
        XCTAssertNotNil(
            settledRevisit.value, "The settled frame revisit must render for \(control.name)")
        result.settledRevisit = settledRevisit.milliseconds
        return result
    }

    func testPrintInteractionLatency() async throws {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAWs; see Fixtures.localRAWURLs") }
        for url in urls {
            let source = ImageSource(url: url, nativeExtent: CGSize(width: 6000, height: 4000))
            for control in controls {
                let r = await run(source, control: control)
                print(
                    "RAW-HIGHLIGHT-INTERACTION",
                    url.lastPathComponent, control.name.padding(toLength: 10, withPad: " ", startingAt: 0),
                    String(
                        format:
                            "first=%.0fms tick p50=%.1fms p95=%.1fms max=%.1fms settled=%.0fms (cached %.0fms)",
                        r.first, r.tickP50, r.tickP95, r.tickMax, r.settled, r.settledRevisit),
                    "first: rawOutputs=\(r.firstOutputRequests) filters=\(r.firstConstructions) developedSource misses=\(r.firstDevelopMisses)",
                    "ticks[n=\(measuredTicks)]: rawOutputs=\(r.tickOutputRequests) filters=\(r.tickConstructions) developedSource hit/miss=\(r.tickDevelopHits)/\(r.tickDevelopMisses) prefixMaterializations=\(r.tickPrefixMaterializations)",
                    "settled: rawOutputs=\(r.settledOutputRequests) developedSource misses=\(r.settledDevelopMisses)")
            }
        }
    }
}
