import SwiftUI
import XCTest
@testable import KromoraKit

final class MenuCommandTests: XCTestCase {
    func testSettingsCommandComesFromTheNativeSettingsScene() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KromoraKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let menuCommands = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/MenuCommands.swift"),
            encoding: .utf8
        )
        let scene = try String(
            contentsOf: packageRoot.appendingPathComponent(
                "Sources/KromoraKit/Presentation/KromoraScene.swift"
            ),
            encoding: .utf8
        )
        let app = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Kromora/KromoraApp.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(app.contains("@NSApplicationDelegateAdaptor(KromoraAppDelegate.self)"))

        XCTAssertFalse(menuCommands.contains("SettingsLink()"))
        XCTAssertEqual(scene.components(separatedBy: "\n        Settings {").count - 1, 1)
    }

    func testUndoRedoLiveOnlyInTheEditMenu() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/MenuCommands.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(source.components(separatedBy: "UndoRedoRouting.perform(.undo").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "Button(availability?.undoTitle").count - 1, 1)
        XCTAssertEqual(source.components(separatedBy: "Button(availability?.redoTitle").count - 1, 1)
        let undoRedo = try XCTUnwrap(source.range(of: "CommandGroup(replacing: .undoRedo)"))
        let newItem = try XCTUnwrap(source.range(of: "CommandGroup(replacing: .newItem)"))
        let undo = try XCTUnwrap(source.range(of: "Button(availability?.undoTitle"))
        let redo = try XCTUnwrap(source.range(of: "Button(availability?.redoTitle"))
        XCTAssertTrue(undoRedo.upperBound <= undo.lowerBound && redo.lowerBound < newItem.lowerBound,
                      "Undo and Redo belong to the .undoRedo group, not File")
    }

    func testEditTransferShortcutsDoNotClaimStandardTextClipboardKeys() {
        let modifiers = KromoraEditTransferShortcuts.modifiers

        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertTrue(modifiers.contains(.option))
        XCTAssertFalse(modifiers.contains(.shift))
        XCTAssertFalse(modifiers.contains(.control))
        XCTAssertEqual(KromoraEditTransferShortcuts.copyKey, "c")
        XCTAssertEqual(KromoraEditTransferShortcuts.pasteKey, "v")
    }

    func testAutoEditShortcutIsDiscoverableInMenuAndReference() {
        XCTAssertEqual(KromoraAutoAdjustmentShortcut.displayString, "⇧A")
        XCTAssertEqual(KromoraAutoAdjustmentShortcut.menuTitle, "Apply Auto Edits")
        XCTAssertEqual(KromoraAutoAdjustmentShortcut.referenceAction, "Apply Auto edits")
    }

    func testLookFolderMenuUsesTheCanonicalLookRoute() {
        XCTAssertEqual(Notification.Name.chooseLookFolder.rawValue, "Kromora.chooseLookFolder")
        XCTAssertEqual(Notification.Name.importLook.rawValue, "Kromora.importLook")
    }

    func testBatchExportMenuUsesOriginalsLabelAndExistingRoute() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KromoraKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let menuCommands = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/MenuCommands.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(menuCommands.contains("Button(\"Export Originals...\") { run(.exportSelected) }"))
        XCTAssertTrue(menuCommands.contains(".keyboardShortcut(\"e\", modifiers: [.command, .shift])"))
        XCTAssertFalse(menuCommands.contains("Button(\"Export Selected...\")"))
    }

    func testViewMenuRoutesRelocatedEditorActionsAndKeepsComparisonToolbarStable() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KromoraKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let menuCommands = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/MenuCommands.swift"),
            encoding: .utf8
        )
        let appDelegate = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Presentation/KromoraAppDelegate.swift"),
            encoding: .utf8
        )
        let contentView = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/ContentView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appDelegate.contains("NSWindow.allowsAutomaticWindowTabbing = false"))
        XCTAssertTrue(menuCommands.contains("CommandGroup(replacing: .sidebar)"))
        XCTAssertFalse(
            menuCommands.contains("CommandMenu(\"View\")"),
            "a CommandMenu named View sits beside AppKit's View menu"
        )
        XCTAssertTrue(menuCommands.contains("\"Hide Clipping Alerts\""))
        XCTAssertTrue(menuCommands.contains("\"Show Clipping Alerts\""))
        XCTAssertTrue(menuCommands.contains("settings.showClippingAlerts.toggle()"))
        XCTAssertTrue(menuCommands.contains("Button(\"Reset Rotation\") { post(.resetRotation) }"))
        XCTAssertTrue(menuCommands.contains("Button(\"Info Inspector\") { post(.toggleInspector) }"))
        XCTAssertTrue(menuCommands.contains(".keyboardShortcut(\"i\", modifiers: .command)"))
        XCTAssertTrue(menuCommands.contains(".onReceive(NotificationCenter.default.publisher(for: .resetRotation))"))
        XCTAssertTrue(menuCommands.contains(".onReceive(NotificationCenter.default.publisher(for: .toggleInspector))"))

        XCTAssertEqual(contentView.components(separatedBy: "Label(\"Reset Rotation\"").count, 1)
        XCTAssertEqual(contentView.components(separatedBy: "Label(\"Info\", systemImage: \"sidebar.right\"").count, 2)
        XCTAssertFalse(contentView.contains("systemImage: \"sidebar.leading\""))
        XCTAssertTrue(menuCommands.contains("viewModel.toggleInspector()"))
        XCTAssertFalse(contentView.contains("viewModel.toggleInspector()"))
        XCTAssertTrue(contentView.contains(".disabled(!viewModel.toolbarPhotoActionsAvailable)"))
        XCTAssertFalse(contentView.contains("Label(\"Copy Edits…\", systemImage: \"doc.on.doc\")"))
        XCTAssertFalse(contentView.contains("Label(\"Paste Edits\", systemImage: \"doc.on.clipboard\")"))
        XCTAssertFalse(contentView.contains("Label(\"Export Selected\", systemImage: \"square.and.arrow.up.on.square\")"))
        XCTAssertTrue(contentView.contains("viewModel.shareDialog()"),
                      "the Edit toolbar export/share action must use the selection-aware route")
    }

    func testImportAndExportToolbarControlsHaveNoStandaloneSeparator() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KromoraKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let contentView = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/ContentView.swift"),
            encoding: .utf8
        )
        let transferPill = try XCTUnwrap(
            contentView.components(separatedBy: "private var transferToolbarPill: some View {")
                .dropFirst().first?
                .components(separatedBy: "private var cropToolbarPill: some View {").first
        )
        XCTAssertTrue(transferPill.contains("ControlGroup {"))
        XCTAssertTrue(transferPill.contains(".controlGroupStyle(.navigation)"))
        XCTAssertFalse(
            contentView.contains(".glassEffect(.regular.interactive(), in: Capsule())"),
            "toolbar groups use the system control, not a painted capsule"
        )
        XCTAssertFalse(transferPill.contains("glassEffectUnion(id: \"transfer\""))
        let betweenImportAndExport = transferPill.components(separatedBy: "Label(\"Import\"").dropFirst().first?
            .components(separatedBy: "Label(\"Export\"").first ?? ""
        XCTAssertFalse(
            betweenImportAndExport.contains("Divider()"),
            "Import and Export stay adjacent inside one system control group"
        )
        XCTAssertTrue(contentView.contains("viewModel.importFromPhotos()"))
        XCTAssertTrue(contentView.contains("viewModel.shareDialog()"))
        XCTAssertTrue(contentView.contains("Label(\"Import\", systemImage: \"photo.on.rectangle\")"))
        XCTAssertTrue(contentView.contains("Label(\"Export\", systemImage: \"square.and.arrow.up\")"))
    }

    @MainActor
    func testCropToolbarOwnsExclusiveWindowChrome() throws {
        XCTAssertEqual(ContentView.toolbarMode(isCropToolActive: true), .crop)
        XCTAssertEqual(ContentView.toolbarMode(isCropToolActive: false), .edit)

        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KromoraKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let contentView = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/ContentView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(contentView.contains("private var cropToolbarPill: some View"))
        XCTAssertTrue(contentView.contains("CropToolbarControls("))
        XCTAssertTrue(
            contentView.contains("ToolbarItem(placement: .navigation)"),
            "The workspace picker and edit controls sit on the leading edge"
        )
        XCTAssertFalse(
            contentView.contains("ToolbarItemGroup(placement: .navigation)"),
            "Crop and the other edit actions stay in the trailing toolbar group"
        )
        XCTAssertTrue(contentView.contains("ToolbarSpacer(.fixed)"))
        XCTAssertTrue(contentView.contains("ToolbarSpacer(.flexible)"))
        XCTAssertTrue(contentView.contains(".toolbarBackgroundVisibility(.visible, for: .windowToolbar)"))
        XCTAssertTrue(contentView.contains(".toolbarBackground(KromoraTheme.toolbarChrome, for: .windowToolbar)"))
        XCTAssertTrue(contentView.contains("GlassEffectContainer(spacing: 10)"))
        XCTAssertTrue(contentView.contains(".buttonStyle(.glass)"))
        XCTAssertTrue(contentView.contains(".buttonStyle(.glassProminent)"))
        XCTAssertFalse(contentView.contains("#available(macOS 26.0"))
        XCTAssertTrue(contentView.contains("Label(\"Save\", systemImage: \"checkmark\")"))
        XCTAssertTrue(contentView.contains("Label(\"Cancel\", systemImage: \"xmark\")"))
        XCTAssertTrue(contentView.contains("Label(\"Undo\", systemImage: \"arrow.uturn.backward\")"))
        XCTAssertTrue(contentView.contains(".disabled(!hasImage || !viewModel.canUndo)"))
        XCTAssertEqual(
            contentView.components(separatedBy: ".tint(nil)").count - 1, 3,
            "Cancel, Undo and the Import/Export pill reset the window accent; only Save keeps it"
        )

        let cropInspector = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/CropInspectorView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            cropInspector.contains("onDone"),
            "Save lives only in the window toolbar; the inspector must not duplicate it"
        )
    }

    func testRelocatedViewActionsHaveStableNotificationNames() {
        XCTAssertEqual(Notification.Name.resetRotation.rawValue, "Kromora.resetRotation")
        XCTAssertEqual(Notification.Name.toggleInspector.rawValue, "Kromora.toggleInspector")
    }

    func testCropInspectorDoesNotAdvertiseUnavailableAutoAction() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KromoraKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let cropInspector = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/CropInspectorView.swift"),
            encoding: .utf8
        )
        let canvasWorkflow = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/ViewModels/CanvasWorkflowCoordinator.swift"),
            encoding: .utf8
        )
        let appViewModel = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/ViewModels/AppViewModel.swift"),
            encoding: .utf8
        )
        let infoInspector = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/InfoInspectorView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(cropInspector.contains("onAuto"))
        XCTAssertFalse(cropInspector.contains("Label(\"Auto\""))
        XCTAssertFalse(cropInspector.contains("Suggest a horizon straighten"))
        XCTAssertFalse(canvasWorkflow.contains("runCropAuto"))
        XCTAssertFalse(canvasWorkflow.contains("Auto crop:"))
        XCTAssertFalse(appViewModel.contains("runCropAuto"))
        XCTAssertFalse(infoInspector.contains("runCropAuto"))
        XCTAssertFalse(infoInspector.contains("onAuto:"))
        XCTAssertFalse(cropInspector.contains("Button(\"Cancel\""))
        XCTAssertFalse(cropInspector.contains("Button(\"Save\""))
        XCTAssertTrue(cropInspector.contains("ResettableAdjustmentLabel(title: \"Straighten\""))
    }

    @MainActor
    func testAutoToolbarButtonKeepsItsFittingSizeAcrossProgressState() {
        let idle = NSHostingView(rootView: AutoToolbarButton(isInProgress: false, action: {}))
        let inProgress = NSHostingView(rootView: AutoToolbarButton(isInProgress: true, action: {}))

        idle.layoutSubtreeIfNeeded()
        inProgress.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            idle.fittingSize,
            inProgress.fittingSize,
            "the Auto toolbar button must not reflow when its icon changes"
        )
    }

    // MARK: - MenuCommandAvailability

    func testNoPhotoDisablesEveryPhotoCommandButNotPaste() {
        let a = MenuCommandAvailability()
        for command: MenuCommand in [
            .export, .exportSelected, .editInExternalEditor, .exportOriginalWithSettings,
            .resetPhoto, .selectiveCopy, .copyAllEdits, .pasteEdits, .saveLook, .deleteSelectedPhotos,
        ] {
            XCTAssertFalse(a.isEnabled(command), "\(command)")
        }
    }

    func testOpenPhotoEnablesPhotoCommands() {
        let a = MenuCommandAvailability(hasPhoto: true, selectionCount: 1, canPaste: true)
        for command: MenuCommand in [
            .export, .exportSelected, .editInExternalEditor, .exportOriginalWithSettings,
            .resetPhoto, .selectiveCopy, .copyAllEdits, .pasteEdits, .saveLook,
        ] {
            XCTAssertTrue(a.isEnabled(command), "\(command)")
        }
        XCTAssertFalse(a.isEnabled(.deleteSelectedPhotos), "Delete is a grid command")
        XCTAssertFalse(MenuCommandAvailability(hasPhoto: true).isEnabled(.pasteEdits), "nothing copied")
    }

    func testGridWithSelectionEnablesBatchCommands() {
        let a = MenuCommandAvailability(isGrid: true, selectionCount: 3, canPaste: true)
        XCTAssertTrue(a.isEnabled(.deleteSelectedPhotos))
        XCTAssertTrue(a.isEnabled(.exportSelected))
        XCTAssertTrue(a.isEnabled(.pasteEdits))
        XCTAssertFalse(a.isEnabled(.export))
        XCTAssertFalse(a.isEnabled(.resetPhoto))
    }

    func testGridWithoutSelectionDisablesEverything() {
        let a = MenuCommandAvailability(isGrid: true, selectionCount: 0, canPaste: true)
        XCTAssertFalse(a.isEnabled(.deleteSelectedPhotos))
        XCTAssertFalse(a.isEnabled(.exportSelected))
        XCTAssertFalse(a.isEnabled(.pasteEdits))
    }

    func testUndoRedoTitlesUseActionNameWhenSupplied() {
        XCTAssertEqual(MenuCommandAvailability().undoTitle, "Undo")
        XCTAssertEqual(MenuCommandAvailability().redoTitle, "Redo")
        let named = MenuCommandAvailability(
            canUndo: true, canRedo: true, undoActionName: "Exposure", redoActionName: "Contrast"
        )
        XCTAssertEqual(named.undoTitle, "Undo Exposure")
        XCTAssertEqual(named.redoTitle, "Redo Contrast")
        XCTAssertEqual(MenuCommandAvailability(undoActionName: "").undoTitle, "Undo")
    }
}
