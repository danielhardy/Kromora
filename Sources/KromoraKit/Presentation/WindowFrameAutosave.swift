import AppKit
import SwiftUI

/// Remembers the main window's size and position between launches.
///
/// `WindowGroup.defaultSize` only seeds the first launch, and SwiftUI's own restoration depends on
/// the system "close windows when quitting" setting and does not apply to a launcher run from
/// SwiftPM. AppKit's frame autosave is independent of both: once a name is set the frame is
/// written to user defaults on every move or resize and read back on the next launch.
struct WindowFrameAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView { Anchor(autosaveName: name) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// A zero-size view whose only job is to reach the hosting window.
    final class Anchor: NSView {
        private let autosaveName: String

        init(autosaveName: String) {
            self.autosaveName = autosaveName
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Anchor is created in code") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            Self.attach(autosaveName, to: window)
        }

        /// Apply the saved frame, then keep saving it. A second window with the same name is
        /// refused by AppKit and simply keeps its cascaded default placement.
        static func attach(_ name: String, to window: NSWindow) {
            guard window.frameAutosaveName != name else { return }
            _ = window.setFrameUsingName(name)
            _ = window.setFrameAutosaveName(name)
        }
    }
}
