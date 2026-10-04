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
        let app = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Kromora/KromoraApp.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(menuCommands.contains("SettingsLink()"))
        XCTAssertEqual(app.components(separatedBy: "\n        Settings {").count - 1, 1)
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
        XCTAssertEqual(KromoraAutoAdjustmentShortcut.menuTitle, "Apply Auto Edits (⇧A)")
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

        XCTAssertTrue(menuCommands.contains("Button(\"Export Originals...\") { post(.exportSelected) }"))
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
        let app = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/Kromora/KromoraApp.swift"),
            encoding: .utf8
        )
        let contentView = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/ContentView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(app.contains("NSWindow.allowsAutomaticWindowTabbing = false"))
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

        let cropInspector = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/CropInspectorView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(cropInspector.contains("Button(\"Save\", action: onDone)"))
        XCTAssertFalse(cropInspector.contains("Button(\"Done\", action: onDone)"))
    }

    func testCropResetLivesInPinnedInspectorTitleRow() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KromoraKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
        let cropInspector = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/CropInspectorView.swift"),
            encoding: .utf8
        )

        let titleRowStart = try XCTUnwrap(
            cropInspector.range(of: "HStack {\n                Text(\"Crop\")")
        )
        let titleRowEnd = try XCTUnwrap(
            cropInspector[titleRowStart.upperBound...].range(of: "\n\n            Divider()")
        )
        let titleRow = cropInspector[titleRowStart.lowerBound..<titleRowEnd.lowerBound]

        XCTAssertTrue(titleRow.contains("Button(\"Reset\", action: onReset)"))
        XCTAssertTrue(titleRow.contains(".buttonStyle(.link)"))
        XCTAssertTrue(titleRow.contains(".accessibilityLabel(\"Reset crop\")"))
        XCTAssertTrue(
            titleRow.contains(".accessibilityHint(\"Return the crop frame to the full image\")")
        )
        XCTAssertTrue(titleRow.contains("Spacer(minLength: 8)"))
        XCTAssertEqual(
            cropInspector.components(separatedBy: "Button(\"Reset\", action: onReset)").count - 1,
            1
        )
        XCTAssertTrue(cropInspector.contains("onResetStraighten"))
        XCTAssertTrue(cropInspector.contains("onResetVerticalPerspective"))
        XCTAssertTrue(cropInspector.contains("onResetHorizontalPerspective"))
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
        XCTAssertTrue(cropInspector.contains("Button(\"Cancel\", action: onCancel)"))
        XCTAssertTrue(cropInspector.contains("Button(\"Save\", action: onDone)"))
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
}
