import Darwin
import XCTest

@testable import KromoraKit

/// Opt-in, window-independent `RenderEngine` cost of routing global Exposure through the decoder
/// (KRMA-1174), against the RGB exposure path it replaces for RAW. Prints first/settled/tick
/// p50/p95, cache counters and footprint per local RAW; it asserts nothing about wall-clock time.
final class RAWExposureRoutingBenchmark: XCTestCase {
    private let box = CGSize(width: 1024, height: 1024)
    private let ticks = 24

    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))]
    }

    private func milliseconds(_ body: () async -> Void) async -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        await body()
        let d = clock.now - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    private struct Run {
        var first = 0.0
        var tickP50 = 0.0
        var tickP95 = 0.0
        var settled = 0.0
    var settledRevisit = 0.0
        var peakMB = 0.0
        var constructions = 0
        var outputRequests = 0
        var developMisses = 0
        var developHits = 0
        var prefixMaterializations = 0
    }

    private func run(_ source: ImageSource, routed: Bool) async -> Run {
        let engine = RenderEngine()
        func document(_ ev: Double) -> EditDocument {
            routed
                ? EditDocument(light: LightAdjustments(exposure: ev))
                : EditDocument(adjustments: [.exposure(ev: ev)])
        }
        func request(_ ev: Double, _ quality: RenderQuality) -> RenderRequest {
            RenderRequest(source: source, document: document(ev), targetSize: box, quality: quality)
        }
        var result = Run()
        result.first = await milliseconds { _ = await engine.makeCGImage(request(0.1, .interactive)) }
        var samples: [Double] = []
        for i in 1...ticks {
            let ev = 0.1 + Double(i) * 0.08
            samples.append(await milliseconds { _ = await engine.makeCGImage(request(ev, .interactive)) })
            result.peakMB = max(result.peakMB, footprintMB())
        }
        result.tickP50 = percentile(samples, 0.5)
        result.tickP95 = percentile(samples, 0.95)
        // A value no tick rendered, so the settled frame cannot ride on an interactive output.
        result.settled = await milliseconds {
            _ = await engine.makeCGImage(request(1.37, .preview))
        }
        result.settledRevisit = await milliseconds {
            _ = await engine.makeCGImage(request(1.37, .preview))
        }
        result.peakMB = max(result.peakMB, footprintMB())
        let work = await engine.workStatistics()
        let caches = await engine.cacheStatistics()
        result.constructions = work.rawFilterConstructions
        result.outputRequests = work.rawOutputRequests
        result.developMisses = caches.developedSource.misses
        result.developHits = caches.developedSource.hits
        result.prefixMaterializations = work.processingPrefixMaterializations
        return result
    }

    /// KRMA-1180: routing now reads the file's decoder family before the first exposure frame, from a
    /// throwaway filter when no interactive session exists yet (cached per file afterwards). This
    /// prints what that read costs on its own.
    func testPrintDecoderFamilyReadCost() async throws {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAWs; see Fixtures.localRAWURLs") }
        for url in urls {
            let source = ImageSource(url: url, nativeExtent: CGSize(width: 6000, height: 4000))
            var samples: [Double] = []
            var family = 0.0
            for _ in 0..<5 {
                samples.append(await milliseconds {
                    let state = RenderPipeline.rawFilter(for: source.backing)
                        .map(RenderEngine.InteractiveRAWFilterSession.captureCapabilities)
                    family = RAWExposureRouting.stopsPerSliderStop(decoder: state)
                })
            }
            print(
                "RAW-EXPOSURE-BENCH family-read", url.lastPathComponent, "ratio=\(family)",
                String(format: "p50=%.1fms max=%.1fms", percentile(samples, 0.5), samples.max() ?? 0))
        }
    }

    func testPrintInteractiveCostComparison() async throws {
        let urls = Fixtures.localRAWURLs
        guard !urls.isEmpty else { throw XCTSkip("no local RAWs; see Fixtures.localRAWURLs") }
        for url in urls {
            let source = ImageSource(url: url, nativeExtent: CGSize(width: 6000, height: 4000))
            for routed in [false, true] {
                let r = await run(source, routed: routed)
                print(
                    "RAW-EXPOSURE-BENCH",
                    url.lastPathComponent, routed ? "decoder" : "rgb    ",
                    String(format: "first=%.0fms tick p50=%.1fms p95=%.1fms settled=%.0fms (cached %.0fms) footprint=%.0fMB", r.first, r.tickP50, r.tickP95, r.settled, r.settledRevisit, r.peakMB),
                    "filters=\(r.constructions) rawOutputs=\(r.outputRequests) developedSource hit/miss=\(r.developHits)/\(r.developMisses) prefixMaterializations=\(r.prefixMaterializations)")
            }
        }
    }
}
