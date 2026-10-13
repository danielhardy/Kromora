import XCTest
import SwiftUI
import CoreImage
@testable import KromoraKit

/// Keeps the declarative shortcut table, the menu bar, the reference sheet and the router in
/// agreement, and fails if an `NSEvent` key monitor is reintroduced (KRMA-920).
@MainActor
final class KeyboardShortcutCatalogTests: TempDirectoryTestCase {

    private var menuSpecs: [(spec: KeyboardShortcutSpec, key: KeyEquivalent, modifiers: EventModifiers, command: KeyboardCommand)] {
        KeyboardShortcutCatalog.all.compactMap { spec in
            guard case .menuKey(_, let key, let modifiers, let command) = spec.delivery else { return nil }
            return (spec, key, modifiers, command)
        }
    }

    func testMenuKeysAreUniqueAndEveryOneIsDisplayedInTheReference() {
        var seen = Set<String>()
        for (spec, key, modifiers, _) in menuSpecs {
            let signature = "\(modifiers.rawValue):\(key.character)"
            XCTAssertTrue(seen.insert(signature).inserted, "two menu items share \(spec.keys): \(spec.action)")
            let shown = (modifiers.contains(.shift) ? "⇧" : "") + String(key.character).uppercased()
            XCTAssertEqual(spec.keys, shown, "reference text for \(spec.action) must match its binding")
        }
        XCTAssertEqual(Set(KeyboardShortcutCatalog.all.map(\.action)).count, KeyboardShortcutCatalog.all.count)
    }

    func testMenuKeysAvoidCommandOptionAndControlSoTextFieldsAndTheSystemKeepThem() {
        for (spec, _, modifiers, _) in menuSpecs {
            XCTAssertTrue(modifiers.isSubset(of: .shift), spec.action)
        }
    }

    /// The actual bindings the menu bar installs (`KromoraCommands` renders exactly these) resolve,
    /// through the router's lookup, to the command the catalog declares for them.
    func testMenuBindingsDispatchToTheirCatalogCommands() {
        let bindings = [KeyboardShortcutSpec.Menu.photo, .tools, .view]
            .flatMap { KeyboardShortcutCatalog.menuItems(in: $0) }
        XCTAssertEqual(bindings.count, menuSpecs.count)
        for binding in bindings {
            XCTAssertEqual(KeyboardShortcutCatalog.command(for: binding.input), binding.command, binding.title)
            let spec = menuSpecs.first { $0.spec.action == binding.title }
            XCTAssertEqual(spec?.key, binding.key)
            XCTAssertEqual(spec?.modifiers, binding.modifiers)
        }
    }

    func testSystemModifiedCharactersNeverResolveToCommands() {
        for (spec, key, modifiers, _) in menuSpecs {
            for extra in [EventModifiers.command, .option, .control] {
                XCTAssertNil(
                    KeyboardShortcutCatalog.command(
                        for: KeyInput(.character(String(key.character)), modifiers: modifiers.union(extra))
                    ), spec.action
                )
            }
        }
    }

    func testEverySurfaceKeyIsMappedByTheChainTail() {
        XCTAssertFalse(KeyboardShortcutCatalog.surfaceInputs.isEmpty)
        let characters: [KeyInput.Key: String] = [
            .arrow(.left): String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            .arrow(.right): String(UnicodeScalar(NSRightArrowFunctionKey)!),
            .arrow(.up): String(UnicodeScalar(NSUpArrowFunctionKey)!),
            .arrow(.down): String(UnicodeScalar(NSDownArrowFunctionKey)!),
            .space: " ", .return: "\r", .escape: "\u{1b}", .delete: "\u{7f}",
            .forwardDelete: String(UnicodeScalar(NSDeleteFunctionKey)!),
            .character("\\"): "\\"
        ]
        for input in KeyboardShortcutCatalog.surfaceInputs {
            let chars = characters[input.key]
            var flags = NSEvent.ModifierFlags()
            if input.modifiers.contains(.command) { flags.insert(.command) }
            if input.modifiers.contains(.shift) { flags.insert(.shift) }
            let event = chars.flatMap {
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                    windowNumber: 0, context: nil, characters: $0, charactersIgnoringModifiers: $0,
                    isARepeat: false, keyCode: 0
                )
            }
            XCTAssertEqual(
                event.flatMap(KeyboardChainTail.input(for:)), input,
                "\(input.key) is declared surface-owned but the chain tail does not map it"
            )
        }
    }

    /// Dispatch parity: the router claims every catalog key in every app state, so none of them can
    /// reach the alert path, and it executes a menu command exactly when the context allows it.
    func testRouterClaimsEveryCatalogKeyInEveryAppState() {
        let empty = makeAppViewModel(engine: FakeRenderEngine())
        let withImage = makeAppViewModel(engine: FakeRenderEngine())
        withImage.sourceImage = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        for viewModel in [empty, withImage] {
            let router = KeyboardCommandRouter(viewModel: viewModel)
            for input in KeyboardShortcutCatalog.surfaceInputs {
                XCTAssertTrue(router.perform(input), "\(input.key) down")
                var up = input; up.phase = .up
                XCTAssertTrue(router.perform(up), "\(input.key) up")
                router.releaseHolds()
            }
            for (spec, key, modifiers, _) in menuSpecs {
                XCTAssertTrue(
                    router.perform(KeyInput(.character(String(key.character)), modifiers: modifiers)),
                    spec.action
                )
            }
        }
    }

    func testContextAvailabilityMatchesWhatTheRouterExecutes() {
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        let router = KeyboardCommandRouter(viewModel: viewModel)
        var context = KeyboardContext(viewModel)
        XCTAssertFalse(KeyboardCommand.toggleCrop.isAvailable(in: context))
        XCTAssertTrue(router.perform(KeyInput(.character("c"))))
        XCTAssertFalse(viewModel.isCropToolActive, "unavailable: claimed, not executed")

        viewModel.sourceImage = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        context = KeyboardContext(viewModel)
        XCTAssertTrue(KeyboardCommand.toggleCrop.isAvailable(in: context))
        XCTAssertTrue(router.perform(KeyInput(.character("c"))))
        XCTAssertTrue(viewModel.isCropToolActive)
        XCTAssertTrue(KeyboardContext(viewModel).cropActive)
    }

    func testMenusPartitionTheCatalog() {
        let grouped = [KeyboardShortcutSpec.Menu.photo, .tools, .view]
            .flatMap { KeyboardShortcutCatalog.menuItems(in: $0) }
        XCTAssertEqual(grouped.map(\.title).sorted(), menuSpecs.map(\.spec.action).sorted())
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
