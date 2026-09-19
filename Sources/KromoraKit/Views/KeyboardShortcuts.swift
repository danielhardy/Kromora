import SwiftUI
import AppKit

//
// SwiftUI's `.onKeyPress` modifier only fires when the modified view (or a
// descendant) has focus. Inside a NavigationSplitView the sidebar list eats
// focus when clicked and the detail pane has nothing focusable by default, so
// `.onKeyPress` was effectively never firing. We use an NSEvent local monitor
// instead, which catches every key event at the window level regardless of
// which subview has focus. Menu shortcuts (⌘-anything) still go through the
// standard menu system — we explicitly let those events pass through.

struct KeyboardShortcuts: ViewModifier {
    @ObservedObject var viewModel: AppViewModel

    func body(content: Content) -> some View {
        content.background(KeyMonitorAnchor(viewModel: viewModel))
    }
}

/// Installs the local event monitor once the hosting window exists, and reinstalls it whenever
/// that window becomes key. Local monitors run most-recent-first; SwiftUI pickers, buttons, and
/// scroll views register after a SwiftUI `onAppear`, so a one-shot install loses the race and
/// AppKit still beeps on arrows.
private struct KeyMonitorAnchor: NSViewRepresentable {
    var viewModel: AppViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        context.coordinator.viewModel = viewModel
        nsView.coordinator = context.coordinator
    }

    static func dismantleNSView(_ nsView: AnchorView, coordinator: Coordinator) {
        nsView.detach()
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        var viewModel: AppViewModel
        private var monitor: KeyMonitor?

        init(viewModel: AppViewModel) {
            self.viewModel = viewModel
        }

        func install() {
            monitor?.stop()
            monitor = KeyMonitor(viewModel: viewModel)
        }

        func stop() {
            monitor?.stop()
            monitor = nil
        }
    }

    @MainActor
    final class AnchorView: NSView {
        var coordinator: Coordinator?
        private weak var observedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach(to: window)
        }

        func detach() {
            attach(to: nil)
        }

        private func attach(to window: NSWindow?) {
            guard observedWindow != window else { return }
            if let observedWindow {
                NotificationCenter.default.removeObserver(
                    self, name: NSWindow.didBecomeKeyNotification, object: observedWindow
                )
            }
            observedWindow = window
            if let window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowBecameKey(_:)),
                    name: NSWindow.didBecomeKeyNotification,
                    object: window
                )
                coordinator?.install()
            } else {
                coordinator?.stop()
            }
        }

        @objc private func windowBecameKey(_ notification: Notification) {
            coordinator?.install()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

/// Keyboard routing rules that do not depend on the view model. Keeping these small policies pure
/// makes the focus and system-shortcut contract testable without synthesizing an AppKit window.
enum KeyMonitorPolicy {
    static func textInputOwnsKeyboard(_ responder: NSResponder?) -> Bool {
        responder is NSText
    }

    /// Native controls have their own keyboard contract. In particular, a focused slider must
    /// keep arrow keys for value changes, a text field must keep letters/digits for editing, and a
    /// focused button or picker must keep Space/Return for activation. Character shortcuts still
    /// defer to any `NSControl`; arrow keys use the narrower value-editing policy below so a
    /// focused filmstrip thumbnail or Look list does not produce AppKit's error beep.
    static func controlOwnsKeyboard(_ responder: NSResponder?) -> Bool {
        textInputOwnsKeyboard(responder) || responder is NSControl
    }

    static func globalShortcutsOwnKeyboard(_ responder: NSResponder?) -> Bool {
        !controlOwnsKeyboard(responder)
    }

    /// Arrow keys adjust values on sliders, steppers, and text. Menu pickers, segmented
    /// workspace controls, buttons, and lists do not — those events belong to photo/Look
    /// navigation. Deferring to an `NSSegmentedControl` or `NSPopUpButton` is what produced
    /// AppKit's error beep in Library and the Edit filmstrip: both surfaces keep the toolbar
    /// workspace picker (and often a culling-bar menu) as first responder after a click.
    static func valueEditingControlOwnsArrows(_ responder: NSResponder?) -> Bool {
        if textInputOwnsKeyboard(responder) { return true }
        if responder is NSTextField { return true }
        return responder is NSSlider
            || responder is NSStepper
            || responder is NSComboBox
    }

    /// Left/Right step photos. Ownership is independent of whether a collection currently has an
    /// adjacent item: the event is still consumed as an intentional no-op at either end, or when
    /// only a single image is open.
    static func imageNavigationOwnsKeyboard(
        keyCode: UInt16,
        eventType: NSEvent.EventType,
        responder: NSResponder?
    ) -> Bool {
        guard keyCode == 123 || keyCode == 124,
              eventType == .keyDown || eventType == .keyUp else {
            return false
        }
        return !valueEditingControlOwnsArrows(responder)
    }

    /// Up/Down audition Looks, including the explicit None slot. Same consumption contract as
    /// image navigation: a focused list or button must not fall through to AppKit's error beep.
    static func lookNavigationOwnsKeyboard(
        keyCode: UInt16,
        eventType: NSEvent.EventType,
        responder: NSResponder?
    ) -> Bool {
        guard keyCode == 125 || keyCode == 126,
              eventType == .keyDown || eventType == .keyUp else {
            return false
        }
        return !valueEditingControlOwnsArrows(responder)
    }

    static func isPlainSpace(modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.intersection(.deviceIndependentFlagsMask).isEmpty
    }

    static func hasSystemModifier(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        let system = modifiers.intersection(.deviceIndependentFlagsMask)
        return system.contains(.command) || system.contains(.option) || system.contains(.control)
    }

    /// Character shortcuts are deliberately plain-key gestures. Shift/Command/Option/Control
    /// combinations belong to the system or the focused control and must reach AppKit unchanged.
    static func isPlainCharacterShortcut(modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.intersection(.deviceIndependentFlagsMask).isEmpty && !modifiers.contains(.shift)
    }

    /// Command+Backslash is the dedicated, hold-to-show-Original gesture. The key code keeps the
    /// shortcut stable across keyboard layouts, while the exact modifier match leaves bare
    /// Backslash and shifted/system-modified variants available to AppKit and text entry.
    static func isCommandBackslashShortcut(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        keyCode == 42 && modifiers.intersection(.deviceIndependentFlagsMask) == .command
    }

    static func isCropShortcut(
        characters: String, modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        isPlainCharacterShortcut(modifiers: modifiers) && characters.lowercased() == "c"
    }

    static func isArrowKey(_ keyCode: UInt16) -> Bool {
        keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126
    }
}

/// Owns an NSEvent local monitor for the lifetime of the main content view.
@MainActor
final class KeyMonitor {
    private var token: Any?
    private weak var viewModel: AppViewModel?
    private let removeMonitor: (Any) -> Void
    private let firstResponderProvider: (NSEvent) -> NSResponder?
    /// Tracks the Command+Backslash key-down independently of modifier flags on key-up. Users can
    /// release Command before Backslash, but the temporary Original presentation must still end.
    private var commandBackslashIsHeld = false

    /// True while a monitor is installed. Internal so the lifecycle that replaced `deinit` can be
    /// asserted at all.
    var isMonitoring: Bool { token != nil }

    /// - Parameter removeMonitor: how to tear the monitor down. Injectable **only** because there is
    ///   no way to observe from outside AppKit whether `NSEvent.removeMonitor` was actually called —
    ///   `isMonitoring` alone would pass against a `stop()` that dropped the token and leaked the
    ///   monitor, which is precisely the failure this step's teardown change could introduce. A
    ///   mutation demonstrated that gap. Same seam as `RenderEngine.init(context:)`.
    init(
        viewModel: AppViewModel,
        removeMonitor: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) },
        firstResponderProvider: @escaping (NSEvent) -> NSResponder? = { event in
            event.window?.firstResponder ?? NSApp?.keyWindow?.firstResponder
        }
    ) {
        self.viewModel = viewModel
        self.removeMonitor = removeMonitor
        self.firstResponderProvider = firstResponderProvider
        self.token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            return self?.handle(event) ?? event
        }
    }

    /// Remove the monitor.
    ///
    /// **Explicit rather than in `deinit`, because Step 8 turned Swift 6 language mode on.** A
    /// `deinit` is `nonisolated` — it can run on any thread, so the compiler refuses to let it touch
    /// `token`, which is the `Any?` AppKit hands back and is not `Sendable`. The escape hatches are
    /// `nonisolated(unsafe)` or an `@unchecked Sendable` box, and this module does not use either.
    ///
    /// Losing the `deinit` safety net costs nothing real and fixes something: `NSEvent.removeMonitor`
    /// is an AppKit call that wants the main thread, and reaching it from a `deinit` that could run
    /// anywhere was already the wrong shape. `KeyboardShortcuts.onDisappear` owns the lifetime now,
    /// on the actor that owns the window. Idempotent, so calling it twice is harmless.
    func stop() {
        if let token { removeMonitor(token) }
        token = nil
    }

    func handle(_ event: NSEvent) -> NSEvent? {
        guard let vm = viewModel else { return event }

        let isDown = event.type == .keyDown
        // A key-up can arrive after Command has been released. Once this monitor accepted the
        // matching key-down, consume that key-up and always restore the edited presentation.
        if !isDown, commandBackslashIsHeld, event.keyCode == 42 {
            commandBackslashIsHeld = false
            _ = vm.showOriginal(false)
            return nil
        }

        // If a sheet is up, let the sheet's text fields and buttons handle keys.
        if vm.derive.isSheetPresented
            || vm.lookSave.isSheetPresented
            || vm.isRemovableMediaSelectorPresented
            || vm.isPhotosPickerPresented {
            return event
        }

        // Resolve focus from the window that owns this event. Looking only at NSApp.keyWindow can
        // consult the wrong window during transitions and can also be nil in a test or before the
        // first app window exists. A focused SwiftUI TextField makes that event window's field
        // editor (an NSText) the first responder.
        let firstResponder = firstResponderProvider(event)
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Arrow keys are app-level photo/Look gestures except on value-editing controls. Handle
        // them before the general NSControl gate so a focused filmstrip button or Look list cannot
        // NSBeep after the navigation already succeeded — or instead of it. Option/Control/Command
        // arrows still belong to AppKit and the menu bar.
        if !KeyMonitorPolicy.hasSystemModifier(mods),
           KeyMonitorPolicy.isArrowKey(event.keyCode) {
            return handleArrow(
                event, viewModel: vm, firstResponder: firstResponder, modifiers: mods
            )
        }

        if !KeyMonitorPolicy.globalShortcutsOwnKeyboard(firstResponder) {
            return event
        }
        // Command-A is the one grid command handled here; other Command-modified events belong to
        // the menu bar.
        if mods.contains(.command) {
            if KeyMonitorPolicy.isCommandBackslashShortcut(
                keyCode: event.keyCode, modifiers: mods
            ) {
                // A key-up without an accepted key-down is not ours (for example, if focus
                // changed while the key was pressed), so do not disturb another transient gesture.
                guard isDown else { return event }
                guard vm.sourceImage != nil, vm.isComparisonAvailable, !vm.isSideBySide else {
                    return event
                }
                commandBackslashIsHeld = true
                _ = vm.showOriginal(isDown)
                return nil
            }
            if isDown,
               vm.navigation.isGrid,
               event.charactersIgnoringModifiers?.lowercased() == "a" {
                vm.collection.selectAll()
                return nil
            }
            if isDown, event.charactersIgnoringModifiers?.lowercased() == "z" {
                if mods.contains(.shift) {
                    if vm.canRedo {
                        vm.redo()
                        return nil
                    }
                } else if vm.canUndo {
                    vm.undo()
                    return nil
                } else if vm.undoCullingChange() {
                    return nil
                }
            }
            return event
        }

        // Option- and Control-modified keys belong to AppKit, input sources, or accessibility
        // tools. They are never Kromora's global navigation/comparison shortcuts.
        if KeyMonitorPolicy.hasSystemModifier(mods) { return event }

        // Hardware key codes (US layout independent for arrows/space).
        // Arrow keys are handled above, before the NSControl ownership gate.
        switch event.keyCode {
        case 51, 117: // Delete / Forward Delete
            // Remove the Library selection after confirmation.
            guard isDown, vm.navigation.isGrid else { return event }
            vm.requestDeleteSelectedLibraryItems()
            return nil
        case 53: // Escape — cancel crop first, then a mask gesture/workspace/tool.
            guard isDown else { return event }
            if vm.isCropToolActive {
                vm.cancelCrop()
            } else if vm.maskInteractionState.hasDraft {
                vm.cancelMaskGesture()
            } else if vm.inspectorState.isMaskingWorkspacePresented,
                      vm.maskInteractionState.activeTool != .selection {
                vm.setMaskTool(.selection)
            } else if vm.inspectorState.isMaskingWorkspacePresented {
                vm.closeMaskingWorkspace()
            } else {
                return event
            }
            return nil
        case 49:  // Space — hold to compare original
            guard KeyMonitorPolicy.isPlainSpace(modifiers: mods) else { return event }
            if vm.inspectorState.isMaskingWorkspacePresented,
               vm.maskInteractionState.activeTool != .selection {
                vm.maskInteractionState.setSpacePanning(isDown)
                return nil
            }
            // A one-off or untouched photo has no meaningful before/after surface. Let Space
            // continue through in that state instead of consuming a key that did nothing.
            // Side-by-side already exposes both surfaces. Space is reserved for the temporary
            // Original view in single-image mode and must not replace the adjusted pane beneath
            // a split presentation.
            guard vm.isComparisonAvailable && !vm.isSideBySide else { return event }
            _ = vm.showOriginal(isDown)
            return nil
        case 36: // Return — apply crop, or open the active grid item in Edit.
            if isDown, vm.isCropToolActive {
                vm.commitCrop()
                return nil
            }
            if isDown, vm.navigation.isGrid {
                vm.openLibraryImageForEditing()
                return nil
            }
            return event
        default:
            break
        }

        // Character keys (key-down only)
        guard isDown, let chars = event.charactersIgnoringModifiers?.lowercased() else {
            return event
        }
        if let command = LibraryCullingCommand.parse(
            characters: chars, hasModifiers: !mods.isEmpty
        ) {
            // Culling belongs to a browsable collection. A one-off image opened outside the
            // library should not swallow P/X/rating keys when there is no focused asset to edit.
            guard vm.collection.isActive else { return event }
            switch command {
            case .pick:
                vm.setFocusedFlag(.pick, advance: true)
            case .reject:
                vm.setFocusedFlag(.reject, advance: true)
            case .clearFlag:
                vm.setFocusedFlag(.none, advance: true)
            case .clearRating:
                vm.setFocusedRating(0)
            case .rating(let rating):
                vm.setFocusedRating(rating)
            }
            return nil
        }
        switch chars {
        case "c":
            // Crop is an editor command: leave the key alone when there is no current image, and
            // preserve shifted/system-modified C for AppKit and the focused control.
            guard KeyMonitorPolicy.isCropShortcut(characters: chars, modifiers: mods),
                  vm.sourceImage != nil else { return event }
            vm.toggleCropTool()
            return nil
        case "g":
            if vm.navigate(to: .grid) { return nil }
            return event
        case "e":
            if vm.inspectorState.isMaskingWorkspacePresented {
                vm.setMaskTool(.erase)
                return nil
            }
            if vm.navigate(to: .edit) { return nil }
            return event
        case "b":
            guard vm.inspectorState.isMaskingWorkspacePresented else { return event }
            vm.setMaskTool(.brush)
            return nil
        case "l":
            guard vm.inspectorState.isMaskingWorkspacePresented else { return event }
            vm.setMaskTool(.linear)
            return nil
        case "r":
            guard vm.inspectorState.isMaskingWorkspacePresented else { return event }
            vm.setMaskTool(.radial)
            return nil
        case "v":
            guard KeyMonitorPolicy.isPlainCharacterShortcut(modifiers: mods) else { return event }
            return vm.toggleSideBySide() ? nil : event
        case "[":
            if vm.isCropToolActive {
                vm.rotateCounterClockwise()
                return nil
            }
            if vm.inspectorState.isMaskingWorkspacePresented,
               (vm.maskInteractionState.activeTool == .brush
                || vm.maskInteractionState.activeTool == .erase) {
                if mods.contains(.shift) {
                    vm.maskInteractionState.adjustBrushFeather(by: -0.05)
                } else {
                    vm.maskInteractionState.adjustBrushRadius(by: -0.005)
                }
                return nil
            }
            guard vm.collection.isActive else { return event }
            if vm.navigation.isGrid {
                vm.collection.selectPrevious()
            } else {
                vm.selectPreviousImage()
            }
            return nil
        case "]":
            if vm.isCropToolActive {
                vm.rotateClockwise()
                return nil
            }
            if vm.inspectorState.isMaskingWorkspacePresented,
               (vm.maskInteractionState.activeTool == .brush
                || vm.maskInteractionState.activeTool == .erase) {
                if mods.contains(.shift) {
                    vm.maskInteractionState.adjustBrushFeather(by: 0.05)
                } else {
                    vm.maskInteractionState.adjustBrushRadius(by: 0.005)
                }
                return nil
            }
            guard vm.collection.isActive else { return event }
            if vm.navigation.isGrid {
                vm.collection.selectNext()
            } else {
                vm.selectNextImage()
            }
            return nil
        default:
            return event
        }
    }

    /// Consume Left/Right (photos) and Up/Down (Looks) unless a value-editing control owns them.
    /// Returning `nil` is what keeps AppKit from playing the error beep for a handled gesture.
    private func handleArrow(
        _ event: NSEvent,
        viewModel vm: AppViewModel,
        firstResponder: NSResponder?,
        modifiers mods: NSEvent.ModifierFlags
    ) -> NSEvent? {
        let isDown = event.type == .keyDown
        switch event.keyCode {
        case 126: // Up arrow — previous Look
            guard KeyMonitorPolicy.lookNavigationOwnsKeyboard(
                keyCode: event.keyCode, eventType: event.type, responder: firstResponder
            ) else { return event }
            if isDown, vm.inspectorState.isMaskingWorkspacePresented,
                vm.nudgeSelectedMask(dx: 0, dy: -1, accelerated: mods.contains(.shift)) {
                return nil
            }
            if isDown { vm.selectPreviousLook() }
            return nil
        case 125: // Down arrow — next Look
            guard KeyMonitorPolicy.lookNavigationOwnsKeyboard(
                keyCode: event.keyCode, eventType: event.type, responder: firstResponder
            ) else { return event }
            if isDown, vm.inspectorState.isMaskingWorkspacePresented,
                vm.nudgeSelectedMask(dx: 0, dy: 1, accelerated: mods.contains(.shift)) {
                return nil
            }
            if isDown { vm.selectNextLook() }
            return nil
        case 123: // Left arrow — previous image
            guard KeyMonitorPolicy.imageNavigationOwnsKeyboard(
                keyCode: event.keyCode, eventType: event.type, responder: firstResponder
            ) else { return event }
            if isDown, vm.inspectorState.isMaskingWorkspacePresented,
                vm.nudgeSelectedMask(dx: -1, dy: 0, accelerated: mods.contains(.shift)) {
                return nil
            }
            if isDown, vm.collection.isActive {
                if vm.navigation.isGrid {
                    vm.collection.selectPrevious()
                } else {
                    vm.selectPreviousImage()
                }
            }
            return nil
        case 124: // Right arrow — next image
            guard KeyMonitorPolicy.imageNavigationOwnsKeyboard(
                keyCode: event.keyCode, eventType: event.type, responder: firstResponder
            ) else { return event }
            if isDown, vm.inspectorState.isMaskingWorkspacePresented,
                vm.nudgeSelectedMask(dx: 1, dy: 0, accelerated: mods.contains(.shift)) {
                return nil
            }
            if isDown, vm.collection.isActive {
                if vm.navigation.isGrid {
                    vm.collection.selectNext()
                } else {
                    vm.selectNextImage()
                }
            }
            return nil
        default:
            return event
        }
    }
}
