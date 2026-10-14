import SwiftUI

// Keyboard routing (KRMA-920, KRMA-966). Kromora has no `NSEvent` monitor: the responder chain
// decides who owns a key, and the app claims the keys it owns explicitly.
//
//  * Plain letters, digits, brackets and Shift-letters are menu key equivalents
//    (`KromoraCommands`). AppKit offers them to the focused control first — so text fields and
//    value editors keep typing — and falls back to them *before* the system alert.
//  * Arrows, Space, Return, Escape, Delete and the hold-to-compare gestures reach
//    `KeyboardChainTail`, a responder installed at the end of the window's chain. Whatever the first
//    responder is — the canvas, a toolbar picker, a popup, a button, a list — a key it does not
//    consume arrives there, and the tail claims it (an intentional no-op included) instead of
//    letting AppKit play the alert. Text input and value editors are asked first, so they keep
//    their keys.
//  * Command-C, Command-V and Command-A use the standard Edit-menu commands (`onCopyCommand`,
//    `onCommand`), so a focused text field keeps ordinary copy, paste and select-all.

/// The router that menu-bar commands call, published per scene so `KromoraCommands` can reach the
/// window's view model from outside the view hierarchy.
extension FocusedValues {
    @Entry var keyboardRouter: KeyboardCommandRouter?
    /// Editor state that decides menu enablement; published alongside the router.
    @Entry var keyboardContext: KeyboardContext?
    /// File/Edit command enablement and Undo/Redo titles for the focused window.
    @Entry var menuAvailability: MenuCommandAvailability?
}

struct KeyboardSurface: ViewModifier {
    let router: KeyboardCommandRouter
    let viewModel: AppViewModel
    @FocusState private var isSurfaceFocused: Bool
    @State private var window = WindowBox()

    init(router: KeyboardCommandRouter, viewModel: AppViewModel) {
        self.router = router
        self.viewModel = viewModel
    }

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($isSurfaceFocused)
            .onCopyCommand {
                // Command-C opens Selective Copy for the open photo; nothing goes on the pasteboard.
                guard viewModel.sourceImage != nil else { return [] }
                viewModel.presentSelectiveCopyDialog()
                return []
            }
            // Escape as the text-input system's cancel command (see `KeyboardChainTail`).
            .onExitCommand { router.perform(KeyInput(.escape)) }
            .onCommand(#selector(NSResponder.selectAll(_:))) {
                if viewModel.navigation.isGrid { viewModel.selectAllInGrid() }
            }
            // Command-V pastes edits. It must be a standard Paste command rather than a key
            // handler: a menu item with no responder to enable it swallows Command-V before the
            // surface sees it, while a focused text field's own `paste:` still comes first.
            .onCommand(#selector(NSText.paste(_:))) {
                guard !KeyboardCommandRouter.isModalPresented(viewModel) else { return }
                viewModel.pasteEdits()
            }
            .background(WindowReader(box: window, router: router))
            .focusedSceneValue(\.keyboardRouter, router)
            .focusedSceneValue(\.keyboardContext, KeyboardContext(viewModel))
            .focusedSceneValue(\.menuAvailability, MenuCommandAvailability(viewModel))
            .onAppear { isSurfaceFocused = true }
            // A hold ends with its key-up, but that key-up goes elsewhere once focus leaves the
            // surface or the window stops being key. Restore the edited presentation then.
            .onChange(of: isSurfaceFocused) { _, focused in
                if !focused { router.releaseHolds() }
            }
            // A text field taking first responder also strands the key-up. SwiftUI focus state does
            // not always reflect that, so check the AppKit responder whenever the window updates.
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didUpdateNotification)) { note in
                guard router.isHolding, note.object as AnyObject? === window.window,
                      KeyboardOwnership.textInputOwnsKeyboard(window.window?.firstResponder)
                else { return }
                router.releaseHolds()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
                if note.object as AnyObject? === window.window { router.releaseHolds() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                router.releaseHolds()
            }
    }
}

extension View {
    func keyboardSurface(router: KeyboardCommandRouter, viewModel: AppViewModel) -> some View {
        modifier(KeyboardSurface(router: router, viewModel: viewModel))
    }
}

/// Who owns a key when a native control has first-responder status. Text input and value editors
/// keep the keys they edit with; everything else is the app's. This is the whole of the focus
/// policy — it replaces the monitor's per-key `NSControl` guesses.
enum KeyboardOwnership {
    /// A field editor (`NSText`) or text field: it owns every key.
    static func textInputOwnsKeyboard(_ responder: NSResponder?) -> Bool {
        responder is NSText || responder is NSTextField
    }

    /// Sliders, steppers and combo boxes edit a value with the arrow keys. Segmented controls,
    /// pop-up menus, buttons and lists do not — those arrows are photo/Look navigation.
    static func valueEditingControlOwnsArrows(_ responder: NSResponder?) -> Bool {
        responder is NSSlider || responder is NSStepper || responder is NSComboBox
    }

    /// Whether the app may claim `key` while `firstResponder` is focused. By the time a key reaches
    /// the responder-chain tail the control had its chance and passed, so only text input (every
    /// key) and value editors (arrows) are reserved.
    static func surfaceOwns(_ key: KeyInput.Key, firstResponder: NSResponder?) -> Bool {
        if textInputOwnsKeyboard(firstResponder) { return false }
        if case .arrow = key { return !valueEditingControlOwnsArrows(firstResponder) }
        return true
    }
}

/// The window that owns the surface, so focus is resolved from the right window rather than
/// whichever happens to be key during a transition.
@MainActor
final class WindowBox {
    weak var window: NSWindow?
}

private struct WindowReader: NSViewRepresentable {
    let box: WindowBox
    let router: KeyboardCommandRouter

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.box = box
        view.tail = KeyboardChainTail(router: router)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ReaderView: NSView {
        var box: WindowBox?
        var tail: KeyboardChainTail?
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil { tail?.uninstall() }
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box?.window = window
            if let window { tail?.install(in: window) }
        }
    }
}

/// The last responder in the window's chain. A key press that the first responder and everything
/// above it declined arrives here; the tail hands it to `KeyboardCommandRouter` and, when the app
/// does not own it either, passes it on exactly as AppKit would have (alert included).
@MainActor
final class KeyboardChainTail: NSResponder {
    private let router: KeyboardCommandRouter
    private weak var window: NSWindow?

    init(router: KeyboardCommandRouter) {
        self.router = router
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    func install(in window: NSWindow) {
        guard self.window !== window else { return }
        uninstall()
        self.window = window
        nextResponder = window.nextResponder
        window.nextResponder = self
    }

    func uninstall() {
        if let window, window.nextResponder === self { window.nextResponder = nextResponder }
        nextResponder = nil
        window = nil
    }

    override func keyDown(with event: NSEvent) {
        if claims(event) { return }
        if let nextResponder {
            nextResponder.keyDown(with: event)
        } else {
            window?.noResponder(for: #selector(NSResponder.keyDown(with:)))
        }
    }

    override func keyUp(with event: NSEvent) {
        if claims(event) { return }
        nextResponder?.keyUp(with: event)
    }

    // A first responder that routes keys through the text-input system (`interpretKeyEvents`)
    // turns Return into this editing command instead of passing the key down the chain. It walks
    // the responder chain to this tail, which hands it to the router so the crop tool still
    // applies; an unclaimed one continues to AppKit unchanged. Escape's `cancelOperation:` stops
    // at `NSWindow`, ahead of the tail, so `KeyboardSurface` takes it with `onExitCommand`.
    override func insertNewline(_ sender: Any?) {
        if !performCommand(.return) { nextResponder?.insertNewline(sender) }
    }

    private func performCommand(_ key: KeyInput.Key) -> Bool {
        guard KeyboardOwnership.surfaceOwns(key, firstResponder: window?.firstResponder) else { return false }
        return router.perform(KeyInput(key))
    }

    private func claims(_ event: NSEvent) -> Bool {
        guard let input = Self.input(for: event),
              KeyboardOwnership.surfaceOwns(input.key, firstResponder: window?.firstResponder)
        else { return false }
        return router.perform(input)
    }

    /// Maps a key event onto the router's vocabulary; nil for keys the app has no use for.
    static func input(for event: NSEvent) -> KeyInput? {
        guard event.type == .keyDown || event.type == .keyUp,
              let characters = event.charactersIgnoringModifiers,
              let scalar = characters.unicodeScalars.first else { return nil }
        let key: KeyInput.Key
        switch Int(scalar.value) {
        case NSLeftArrowFunctionKey: key = .arrow(.left)
        case NSRightArrowFunctionKey: key = .arrow(.right)
        case NSUpArrowFunctionKey: key = .arrow(.up)
        case NSDownArrowFunctionKey: key = .arrow(.down)
        case NSDeleteFunctionKey: key = .forwardDelete
        case 0x7F: key = .delete
        case 0x0D, 0x03: key = .return
        case 0x1B: key = .escape
        case 0x20: key = .space
        default:
            key = .character(characters.lowercased())
        }
        var modifiers: EventModifiers = []
        let flags = event.modifierFlags
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return KeyInput(
            key, modifiers: modifiers, phase: event.type == .keyUp ? .up : .down,
            isRepeat: event.type == .keyDown && event.isARepeat
        )
    }
}
