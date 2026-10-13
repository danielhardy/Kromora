import XCTest
import SwiftUI
import AppKit

/// KRMA-921 probe: which key-handling mechanism avoids AppKit's alert beep without stealing text.
/// `NSWindow.noResponderFor(_:)` is AppKit's documented hook for "no responder handled this
/// selector"; its default implementation is what plays the system alert for `keyDown:`.
@MainActor
final class KeyRoutingProbeTests: XCTestCase {

    final class ProbeWindow: NSWindow {
        var unclaimed: [String] = []
        override func noResponder(for eventSelector: Selector) {
            if eventSelector == #selector(NSResponder.keyDown(with:)) { unclaimed.append("keyDown") }
            // Deliberately not calling super: super would beep.
        }
    }

    final class KeyView: NSView {
        var handled: [String] = []
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            handled.append(event.charactersIgnoringModifiers ?? "")
        }
    }

    final class MenuProbe: NSObject {
        var fired = 0
        var enabled = true
        @objc func act(_ sender: Any?) { fired += 1 }
        @objc func validateMenuItem(_ item: NSMenuItem) -> Bool { enabled }
    }

    private func key(_ chars: String, code: UInt16, in window: NSWindow,
                     mods: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: mods, timestamp: 0,
                         windowNumber: window.windowNumber, context: nil, characters: chars,
                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    private func makeWindow(_ content: NSView) -> ProbeWindow {
        let w = ProbeWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                            styleMask: [.titled], backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.contentView = content
        w.makeKeyAndOrderFront(nil)
        return w
    }

    private func installMenu(key: String, probe: MenuProbe, mods: NSEvent.ModifierFlags = []) {
        let main = NSMenu()
        let top = NSMenuItem(); main.addItem(top)
        let sub = NSMenu(title: "T"); top.submenu = sub
        let item = NSMenuItem(title: "Probe", action: #selector(MenuProbe.act(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = mods
        item.target = probe
        sub.addItem(item)
        NSApp.mainMenu = main
    }

    private func send(_ e: NSEvent) { NSApp.sendEvent(e) }

    func testProbe() {
        _ = NSApplication.shared
        var report: [String] = []

        // 1. Controls with no handler: does 'c' reach noResponderFor?
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let button = NSButton(title: "B", target: nil, action: nil)
        let seg = NSSegmentedControl(labels: ["a", "b"], trackingMode: .selectOne, target: nil, action: nil)
        let pop = NSPopUpButton(frame: .zero, pullsDown: false); pop.addItems(withTitles: ["x", "y"])
        let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
        let field = NSTextField(string: "")
        let keyView = KeyView()
        for v in [button, seg, pop, slider, field, keyView] as [NSView] {
            v.frame = NSRect(x: 0, y: 0, width: 80, height: 24); stack.addSubview(v)
        }
        let w = makeWindow(stack)
        NSApp.mainMenu = NSMenu()

        func run(_ name: String, _ responder: NSResponder, code: UInt16 = 8, chars: String = "c") {
            w.unclaimed.removeAll(); keyView.handled.removeAll()
            XCTAssertTrue(w.makeFirstResponder(responder), name)
            send(key(chars, code: code, in: w))
            report.append("[\(name)] '\(chars)' no menu: unclaimed(beep)=\(w.unclaimed.count) keyView.handled=\(keyView.handled.count)")
        }
        run("NSButton", button); run("NSSegmentedControl", seg); run("NSPopUpButton", pop)
        run("NSSlider", slider); run("KeyView", keyView)
        run("NSButton arrow", button, code: 124, chars: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        run("KeyView arrow", keyView, code: 124, chars: String(UnicodeScalar(NSRightArrowFunctionKey)!))

        // 2. Plain-letter menu key equivalent: does it fire from each state?
        let probe = MenuProbe()
        installMenu(key: "c", probe: probe)
        for (name, r) in [("NSButton", button), ("NSSegmentedControl", seg), ("NSPopUpButton", pop),
                          ("NSSlider", slider), ("KeyView", keyView)] as [(String, NSResponder)] {
            probe.fired = 0; w.unclaimed.removeAll()
            _ = w.makeFirstResponder(r)
            send(key("c", code: 8, in: w))
            report.append("[menu 'c' | \(name)] fired=\(probe.fired) unclaimed(beep)=\(w.unclaimed.count)")
        }
        // 3. Text field editing: does the plain-letter menu item steal typing?
        probe.fired = 0; w.unclaimed.removeAll()
        _ = w.makeFirstResponder(field)
        send(key("c", code: 8, in: w))
        report.append("[menu 'c' | NSTextField editing] fired=\(probe.fired) unclaimed=\(w.unclaimed.count) text='\(field.stringValue)' editorText='\((w.fieldEditor(false, for: field) as? NSTextView)?.string ?? "")'")
        // shift-letter
        installMenu(key: "A", probe: probe, mods: [.shift])
        probe.fired = 0
        send(key("A", code: 0, in: w, mods: .shift))
        report.append("[menu ⇧A | NSTextField editing] fired=\(probe.fired)")
        // 4. Disabled menu item
        installMenu(key: "c", probe: probe); probe.enabled = false; probe.fired = 0; w.unclaimed.removeAll()
        _ = w.makeFirstResponder(keyView); keyView.handled.removeAll()
        send(key("c", code: 8, in: w))
        report.append("[disabled menu 'c' | KeyView] fired=\(probe.fired) unclaimed=\(w.unclaimed.count) keyView.handled=\(keyView.handled.count)")
        _ = w.makeFirstResponder(button); w.unclaimed.removeAll()
        send(key("c", code: 8, in: w))
        report.append("[disabled menu 'c' | NSButton] fired=\(probe.fired) unclaimed=\(w.unclaimed.count)")

        func line(_ prefix: String) -> String { report.first { $0.hasPrefix(prefix) } ?? "MISSING \(prefix)" }
        // Unclaimed plain keys on non-text controls reach AppKit's beep path (the reported bug).
        XCTAssertTrue(line("[NSButton] 'c'").contains("unclaimed(beep)=1"))
        XCTAssertTrue(line("[NSSegmentedControl] 'c'").contains("unclaimed(beep)=1"))
        XCTAssertTrue(line("[NSSlider] 'c'").contains("unclaimed(beep)=1"))
        XCTAssertTrue(line("[NSButton arrow]").contains("unclaimed(beep)=1"))
        // A key view as first responder claims plain keys and arrows.
        XCTAssertTrue(line("[KeyView] 'c'").contains("keyView.handled=1"))
        XCTAssertTrue(line("[KeyView arrow]").contains("keyView.handled=1"))
        // A plain-letter menu key equivalent is AppKit's last chance before the beep: it fires from
        // button-like controls with no beep...
        for name in ["NSButton", "NSSegmentedControl", "NSSlider"] {
            XCTAssertTrue(line("[menu 'c' | \(name)]").contains("fired=1 unclaimed(beep)=0"), name)
        }
        // ...and never steals typing from an editing text field (also for Shift+letter).
        XCTAssertTrue(line("[menu 'c' | NSTextField editing]").contains("fired=0"))
        XCTAssertTrue(line("[menu 'c' | NSTextField editing]").contains("text='c'"))
        XCTAssertTrue(line("[menu ⇧A | NSTextField editing]").contains("fired=0"))
        // A disabled menu item still swallows the key (no beep).
        XCTAssertTrue(line("[disabled menu 'c' | NSButton]").contains("unclaimed=0"))
        w.close()
    }

    // MARK: SwiftUI onKeyPress probe

    final class Box: ObservableObject { var presses: [String] = []; var result: KeyPress.Result = .handled }

    struct Surface: View {
        let box: Box
        @FocusState private var focused: Bool
        var body: some View {
            VStack {
                Color.clear.frame(width: 100, height: 40)
                    .focusable().focused($focused).focusEffectDisabled()
                    .onKeyPress(phases: .all) { press in
                        box.presses.append("\(press.characters)/\(press.phase)")
                        return box.result
                    }
                Button("Btn") {}
                Picker("p", selection: .constant(0)) { Text("a").tag(0); Text("b").tag(1) }.pickerStyle(.segmented)
            }
            .onAppear { focused = true }
        }
    }

    func testSwiftUIOnKeyPress() async throws {
        _ = NSApplication.shared
        NSApp.mainMenu = NSMenu()
        for result in [KeyPress.Result.handled, .ignored] {
            let box = Box(); box.result = result
            let host = NSHostingView(rootView: Surface(box: box))
            host.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
            let w = makeWindow(host)
            _ = w.makeFirstResponder(host)
            try await Task.sleep(for: .milliseconds(300))
            var out = "[onKeyPress \(result == .handled ? "handled" : "ignored") | surface focused] firstResponder=\(String(describing: type(of: w.firstResponder!)))"
            w.unclaimed.removeAll()
            send(key("c", code: 8, in: w)); send(key("c", code: 8, in: w, type: .keyUp))
            try await Task.sleep(for: .milliseconds(100))
            out += " presses=\(box.presses) unclaimed(beep)=\(w.unclaimed.count)"
            if result == .handled {
                XCTAssertEqual(box.presses, ["c/.down", "c/.up"], out)
                XCTAssertEqual(w.unclaimed.count, 0, out)
            } else {
                XCTAssertEqual(w.unclaimed.count, 1, "an .ignored key reaches the beep path: " + out)
            }
            w.close()
        }
    }

    func testArrowMenuEquivalent() {
        _ = NSApplication.shared
        let stack = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let button = NSButton(title: "B", target: nil, action: nil)
        let seg = NSSegmentedControl(labels: ["a", "b"], trackingMode: .selectOne, target: nil, action: nil)
        let pop = NSPopUpButton(frame: .zero, pullsDown: false); pop.addItems(withTitles: ["x", "y"])
        let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
        let field = NSTextField(string: "abc")
        for v in [button, seg, pop, slider, field] as [NSView] { v.frame = NSRect(x: 0, y: 0, width: 80, height: 24); stack.addSubview(v) }
        let w = makeWindow(stack)
        let probe = MenuProbe()
        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        installMenu(key: right, probe: probe)
        for (name, r) in [("NSButton", button), ("NSSegmentedControl", seg), ("NSPopUpButton", pop),
                          ("NSSlider", slider), ("NSTextField", field)] as [(String, NSResponder)] {
            probe.fired = 0; w.unclaimed.removeAll()
            _ = w.makeFirstResponder(r)
            let v0 = slider.doubleValue, s0 = seg.selectedSegment
            send(key(right, code: 124, in: w, mods: [.numericPad, .function]))
            _ = (v0, s0)
            // Arrow menu key equivalents fire from every control *including* an editing text field,
            // so arrows cannot be menu-only: they would steal caret movement.
            XCTAssertEqual(probe.fired, 1, name)
            XCTAssertEqual(w.unclaimed.count, 0, name)
        }
        w.close()
    }

    /// Command-modified keys: does a SwiftUI surface see ⌘C through `.onKeyPress` when the standard
    /// Copy menu item exists but is disabled (no responder implements `copy:`)?
    func testCommandKeyReachesOnKeyPressWithDisabledCopyMenuItem() async throws {
        _ = NSApplication.shared
        let probe = MenuProbe(); probe.enabled = false
        installMenu(key: "c", probe: probe, mods: .command)
        let box = Box()
        let host = NSHostingView(rootView: Surface(box: box))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        let w = makeWindow(host)
        _ = w.makeFirstResponder(host)
        try await Task.sleep(for: .milliseconds(300))
        send(key("c", code: 8, in: w, mods: .command))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(box.presses, [], "a disabled ⌘C menu item swallows the key before SwiftUI sees it")
        XCTAssertEqual(probe.fired, 0)
        w.close()
    }

    struct Bare: View { var body: some View { Color.clear.frame(width: 100, height: 40) } }
    struct Focusable: View {
        @FocusState private var f: Bool
        var body: some View { Color.clear.frame(width: 100, height: 40).focusable().focused($f).focusEffectDisabled().onAppear { f = true } }
    }
    struct Ignoring: View {
        @FocusState private var f: Bool
        var body: some View { Color.clear.frame(width: 100, height: 40).focusable().focused($f).focusEffectDisabled().onKeyPress(phases: .all) { _ in .ignored }.onAppear { f = true } }
    }

    struct IgnoringMod: ViewModifier {
        @FocusState private var f: Bool
        func body(content: Content) -> some View {
            content.focusable().focused($f).focusEffectDisabled().onKeyPress(phases: .all) { _ in .ignored }.onAppear { f = true }
        }
    }

    func testMenuKeyEquivalentIsTheFallbackForAHostingViewFirstResponder() async throws {
        _ = NSApplication.shared
        func run(_ name: String, _ view: some View) async throws {
            let probe = MenuProbe()
            installMenu(key: "c", probe: probe)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
            let w = makeWindow(host)
            _ = w.makeFirstResponder(host)
            try await Task.sleep(for: .milliseconds(300))
            send(key("c", code: 8, in: w))
            // A SwiftUI hosting view as first responder falls back to the menu key equivalent —
            // before the alert — whether or not the surface handles keys of its own.
            XCTAssertEqual(probe.fired, 1, name)
            XCTAssertEqual(w.unclaimed.count, 0, name)
            w.close()
        }
        try await run("bare", Bare())
        try await run("focusable", Focusable())
        try await run("onKeyPress ignored", Ignoring())
        try await run("ignored + TextField/Button", VStack { TextField("t", text: .constant("")); Button("b") {} }.modifier(IgnoringMod()))
        try await run("ignored + onCopyCommand", Color.clear.frame(width: 100, height: 40).modifier(IgnoringMod()).onCopyCommand { [] })
        try await run("ignored + onCommand selectAll", Color.clear.frame(width: 100, height: 40).modifier(IgnoringMod()).onCommand(#selector(NSResponder.selectAll(_:))) {})
    }
}
