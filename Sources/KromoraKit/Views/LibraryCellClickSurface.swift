import AppKit
import SwiftUI

/// AppKit counts physical clicks before main-actor delivery. A thumbnail publication or slow
/// selection callback must not reset a SwiftUI double-tap recognizer between the two clicks.
struct LibraryCellClickSurface: NSViewRepresentable {
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onOpen: () -> Void

    func makeNSView(context: Context) -> LibraryCellClickNSView {
        let view = LibraryCellClickNSView(frame: .zero)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: LibraryCellClickNSView, context: Context) {
        view.onSelect = onSelect
        view.onOpen = onOpen
    }
}

final class LibraryCellClickNSView: NSView {
    var onSelect: ((NSEvent.ModifierFlags) -> Void)?
    var onOpen: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            // Opening establishes focus once, without replaying Command/Shift selection toggles.
            onOpen?()
        } else if event.clickCount == 1 {
            onSelect?(event.modifierFlags)
        }
    }
}
