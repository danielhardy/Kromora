import Foundation

/// Actions offered by the photo context menu in the Library grid and the Edit filmstrip.
enum LibraryContextAction: Equatable, Sendable {
    case openInEdit
    case copyImage
    case copyEditSettings
    case pasteEditSettings
    case createVirtualCopy
    case setFlag(PhotoFlag)
    case setRating(Int)
    case export
    case share
    case deleteFromLibrary
}

/// Which photos a context-menu action applies to. Value-based and short-lived: it is recomputed
/// whenever a menu opens and again when an action is delivered, because windowed library pages and
/// the selection can change while a menu is on screen.
struct LibraryContextTarget: Equatable, Sendable {
    /// The photo under the pointer.
    let contextID: PhotoAssetID
    /// True when the context photo is not part of the current selection, so the selection must be
    /// replaced by it before any action runs.
    let replacesSelection: Bool
    /// The photos selection-wide actions apply to.
    let selectionCount: Int

    /// - Parameters:
    ///   - selectedIDs: the explicit selection; may be empty.
    ///   - activeID: the focused photo, which is the implicit selection when `selectedIDs` is empty.
    static func resolve(
        contextID: PhotoAssetID, selectedIDs: Set<PhotoAssetID>, activeID: PhotoAssetID?
    ) -> LibraryContextTarget {
        let effective: Set<PhotoAssetID> = selectedIDs.isEmpty
            ? (activeID.map { [$0] } ?? []) : selectedIDs
        if effective.contains(contextID) {
            return LibraryContextTarget(
                contextID: contextID, replacesSelection: false, selectionCount: effective.count)
        }
        return LibraryContextTarget(contextID: contextID, replacesSelection: true, selectionCount: 1)
    }
}

/// Enabled state and disabled reasons for the context menu. Pure value logic so each case is
/// testable without a window.
struct LibraryContextMenuState: Equatable, Sendable {
    var target: LibraryContextTarget
    var isLibraryReady = true
    var isGrid = true
    var isExportBusy = false
    var canPaste = false
    /// The context photo belongs to a managed package library.
    var isPackagePhoto = false
    var isCreatingVirtualCopy = false

    func isEnabled(_ action: LibraryContextAction) -> Bool {
        disabledReason(for: action) == nil
    }

    /// A short reason the action is unavailable, or nil when it can run.
    func disabledReason(for action: LibraryContextAction) -> String? {
        guard isLibraryReady else { return "The library is not ready" }
        switch action {
        case .openInEdit, .copyEditSettings, .setFlag, .setRating:
            return nil
        case .copyImage, .export, .share:
            return isExportBusy ? "Another export is already running" : nil
        case .pasteEditSettings:
            return canPaste ? nil : "Copy edit settings first"
        case .createVirtualCopy:
            if !isPackagePhoto { return "Virtual copies need a photo in a Kromora library" }
            return isCreatingVirtualCopy ? "A virtual copy is already being created" : nil
        case .deleteFromLibrary:
            return isGrid ? nil : "Return to the Library to remove photos"
        }
    }

    /// States that a virtual copy stores its own copy of the original, so it is never presented as
    /// a free alias.
    static let virtualCopyTitle = "Create Virtual Copy (stores another copy of the original)"
}
