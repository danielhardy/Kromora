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
