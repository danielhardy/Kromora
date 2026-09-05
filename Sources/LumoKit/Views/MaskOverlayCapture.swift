import AppKit
import Metal

/// Standalone hardware-capture host for LUMO-227. It is intentionally separate from the product
/// window so the pointer stream is delivered by AppKit to the same transparent MTKView that the
/// prototype uses, without requiring a source photo or durable mask state.
@MainActor
public final class MaskOverlayCaptureController {
    @MainActor
    private final class Measurements {
        private var inputEvents = 0
        private var presentations: [Double] = []
        private var gpu: [Double] = []

        func input() {
            inputEvents += 1
        }

        func presented(_ latency: Double) {
            presentations.append(latency)
        }

        func completed(input: TimeInterval, at time: TimeInterval) {
            gpu.append(max(0, time - input) * 1_000)
        }

        func result() -> (inputs: Int, presentations: [Double], gpu: [Double]) {
            return (inputEvents, presentations, gpu)
        }
    }

    private let measurements = Measurements()
    private var window: NSWindow?
    private var view: MaskOverlayMTKView?
    private var renderer: MaskOverlayRenderer?
    private var localPointerMonitor: Any?
    private var snapshot = MaskOverlayPrototypeSnapshot()

    public init() {}

    public func start() {
        precondition(
            ProcessInfo.processInfo.environment["LUMO_MASK_OVERLAY_PROTOTYPE"] == "1",
            "LUMO_MASK_OVERLAY_PROTOTYPE=1 is required for the capture host"
        )
        guard let device = MTLCreateSystemDefaultDevice() else {
            fputs("Metal is unavailable\n", stderr)
            NSApp.terminate(nil)
            return
        }

        let captureView = MaskOverlayMTKView(
            frame: CGRect(x: 0, y: 0, width: 1280, height: 800), device: device
        )
        let captureRenderer = MaskOverlayRenderer()
        captureView.delegate = captureRenderer
        captureView.isInteractive = true
        captureView.onPointer = { [weak self] event in
            guard let self else { return nil }
            measurements.input()
            switch event {
            case .moved(let point, let time), .began(let point, let time), .dragged(let point, let time):
                snapshot.cursor = CGPoint(x: point.x / 1280, y: point.y / 800)
                snapshot.inputTime = time
                snapshot.inputSequence &+= 1
                if case .began = event { snapshot.brushStroke = [snapshot.cursor!] }
                if case .dragged = event { snapshot.brushStroke.append(snapshot.cursor!) }
            case .ended(let point):
                if let point { snapshot.cursor = CGPoint(x: point.x / 1280, y: point.y / 800) }
                snapshot.inputTime = nil
            }
            return snapshot
        }
        captureRenderer.onPresented = { [weak self] _, latency in
            Task { @MainActor [weak self] in
                self?.measurements.presented(latency)
            }
        }
        captureRenderer.onGPUCompleted = { [weak self] input, completed in
            Task { @MainActor [weak self] in
                self?.measurements.completed(input: input, at: completed)
            }
        }
        snapshot.brushStroke = [CGPoint(x: 0.2, y: 0.72), CGPoint(x: 0.48, y: 0.56)]
        captureView.configure(
            snapshot: snapshot, sourceSize: CGSize(width: 6000, height: 4000), crop: .neutral,
            navigation: CanvasNavigation(), backingScale: 2
        )

        let captureWindow = NSWindow(
            contentRect: captureView.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        captureWindow.title = "LUMO-227 Mask Overlay Capture"
        captureWindow.contentView = captureView
        captureWindow.isReleasedWhenClosed = false
        captureWindow.acceptsMouseMovedEvents = true
        window = captureWindow
        view = captureView
        renderer = captureRenderer

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        captureWindow.makeKeyAndOrderFront(nil)
        captureWindow.displayIfNeeded()
        captureWindow.makeFirstResponder(captureView)
        localPointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak captureView] event in
            guard let captureView else {
                return event
            }
            switch event.type {
            case .mouseMoved: captureView.mouseMoved(with: event)
            case .leftMouseDown: captureView.mouseDown(with: event)
            case .leftMouseDragged: captureView.mouseDragged(with: event)
            case .leftMouseUp: captureView.mouseUp(with: event)
            default: break
            }
            return event
        }

        let duration = max(
            10,
            min(Double(ProcessInfo.processInfo.environment["LUMO_MASK_OVERLAY_REAL_POINTER_DURATION"] ?? "30") ?? 30, 120)
        )
        print("MASK_OVERLAY_READY title=\(captureWindow.title) duration_seconds=\(duration)")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.finish()
        }
    }

    private func finish() {
        let result = measurements.result()
        let presentation = result.presentations.filter { $0 > 0 }
        let gpu = result.gpu.filter { $0 > 0 }
        guard !presentation.isEmpty else {
            fputs("MASK_OVERLAY_REAL_POINTER input_events=\(result.inputs) presentations=0; move and drag over the capture window\n", stderr)
            NSApp.terminate(nil)
            return
        }

        func percentile(_ values: [Double], _ p: Double) -> Double {
            let sorted = values.sorted()
            return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
        }
        print(String(format: "MASK_OVERLAY_REAL_POINTER source_extent=6000x4000 viewport_points=1280x800 backing_pixels=%dx%d configuration=Release input_events=%d presentations=%d input_to_present_p50_ms=%.3f input_to_present_p95_ms=%.3f input_to_present_p99_ms=%.3f input_to_gpu_p95_ms=%.3f architecture=transparent-metal-sibling", max(Int(view?.drawableSize.width ?? 2560), 2560), max(Int(view?.drawableSize.height ?? 1600), 1600), result.inputs, presentation.count, percentile(presentation, 0.50), percentile(presentation, 0.95), percentile(presentation, 0.99), gpu.isEmpty ? 0.0 : percentile(gpu, 0.95)))
        window?.orderOut(nil)
        window?.close()
        if let localPointerMonitor { NSEvent.removeMonitor(localPointerMonitor) }
        localPointerMonitor = nil
        NSApp.terminate(nil)
    }
}
