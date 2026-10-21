import AppKit
import SwiftUI

/// The context menu for a photo thumbnail in the Library grid and the Edit filmstrip. Enablement
/// comes from `LibraryContextMenuState`; every action is delivered through
/// `AppViewModel.performLibraryContextAction`, which re-resolves the target.
struct LibraryContextMenuItems: View {
    let viewModel: AppViewModel
    let photoID: PhotoAssetID

    var body: some View {
        let state = viewModel.libraryContextMenuState(for: photoID)
        let count = state.target.selectionCount

        Button("Open in Edit") { run(.openInEdit) }
            .disabled(!state.isEnabled(.openInEdit))

        Divider()

        Button(count > 1 ? "Copy \(count) Images" : "Copy Image") { run(.copyImage) }
            .disabled(!state.isEnabled(.copyImage))
            .help(state.disabledReason(for: .copyImage) ?? "Copy the developed image")
        Button("Copy Edit Settings") { run(.copyEditSettings) }
            .disabled(!state.isEnabled(.copyEditSettings))
        Button(count > 1 ? "Paste Edit Settings to \(count) Photos" : "Paste Edit Settings") {
            run(.pasteEditSettings)
        }
        .disabled(!state.isEnabled(.pasteEditSettings))
        .help(state.disabledReason(for: .pasteEditSettings) ?? "Paste the copied edit settings")

        Divider()

        Button(LibraryContextMenuState.virtualCopyTitle) { run(.createVirtualCopy) }
            .disabled(!state.isEnabled(.createVirtualCopy))
            .help(
                state.disabledReason(for: .createVirtualCopy)
                    ?? "Creates an independent photo with these edits. It stores its own copy of the original.")

        Divider()

        Menu("Flag") {
            Button("Pick") { run(.setFlag(.pick)) }
            Button("Reject") { run(.setFlag(.reject)) }
            Button("Clear Flag") { run(.setFlag(.none)) }
        }
        Menu("Rating") {
            ForEach(1...5, id: \.self) { stars in
                Button(stars == 1 ? "1 Star" : "\(stars) Stars") { run(.setRating(stars)) }
            }
            Button("Clear Rating") { run(.setRating(0)) }
        }

        Divider()

        Button(count > 1 ? "Export \(count) Photos…" : "Export…") { run(.export) }
            .disabled(!state.isEnabled(.export))
            .help(state.disabledReason(for: .export) ?? "Export the developed photos")
        Button("Share…") { run(.share) }
            .disabled(!state.isEnabled(.share))
            .help(state.disabledReason(for: .share) ?? "Share the developed photos")

        Divider()

        Button(count > 1 ? "Delete \(count) Photos from Library…" : "Delete from Library…", role: .destructive) {
            run(.deleteFromLibrary)
        }
        .disabled(!state.isEnabled(.deleteFromLibrary))
        .help(state.disabledReason(for: .deleteFromLibrary) ?? "Remove from the Library, after confirmation")
    }

    private func run(_ action: LibraryContextAction) {
        viewModel.performLibraryContextAction(action, on: photoID)
    }
}

/// Reports a right-click (or Control-click) on a thumbnail before the context menu opens, then
/// lets the click continue to the menu. It only claims hit-testing for those events, so ordinary
/// clicks, double-clicks, and drags reach the thumbnail unchanged.
struct LibraryContextClickRetarget: NSViewRepresentable {
    let onContextClick: () -> Void

    func makeNSView(context: Context) -> RetargetView {
        let view = RetargetView(frame: .zero)
        view.onContextClick = onContextClick
        return view
    }

    func updateNSView(_ view: RetargetView, context: Context) {
        view.onContextClick = onContextClick
    }

    final class RetargetView: NSView {
        var onContextClick: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, Self.isContextClick(event) else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            onContextClick?()
            super.rightMouseDown(with: event)
        }

        override func mouseDown(with event: NSEvent) {
            guard Self.isContextClick(event) else { return super.mouseDown(with: event) }
            rightMouseDown(with: event)
        }

        private static func isContextClick(_ event: NSEvent) -> Bool {
            event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }
    }
}
