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
}
