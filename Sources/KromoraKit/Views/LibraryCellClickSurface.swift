import AppKit
import SwiftUI

/// AppKit counts physical clicks before main-actor delivery. A thumbnail publication or slow
/// selection callback must not reset a SwiftUI double-tap recognizer between the two clicks.
struct LibraryCellClickSurface: NSViewRepresentable {
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onOpen: () -> Void
    /// Receives the cell's thumbnail-square origin and size in SwiftUI window coordinates just
    /// before `onOpen`, so the Edit handoff can start from the clicked cell.
    var onOpenFrame: ((CGRect?) -> Void)?

    func makeNSView(context: Context) -> LibraryCellClickNSView {
        let view = LibraryCellClickNSView(frame: .zero)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: LibraryCellClickNSView, context: Context) {
        view.onSelect = onSelect
        view.onOpen = onOpen
        view.onOpenFrame = onOpenFrame
    }
}

final class LibraryCellClickNSView: NSView {
    var onSelect: ((NSEvent.ModifierFlags) -> Void)?
    var onOpen: (() -> Void)?
    var onOpenFrame: ((CGRect?) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Opening establishes focus once, without replaying Command/Shift selection toggles.
            onOpenFrame?(windowTopLeftFrame())
            onOpen?()
        } else if event.clickCount == 1 {
            onSelect?(event.modifierFlags)
        }
    }

    /// This view's bounds in top-left window coordinates, matching SwiftUI's global space.
    private func windowTopLeftFrame() -> CGRect? {
        guard let contentHeight = window?.contentView?.bounds.height else { return nil }
        let rect = convert(bounds, to: nil)
        return CGRect(x: rect.minX, y: contentHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
