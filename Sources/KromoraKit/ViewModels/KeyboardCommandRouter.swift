import SwiftUI

/// A key press reduced to the values Kromora's shortcuts care about. Both entry points build one
/// of these — the focus-scoped `.onKeyPress` surface (`KeyboardSurface`) and the menu bar's
/// plain-key `Commands` items — so there is exactly one dispatch table and no `NSEvent` anywhere.
struct KeyInput: Equatable, Sendable {
    enum Arrow: Hashable, Sendable { case left, right, up, down }

    enum Key: Hashable, Sendable {
        case arrow(Arrow)
        case space
        case `return`
        case escape
        case delete
        case forwardDelete
        /// A character key, lowercased and ignoring modifiers (`"c"`, `"["`, `"\\"`, `"5"`).
        case character(String)
    }

    enum Phase: Equatable, Sendable { case down, up }

    var key: Key
    var modifiers: EventModifiers
    var phase: Phase
    /// An auto-repeat key-down. Hold gestures start once; repeats of a held key are claimed.
    var isRepeat: Bool

    init(_ key: Key, modifiers: EventModifiers = [], phase: Phase = .down, isRepeat: Bool = false) {
        self.key = key
        self.modifiers = modifiers.intersection(Self.significantModifiers)
        self.phase = phase
        self.isRepeat = isRepeat
    }

    /// Caps Lock, numeric-pad and function flags never change what a shortcut means.
    static let significantModifiers: EventModifiers = [.shift, .control, .option, .command]

    var isDown: Bool { phase == .down }
    var hasSystemModifier: Bool {
        !modifiers.isDisjoint(with: [.command, .option, .control])
    }
    /// Plain-key gestures: no Shift/Command/Option/Control.
    var isPlain: Bool { modifiers.isEmpty }
}

/// The slice of editor state that decides whether a shortcut can act. Published per scene
/// (`FocusedValues.keyboardContext`) so menu items show the right enabled state, and rebuilt from
/// the live view model when the router dispatches, so both read the same answer.
struct KeyboardContext: Equatable, Sendable {
    var hasImage = false
    var collectionActive = false
    var isGrid = false
    var isEdit = false
    var cropActive = false
    var retouchActive = false
    var maskingActive = false
    var brushMaskToolActive = false
    var canAutoAdjust = false

    @MainActor
    init(_ vm: AppViewModel) {
        hasImage = vm.sourceImage != nil
        collectionActive = vm.collection.isActive
        isGrid = vm.navigation.isGrid
        isEdit = vm.navigation.isEdit
        cropActive = vm.isCropToolActive
        retouchActive = vm.isRetouchCanvasActive
        maskingActive = vm.inspectorState.isMaskingWorkspacePresented
        brushMaskToolActive = maskingActive
            && (vm.maskInteractionState.activeTool == .brush
                || vm.maskInteractionState.activeTool == .erase)
        canAutoAdjust = vm.canRunAutoAdjustment
    }

    init() {}
}

/// Routes `KeyInput` to the view model. It replaces the `NSEvent` local monitor (`KeyMonitor`).
///
/// **Why this shape (KRMA-920).** A monitor swallows events ahead of the responder chain, so it
/// had to guess whether a control or text field should keep a key; every wrong guess returned the
/// event unclaimed and AppKit played the system alert. Here the responder chain decides:
/// text fields and value-editing controls see their keys first, plain letters/digits/brackets arrive
/// as menu key equivalents (AppKit's last chance before the beep — the real-window
/// `KeyRoutingProbeTests` pin that behavior), and arrows, Space, Return, Esc, Delete and the
/// hold-to-compare gestures arrive through `.onKeyPress(phases: .all)` on the focusable app surface,
/// which always reports `.handled` for a key the app owns — including an intentional no-op.
@MainActor
final class KeyboardCommandRouter {
    private weak var viewModel: AppViewModel?
    /// Tracks the Backslash key-down independently of modifier flags on key-up. A modifier pressed
    /// during the hold can change the key-up's flags, but the temporary Original presentation must
    /// still end.
    private(set) var backslashIsHeld = false
    /// Space is held (comparison or canvas pan). Tracked so focus or window loss can end it.
    private(set) var spaceIsHeld = false

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    /// Returns true when the app claimed the key. `false` hands the key back to the responder
    /// chain / menu bar unchanged.
    @discardableResult
    func perform(_ input: KeyInput) -> Bool {
        guard let vm = viewModel else { return false }

        // A key-up can arrive after Command has been released. Once the matching key-down was
        // accepted, consume the key-up and always restore the edited presentation.
        if !input.isDown, backslashIsHeld, input.key == .character("\\") {
            releaseHolds()
            return true
        }

        // While a sheet is up its own text fields and buttons own the keyboard. A menu key
        // equivalent still reaches this router, so claim it as an intentional no-op rather than
        // let the unclaimed key fall back to the alert sound.
        if Self.isModalPresented(vm) { return true }

        switch input.key {
        case .arrow(let arrow):
            return handleArrow(arrow, input: input, vm: vm)
        case .delete, .forwardDelete:
            return handleDelete(input, vm: vm)
        case .escape:
            return handleEscape(input, vm: vm)
        case .space:
            return handleSpace(input, vm: vm)
        case .return:
            return handleReturn(input, vm: vm)
        case .character(let characters):
            return handleCharacter(characters, input: input, vm: vm)
        }
    }

    static func isModalPresented(_ vm: AppViewModel) -> Bool {
        vm.derive.isSheetPresented
            || vm.lookSave.isSheetPresented
            || vm.isRemovableMediaSelectorPresented
            || vm.isPhotosPickerPresented
            || vm.isSelectiveCopyDialogPresented
    }

    // MARK: - Command-modified gestures

    /// Command-C opens Selective Copy, Command-V pastes edits and Command-A selects the grid; the
    /// surface installs them as standard Edit-menu commands (`onCopyCommand`, `onCommand`) so a
    /// focused text field keeps its normal copy, paste and select-all. Command-Backslash is a hold
    /// gesture and arrives through the key surface.
    private func handleBackslash(_ input: KeyInput, vm: AppViewModel) -> Bool {
        // A key-up without an accepted key-down is not ours (for example, if focus changed while
        // the key was pressed); claim it without disturbing another transient gesture.
        guard input.isDown else { return true }
        // Auto-repeat of a held key must not restart the transition.
        if input.isRepeat { return true }
        guard vm.sourceImage != nil, vm.isComparisonAvailable, !vm.isSideBySide else {
            return true
        }
        backslashIsHeld = true
        _ = vm.showOriginal(true)
        return true
    }

    var isHolding: Bool { backslashIsHeld || spaceIsHeld }

    /// Ends every transient hold gesture and restores the edited presentation. Called on key-up
    /// and whenever the surface loses focus or its window stops being key, because the matching
    /// key-up is then delivered elsewhere (or never).
    func releaseHolds() {
        guard backslashIsHeld || spaceIsHeld, let vm = viewModel else { return }
        if spaceIsHeld {
            vm.retouchInteractionState.setSpacePanning(false)
            vm.maskInteractionState.setSpacePanning(false)
        }
        backslashIsHeld = false
        spaceIsHeld = false
        _ = vm.showOriginal(false)
    }

    // MARK: - Arrows

    /// Left/Right step photos, Up/Down audition Looks (grid rows in Library). Option/Control/Command
    /// arrows belong to AppKit and the menu bar. The key is claimed even when it is an intentional
    /// no-op (either end of the collection, a single open image).
    private func handleArrow(_ arrow: KeyInput.Arrow, input: KeyInput, vm: AppViewModel) -> Bool {
        guard !input.hasSystemModifier else { return false }
        let isDown = input.isDown
        let accelerated = input.modifiers.contains(.shift)

        switch arrow {
        case .up:
            if isDown, vm.inspectorState.isMaskingWorkspacePresented,
               vm.nudgeSelectedMask(dx: 0, dy: -1, accelerated: accelerated) {
                return true
            }
            if isDown, vm.navigation.isGrid, vm.collection.isActive {
                vm.selectPortableRowAboveInGrid()
            } else if isDown, !vm.navigation.isGrid {
                vm.selectPreviousLook()
            }
        case .down:
            if isDown, vm.inspectorState.isMaskingWorkspacePresented,
               vm.nudgeSelectedMask(dx: 0, dy: 1, accelerated: accelerated) {
                return true
            }
            if isDown, vm.navigation.isGrid, vm.collection.isActive {
                vm.selectPortableRowBelowInGrid()
            } else if isDown, !vm.navigation.isGrid {
                vm.selectNextLook()
            }
        case .left:
            if isDown, vm.inspectorState.isMaskingWorkspacePresented,
               vm.nudgeSelectedMask(dx: -1, dy: 0, accelerated: accelerated) {
                return true
            }
            if isDown, vm.collection.isActive {
                if vm.navigation.isGrid {
                    vm.selectPreviousPortableInGrid()
                } else {
                    vm.selectPreviousImage()
                }
            }
        case .right:
            if isDown, vm.inspectorState.isMaskingWorkspacePresented,
               vm.nudgeSelectedMask(dx: 1, dy: 0, accelerated: accelerated) {
                return true
            }
            if isDown, vm.collection.isActive {
                if vm.navigation.isGrid {
                    vm.selectNextPortableInGrid()
                } else {
                    vm.selectNextImage()
                }
            }
        }
        return true
    }

    // MARK: - Delete, Escape, Space, Return

    private func handleDelete(_ input: KeyInput, vm: AppViewModel) -> Bool {
        guard !input.hasSystemModifier else { return false }
        guard input.isDown else { return true }
        if vm.isRetouchCanvasActive, vm.retouchInteractionState.selectedSpotID != nil {
            vm.retouchWorkflow.deleteSelected()
        } else {
            // Removes the Library selection after confirmation; a no-op outside the grid.
            vm.requestDeleteSelectedLibraryItems()
        }
        return true
    }

    /// Cancel crop first, then deselect/exit the active canvas tool.
    private func handleEscape(_ input: KeyInput, vm: AppViewModel) -> Bool {
        guard !input.hasSystemModifier else { return false }
        guard input.isDown else { return true }
        if vm.isCropToolActive {
            vm.cancelCrop()
        } else if vm.isRetouchCanvasActive && vm.retouchInteractionState.hasDraft {
            vm.retouchWorkflow.cancelGesture()
        } else if vm.isRetouchCanvasActive,
                  vm.retouchInteractionState.selectedSpotID != nil {
            vm.retouchInteractionState.select(nil)
        } else if vm.maskInteractionState.hasDraft {
            vm.cancelMaskGesture()
        } else if vm.inspectorState.isMaskingWorkspacePresented,
                  vm.maskInteractionState.activeTool != .selection {
            vm.setMaskTool(.selection)
        } else if vm.inspectorState.isMaskingWorkspacePresented {
            vm.closeMaskingWorkspace()
        } else if vm.isRetouchCanvasActive {
            vm.retouchWorkflow.setArmed(false)
            vm.inspectorState.select(.info)
        }
        // Nothing to cancel is an intentional no-op, still claimed.
        return true
    }

    /// Hold Space to compare the original (or pan while a canvas tool is active).
    private func handleSpace(_ input: KeyInput, vm: AppViewModel) -> Bool {
        guard input.isPlain else { return false }
        guard input.isDown else {
            releaseHolds()
            return true
        }
        if input.isRepeat { return true }
        if vm.isRetouchCanvasActive {
            spaceIsHeld = true
            vm.retouchInteractionState.setSpacePanning(true)
        } else if vm.inspectorState.isMaskingWorkspacePresented,
                  vm.maskInteractionState.activeTool != .selection {
            spaceIsHeld = true
            vm.maskInteractionState.setSpacePanning(true)
        } else if vm.isComparisonAvailable && !vm.isSideBySide {
            // A one-off or untouched photo has no before/after surface and side-by-side already
            // shows both, so Space is a claimed no-op there.
            spaceIsHeld = true
            _ = vm.showOriginal(true)
        }
        return true
    }

    /// Apply crop, or open the active grid item in Edit.
    private func handleReturn(_ input: KeyInput, vm: AppViewModel) -> Bool {
        guard !input.hasSystemModifier else { return false }
        guard input.isDown else { return true }
        if vm.isCropToolActive {
            vm.commitCrop()
        } else if vm.navigation.isGrid {
            vm.openLibraryImageForEditing()
        }
        return true
    }

    // MARK: - Character keys

    private func handleCharacter(_ characters: String, input: KeyInput, vm: AppViewModel) -> Bool {
        if characters == "\\", input.modifiers == .command {
            return handleBackslash(input, vm: vm)
        }
        // Option/Control/Command-modified characters belong to AppKit, input sources and the
        // menu bar; the catalog never binds them. An unavailable command is a claimed no-op.
        guard input.isDown, let command = KeyboardShortcutCatalog.command(for: input) else {
            return false
        }
        if command.isAvailable(in: KeyboardContext(vm)) { execute(command, vm: vm) }
        return true
    }

    private func execute(_ command: KeyboardCommand, vm: AppViewModel) {
        switch command {
        case .cull(let culling): vm.perform(culling)
        case .toggleRetouchVisualization: vm.toggleRetouchVisualization()
        case .toggleCaptureOverlay:
            // A preview-only presentation toggle; Command-I stays the Info Inspector.
            NotificationCenter.default.post(name: .toggleCaptureMetadataOverlay, object: nil)
        case .toggleCrop: vm.toggleCropTool()
        case .toggleRetouch:
            if vm.isRetouchCanvasActive {
                vm.retouchWorkflow.setArmed(false)
                vm.inspectorState.select(.info)
            } else {
                vm.retouchWorkflow.setArmed(true)
            }
        case .showLibrary: _ = vm.navigate(to: .grid)
        case .showEdit:
            if vm.inspectorState.isMaskingWorkspacePresented {
                vm.setMaskTool(.erase)
            } else {
                _ = vm.navigate(to: .edit)
            }
        case .toggleMaskOverlay:
            // Lightroom's key for the mask overlay: show or hide it while masking.
            vm.maskInteractionState.toggleOverlay()
        case .nextRetouchSource: vm.retouchWorkflow.nextSource()
        case .cycleRetouchOverlay: vm.retouchInteractionState.cycleOverlayPolicy()
        case .maskBrush: vm.setMaskTool(.brush)
        case .maskLinear: vm.setMaskTool(.linear)
        case .maskRadial: vm.setMaskTool(.radial)
        case .toggleComparison: _ = vm.toggleSideBySide()
        case .step(let increase, let feather):
            handleBracket(increase: increase, shift: feather, vm: vm)
        }
    }

    /// `[` / `]`: rotate in crop, brush size/feather in masking, spot size/feather in retouch,
    /// otherwise previous/next photo.
    private func handleBracket(increase: Bool, shift: Bool, vm: AppViewModel) {
        let sign: Double = increase ? 1 : -1
        if vm.isCropToolActive {
            if increase { vm.rotateClockwise() } else { vm.rotateCounterClockwise() }
            return
        }
        if vm.inspectorState.isMaskingWorkspacePresented,
           vm.maskInteractionState.activeTool == .brush
            || vm.maskInteractionState.activeTool == .erase {
            if shift {
                vm.maskInteractionState.adjustBrushFeather(by: 0.05 * sign)
            } else {
                vm.maskInteractionState.adjustBrushRadius(by: 0.005 * sign)
            }
            return
        }
        if vm.isRetouchCanvasActive {
            if shift {
                let feather = vm.retouchInteractionState.feather + 0.05 * sign
                vm.retouchInteractionState.feather = increase ? min(1, feather) : max(0, feather)
            } else {
                let radius = vm.retouchInteractionState.radius + 0.002 * sign
                vm.retouchInteractionState.radius = increase ? min(0.25, radius) : max(0.0005, radius)
            }
            return
        }
        guard vm.collection.isActive else { return }
        switch (vm.navigation.isGrid, increase) {
        case (true, false): vm.selectPreviousPortableInGrid()
        case (true, true): vm.selectNextPortableInGrid()
        case (false, false): vm.selectPreviousImage()
        case (false, true): vm.selectNextImage()
        }
    }
}
