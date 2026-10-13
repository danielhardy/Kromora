import XCTest
import SwiftUI
import AppKit
import CoreImage
@testable import KromoraKit

/// KRMA-966: the full shortcut inventory against every kind of first responder, driven through
/// `NSApp.sendEvent` in a real window. `ProbeWindow.noResponder(for:)` is the call that plays the
/// system alert, so `unclaimed` is empty exactly when no inventory key can beep. The menu bar is
/// rebuilt from `KeyboardShortcutCatalog` with the same enablement the app derives from
/// `KeyboardContext`, so the matrix exercises the catalog, the bindings and the router together.
/// Whether the running app is silent is still a by-ear check.
@MainActor
final class KeyboardInventoryMatrixTests: TempDirectoryTestCase {

    private final class ProbeWindow: NSWindow {
        var unclaimed = 0
        override func noResponder(for eventSelector: Selector) {
            if eventSelector == #selector(NSResponder.keyDown(with:)) { unclaimed += 1 }
        }
    }

    @MainActor private final class MenuTarget: NSObject {
        let router: KeyboardCommandRouter
        let viewModel: AppViewModel
        var commands: [String: KeyboardCommand] = [:]
        var autoFired = 0
        var pasteEditsFired = 0
        weak var window: NSWindow?
        init(router: KeyboardCommandRouter, viewModel: AppViewModel) {
            self.router = router
            self.viewModel = viewModel
        }
        @objc func act(_ item: NSMenuItem) {
            let mods = item.keyEquivalentModifierMask.contains(.shift) ? EventModifiers.shift : []
            router.perform(KeyInput(.character(item.keyEquivalent), modifiers: mods))
        }
        @objc func auto(_ item: NSMenuItem) { autoFired += 1 }
        @objc func pasteEdits(_ item: NSMenuItem) { pasteEditsFired += 1 }
        /// A standard Edit item has no target and walks the responder chain from the first
        /// responder. Doing that walk directly keeps the test independent of key-window state.
        @objc func edit(_ item: NSMenuItem) {
            _ = window?.firstResponder?.tryToPerform(item.representedObject as! Selector, with: item)
        }
        @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
            if item.action == #selector(auto(_:)) { return KeyboardContext(viewModel).canAutoAdjust }
            guard item.action == #selector(act(_:)),
                  let command = commands[item.title] else { return true }
            return command.isAvailable(in: KeyboardContext(viewModel))
        }
    }

    @Observable @MainActor fileprivate final class Values {
        var stepper = 5
        var text = ""
        var pick = 0
        var listPick: Int? = 0
        var focusField = false
    }

    /// An AppKit control as the toolbar and inspector use it. SwiftUI's own Button, menu Picker and
    /// Slider render as non-focusable proxies here, so these are the real `NSControl` responders.
    private struct NativeControl<V: NSView>: NSViewRepresentable {
        let make: () -> V
        init(_ make: @escaping () -> V) { self.make = make }
        func makeNSView(context: Context) -> V { make() }
        func updateNSView(_ nsView: V, context: Context) {}
    }

    private struct Host: View {
        let router: KeyboardCommandRouter
        let viewModel: AppViewModel
        @Bindable var values: Values
        @FocusState private var fieldFocused: Bool
        var body: some View {
            VStack {
                Picker("Workspace", selection: $values.pick) {
                    Text("Library").tag(0); Text("Edit").tag(1)
                }
                .pickerStyle(.segmented)
                NativeControl { () -> NSPopUpButton in
                    let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
                    popUp.addItems(withTitles: ["All", "Picks"])
                    return popUp
                }
                NativeControl { NSButton(title: "Button", target: nil, action: nil) }
                List(selection: $values.listPick) {
                    Text("One").tag(0); Text("Two").tag(1)
                }
                .frame(height: 60)
                TextField("Name", text: $values.text).focused($fieldFocused)
                NativeControl { NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil) }
                Stepper("Count", value: $values.stepper, in: 0...10)
            }
            .keyboardSurface(router: router, viewModel: viewModel)
            .onChange(of: values.focusField) { _, newValue in fieldFocused = newValue }
        }
    }

    private struct Fixture {
        let window: ProbeWindow
        let viewModel: AppViewModel
        let router: KeyboardCommandRouter
        let target: MenuTarget
        let values: Values
        let host: NSHostingView<Host>
    }

    private func makeFixture(withPhotos: Bool) async throws -> Fixture {
        _ = NSApplication.shared
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        if withPhotos {
            for name in ["a.png", "b.png", "c.png"] {
                try Fixtures.writeGradientPNG(width: 8, height: 8, named: name, in: tempDirectory)
            }
            viewModel.collection.loadFromFolder(tempDirectory)
            await viewModel.collection.scanCompletion()
            viewModel.collection.setSelection(at: 1)
            XCTAssertTrue(viewModel.navigate(to: .edit))
        }
        let router = KeyboardCommandRouter(viewModel: viewModel)
        let target = MenuTarget(router: router, viewModel: viewModel)
        NSApp.mainMenu = makeMenu(target: target)

        let values = Values()
        let host = NSHostingView(
            rootView: Host(router: router, viewModel: viewModel, values: values)
        )
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 420)
        let window = ProbeWindow(
            contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        target.window = window
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(host)
        try await Task.sleep(for: .milliseconds(400))
        if withPhotos {
            // Opening the selected photo resets the document asynchronously, so edit afterwards.
            viewModel.sourceImage = CIImage(color: .gray)
                .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
            viewModel.updateDocument { $0.adjustments = [.exposure(ev: 0.5)] }
        }
        return Fixture(
            window: window, viewModel: viewModel, router: router, target: target,
            values: values, host: host
        )
    }

    /// The menu bar as `KromoraCommands` builds it: catalog items, Shift-A Auto, Option-Command-V
    /// Paste Edits, and the standard Edit items that `KeyboardSurface` hooks with `onCommand`.
    private func makeMenu(target: MenuTarget) -> NSMenu {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let top = NSMenuItem(); main.addItem(top)
            let sub = NSMenu(title: title); top.submenu = sub
            return sub
        }
        for menu in [KeyboardShortcutSpec.Menu.photo, .tools, .view] {
            let sub = submenu(menu.rawValue)
            for binding in KeyboardShortcutCatalog.menuItems(in: menu) {
                let item = NSMenuItem(
                    title: binding.title, action: #selector(MenuTarget.act(_:)),
                    keyEquivalent: String(binding.key.character)
                )
                item.keyEquivalentModifierMask = binding.modifiers.contains(.shift) ? [.shift] : []
                item.target = target
                target.commands[binding.title] = binding.command
                sub.addItem(item)
            }
        }
        let file = submenu("File")
        let auto = NSMenuItem(title: "Auto", action: #selector(MenuTarget.auto(_:)), keyEquivalent: "A")
        auto.keyEquivalentModifierMask = [.shift]
        auto.target = target
        file.addItem(auto)
        let pasteEdits = NSMenuItem(
            title: "Paste Edits", action: #selector(MenuTarget.pasteEdits(_:)), keyEquivalent: "v"
        )
        pasteEdits.keyEquivalentModifierMask = [.command, .option]
        pasteEdits.target = target
        file.addItem(pasteEdits)

        let edit = submenu("Edit")
        for (title, selector, key) in [
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSResponder.selectAll(_:)), "a")
        ] {
            let item = NSMenuItem(title: title, action: #selector(MenuTarget.edit(_:)), keyEquivalent: key)
            item.representedObject = selector
            item.target = target
            edit.addItem(item)
        }
        return main
    }

    // MARK: Events

    private struct Stroke {
        let name: String
        let chars: String
        let code: UInt16
        var mods: NSEvent.ModifierFlags = []
        /// Space, Return, Escape and the arrows may legitimately belong to the responder itself.
        var isHold = false
    }

    private static func fn(_ scalar: Int) -> String { String(UnicodeScalar(scalar)!) }

    private static let arrowMods: NSEvent.ModifierFlags = [.numericPad, .function]

    /// The surface-owned half of the inventory.
    private static let surfaceStrokes: [Stroke] = [
        Stroke(name: "←", chars: fn(NSLeftArrowFunctionKey), code: 123, mods: arrowMods),
        Stroke(name: "→", chars: fn(NSRightArrowFunctionKey), code: 124, mods: arrowMods),
        Stroke(name: "↑", chars: fn(NSUpArrowFunctionKey), code: 126, mods: arrowMods),
        Stroke(name: "↓", chars: fn(NSDownArrowFunctionKey), code: 125, mods: arrowMods),
        Stroke(name: "⇧←", chars: fn(NSLeftArrowFunctionKey), code: 123, mods: arrowMods.union(.shift)),
        Stroke(name: "Space", chars: " ", code: 49, isHold: true),
        Stroke(name: "Return", chars: "\r", code: 36),
        Stroke(name: "Escape", chars: "\u{1b}", code: 53),
        Stroke(name: "Delete", chars: "\u{7f}", code: 51),
        Stroke(name: "Forward Delete", chars: fn(NSDeleteFunctionKey), code: 117, mods: [.function]),
        Stroke(name: "⌘\\", chars: "\\", code: 42, mods: .command, isHold: true)
    ]

    /// Every plain/Shift menu key in the catalog, plus Shift-A.
    private static var menuStrokes: [Stroke] {
        KeyboardShortcutCatalog.all.compactMap { spec in
            guard case .menuKey(_, let key, let modifiers, _) = spec.delivery else { return nil }
            return Stroke(
                name: spec.keys, chars: String(key.character), code: 0,
                mods: modifiers.contains(.shift) ? .shift : []
            )
        } + [Stroke(name: "⇧A", chars: "A", code: 0, mods: .shift)]
    }

    private static let editStrokes: [Stroke] = [
        Stroke(name: "⌘C", chars: "c", code: 8, mods: .command),
        Stroke(name: "⌘V", chars: "v", code: 9, mods: .command),
        Stroke(name: "⌘A", chars: "a", code: 0, mods: .command)
    ]

    private func event(_ stroke: Stroke, in window: NSWindow, type: NSEvent.EventType) -> NSEvent {
        NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: stroke.mods, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: stroke.chars,
            charactersIgnoringModifiers: stroke.chars, isARepeat: false, keyCode: stroke.code
        )!
    }

    private func send(_ stroke: Stroke, in window: NSWindow) {
        NSApp.sendEvent(event(stroke, in: window, type: .keyDown))
        NSApp.sendEvent(event(stroke, in: window, type: .keyUp))
    }

    private static func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews {
            if let match = firstSubview(of: type, in: sub) { return match }
        }
        return nil
    }

    // MARK: Matrix

    private enum Responder: String, CaseIterable {
        case canvas, workspacePicker, cullingPopup, button, list, textField, slider, stepper
    }

    private func focus(_ responder: Responder, in f: Fixture) throws {
        let root = try XCTUnwrap(f.window.contentView)
        let target: NSResponder
        switch responder {
        case .canvas: target = f.host
        case .workspacePicker: target = try XCTUnwrap(Self.firstSubview(of: NSSegmentedControl.self, in: root))
        case .cullingPopup: target = try XCTUnwrap(Self.firstSubview(of: NSPopUpButton.self, in: root))
        case .button:
            target = try XCTUnwrap(Self.firstSubview(of: NSButton.self, in: root) { button in
                !(button is NSPopUpButton) && button.title == "Button"
            })
        case .list: target = try XCTUnwrap(Self.firstSubview(of: NSTableView.self, in: root))
        case .textField: target = try XCTUnwrap(Self.firstSubview(of: NSTextField.self, in: root) { $0.isEditable })
        case .slider: target = try XCTUnwrap(Self.firstSubview(of: NSSlider.self, in: root))
        case .stepper: target = try XCTUnwrap(Self.firstSubview(of: NSStepper.self, in: root))
        }
        XCTAssertTrue(f.window.makeFirstResponder(target), "could not focus \(responder.rawValue)")
    }

    /// Keys that a text field or value editor deliberately keeps for itself.
    private static func isLeftToResponder(_ stroke: Stroke, _ responder: Responder) -> Bool {
        switch responder {
        case .textField: return true
        case .slider, .stepper: return stroke.chars.unicodeScalars.first.map {
            (NSUpArrowFunctionKey...NSRightArrowFunctionKey).contains(Int($0.value))
        } ?? false
        default: return false
        }
    }

    func testNoInventoryKeyReachesTheAlertPathInAnyResponderOrAppState() async throws {
        let strokes = Self.surfaceStrokes + Self.menuStrokes + Self.editStrokes
        var failures: [String] = []
        for withPhotos in [true, false] {
            let f = try await makeFixture(withPhotos: withPhotos)
            defer { f.window.close() }
            for responder in Responder.allCases {
                for stroke in strokes {
                    // The surface may have moved the app; keep the scenario comparable per key.
                    try focus(responder, in: f)
                    f.window.unclaimed = 0
                    send(stroke, in: f.window)
                    f.router.releaseHolds()
                    if f.window.unclaimed != 0, !Self.isLeftToResponder(stroke, responder) {
                        failures.append(
                            "\(withPhotos ? "edit" : "empty") | \(responder.rawValue) | \(stroke.name)"
                        )
                    }
                }
            }
        }
        XCTAssertEqual(failures, [], "inventory keys that reached noResponder(keyDown)")
    }

    // MARK: Text editing

    func testTextFieldKeepsLettersDigitsBracketsSpaceDeletionArrowsAndShiftA() async throws {
        let f = try await makeFixture(withPhotos: true)
        defer { f.window.close() }
        try focus(.textField, in: f)
        let field = try XCTUnwrap(Self.firstSubview(of: NSTextField.self, in: f.window.contentView!) { $0.isEditable })
        let editor = try XCTUnwrap(f.window.fieldEditor(false, for: field) as? NSTextView)
        let before = (f.viewModel.collection.selectedIndex, f.viewModel.navigation.isEdit)

        func type(_ chars: String, code: UInt16 = 0, mods: NSEvent.ModifierFlags = []) {
            send(Stroke(name: chars, chars: chars, code: code, mods: mods), in: f.window)
        }
        let typed = ["g", "c", "v", "q", "p", "x", "u", "e", "i", "b", "l", "r", "o", "h", "a", "/",
                     "0", "1", "2", "3", "4", "5", "[", "]", " "]
        typed.forEach { type($0) }
        type("A", mods: .shift)
        XCTAssertEqual(editor.string, typed.joined() + "A")

        // Backspace removes the "A", Left moves the caret instead of changing photos, and Forward
        // Delete then removes the character after the caret (the final space).
        type("\u{7f}", code: 51)
        XCTAssertEqual(editor.string, typed.joined())
        type(Self.fn(NSLeftArrowFunctionKey), code: 123, mods: Self.arrowMods)
        type(Self.fn(NSDeleteFunctionKey), code: 117, mods: [.function])
        XCTAssertEqual(editor.string, typed.joined().dropLast().description, "Forward Delete removed one character")
        let right = Self.fn(NSRightArrowFunctionKey)
        type(right, code: 124, mods: Self.arrowMods)
        type(Self.fn(NSUpArrowFunctionKey), code: 126, mods: Self.arrowMods)
        type(Self.fn(NSDownArrowFunctionKey), code: 125, mods: Self.arrowMods)

        XCTAssertEqual(f.viewModel.collection.selectedIndex, before.0, "arrows move the caret, not photos")
        XCTAssertEqual(f.viewModel.navigation.isEdit, before.1, "G/E typed into a field must not navigate")
        XCTAssertFalse(f.viewModel.isCropToolActive, "C typed into a field must not crop")
        XCTAssertFalse(f.viewModel.isSideBySide, "V typed into a field must not split the canvas")
        XCTAssertFalse(f.viewModel.isShowingOriginal)
        XCTAssertEqual(f.target.autoFired, 0, "Shift-A typed into a field must not run Auto")
        XCTAssertEqual(f.window.unclaimed, 0)
    }

    func testSliderAndStepperKeepTheirArrows() async throws {
        let f = try await makeFixture(withPhotos: true)
        defer { f.window.close() }
        let index = f.viewModel.collection.selectedIndex

        // Value editors edit with arrows (when AppKit's full keyboard access lets them), so the app
        // must leave those keys alone: no claim, no photo change.
        for responder in [Responder.slider, .stepper] {
            try focus(responder, in: f)
            for stroke in Self.surfaceStrokes.prefix(5) {
                f.window.unclaimed = 0
                send(stroke, in: f.window)
                XCTAssertEqual(f.window.unclaimed, 1, "\(responder) \(stroke.name) is left to the control")
                XCTAssertEqual(f.viewModel.collection.selectedIndex, index, "\(stroke.name) must not navigate")
            }
            // Other keys are still the app's.
            f.window.unclaimed = 0
            send(Self.surfaceStrokes[7], in: f.window)  // Escape
            XCTAssertEqual(f.window.unclaimed, 0)
        }
    }

    // MARK: Paste, hold and focus loss

    func testCommandVPastesEditsButATextFieldKeepsOrdinaryPaste() async throws {
        let f = try await makeFixture(withPhotos: true)
        defer { f.window.close() }
        let paste = Self.editStrokes[1]

        try focus(.canvas, in: f)
        f.viewModel.statusMessage = ""
        send(paste, in: f.window)
        XCTAssertEqual(f.viewModel.statusMessage, "Copy edits first", "⌘V reaches Paste Edits")
        XCTAssertEqual(f.window.unclaimed, 0)

        try focus(.textField, in: f)
        f.viewModel.statusMessage = ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("pasted", forType: .string)
        send(paste, in: f.window)
        XCTAssertEqual(f.viewModel.statusMessage, "", "a text field keeps ⌘V for the pasteboard")
        let field = try XCTUnwrap(Self.firstSubview(of: NSTextField.self, in: f.window.contentView!) { $0.isEditable })
        XCTAssertEqual((f.window.fieldEditor(false, for: field) as? NSTextView)?.string, "pasted")
    }

    func testCommandBackslashHoldRestoresWhenFocusOrWindowIsLost() async throws {
        let f = try await makeFixture(withPhotos: true)
        defer { f.window.close() }
        let hold = Self.surfaceStrokes[10]
        try focus(.canvas, in: f)

        // A bare backslash is not the hold key.
        NSApp.sendEvent(event(Stroke(name: "\\", chars: "\\", code: 42), in: f.window, type: .keyDown))
        XCTAssertFalse(f.viewModel.isShowingOriginal)

        NSApp.sendEvent(event(hold, in: f.window, type: .keyDown))
        XCTAssertTrue(f.viewModel.isShowingOriginal, "⌘\\ shows Original while held")
        XCTAssertTrue(f.router.backslashIsHeld)

        // Moving focus to a text field strands the key-up; the edited presentation must return.
        f.values.focusField = true
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(f.viewModel.isShowingOriginal, "focus loss restores the edit")
        XCTAssertFalse(f.router.backslashIsHeld)

        f.values.focusField = false
        try await Task.sleep(for: .milliseconds(300))
        try focus(.canvas, in: f)
        NSApp.sendEvent(event(hold, in: f.window, type: .keyDown))
        XCTAssertTrue(f.viewModel.isShowingOriginal)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: f.window)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(f.viewModel.isShowingOriginal, "losing key-window status restores the edit")
    }
}

private extension KeyboardInventoryMatrixTests {
    static func firstSubview<T: NSView>(
        of type: T.Type, in view: NSView, where predicate: (T) -> Bool
    ) -> T? {
        if let match = view as? T, predicate(match) { return match }
        for sub in view.subviews {
            if let match = firstSubview(of: type, in: sub, where: predicate) { return match }
        }
        return nil
    }
}
