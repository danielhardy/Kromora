import AppKit
import CoreImage
import SwiftUI
import XCTest

@testable import KromoraKit

/// KRMA-969: Esc and Return in the crop tool, driven through the real `ContentView` responder
/// chain with synthesized key events (not `router.handle`). `ProbeWindow.noResponder(for:)` is the
/// call that plays the alert.
@MainActor
final class CropKeyboardWindowTests: TempDirectoryTestCase {
    private final class ProbeWindow: NSWindow {
        var unclaimed = 0
        override func noResponder(for eventSelector: Selector) {
            if eventSelector == #selector(NSResponder.keyDown(with:)) { unclaimed += 1 }
        }
    }

    /// A responder that sends keys through the text-input system, as a text-aware SwiftUI or
    /// AppKit view does: Escape becomes `cancelOperation:` and Return `insertNewline:`, which
    /// travel the responder chain instead of arriving as a key-down.
    private final class TextInputStyleView: NSView {
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) { interpretKeyEvents([event]) }
        override func doCommand(by selector: Selector) {
            if !tryToPerform(selector, with: nil) { window?.noResponder(for: #selector(NSResponder.keyDown(with:))) }
        }
    }

    private struct Fixture {
        let window: ProbeWindow
        let viewModel: AppViewModel
    }

    private func makeFixture() async throws -> Fixture {
        _ = NSApplication.shared
        for name in ["a.png", "b.png"] {
            try Fixtures.writeGradientPNG(width: 8, height: 8, named: name, in: tempDirectory)
        }
        let viewModel = makeAppViewModel(engine: FakeRenderEngine())
        viewModel.collection.loadFromFolder(tempDirectory)
        await viewModel.collection.scanCompletion()
        viewModel.collection.setSelection(at: 0)
        XCTAssertTrue(viewModel.navigate(to: .edit))
        viewModel.sourceImage = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))

        let hosting = NSHostingView(rootView: ContentView(viewModel: viewModel))
        let window = ProbeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = window.contentView?.bounds ?? .zero
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(500))
        return Fixture(window: window, viewModel: viewModel)
    }

    private func send(_ chars: String, code: UInt16, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            NSApp.sendEvent(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code
            )!)
        }
    }

    private static func focusable(in view: NSView) -> [NSView] {
        var found = view.acceptsFirstResponder ? [view] : []
        for sub in view.subviews { found += focusable(in: sub) }
        return found
    }

    private static let keys: [(name: String, chars: String, code: UInt16, applies: Bool)] = [
        ("Escape", "\u{1b}", 53, false), ("Return", "\r", 36, true)
    ]

    /// Every focusable view in the window (the SwiftUI key-view proxy, toolbar and inspector
    /// controls, sliders, pickers), the window and the hosting view as first responder.
    func testEscapeCancelsAndReturnAppliesCropFromEveryResponderState() async throws {
        let f = try await makeFixture()
        defer { f.window.close() }
        let root = try XCTUnwrap(f.window.contentView)
        var failures: [String] = []

        for key in Self.keys {
            f.viewModel.beginCrop()
            try await Task.sleep(for: .milliseconds(300))
            var states: [(String, NSResponder)] = [("entry", try XCTUnwrap(f.window.firstResponder))]
            states += Self.focusable(in: root).map { (String(describing: type(of: $0)), $0) }
            states += [("window", f.window), ("hosting view", root)]
            for item in f.window.toolbar?.items ?? [] {
                guard let view = item.view else { continue }
                states.append(("toolbar item", view))
                states += Self.focusable(in: view).map { ("toolbar \(type(of: $0))", $0) }
            }
            for (state, responder) in states {
                if !f.viewModel.isCropToolActive { f.viewModel.beginCrop() }
                _ = f.window.makeFirstResponder(responder)
                f.window.unclaimed = 0
                send(key.chars, code: key.code, in: f.window)
                if f.viewModel.isCropToolActive || f.window.unclaimed != 0 {
                    failures.append("\(key.name) | \(state) | active=\(f.viewModel.isCropToolActive) beeps=\(f.window.unclaimed)")
                }
            }
            if f.viewModel.isCropToolActive { f.viewModel.cancelCrop() }
        }
        XCTAssertEqual(failures, [])
    }

    func testTextInputStyleResponderDeliversEscapeAndReturnToTheTail() async throws {
        let f = try await makeFixture()
        defer { f.window.close() }
        let root = try XCTUnwrap(f.window.contentView)
        let view = TextInputStyleView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        root.addSubview(view)

        for key in Self.keys {
            f.viewModel.beginCrop()
            f.viewModel.updateCropDraft(CGRect(x: 0.1, y: 0.2, width: 0.7, height: 0.6))
            XCTAssertTrue(f.window.makeFirstResponder(view))
            f.window.unclaimed = 0
            send(key.chars, code: key.code, in: f.window)
            XCTAssertFalse(f.viewModel.isCropToolActive, "\(key.name) must end the crop")
            XCTAssertEqual(f.window.unclaimed, 0, "\(key.name) must not beep")
            XCTAssertEqual(!f.viewModel.document.crop.isIdentity, key.applies, "\(key.name) applies=\(key.applies)")
            f.viewModel.resetCrop()
            f.viewModel.updateDocument { $0.crop = .neutral }
        }
    }
}
