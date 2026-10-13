import XCTest
import SwiftUI
import AppKit
import CoreImage
@testable import KromoraKit

/// The real `KeyboardSurface` inside a real window, driven by synthesized key events through
/// `NSApp.sendEvent`. `ProbeWindow.noResponder(for:)` is AppKit's "nobody claimed this key" hook —
/// the call that plays the system alert — so `unclaimed == 0` is the machine-checkable form of
/// "no boop" (KRMA-920). Whether the sound is actually silent is still confirmed by ear in the app.
@MainActor
final class KeyboardSurfaceWindowTests: TempDirectoryTestCase {

    private final class ProbeWindow: NSWindow {
        var unclaimed = 0
        override func noResponder(for eventSelector: Selector) {
            if eventSelector == #selector(NSResponder.keyDown(with:)) { unclaimed += 1 }
        }
    }

    @MainActor private final class MenuTarget: NSObject {
        let router: KeyboardCommandRouter
        init(router: KeyboardCommandRouter) { self.router = router }
        @objc func act(_ item: NSMenuItem) {
            router.perform(KeyInput(.character(item.keyEquivalent)))
        }
    }

    @Observable @MainActor fileprivate final class FocusDriver { var focusField = false }

    private struct Host: View {
        let router: KeyboardCommandRouter
        let viewModel: AppViewModel
        let driver: FocusDriver
        @State private var text = ""
        @FocusState private var fieldFocused: Bool
        var body: some View {
            VStack {
                TextField("Name", text: $text).focused($fieldFocused)
                Button("Button") {}
            }
            .keyboardSurface(router: router, viewModel: viewModel)
            .onChange(of: driver.focusField) { _, newValue in fieldFocused = newValue }
        }
    }

    private struct Fixture {
        let window: ProbeWindow
        let viewModel: AppViewModel
        let router: KeyboardCommandRouter
        let menuTarget: MenuTarget
        let driver: FocusDriver
    }

    private func makeFixture() async throws -> Fixture {
        _ = NSApplication.shared
        for name in ["a.png", "b.png", "c.png"] {
            try Fixtures.writeGradientPNG(width: 8, height: 8, named: name, in: tempDirectory)
        }
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        viewModel.collection.setSelection(at: 1)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        viewModel.sourceImage = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let router = KeyboardCommandRouter(viewModel: viewModel)

        // Mirrors `KromoraCommands`: a plain-letter menu key equivalent that calls the router.
        let target = MenuTarget(router: router)
        let main = NSMenu()
        let top = NSMenuItem(); main.addItem(top)
        let sub = NSMenu(title: "Tools"); top.submenu = sub
        let item = NSMenuItem(title: "Library", action: #selector(MenuTarget.act(_:)), keyEquivalent: "g")
        item.keyEquivalentModifierMask = []
        item.target = target
        sub.addItem(item)
        NSApp.mainMenu = main

        let driver = FocusDriver()
        let host = NSHostingView(rootView: Host(router: router, viewModel: viewModel, driver: driver))
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
        let window = ProbeWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        _ = window.makeFirstResponder(host)
        try await Task.sleep(for: .milliseconds(300))
        return Fixture(window: window, viewModel: viewModel, router: router, menuTarget: target, driver: driver)
    }

    private func key(
        _ chars: String, code: UInt16, in window: NSWindow,
        mods: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: mods, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: chars,
            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code
        )!
    }

    private func shiftZ(in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "Z",
            charactersIgnoringModifiers: "Z", isARepeat: false, keyCode: 6
        )!
    }

    private func send(_ event: NSEvent) { NSApp.sendEvent(event) }

    private var rightArrow: String { String(UnicodeScalar(NSRightArrowFunctionKey)!) }
    private var leftArrow: String { String(UnicodeScalar(NSLeftArrowFunctionKey)!) }

    func testSurfaceOwnsArrowsAndLettersReachTheMenuWithoutAlert() async throws {
        let f = try await makeFixture()
        defer { f.window.close() }

        send(key(rightArrow, code: 124, in: f.window, mods: [.numericPad, .function]))
        send(key(rightArrow, code: 124, in: f.window, mods: [.numericPad, .function], type: .keyUp))
        XCTAssertEqual(f.viewModel.collection.selectedIndex, 2)
        send(key(rightArrow, code: 124, in: f.window, mods: [.numericPad, .function]))
        XCTAssertEqual(f.viewModel.collection.selectedIndex, 2, "the last image is a claimed no-op")

        XCTAssertTrue(f.viewModel.navigation.isEdit)
        send(key("g", code: 5, in: f.window))
        XCTAssertTrue(f.viewModel.navigation.isGrid, "plain G arrives as a menu key equivalent")

        XCTAssertEqual(f.window.unclaimed, 0, "no owned key may fall through to the system alert")
    }

    func testTextFieldKeepsItsKeysAndNothingFires() async throws {
        let f = try await makeFixture()
        defer { f.window.close() }

        // Focus the field the way a click does: SwiftUI focus moves off the key surface.
        f.driver.focusField = true
        try await Task.sleep(for: .milliseconds(300))
        let field = try XCTUnwrap(Self.firstSubview(of: NSTextField.self, in: f.window.contentView!))
        XCTAssertTrue(f.window.firstResponder is NSText, "the field editor owns the keyboard")
        send(key("g", code: 5, in: f.window))
        send(key(leftArrow, code: 123, in: f.window, mods: [.numericPad, .function]))
        send(key(" ", code: 49, in: f.window))

        XCTAssertTrue(f.viewModel.navigation.isEdit, "typing G in a text field must not switch workspace")
        XCTAssertEqual(f.viewModel.collection.selectedIndex, 1, "caret arrows must not change photos")
        XCTAssertFalse(f.viewModel.isShowingOriginal, "Space in a text field is a space")
        let editor = f.window.fieldEditor(false, for: field) as? NSTextView
        XCTAssertEqual(editor?.string, " g", // Left moved the caret, then Space inserted before the g
                        "the field editor received the typed characters")
        XCTAssertEqual(f.window.unclaimed, 0)
    }

    /// Installs a main-menu ⌘Z / ⇧⌘Z that calls the production `UndoRedoRouting`, as the Edit menu does.
    @MainActor private final class UndoTarget: NSObject {
        /// Stands in for `NSApp.keyWindow`, which is nil while the test process is not active.
        weak var window: NSWindow?
        @objc func undo(_ item: NSMenuItem) { UndoRedoRouting.perform(.undo, in: window) }
        @objc func redo(_ item: NSMenuItem) { UndoRedoRouting.perform(.redo, in: window) }
    }

    private func installUndoMenu(_ target: UndoTarget) {
        let main = NSMenu()
        let top = NSMenuItem(); main.addItem(top)
        let sub = NSMenu(title: "Edit"); top.submenu = sub
        let undo = NSMenuItem(title: "Undo", action: #selector(UndoTarget.undo(_:)), keyEquivalent: "z")
        undo.target = target
        let redo = NSMenuItem(title: "Redo", action: #selector(UndoTarget.redo(_:)), keyEquivalent: "z")
        redo.keyEquivalent = "Z"
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = target
        sub.addItem(undo); sub.addItem(redo)
        NSApp.mainMenu = main
    }

    func testCommandZUndoesTextInAFieldAndThePhotoElsewhere() async throws {
        let f = try await makeFixture()
        defer { f.window.close() }
        let target = UndoTarget()
        target.window = f.window
        installUndoMenu(target)
        var undone = 0, redone = 0
        let tokens = [
            NotificationCenter.default.addObserver(forName: .undoEdit, object: nil, queue: nil) { _ in undone += 1 },
            NotificationCenter.default.addObserver(forName: .redoEdit, object: nil, queue: nil) { _ in redone += 1 },
        ]
        defer { tokens.forEach(NotificationCenter.default.removeObserver) }

        // Canvas focused: the photo edit is undone/redone.
        send(key("z", code: 6, in: f.window, mods: [.command]))
        send(shiftZ(in: f.window))
        XCTAssertEqual(undone, 1)
        XCTAssertEqual(redone, 1)

        // Text field editing: ⌘Z / ⇧⌘Z belong to the field editor's own undo manager.
        f.driver.focusField = true
        try await Task.sleep(for: .milliseconds(300))
        let field = try XCTUnwrap(Self.firstSubview(of: NSTextField.self, in: f.window.contentView!))
        let editor = try XCTUnwrap(f.window.fieldEditor(false, for: field) as? NSTextView)
        XCTAssertTrue(f.window.firstResponder === editor)
        editor.insertText("abc", replacementRange: editor.selectedRange())
        send(key("z", code: 6, in: f.window, mods: [.command]))
        send(shiftZ(in: f.window))
        XCTAssertEqual(undone, 1, "⌘Z in a text field must not undo the photo")
        XCTAssertEqual(redone, 1, "⇧⌘Z in a text field must not redo the photo")
    }

    private static func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews {
            if let match = firstSubview(of: type, in: sub) { return match }
        }
        return nil
    }
}
