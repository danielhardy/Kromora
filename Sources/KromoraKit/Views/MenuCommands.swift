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

/// Kromora's File menu, replacing SwiftUI's default "New" group.
///
/// One of two entry points KromoraKit exposes to the executable (the other is
/// `ContentView`). Each item posts a notification that `MenuCommandReceivers`
/// picks up on the view side — the menu bar is outside the view hierarchy, so
/// it can't reach the view model directly.
public struct KromoraCommands: Commands {
    @ObservedObject private var settings: KromoraSettings
#if KROMORA_DIRECT_DISTRIBUTION
    @ObservedObject private var updateCoordinator: UpdateCoordinator
#endif

#if KROMORA_DIRECT_DISTRIBUTION
    public init(
        settings: KromoraSettings = KromoraSettings(),
        updateCoordinator: UpdateCoordinator? = nil
    ) {
        _settings = ObservedObject(wrappedValue: settings)
        _updateCoordinator = ObservedObject(wrappedValue: updateCoordinator ?? UpdateCoordinator())
    }
#else
    public init(settings: KromoraSettings = KromoraSettings()) {
        _settings = ObservedObject(wrappedValue: settings)
    }
#endif

    public var body: some Commands {
        CommandMenu("View") {
            Toggle("Show Photo Names", isOn: $settings.showPhotoNames)
                .accessibilityLabel("Show Photo Names")

            Divider()

            Button("Reset Rotation") { post(.resetRotation) }
                .accessibilityLabel("Reset Rotation")

            Button("Info Inspector") { post(.toggleInspector) }
                .keyboardShortcut("i", modifiers: .command)
                .accessibilityLabel("Info Inspector")
        }

        CommandGroup(replacing: .newItem) {
            Button("Open Image...") { post(.openImage) }
                .keyboardShortcut("o")

            Button("Choose Look Folder...") { post(.chooseLookFolder) }
                .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Import Look...") { post(.importLook) }
                .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button("Import from Photos...") { post(.importFromPhotos) }
                .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Open Source Folder...") { post(.openSourceFolder) }
                .keyboardShortcut("i", modifiers: [.command, .option])

            Button("Import from Removable Media...") { post(.importFromRemovableMedia) }

            Button("Refresh Source Folder") { post(.refreshSourceFolder) }
                .keyboardShortcut("r", modifiers: [.command])

            Button("Delete Selected Photos") { post(.deleteSelectedPhotos) }
                .keyboardShortcut(.delete)

            Divider()

            Button("Undo") { post(.undoEdit) }
                .keyboardShortcut("z", modifiers: [.command])
            Button("Redo") { post(.redoEdit) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Button("Reset Photo") { post(.resetPhoto) }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Copy All Edits") { post(.copyAllEdits) }
                .keyboardShortcut(
                    KromoraEditTransferShortcuts.copyKey,
                    modifiers: KromoraEditTransferShortcuts.modifiers
                )
            Button("Paste Edits") { post(.pasteEdits) }
                .keyboardShortcut(
                    KromoraEditTransferShortcuts.pasteKey,
                    modifiers: KromoraEditTransferShortcuts.modifiers
                )

            Divider()

            Button("Derive Look from JPG…") { post(.deriveRecipe) }
                .keyboardShortcut("d")

            Button("Save as Look/LUT…") { post(.saveLook) }

            Divider()

            Button("Export...") { post(.exportImage) }
                .keyboardShortcut("s")

            Button("Export Selected...") { post(.exportSelected) }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }

#if KROMORA_DIRECT_DISTRIBUTION
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updateCoordinator.checkNow() }
        }
#endif
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
            .modifier(FileMenuCommandReceiver(viewModel: viewModel))
            .modifier(ViewMenuCommandReceivers(viewModel: viewModel))
            .modifier(DeleteMenuCommandReceiver(viewModel: viewModel))
    }
}

private struct FileMenuCommandReceiver: ViewModifier {
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openImage)) { _ in
                viewModel.openImageDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportImage)) { _ in
                viewModel.exportDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportSelected)) { _ in
                viewModel.exportSelectedDialog()
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
                viewModel.undo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .redoEdit)) { _ in
                viewModel.redo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetPhoto)) { _ in
                viewModel.resetPhoto()
            }
            .onReceive(NotificationCenter.default.publisher(for: .copyAllEdits)) { _ in
                viewModel.copyAllEdits()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pasteEdits)) { _ in
                viewModel.pasteEdits()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deriveRecipe)) { _ in
                viewModel.presentRecipeExtractor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveLook)) { _ in
                viewModel.presentSaveLook()
            }
    }
}

private struct DeleteMenuCommandReceiver: ViewModifier {
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .deleteSelectedPhotos)) { _ in
            viewModel.requestDeleteSelectedLibraryItems()
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
    static let exportImage = Notification.Name("Kromora.exportImage")
    static let exportSelected = Notification.Name("Kromora.exportSelected")
    /// Compatibility name for callers from the pre-selection export flow.
    static let exportAll = exportSelected
    static let chooseLookFolder = Notification.Name("Kromora.chooseLookFolder")
    static let importLook = Notification.Name("Kromora.importLook")
    static let importFromPhotos = Notification.Name("Kromora.importFromPhotos")
    static let openSourceFolder = Notification.Name("Kromora.openSourceFolder")
    static let importFromRemovableMedia = Notification.Name("Kromora.importFromRemovableMedia")
    static let refreshSourceFolder = Notification.Name("Kromora.refreshSourceFolder")
    static let deleteSelectedPhotos = Notification.Name("Kromora.deleteSelectedPhotos")
    static let undoEdit = Notification.Name("Kromora.undoEdit")
    static let redoEdit = Notification.Name("Kromora.redoEdit")
    static let resetPhoto = Notification.Name("Kromora.resetPhoto")
    static let resetRotation = Notification.Name("Kromora.resetRotation")
    static let toggleInspector = Notification.Name("Kromora.toggleInspector")
    static let copyAllEdits = Notification.Name("Kromora.copyAllEdits")
    static let pasteEdits = Notification.Name("Kromora.pasteEdits")
    static let deriveRecipe = Notification.Name("Kromora.deriveRecipe")
    static let saveLook = Notification.Name("Kromora.saveLook")
}
