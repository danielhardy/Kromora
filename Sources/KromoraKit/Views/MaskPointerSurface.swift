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
    /// The pointer left the canvas; hover-only presentation such as the brush ring should go.
    case exited
}

struct MaskNativePointerSample: Sendable {
    let point: CGPoint
    let pressure: Double?
    let time: TimeInterval
}

struct MaskPointerSurface: NSViewRepresentable {
    let isInteractive: Bool
    /// The system cursor while the pointer is over an interactive surface. Drawing tools use a
    /// precise crosshair so it sits inside the brush ring rather than an arrow tip beside it.
    var cursor: NSCursor = .crosshair
    let onPointer: (MaskNativePointerEvent) -> Void

    func makeNSView(context: Context) -> MaskPointerNSView {
        let view = MaskPointerNSView(frame: .zero)
        view.onPointer = onPointer
        view.isInteractive = isInteractive
        view.cursor = cursor
        return view
    }

    func updateNSView(_ view: MaskPointerNSView, context: Context) {
        view.onPointer = onPointer
        view.isInteractive = isInteractive
        view.cursor = cursor
    }
}

final class MaskPointerNSView: NSView {
    var onPointer: ((MaskNativePointerEvent) -> Void)?
    var isInteractive = false {
        didSet {
            guard isInteractive != oldValue else { return }
            updateTrackingAreas()
            window?.invalidateCursorRects(for: self)
        }
    }
    var cursor: NSCursor = .crosshair {
        didSet {
            guard cursor != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            // Cursor rects are only re-evaluated on movement; apply a change made under a
            // stationary pointer (Space pressed to pan) immediately.
            guard isInteractive, let window else { return }
            let pointer = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(pointer) { cursor.set() }
        }
    }
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isInteractive ? self : nil
    }

    override func resetCursorRects() {
        guard isInteractive else { return }
        addCursorRect(bounds, cursor: cursor)
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
    override func mouseExited(with event: NSEvent) { send(.exited) }
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
