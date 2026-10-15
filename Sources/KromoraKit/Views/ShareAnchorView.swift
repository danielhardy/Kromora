import AppKit
import SwiftUI

/// An invisible view placed behind the Share control so the sharing menu opens at the button
/// instead of at the window's content view.
///
/// Toolbar content can be instantiated more than once (overflow, customization, workspace
/// switches), and a copy may never join a window. The anchor therefore registers itself only
/// once it is in a window and unregisters when it leaves, so the workflow never holds a detached
/// copy.
struct ShareAnchorView: NSViewRepresentable {
    let workflow: ExportWorkflowCoordinator

    func makeNSView(context: Context) -> NSView {
        AnchorView(workflow: workflow)
    }

    func updateNSView(_ view: NSView, context: Context) {}

    private final class AnchorView: NSView {
        private let workflow: ExportWorkflowCoordinator

        init(workflow: ExportWorkflowCoordinator) {
            self.workflow = workflow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                workflow.shareAnchorView = self
            } else if workflow.shareAnchorView === self {
                workflow.shareAnchorView = nil
            }
        }
    }
}
