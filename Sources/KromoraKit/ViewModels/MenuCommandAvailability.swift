import Foundation

/// File-menu commands that act on the open photo or the library selection. The menu bar reaches
/// them through the focused `KeyboardCommandRouter` instead of a notification, so a command with
/// nothing to act on is disabled rather than silently doing nothing.
enum MenuCommand: Equatable, Sendable {
    case export
    case exportSelected
    case editInExternalEditor
    case exportOriginalWithSettings
    case resetPhoto
    case selectiveCopy
    case copyAllEdits
    case pasteEdits
    case saveLook
    case deleteSelectedPhotos
}

/// Maps app state to File/Edit menu enablement and titles. Pure value logic so every case is
/// testable without a window; `AppViewModel` is read only by `init(_:)`.
struct MenuCommandAvailability: Equatable, Sendable {
    var hasPhoto = false
    var isGrid = false
    var selectionCount = 0
    var canPaste = false
    var canUndo = false
    var canRedo = false
    /// False while the library package is opening or failed to open; every library-dependent
    /// command (import, open, export, delete) is disabled until it is true.
    var isLibraryReady = true
    var undoActionName: String?
    var redoActionName: String?

    init(
        hasPhoto: Bool = false,
        isGrid: Bool = false,
        selectionCount: Int = 0,
        canPaste: Bool = false,
        canUndo: Bool = false,
        canRedo: Bool = false,
        isLibraryReady: Bool = true,
        undoActionName: String? = nil,
        redoActionName: String? = nil
    ) {
        self.hasPhoto = hasPhoto
        self.isGrid = isGrid
        self.selectionCount = selectionCount
        self.canPaste = canPaste
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.isLibraryReady = isLibraryReady
        self.undoActionName = undoActionName
        self.redoActionName = redoActionName
    }

    @MainActor
    init(_ vm: AppViewModel) {
        let selection = vm.collection.selection
        self.init(
            hasPhoto: vm.sourceImage != nil,
            isGrid: vm.navigation.isGrid,
            selectionCount: selection.selectedIDs.isEmpty
                ? (selection.activeID == nil ? 0 : 1) : selection.selectedIDs.count,
            canPaste: vm.canPasteEdits,
            canUndo: vm.canUndo,
            canRedo: vm.canRedo,
            isLibraryReady: vm.canImportIntoPortableLibrary,
            undoActionName: vm.undoActionName,
            redoActionName: vm.redoActionName
        )
    }

    /// Menu commands must fail closed when no scene is focused and no availability was published.
    static func isLibraryReady(_ availability: Self?) -> Bool {
        availability?.isLibraryReady == true
    }

    func isEnabled(_ command: MenuCommand) -> Bool {
        guard isLibraryReady else { return false }
        return switch command {
        case .export, .editInExternalEditor, .exportOriginalWithSettings,
             .resetPhoto, .selectiveCopy, .copyAllEdits, .saveLook:
            hasPhoto
        case .pasteEdits:
            canPaste && (hasPhoto || selectionCount > 0)
        case .exportSelected:
            selectionCount > 0 || hasPhoto
        case .deleteSelectedPhotos:
            isGrid && selectionCount > 0
        }
    }

    var undoTitle: String { Self.title("Undo", actionName: undoActionName) }
    var redoTitle: String { Self.title("Redo", actionName: redoActionName) }

    private static func title(_ verb: String, actionName: String?) -> String {
        guard let actionName, !actionName.isEmpty else { return verb }
        return "\(verb) \(actionName)"
    }
}
