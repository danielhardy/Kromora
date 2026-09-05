import AppKit
import SwiftUI

/// Native AppKit input surface for mask painting. SwiftUI remains responsible for the guides, but
/// pointer delivery is owned by an NSView so mouse/tablet pressure and coalesced direct-touch
/// samples arrive without a gesture-recognizer hop or broad view invalidation.
enum MaskNativePointerEvent: Sendable {
    case moved([MaskNativePointerSample])
    case began([MaskNativePointerSample])
    case dragged([MaskNativePointerSample])
    case ended(MaskNativePointerSample?)
}

struct MaskNativePointerSample: Sendable {
    let point: CGPoint
    let pressure: Double?
    let time: TimeInterval
}

struct MaskPointerSurface: NSViewRepresentable {
    let isInteractive: Bool
    let onPointer: (MaskNativePointerEvent) -> Void

    func makeNSView(context: Context) -> MaskPointerNSView {
        let view = MaskPointerNSView(frame: .zero)
        view.onPointer = onPointer
        view.isInteractive = isInteractive
        return view
    }

    func updateNSView(_ view: MaskPointerNSView, context: Context) {
        view.onPointer = onPointer
        view.isInteractive = isInteractive
    }
}

final class MaskPointerNSView: NSView {
    var onPointer: ((MaskNativePointerEvent) -> Void)?
    var isInteractive = false { didSet { updateTrackingAreas() } }
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isInteractive ? self : nil
    }

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        guard isInteractive else { return }
        let area = NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) { send(.moved(samples(for: event))) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        send(.began(samples(for: event)))
    }
    override func mouseDragged(with event: NSEvent) { send(.dragged(samples(for: event))) }
    override func mouseUp(with event: NSEvent) {
        send(.ended(samples(for: event).last))
    }

    private func samples(for event: NSEvent) -> [MaskNativePointerSample] {
        let pressure: Double? =
            event.type == .tabletPoint || event.subtype == .tabletPoint
            ? Double(event.pressure) : nil
        let main = MaskNativePointerSample(
            point: convert(event.locationInWindow, from: nil), pressure: pressure,
            time: event.timestamp)

        // Direct-touch events can contain auxiliary/coalesced samples. Mouse and tablet events
        // have no such collection in AppKit, so the native event itself is the sample and mouse
        // pressure intentionally remains nil (BrushMaskMath treats it as pressure 1).
        guard event.type == .directTouch else { return [main] }
        let touches = event.touches(matching: .moved, in: self)
        let coalesced = touches.flatMap { event.coalescedTouches(for: $0) }
        let touchSamples = coalesced.map {
            MaskNativePointerSample(
                point: $0.location(in: self), pressure: nil, time: event.timestamp)
        }
        return touchSamples.isEmpty ? [main] : touchSamples
    }

    private func send(_ event: MaskNativePointerEvent) {
        guard isInteractive else { return }
        onPointer?(event)
    }
}
