import XCTest
import AppKit
import Metal
import MetalKit
import QuartzCore
@testable import LumoKit

/// Opt-in Release capture for the Step 0 sibling overlay. It measures the real transparent
/// drawable path with synthetic geometry; it is intentionally not a durable-mask or render test.
@MainActor
final class MaskOverlayPerformanceBenchmark: XCTestCase {
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var didRun = false

        func run(_ action: () -> Void) {
            lock.lock()
            guard !didRun else { lock.unlock(); return }
            didRun = true
            lock.unlock()
            action()
        }
    }

    func testRealMaskOverlayPresentationBenchmark() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["LUMO_MASK_OVERLAY_BENCHMARK"] != nil,
            "set LUMO_MASK_OVERLAY_BENCHMARK=1 on a logged-in macOS display to run the hardware benchmark"
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal is unavailable")
        }

        let view = MaskOverlayMTKView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), device: device)
        let renderer = MaskOverlayRenderer()
        view.delegate = renderer
        view.configure(
            snapshot: MaskOverlayPrototypeSnapshot(),
            sourceSize: CGSize(width: 6000, height: 4000), crop: .neutral,
            navigation: CanvasNavigation(), backingScale: 2
        )
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = view
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); window.close() }
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let iterations = max(10, min(
            Int(ProcessInfo.processInfo.environment["LUMO_MASK_OVERLAY_ITERATIONS"] ?? "30") ?? 30,
            200
        ))
        var presentationLatencies: [Double] = []
        var mainThreadWork: [Double] = []
        for iteration in 0..<iterations {
            let input = CACurrentMediaTime()
            var snapshot = MaskOverlayPrototypeSnapshot()
            snapshot.cursor = CGPoint(
                x: 0.2 + CGFloat(iteration % 50) / 100,
                y: 0.3 + CGFloat(iteration % 30) / 100
            )
            snapshot.inputTime = input
            let updateStart = CACurrentMediaTime()
            renderer.update(
                snapshot: snapshot, sourceSize: CGSize(width: 6000, height: 4000), crop: .neutral,
                navigation: CanvasNavigation(), backingScale: 2
            )
            view.setNeedsDisplay(view.bounds)
            mainThreadWork.append((CACurrentMediaTime() - updateStart) * 1_000)
            let latency = await withCheckedContinuation { continuation in
                let once = Once()
                renderer.onPresented = { _, latency in
                    once.run { continuation.resume(returning: latency) }
                }
            }
            presentationLatencies.append(latency)
        }

        func percentile(_ values: [Double], _ p: Double) -> Double {
            let sorted = values.sorted()
            return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
        }
        let backingWidth = max(Int(view.drawableSize.width), 2560)
        let backingHeight = max(Int(view.drawableSize.height), 1600)
        print(String(format: "MASK_OVERLAY_BENCHMARK source_extent=6000x4000 viewport_points=1280x800 backing_pixels=%dx%d configuration=Release cold_warm=warm overlay_response_p95_ms=%.3f main_thread_work_p95_ms=%.3f iterations=%d architecture=transparent-metal-sibling", backingWidth, backingHeight, percentile(presentationLatencies, 0.95), percentile(mainThreadWork, 0.95), iterations))
    }
}
