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
        let contentView = try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/KromoraKit/Views/ContentView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(menuCommands.contains("Button(\"Reset Rotation\") { post(.resetRotation) }"))
        XCTAssertTrue(menuCommands.contains("Button(\"Info Inspector\") { post(.toggleInspector) }"))
        XCTAssertTrue(menuCommands.contains(".keyboardShortcut(\"i\", modifiers: .command)"))
        XCTAssertTrue(menuCommands.contains(".onReceive(NotificationCenter.default.publisher(for: .resetRotation))"))
        XCTAssertTrue(menuCommands.contains(".onReceive(NotificationCenter.default.publisher(for: .toggleInspector))"))

        XCTAssertEqual(contentView.components(separatedBy: "Label(\"Reset Rotation\"").count, 1)
        XCTAssertEqual(contentView.components(separatedBy: "Label(\"Info\", systemImage: \"sidebar.right\"").count, 2)
        XCTAssertFalse(contentView.contains("systemImage: \"sidebar.leading\""))
        XCTAssertTrue(contentView.contains("viewModel.toggleInspector()"))
        XCTAssertTrue(contentView.contains(".disabled(!viewModel.isComparisonPresentationAvailable)"))
        XCTAssertFalse(contentView.contains("Label(\"Copy Edits…\", systemImage: \"doc.on.doc\")"))
        XCTAssertFalse(contentView.contains("Label(\"Paste Edits\", systemImage: \"doc.on.clipboard\")"))
        XCTAssertFalse(contentView.contains("Label(\"Export Selected\", systemImage: \"square.and.arrow.up.on.square\")"))
        XCTAssertTrue(contentView.contains("viewModel.shareDialog()"),
                      "the Edit toolbar export/share action must use the selection-aware route")
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
        let cropBranch = try XCTUnwrap(
            contentView
                .components(separatedBy: "case .crop:")
                .dropFirst()
                .first?
                .components(separatedBy: "case .edit:")
                .first
        )

        XCTAssertTrue(cropBranch.contains("CropToolbarControls("))
        XCTAssertFalse(cropBranch.contains("Picker(\"Workspace\""))
        XCTAssertFalse(cropBranch.contains("AutoToolbarButton"))
        XCTAssertFalse(cropBranch.contains("Export Selected"))
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

    func testRelocatedViewActionsHaveStableNotificationNames() {
        XCTAssertEqual(Notification.Name.resetRotation.rawValue, "Kromora.resetRotation")
        XCTAssertEqual(Notification.Name.toggleInspector.rawValue, "Kromora.toggleInspector")
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
