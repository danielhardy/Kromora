import CoreGraphics
import XCTest
@testable import KromoraKit

final class RetouchEnginePerformanceTests: TempDirectoryTestCase {
    func testRecordEngineRemoveTimings() async throws {
        guard ProcessInfo.processInfo.environment["KROMORA_RUN_RETOUCH_ENGINE_BENCHMARK"] == "1" else {
            throw XCTSkip("Set KROMORA_RUN_RETOUCH_ENGINE_BENCHMARK=1 to run the full-resolution Remove timing capture")
        }
        let url = try Fixtures.writeClarityPNG(width: 3_200, height: 900, named: "retouch-engine-timing.png", in: tempDirectory)
        let source = ImageSource(url: url, nativeExtent: CGSize(width: 3_200, height: 900))
        let dust = RetouchSpot(mode: .remove,
                               region: RetouchRegion(samples: [BrushSample(point: CGPoint(x: 0.5, y: 0.5))], radius: 30.0 / 900), seed: 658)
        let engine = RenderEngine()
        func render(_ spot: RetouchSpot) async throws {
            let image = await engine.makeCGImage(RenderRequest(
                source: source, document: EditDocument(retouch: RetouchSettings(spots: [spot])), quality: .fullResolution
            ))
            _ = try XCTUnwrap(image)
        }
        let t0 = ProcessInfo.processInfo.systemUptime
        try await render(dust)
        let dustMiss = (ProcessInfo.processInfo.systemUptime - t0) * 1_000
        let t1 = ProcessInfo.processInfo.systemUptime
        try await render(dust)
        let dustHit = (ProcessInfo.processInfo.systemUptime - t1) * 1_000

        let wire = RetouchSpot(mode: .remove,
                               region: RetouchRegion(samples: [
                                BrushSample(point: CGPoint(x: 0.03, y: 0.5)),
                                BrushSample(point: CGPoint(x: 0.97, y: 0.5))
                               ], radius: 6.0 / 900), seed: 658)
        let t2 = ProcessInfo.processInfo.systemUptime
        try await render(wire)
        let wireMiss = (ProcessInfo.processInfo.systemUptime - t2) * 1_000
        let solverTimes = await engine.retouchSolveDurationsMilliseconds
        print("REMOVE_ENGINE_TIMING setup=Apple-M4-Pro-12-core dust_miss_ms=\(dustMiss) dust_solver_ms=\(solverTimes.first ?? -1) dust_hit_ms=\(dustHit) wire3000_miss_ms=\(wireMiss) wire_solver_ms=\(solverTimes.last ?? -1)")
    }
}
