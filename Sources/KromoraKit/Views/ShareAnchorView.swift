import AppKit
import SwiftUI

/// An invisible view placed behind the Share control so the sharing menu opens at the button
/// instead of at the window's content view.
struct ShareAnchorView: NSViewRepresentable {
    let workflow: ExportWorkflowCoordinator

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        workflow.shareAnchorView = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        workflow.shareAnchorView = view
    }
}
