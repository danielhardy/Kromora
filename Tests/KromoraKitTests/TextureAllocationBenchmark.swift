import CoreImage
import Metal
import XCTest
@testable import KromoraKit

/// KRMA-1029: window-independent measurement of per-render processing-texture allocation, the
/// cost a texture pool would remove. No `NSWindow`; opt-in through `scripts/ci-tests.sh optional`.
@MainActor
final class TextureAllocationBenchmark: XCTestCase {
    func testProcessingTextureAllocationCostAtSliderDragRates() throws {
        try XCTSkipUnless(MTLCreateSystemDefaultDevice() != nil, "Metal is unavailable on this host")
        let resources = RenderEngineResources(configuration: RenderCacheConfiguration())
        let sizes: [(String, Int, Int, MTLPixelFormat)] = [
            ("interactive 1600x1067 rgba8", 1600, 1067, .rgba8Unorm),
            ("preview 2560x1707 rgba16f", 2560, 1707, .rgba16Float),
            ("preview 3840x2560 rgba16f", 3840, 2560, .rgba16Float),
        ]
        let iterations = 200
        for (name, width, height, format) in sizes {
            var samples: [Double] = []
            for _ in 0..<iterations {
                let start = ContinuousClock.now
                let texture = resources.makeProcessingTexture(
                    width: width, height: height, pixelFormat: format)
                let elapsed = ContinuousClock.now - start
                XCTAssertNotNil(texture)
                samples.append(Double(elapsed.components.attoseconds) / 1e15
                    + Double(elapsed.components.seconds) * 1e3)
            }
            samples.sort()
            let median = samples[samples.count / 2]
            let p95 = samples[Int(Double(samples.count) * 0.95)]
            print("TextureAllocationBenchmark \(name): median \(median) ms, p95 \(p95) ms")
            // A 60 Hz slider-drag frame is 16.7 ms; allocation must stay a small fraction.
            XCTAssertLessThan(median, 4.0, name)
        }
    }
}
