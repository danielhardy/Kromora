import AppKit
import MetalKit
import SwiftUI
import simd

/// Tools deliberately limited to synthetic geometry for the Step 0 prototype. They are not a
/// durable mask model and must not be added to EditDocument.
enum MaskOverlayPrototypeTool: String, CaseIterable, Sendable {
    case brush
    case linear
    case radial
}

struct MaskOverlayPrototypeSnapshot: Equatable, Sendable {
    var tool: MaskOverlayPrototypeTool = .brush
    var cursor: CGPoint?
    var brushStroke: [CGPoint] = []
    var linearStart = CGPoint(x: 0.2, y: 0.5)
    var linearEnd = CGPoint(x: 0.8, y: 0.5)
    var radialCenter = CGPoint(x: 0.68, y: 0.54)
    var radialRadius = CGSize(width: 0.18, height: 0.24)
    var inputTime: TimeInterval?
    var inputSequence: UInt64 = 0
}

/// Narrow observation boundary for pointer-frequency overlay state. The snapshot contains only
/// normalized presentation geometry; it never publishes through AppViewModel and never triggers a
/// render or persistence operation.
@MainActor
final class MaskOverlayInteractionState: ObservableObject {
    @Published private(set) var snapshot = MaskOverlayPrototypeSnapshot()
    @Published private(set) var isActive = false

    func activate() {
        isActive = true
        resetDemoGeometry()
    }

    func deactivate() {
        isActive = false
        snapshot.cursor = nil
        snapshot.brushStroke.removeAll(keepingCapacity: true)
        snapshot.inputTime = nil
    }

    func selectTool(_ tool: MaskOverlayPrototypeTool) {
        snapshot.tool = tool
        snapshot.brushStroke.removeAll(keepingCapacity: true)
    }

    func pointerMoved(to sourcePoint: CGPoint, time: TimeInterval = LiveEditTelemetryClock.now) {
        guard isActive, sourcePoint.x.isFinite, sourcePoint.y.isFinite else { return }
        snapshot.inputSequence &+= 1
        snapshot.cursor = sourcePoint
        snapshot.inputTime = time
    }

    func beginPointer(at sourcePoint: CGPoint, time: TimeInterval = LiveEditTelemetryClock.now) {
        guard isActive else { return }
        pointerMoved(to: sourcePoint, time: time)
        switch snapshot.tool {
        case .brush:
            snapshot.brushStroke = [sourcePoint]
        case .linear:
            snapshot.linearStart = sourcePoint
            snapshot.linearEnd = sourcePoint
        case .radial:
            snapshot.radialCenter = sourcePoint
            snapshot.radialRadius = .zero
        }
    }

    func dragPointer(to sourcePoint: CGPoint, time: TimeInterval = LiveEditTelemetryClock.now) {
        guard isActive else { return }
        pointerMoved(to: sourcePoint, time: time)
        switch snapshot.tool {
        case .brush:
            snapshot.brushStroke.append(sourcePoint)
        case .linear:
            snapshot.linearEnd = sourcePoint
        case .radial:
            let dx = abs(sourcePoint.x - snapshot.radialCenter.x)
            let dy = abs(sourcePoint.y - snapshot.radialCenter.y)
            snapshot.radialRadius = CGSize(width: dx, height: dy)
        }
    }

    func endPointer(at sourcePoint: CGPoint? = nil) {
        if let sourcePoint { dragPointer(to: sourcePoint) }
        snapshot.inputTime = nil
    }

    func resetDemoGeometry() {
        snapshot = MaskOverlayPrototypeSnapshot()
        snapshot.brushStroke = [
            CGPoint(x: 0.20, y: 0.72), CGPoint(x: 0.28, y: 0.65),
            CGPoint(x: 0.38, y: 0.68), CGPoint(x: 0.48, y: 0.56)
        ]
    }
}

/// A transparent Metal sibling of PreviewSurfaceView. It shares the presentation device and queue
/// but has its own drawable lifecycle, so pointer-frequency redraws never mutate the persistent
/// preview surface or introduce a second CIContext.
struct MaskOverlaySurfaceView: NSViewRepresentable {
    let snapshot: MaskOverlayPrototypeSnapshot
    let sourceSize: CGSize
    let crop: CropAdjustments
    let navigation: CanvasNavigation
    let backingScale: CGFloat
    let isInteractive: Bool
    let onPointer: ((MaskOverlayPointerEvent) -> MaskOverlayPrototypeSnapshot?)?

    func makeNSView(context: Context) -> MaskOverlayMTKView {
        let view = MaskOverlayMTKView(frame: .zero, device: RenderEngine.presentationDevice)
        view.delegate = context.coordinator
        view.onPointer = onPointer
        view.isInteractive = isInteractive
        view.configure(
            snapshot: snapshot, sourceSize: sourceSize, crop: crop,
            navigation: navigation, backingScale: backingScale
        )
        return view
    }

    func updateNSView(_ view: MaskOverlayMTKView, context: Context) {
        context.coordinator.update(
            snapshot: snapshot, sourceSize: sourceSize, crop: crop,
            navigation: navigation, backingScale: backingScale
        )
        view.onPointer = onPointer
        view.isInteractive = isInteractive
        view.setNeedsDisplay(view.bounds)
    }

    func makeCoordinator() -> MaskOverlayRenderer { MaskOverlayRenderer() }
}

enum MaskOverlayPointerEvent: Sendable {
    case moved(CGPoint, TimeInterval)
    case began(CGPoint, TimeInterval)
    case dragged(CGPoint, TimeInterval)
    case ended(CGPoint?)
}

final class MaskOverlayMTKView: MTKView {
    var onPointer: ((MaskOverlayPointerEvent) -> MaskOverlayPrototypeSnapshot?)?
    var isInteractive = false { didSet { updateTrackingAreas() } }
    private var tracking: NSTrackingArea?

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    func configure(
        snapshot: MaskOverlayPrototypeSnapshot, sourceSize: CGSize, crop: CropAdjustments,
        navigation: CanvasNavigation, backingScale: CGFloat
    ) {
        enableSetNeedsDisplay = true
        isPaused = true
        framebufferOnly = true
        autoResizeDrawable = true
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        (delegate as? MaskOverlayRenderer)?.update(
            snapshot: snapshot, sourceSize: sourceSize, crop: crop,
            navigation: navigation, backingScale: backingScale
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isInteractive ? self : nil
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        guard isInteractive else { return }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        send(.moved(localPoint(event), LiveEditTelemetryClock.now))
    }

    override func mouseDown(with event: NSEvent) {
        send(.began(localPoint(event), LiveEditTelemetryClock.now))
    }

    override func mouseDragged(with event: NSEvent) {
        send(.dragged(localPoint(event), LiveEditTelemetryClock.now))
    }

    override func mouseUp(with event: NSEvent) {
        send(.ended(localPoint(event)))
    }

    private func localPoint(_ event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func send(_ event: MaskOverlayPointerEvent) {
        guard isInteractive else { return }
        if let snapshot = onPointer?(event), let renderer = delegate as? MaskOverlayRenderer {
            LumoObservability.event(
                .maskOverlayPointerInput,
                detail: "surface=maskOverlay input_sequence=\(snapshot.inputSequence)"
            )
            renderer.update(snapshot: snapshot)
        }
        // Keep the draw asynchronous so drawable acquisition never blocks the main actor. The
        // renderer's one-in-flight pacer redraws the newest snapshot after completion.
        setNeedsDisplay(bounds)
    }
}

@MainActor
final class MaskOverlayRenderer: NSObject, MTKViewDelegate {
    private struct Vertex {
        var position: SIMD2<Float>
        var color: SIMD4<Float>
    }

    private var snapshot = MaskOverlayPrototypeSnapshot()
    private var pipeline: MTLRenderPipelineState?
    private let queue = RenderEngine.presentationQueue
    private let device = RenderEngine.presentationDevice
    private weak var view: MTKView?
    var onPresented: (@Sendable (TimeInterval, Double) -> Void)?
    var onGPUCompleted: (@Sendable (TimeInterval, TimeInterval) -> Void)?
    private var isDrawing = false

    override init() {
        super.init()
        let library: MTLLibrary?
        if let url = Bundle.module.url(forResource: "MaskOverlay", withExtension: "metal"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            library = try? device.makeLibrary(source: source, options: nil)
        } else {
            library = device.makeDefaultLibrary()
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library?.makeFunction(name: "mask_overlay_vertex")
        descriptor.fragmentFunction = library?.makeFunction(name: "mask_overlay_fragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    func update(
        snapshot: MaskOverlayPrototypeSnapshot, sourceSize: CGSize, crop: CropAdjustments,
        navigation: CanvasNavigation, backingScale: CGFloat
    ) {
        self.snapshot = snapshot
        // MTKView.drawableSize is the authoritative viewport. The SwiftUI point size is supplied
        // at draw time, so this is refreshed in draw(in:) after the drawable is acquired.
        pendingGeometry = (sourceSize, crop, navigation, backingScale)
    }

    func update(snapshot: MaskOverlayPrototypeSnapshot) {
        self.snapshot = snapshot
    }

    private var pendingGeometry: (CGSize, CropAdjustments, CanvasNavigation, CGFloat)?

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        view.setNeedsDisplay(view.bounds)
    }

    func draw(in view: MTKView) {
        self.view = view
        guard !isDrawing else { return }
        guard let drawable = view.currentDrawable,
              let commandBuffer = queue.makeCommandBuffer(),
              let pipeline,
              let pendingGeometry,
              let renderPass = view.currentRenderPassDescriptor else { return }

        let sourceSize = pendingGeometry.0
        let crop = pendingGeometry.1
        let navigation = pendingGeometry.2
        let scale = pendingGeometry.3
        let viewportPoints = CGSize(width: view.bounds.width, height: view.bounds.height)
        let transform = CanvasMaskTransform(
            sourceSize: sourceSize, crop: crop, navigation: navigation,
            viewportSize: viewportPoints, backingScale: scale
        )

        let vertices = makeVertices(snapshot: snapshot, transform: transform,
                                    drawableSize: view.drawableSize)
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        guard !vertices.isEmpty else {
            commandBuffer.commit()
            return
        }
        isDrawing = true
        let buffer = vertices.withUnsafeBytes { data in
            device.makeBuffer(bytes: data.baseAddress!, length: data.count, options: .storageModeShared)
        }
        guard let buffer else { return }
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
        encoder?.setRenderPipelineState(pipeline)
        encoder?.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder?.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: vertices.count)
        encoder?.endEncoding()
        commandBuffer.present(drawable)
        let presentationHandler = onPresented
        let inputTime = snapshot.inputTime
        let inputSequence = snapshot.inputSequence
        LumoObservability.event(
            .maskOverlayPresentationEncoded,
            detail: "surface=maskOverlay input_sequence=\(inputSequence)"
        )
        drawable.addPresentedHandler { drawable in
            let presented = drawable.presentedTime > 0 ? drawable.presentedTime : CACurrentMediaTime()
            let latency = inputTime.map { max(0.0, presented - $0) * 1_000 } ?? 0.0
            LumoObservability.event(
                .maskOverlayDrawablePresented,
                detail: "surface=maskOverlay input_sequence=\(inputSequence) latency_ms=\(String(format: "%.3f", Double(latency)))"
            )
            guard let inputTime else {
                presentationHandler?(presented, 0)
                return
            }
            presentationHandler?(presented, max(0, presented - inputTime) * 1_000)
        }
        commandBuffer.addCompletedHandler { [weak self, weak view] _ in
            let completed = CACurrentMediaTime()
            LumoObservability.event(
                .maskOverlayGPUComplete,
                detail: "surface=maskOverlay input_sequence=\(inputSequence) gpu_ms=\(String(format: "%.3f", Double(inputTime.map { max(0.0, completed - $0) * 1_000 } ?? 0.0)))"
            )
            Task { @MainActor in
                if let inputTime {
                    self?.onGPUCompleted?(inputTime, completed)
                }
                self?.isDrawing = false
                view?.setNeedsDisplay(view?.bounds ?? .zero)
            }
        }
        commandBuffer.commit()
    }

    private func makeVertices(
        snapshot: MaskOverlayPrototypeSnapshot, transform: CanvasMaskTransform,
        drawableSize: CGSize
    ) -> [Vertex] {
        guard drawableSize.width > 0, drawableSize.height > 0 else { return [] }
        let orange = SIMD4<Float>(1, 0.58, 0.08, 0.95)
        let cyan = SIMD4<Float>(0.12, 0.9, 1, 0.95)
        var result: [Vertex] = []

        func appendLine(_ points: [CGPoint], color: SIMD4<Float>) {
            for point in points {
                guard let viewportPoint = transform.viewportPoint(forSourceNormalized: point) else { continue }
                result.append(Vertex(
                    position: SIMD2(
                        Float(viewportPoint.x * transform.backingScale / drawableSize.width),
                        Float(viewportPoint.y * transform.backingScale / drawableSize.height)
                    ), color: color
                ))
            }
        }

        appendLine(snapshot.brushStroke, color: orange)

        // The linear prototype uses the three familiar guide bars: the two transition edges and
        // the center bar. They are synthetic guides only; no gradient alpha is evaluated here.
        let linearDX = snapshot.linearEnd.x - snapshot.linearStart.x
        let linearDY = snapshot.linearEnd.y - snapshot.linearStart.y
        let linearLength = max(sqrt(linearDX * linearDX + linearDY * linearDY), 0.000_001)
        let perpendicular = CGPoint(x: -linearDY / linearLength * 0.035,
                                    y: linearDX / linearLength * 0.035)
        appendLine([
            CGPoint(x: snapshot.linearStart.x + perpendicular.x,
                    y: snapshot.linearStart.y + perpendicular.y),
            CGPoint(x: snapshot.linearEnd.x + perpendicular.x,
                    y: snapshot.linearEnd.y + perpendicular.y)
        ], color: cyan)
        appendLine([snapshot.linearStart, snapshot.linearEnd], color: cyan)
        appendLine([
            CGPoint(x: snapshot.linearStart.x - perpendicular.x,
                    y: snapshot.linearStart.y - perpendicular.y),
            CGPoint(x: snapshot.linearEnd.x - perpendicular.x,
                    y: snapshot.linearEnd.y - perpendicular.y)
        ], color: cyan)

        let center = snapshot.radialCenter
        let radius = snapshot.radialRadius
        if radius.width > 0, radius.height > 0 {
            let ellipse = (0...32).map { step -> CGPoint in
                let angle = CGFloat(step) / 32 * 2 * .pi
                return CGPoint(
                    x: center.x + cos(angle) * radius.width,
                    y: center.y + sin(angle) * radius.height
                )
            }
            appendLine(ellipse, color: cyan)
            appendLine([
                CGPoint(x: center.x - 0.02, y: center.y),
                CGPoint(x: center.x + 0.02, y: center.y)
            ], color: cyan)
            appendLine([
                CGPoint(x: center.x, y: center.y - 0.02),
                CGPoint(x: center.x, y: center.y + 0.02)
            ], color: cyan)
        } else {
            appendLine([center, CGPoint(x: center.x + 0.001, y: center.y)], color: cyan)
        }

        if let cursor = snapshot.cursor {
            let displayedShortSide = min(
                transform.sourceSize.width * transform.cropRect.width,
                transform.sourceSize.height * transform.cropRect.height
            )
            let cursorRadius = max(
                10 * transform.backingScale
                    / max(transform.canvasTransform.scale * displayedShortSide, 1),
                0.002
            )
            let circle = (0...24).map { step -> CGPoint in
                let angle = CGFloat(step) / 24 * 2 * .pi
                return CGPoint(x: cursor.x + cos(angle) * cursorRadius,
                               y: cursor.y + sin(angle) * cursorRadius)
            }
            appendLine(circle, color: orange)
        }
        return result
    }
}
