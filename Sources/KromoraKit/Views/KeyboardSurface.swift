import SwiftUI

// Keyboard routing (KRMA-920). Kromora has no `NSEvent` monitor: the responder chain decides who
// owns a key, and the app claims the keys it owns explicitly.
//
//  * Plain letters, digits, brackets and Shift-letters are menu key equivalents
//    (`KromoraCommands`). AppKit offers them to the focused control first — so text fields and
//    value editors keep typing — and falls back to them *before* the system alert.
//  * Arrows, Space, Return, Escape, Delete and the hold-to-compare gestures arrive here, through
//    `.onKeyPress(phases: .all)` on a focusable root. Returning `.handled` is what keeps AppKit
//    from playing the alert; `.ignored` hands the key on (to the menu bar, or to the alert if
//    nothing owns it).
//  * Command-C and Command-A use the standard Edit-menu commands (`onCopyCommand`,
//    `onCommand(selectAll:)`), so a focused text field keeps ordinary copy and select-all.

/// The router that menu-bar commands call, published per scene so `KromoraCommands` can reach the
/// window's view model from outside the view hierarchy.
extension FocusedValues {
    @Entry var keyboardRouter: KeyboardCommandRouter?
}

struct KeyboardSurface: ViewModifier {
    let router: KeyboardCommandRouter
    let viewModel: AppViewModel
    @FocusState private var isSurfaceFocused: Bool
    @State private var window = WindowBox()

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($isSurfaceFocused)
            .onKeyPress(phases: .all) { press in
                guard let input = Self.input(
                    key: press.key, modifiers: press.modifiers, phase: press.phase
                ) else { return .ignored }
                // SwiftUI offers keys to this ancestor even while a text field or slider below it
                // has focus, so ask the responder chain who owns the key before claiming it.
                let responder = window.window?.firstResponder
                guard KeyboardOwnership.surfaceOwns(input.key, firstResponder: responder) else {
                    return .ignored
                }
                return router.perform(input) ? .handled : .ignored
            }
            .onCopyCommand {
                // Command-C opens Selective Copy for the open photo; nothing goes on the pasteboard.
                guard viewModel.sourceImage != nil else { return [] }
                viewModel.presentSelectiveCopyDialog()
                return []
            }
            .onCommand(#selector(NSResponder.selectAll(_:))) {
                if viewModel.navigation.isGrid { viewModel.collection.selectAll() }
            }
            .background(WindowReader(box: window))
            .focusedSceneValue(\.keyboardRouter, router)
            .onAppear { isSurfaceFocused = true }
    }

    /// Maps a SwiftUI key press onto the keys this surface owns. Letters are intentionally absent:
    /// they are menu key equivalents.
    static func input(
        key pressedKey: KeyEquivalent, modifiers: EventModifiers, phase: KeyPress.Phases
    ) -> KeyInput? {
        let key: KeyInput.Key
        switch pressedKey {
        case .leftArrow: key = .arrow(.left)
        case .rightArrow: key = .arrow(.right)
        case .upArrow: key = .arrow(.up)
        case .downArrow: key = .arrow(.down)
        case .space: key = .space
        case .return: key = .return
        case .escape: key = .escape
        case .delete: key = .delete
        case .deleteForward: key = .forwardDelete
        case KeyEquivalent("\\"): key = .character("\\")
        default: return nil
        }
        return KeyInput(key, modifiers: modifiers, phase: phase == .up ? .up : .down)
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

    static func surfaceOwns(_ key: KeyInput.Key, firstResponder: NSResponder?) -> Bool {
        if textInputOwnsKeyboard(firstResponder) { return false }
        switch key {
        case .arrow:
            return !valueEditingControlOwnsArrows(firstResponder)
        case .space, .return:
            // A focused button, picker or menu activates with Space/Return.
            return !(firstResponder is NSControl)
        default:
            return true
        }
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

    func makeNSView(context: Context) -> NSView {
        let view = ReaderView()
        view.box = box
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ReaderView: NSView {
        var box: WindowBox?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box?.window = window
        }
    }
}
