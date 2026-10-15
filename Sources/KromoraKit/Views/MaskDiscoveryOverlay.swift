import Combine
import MetalKit
import SwiftUI

/// Replaceable, presentation-only surface. The existing preview renderer stays paused and owns
/// the photograph; this independently scheduled transparent layer owns only the optical effect.
struct MaskDiscoveryOverlay: View {
    let state: MaskDiscoveryState
    let loadPixels: @Sendable (RegionMaskReference) async -> NormalizedMask?
    let mapping: GeometryPointMapping
    let navigation: CanvasNavigation
    let backingScale: CGFloat
    let reduceMotion: Bool
    @State private var raster: MaskDiscoveryRaster?
    @State private var rasterRequestID: UUID?

    var body: some View {
        GeometryReader { geometry in
            let placement = MaskDiscoveryGeometry(
                mapping: mapping, navigation: navigation, viewportSize: geometry.size,
                backingScale: backingScale)
            DiscoveryMetalSurface(
                state: state, geometry: placement, reduceMotion: reduceMotion,
                raster: rasterRequestID == state.request?.id ? raster : nil)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .overlay(alignment: .bottomLeading) {
                    if let request = state.request {
                        Text(label(for: request))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(16)
                            .allowsHitTesting(false)
                            .accessibilityLabel(label(for: request))
                    }
                }
        }
        .task(id: state.request) {
            guard let request = state.request else {
                raster = nil
                rasterRequestID = nil
                return
            }
            switch request.phase {
            case .waiting:
                raster = nil
                rasterRequestID = nil
            case .resolved(let reference):
                // A store read only: no provider call, graph evaluation, or preview request.
                guard let pixels = await loadPixels(reference), !Task.isCancelled else {
                    if !Task.isCancelled { state.finish(request.id) }
                    return
                }
                let result = try? await Self.prepareRaster(pixels)
                guard !Task.isCancelled else { return }
                raster = result
                rasterRequestID = request.id
                // This is presentation time only. The durable mask has already been committed.
                try? await Task.sleep(for: .seconds(MaskDiscoveryTiming.revealDuration))
                if !Task.isCancelled { state.finish(request.id) }
            case .ending:
                try? await Task.sleep(for: .seconds(MaskDiscoveryTiming.dismissalDuration))
                if !Task.isCancelled { state.finish(request.id) }
            }
        }
        .onDisappear { state.reset() }
    }

    @concurrent private static func prepareRaster(_ pixels: NormalizedMask) async throws -> MaskDiscoveryRaster {
        try MaskDiscoveryRaster.make(from: pixels)
    }

    private func label(for request: MaskDiscoveryState.Request) -> String {
        switch request.phase {
        case .waiting: "Discovering \(request.title.lowercased())…"
        case .resolved: "\(request.title) mask ready"
        case .ending: "Discovery ended"
        }
    }
}

private struct DiscoveryMetalSurface: NSViewRepresentable {
    let state: MaskDiscoveryState
    let geometry: MaskDiscoveryGeometry?
    let reduceMotion: Bool
    let raster: MaskDiscoveryRaster?

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> MTKView {
        let view = DiscoveryMTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.layer?.isOpaque = false
        view.autoResizeDrawable = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.update(geometry: geometry, reduceMotion: reduceMotion, raster: raster)
    }

    static func dismantleNSView(_ view: MTKView, coordinator: Coordinator) {
        coordinator.stop()
        view.delegate = nil
    }

    /// All GPU resources and scheduling belong here, never to the analysis actor or preview
    /// renderer. The fixed cap bounds fragment work even on a large Retina display.
    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        let device = RenderEngine.presentationDevice
        private let state: MaskDiscoveryState
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var emptyTexture: MTLTexture?
        private var maskTexture: MTLTexture?
        private weak var view: MTKView?
        private var timer: Timer?
        private var activityObservers: [NSObjectProtocol] = []
        private var geometry: MaskDiscoveryGeometry?
        private var reduceMotion = false
        private var requestID: UUID?
        private var revealStartedAt: TimeInterval?
        private var isDrawing = false

        init(state: MaskDiscoveryState) {
            self.state = state
            super.init()
            // Prewarm when the canvas mounts, before the first intelligent-mask request.
            queue = device.makeCommandQueue(maxCommandBufferCount: 1)
            queue?.label = "Mask discovery presentation"
            if let url = KromoraKitResourceBundle.presentationMetallibURL(),
               let library = try? device.makeLibrary(URL: url),
               let vertex = library.makeFunction(name: "mask_discovery_vertex"),
               let fragment = library.makeFunction(name: "mask_discovery_fragment") {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = vertex
                descriptor.fragmentFunction = fragment
                let attachment = descriptor.colorAttachments[0]!
                attachment.pixelFormat = .bgra8Unorm
                attachment.isBlendingEnabled = true
                attachment.sourceRGBBlendFactor = .one
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
            }
            emptyTexture = texture(width: 1, height: 1, bytes: [0])
        }

        func attach(_ view: DiscoveryMTKView) {
            self.view = view
            view.onVisibilityChange = { [weak self] in self?.refreshActivity() }
            for name in [NSApplication.didBecomeActiveNotification,
                         NSApplication.didResignActiveNotification,
                         NSWindow.didChangeOcclusionStateNotification,
                         Notification.Name.NSProcessInfoPowerStateDidChange,
                         ProcessInfo.thermalStateDidChangeNotification] {
                let observer = NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.refreshActivity() }
                }
                activityObservers.append(observer)
            }
        }

        func update(geometry: MaskDiscoveryGeometry?, reduceMotion: Bool, raster: MaskDiscoveryRaster?) {
            self.geometry = geometry
            self.reduceMotion = reduceMotion
            if requestID != state.request?.id {
                requestID = state.request?.id
                maskTexture = nil
                revealStartedAt = nil
            }
            if maskTexture == nil, let raster {
                maskTexture = texture(width: raster.size.width, height: raster.size.height, bytes: raster.bytes)
                revealStartedAt = ProcessInfo.processInfo.systemUptime
            }
            refreshActivity()
            view?.setNeedsDisplay(view?.bounds ?? .zero)
        }

        private func refreshActivity() {
            timer?.invalidate()
            timer = nil
            guard state.request != nil, !reduceMotion, pipeline != nil,
                  let view, let window = view.window, !view.isHiddenOrHasHiddenAncestor,
                  window.occlusionState.contains(.visible), NSApplication.shared.isActive else { return }
            let process = ProcessInfo.processInfo
            let constrained = process.isLowPowerModeEnabled || process.thermalState == .serious
                || process.thermalState == .critical
            let interval = 1.0 / (constrained ? 12.0 : 24.0)
            let timer = Timer(timeInterval: interval, target: self,
                              selector: #selector(requestFrame), userInfo: nil, repeats: true)
            timer.tolerance = interval * 0.15
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        @objc private func requestFrame() {
            guard !isDrawing, let view else { return }
            view.setNeedsDisplay(view.bounds)
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            for observer in activityObservers { NotificationCenter.default.removeObserver(observer) }
            activityObservers.removeAll()
            (view as? DiscoveryMTKView)?.onVisibilityChange = nil
            view = nil
            maskTexture = nil
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard !isDrawing, view.bounds.width > 0, view.bounds.height > 0,
                  let queue, let command = queue.makeCommandBuffer(),
                  let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
                  let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
            if let request = state.request, let geometry, let pipeline,
               let texture = maskTexture ?? emptyTexture {
                let now = ProcessInfo.processInfo.systemUptime
                let elapsed = now - request.startedAt
                let reveal = revealStartedAt.map { MaskDiscoveryTiming.revealProgress(elapsed: now - $0) } ?? 0
                var opacity: Float = 1
                if case .ending(let end) = request.phase {
                    opacity = Float(max(0, 1 - (now - end) / MaskDiscoveryTiming.dismissalDuration))
                }
                let size = view.bounds.size
                let rect = geometry.imageRect
                let crop = geometry.cropRect
                var uniforms = MaskDiscoveryUniforms(
                    imageRect: SIMD4(Float(rect.minX / size.width), Float(rect.minY / size.height),
                                     Float(rect.width / size.width), Float(rect.height / size.height)),
                    cropRect: SIMD4(Float(crop.minX), Float(crop.minY), Float(crop.width), Float(crop.height)),
                    sourceX: geometry.sourceX, sourceY: geometry.sourceY, sourceW: geometry.sourceW,
                    timing: SIMD4(Float(elapsed),
                                  reduceMotion ? 0.65 : MaskDiscoveryTiming.waitingOpacity(elapsed: elapsed),
                                  reveal, reduceMotion ? 1 : 0),
                    display: SIMD4(Float(size.width / size.height), opacity, maskTexture == nil ? 0 : 1, 0))
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MaskDiscoveryUniforms>.stride, index: 0)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            }
            encoder.endEncoding()
            isDrawing = true
            command.present(drawable)
            command.addCompletedHandler { [weak self] _ in
                Task { @MainActor in self?.isDrawing = false }
            }
            command.commit()
        }

        private func texture(width: Int, height: Int, bytes: [UInt8]) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .shared
            descriptor.usage = .shaderRead
            guard let result = device.makeTexture(descriptor: descriptor) else { return nil }
            bytes.withUnsafeBytes { buffer in
                if let address = buffer.baseAddress {
                    result.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                                   withBytes: address, bytesPerRow: width)
                }
            }
            return result
        }
    }
}

/// Pointer input continues to reach the existing canvas. Drawable resolution is independent of
/// backing scale: this soft optical overlay needs at most 960 pixels on its longest edge.
private final class DiscoveryMTKView: MTKView {
    var onVisibilityChange: (() -> Void)?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        let scale = min(1, 960 / max(bounds.width, bounds.height, 1))
        drawableSize = CGSize(width: max(1, (bounds.width * scale).rounded()),
                              height: max(1, (bounds.height * scale).rounded()))
        setNeedsDisplay(bounds)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onVisibilityChange?()
    }

    override func viewDidHide() {
        super.viewDidHide()
        onVisibilityChange?()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        onVisibilityChange?()
    }
}
