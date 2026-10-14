import SwiftUI

// The File menu and the notifications it posts. These live in KromoraKit rather
// than beside `@main` so the executable target stays a thin entry point (and so
// the menu can be exercised from tests).

// MARK: - Commands

/// The edit-transfer shortcuts deliberately include Option so they do not compete with AppKit's
/// standard Command-C/Command-V actions when a text field owns the first responder.
enum KromoraEditTransferShortcuts {
    static let modifiers: EventModifiers = [.command, .option]
    static let copyKey: KeyEquivalent = "c"
    static let pasteKey: KeyEquivalent = "v"
}

/// Shift+A applies Auto. Plain A already toggles the retouch visualization, so the shifted
/// variant keeps both editor commands available without changing the existing gesture. The menu
/// item carries the key equivalent: AppKit offers it to a focused text field first, so typing a
/// capital A is never stolen, and it is the last chance before the system alert for other focus.
enum KromoraAutoAdjustmentShortcut {
    static let displayString = "⇧A"
    static let menuTitle = "Apply Auto Edits"
    static let referenceAction = "Apply Auto edits"
}

/// Command-Z / Shift-Command-Z. A modified menu key equivalent fires even while a text field is
/// editing, so the menu action decides: a field editor undoes its own text, anything else undoes
/// the photo edit through the existing notifications.
@MainActor
enum UndoRedoRouting {
    enum Direction { case undo, redo }

    static func perform(_ direction: Direction, in window: NSWindow?) {
        if let editor = window?.firstResponder as? NSTextView, let manager = editor.undoManager {
            switch direction {
            case .undo: if manager.canUndo { manager.undo() }
            case .redo: if manager.canRedo { manager.redo() }
            }
            return
        }
        NotificationCenter.default.post(
            name: direction == .undo ? .undoEdit : .redoEdit, object: nil
        )
    }
}

/// Kromora's File menu, replacing SwiftUI's default "New" group.
///
/// One of two entry points KromoraKit exposes to the executable (the other is
/// `ContentView`). Commands that need a photo or selection run through the focused
/// `KeyboardCommandRouter` and are enabled by the focused `MenuCommandAvailability`; the remaining
/// items post a notification that `MenuCommandReceivers` picks up on the view side.
public struct KromoraCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var settings: KromoraSettings
    @FocusedValue(\.keyboardRouter) private var keyboardRouter
    @FocusedValue(\.keyboardContext) private var keyboardContext
    @FocusedValue(\.menuAvailability) private var availability

    public init(settings: KromoraSettings = KromoraSettings()) {
        _settings = ObservedObject(wrappedValue: settings)
    }

    public var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Kromora") { openWindow(id: KromoraAboutView.windowID) }
        }

        // These editor commands belong in AppKit's View menu, with Enter Full Screen.
        CommandGroup(replacing: .sidebar) {
            Toggle("Show Photo Names", isOn: $settings.showPhotoNames)
                .accessibilityLabel("Show Photo Names")

            Divider()

            keyboardItems(.view)

            Button("Reset Rotation") { post(.resetRotation) }
                .accessibilityLabel("Reset Rotation")

            Button(settings.showClippingAlerts ? "Hide Clipping Alerts" : "Show Clipping Alerts") {
                settings.showClippingAlerts.toggle()
            }
            .accessibilityLabel(
                settings.showClippingAlerts ? "Hide Clipping Alerts" : "Show Clipping Alerts"
            )

            Button("Info Inspector") { post(.toggleInspector) }
                .keyboardShortcut("i", modifiers: .command)
                .accessibilityLabel("Info Inspector")

            Divider()

            Button("Keyboard Shortcuts…") { post(.showKeyboardShortcuts) }
        }

        CommandMenu("Photo") { keyboardItems(.photo) }

        CommandMenu("Tools") { keyboardItems(.tools) }

        // Undo/Redo live in the Edit menu. The items stay enabled: a focused text field can have
        // text to undo while the photo has none, so photo `canUndo` is not the whole answer. The
        // titles follow the focused window's action name.
        CommandGroup(replacing: .undoRedo) {
            Button(availability?.undoTitle ?? "Undo") { UndoRedoRouting.perform(.undo, in: NSApp.keyWindow) }
                .keyboardShortcut("z", modifiers: [.command])
            Button(availability?.redoTitle ?? "Redo") { UndoRedoRouting.perform(.redo, in: NSApp.keyWindow) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .newItem) {
            Button("Open Image…") { post(.openImage) }
                .keyboardShortcut("o")
                .disabled(!MenuCommandAvailability.isLibraryReady(availability))

            Button("Choose Look Folder…") { post(.chooseLookFolder) }
                .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Import Look…") { post(.importLook) }
                .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button("Import from Photos…") { post(.importFromPhotos) }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(!MenuCommandAvailability.isLibraryReady(availability))

            Button("Import Folder…") { post(.openSourceFolder) }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(!MenuCommandAvailability.isLibraryReady(availability))

            Button("Import from Removable Media…") { post(.importFromRemovableMedia) }
                .disabled(!MenuCommandAvailability.isLibraryReady(availability))

            Button("Rebuild Library Index") { post(.refreshSourceFolder) }
                .keyboardShortcut("r", modifiers: [.command])

            Button("Delete Selected Photos") { run(.deleteSelectedPhotos) }
                .keyboardShortcut(.delete)
                .disabled(!isEnabled(.deleteSelectedPhotos))

            Divider()

            Button("Reset Photo") { run(.resetPhoto) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!isEnabled(.resetPhoto))

            Button(KromoraAutoAdjustmentShortcut.menuTitle) { post(.applyAutoAdjustment) }
                .keyboardShortcut("a", modifiers: .shift)
                .disabled(keyboardContext?.canAutoAdjust != true)

            Divider()

            Button("Copy Edits…") { run(.selectiveCopy) }
                .disabled(!isEnabled(.selectiveCopy))
            Button("Copy All Edits") { run(.copyAllEdits) }
                .keyboardShortcut(
                    KromoraEditTransferShortcuts.copyKey,
                    modifiers: KromoraEditTransferShortcuts.modifiers
                )
                .disabled(!isEnabled(.copyAllEdits))
            Button("Paste Edits") { run(.pasteEdits) }
                .keyboardShortcut(
                    KromoraEditTransferShortcuts.pasteKey,
                    modifiers: KromoraEditTransferShortcuts.modifiers
                )
                .disabled(!isEnabled(.pasteEdits))

            Divider()

            Button("Derive Look from JPG…") { post(.deriveRecipe) }
                .keyboardShortcut("d")

            Button("Save as Look/LUT…") { run(.saveLook) }
                .disabled(!isEnabled(.saveLook))

            Divider()

            Button("Export…") { run(.export) }
                .keyboardShortcut("s")
                .disabled(!isEnabled(.export))

            Button("Export Originals…") { run(.exportSelected) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!isEnabled(.exportSelected))

            Button("Edit in External Editor…") { run(.editInExternalEditor) }
                .keyboardShortcut("e", modifiers: [.command, .option])
                .disabled(!isEnabled(.editInExternalEditor))

            Button("Export Original + Settings Bundle…") { run(.exportOriginalWithSettings) }
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(!isEnabled(.exportOriginalWithSettings))
        }
    }

    /// Plain-key shortcuts as menu items, built from the catalog. The action goes through
    /// `KeyboardCommandRouter`, which is where precedence and context live. A disabled item still
    /// swallows its key (no alert), so greying a command out is silent as well as truthful.
    @ViewBuilder
    private func keyboardItems(_ menu: KeyboardShortcutSpec.Menu) -> some View {
        ForEach(KeyboardShortcutCatalog.menuItems(in: menu)) { binding in
            Button(binding.title) { keyboardRouter?.perform(binding.input) }
                .keyboardShortcut(binding.key, modifiers: binding.modifiers)
                .disabled(!isEnabled(binding.command))
        }
    }

    private func isEnabled(_ command: KeyboardCommand) -> Bool {
        guard keyboardRouter != nil, let keyboardContext else { return false }
        return command.isAvailable(in: keyboardContext)
    }

    private func run(_ command: MenuCommand) { keyboardRouter?.perform(command) }

    private func isEnabled(_ command: MenuCommand) -> Bool {
        availability?.isEnabled(command) ?? false
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

// MARK: - Receivers

/// Bridges the menu's notifications back to the view model.
struct MenuCommandReceivers: ViewModifier {
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .modifier(AutoAdjustmentCommandReceiver(viewModel: viewModel))
            .modifier(FileMenuCommandReceiver(viewModel: viewModel))
            .modifier(ViewMenuCommandReceivers(viewModel: viewModel))
    }
}

private struct FileMenuCommandReceiver: ViewModifier {
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openImage)) { _ in
                viewModel.openImageDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .chooseLookFolder)) { _ in
                viewModel.chooseLookFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importLook)) { _ in
                viewModel.chooseLookFile()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importFromPhotos)) { _ in
                viewModel.importFromPhotos()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSourceFolder)) { _ in
                viewModel.chooseSourceFolder()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importFromRemovableMedia)) { _ in
                viewModel.importFromRemovableMedia()
            }
            .onReceive(NotificationCenter.default.publisher(for: .refreshSourceFolder)) { _ in
                viewModel.refreshSource()
            }
            .onReceive(NotificationCenter.default.publisher(for: .undoEdit)) { _ in
                // A pending culling change (pick/reject/rating) is undoable once edit history is empty.
                if viewModel.canUndo {
                    viewModel.undo()
                } else {
                    _ = viewModel.undoCullingChange()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .redoEdit)) { _ in
                viewModel.redo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deriveRecipe)) { _ in
                viewModel.presentRecipeExtractor()
            }
    }
}

private struct AutoAdjustmentCommandReceiver: ViewModifier {
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .applyAutoAdjustment)) { _ in
            viewModel.runAutoAdjustment()
        }
    }
}

/// Receivers for the editor actions exposed from the View menu. Keeping these separate from the
/// larger File-menu receiver chain keeps SwiftUI's modifier expression type-checkable.
private struct ViewMenuCommandReceivers: ViewModifier {
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .resetRotation)) { _ in
                viewModel.resetRotation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
                viewModel.toggleInspector()
            }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openImage = Notification.Name("Kromora.openImage")
    static let chooseLookFolder = Notification.Name("Kromora.chooseLookFolder")
    static let importLook = Notification.Name("Kromora.importLook")
    static let importFromPhotos = Notification.Name("Kromora.importFromPhotos")
    static let openSourceFolder = Notification.Name("Kromora.openSourceFolder")
    static let importFromRemovableMedia = Notification.Name("Kromora.importFromRemovableMedia")
    static let refreshSourceFolder = Notification.Name("Kromora.refreshSourceFolder")
    static let undoEdit = Notification.Name("Kromora.undoEdit")
    static let redoEdit = Notification.Name("Kromora.redoEdit")
    static let applyAutoAdjustment = Notification.Name("Kromora.applyAutoAdjustment")
    /// Notification used by the View menu command to clear a committed rotation.
    static let resetRotation = Notification.Name("Kromora.resetRotation")
    static let toggleInspector = Notification.Name("Kromora.toggleInspector")
    static let showKeyboardShortcuts = Notification.Name("Kromora.showKeyboardShortcuts")
    static let toggleCaptureMetadataOverlay = Notification.Name("Kromora.toggleCaptureMetadataOverlay")
    static let deriveRecipe = Notification.Name("Kromora.deriveRecipe")
}
