import XCTest
import SwiftUI
@testable import KromoraKit

/// Keeps the declarative shortcut table, the menu bar, the reference sheet and the router in
/// agreement, and fails if an `NSEvent` key monitor is reintroduced (KRMA-920).
@MainActor
final class KeyboardShortcutCatalogTests: XCTestCase {

    func testMenuKeysAreUniqueAndEveryOneIsDisplayedInTheReference() {
        var seen = Set<String>()
        for spec in KeyboardShortcutCatalog.all {
            guard case .menuKey(_, let key, let modifiers) = spec.delivery else { continue }
            let signature = "\(modifiers.rawValue):\(key.character)"
            XCTAssertTrue(seen.insert(signature).inserted, "two menu items share \(spec.keys): \(spec.action)")
            let shown = (modifiers.contains(.shift) ? "⇧" : "") + String(key.character).uppercased()
            XCTAssertEqual(spec.keys, shown, "reference text for \(spec.action) must match its binding")
            XCTAssertNotNil(KromoraCommands.keyInput(for: key, modifiers: modifiers))
        }
        XCTAssertEqual(Set(KeyboardShortcutCatalog.all.map(\.action)).count, KeyboardShortcutCatalog.all.count)
    }

    func testMenuKeysAvoidCommandOptionAndControlSoTextFieldsAndTheSystemKeepThem() {
        for spec in KeyboardShortcutCatalog.all {
            guard case .menuKey(_, _, let modifiers) = spec.delivery else { continue }
            XCTAssertTrue(modifiers.isSubset(of: .shift), spec.action)
        }
    }

    func testEveryMenuKeyIsOwnedByTheRouterSurfaceMappingNever() {
        // Letters/digits/brackets are menu key equivalents; the key surface must never claim them
        // (it would then have to guess about focus again).
        for spec in KeyboardShortcutCatalog.all {
            guard case .menuKey(_, let key, let modifiers) = spec.delivery else { continue }
            XCTAssertNil(KeyboardSurface.input(key: key, modifiers: modifiers, phase: .down), spec.action)
        }
    }

    func testMenusPartitionTheCatalog() {
        let grouped = [KeyboardShortcutSpec.Menu.photo, .tools, .view]
            .flatMap { KeyboardShortcutCatalog.menuItems(in: $0) }
        let menuKeys = KeyboardShortcutCatalog.all.filter {
            if case .menuKey = $0.delivery { return true }
            return false
        }
        XCTAssertEqual(grouped.map(\.action).sorted(), menuKeys.map(\.action).sorted())
    }

    func testNoKeyEventMonitorsRemainInTheProduct() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for token in ["addLocalMonitorForEvents", "addGlobalMonitorForEvents", "KeyMonitor"] {
                // Comments may name the removed type; code may not call the API.
                let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                if code.contains(where: { $0.contains(token) }) { offenders.append("\(url.lastPathComponent): \(token)") }
            }
        }
        XCTAssertEqual(offenders, [], "KRMA-920: keys are routed by the responder chain, not an NSEvent monitor")
    }
}
