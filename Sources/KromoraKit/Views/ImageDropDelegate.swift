import AppKit
import SwiftUI

/// Reads the AppKit drag pasteboard because SwiftUI's `NSItemProvider` surface cannot redeem
/// `NSFilePromiseReceiver` instances supplied by Apple Photos.
@MainActor
struct ImageDropDelegate: DropDelegate {
    let viewModel: AppViewModel
    @Binding var isTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        ImageDrop.canAccept(NSPasteboard(name: .drag))
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard let payload = ImageDrop.payload(from: NSPasteboard(name: .drag)) else {
            return false
        }
        viewModel.handleDrop(payload)
        return true
    }
}
