import SwiftUI

/// A key press reduced to the values Kromora's shortcuts care about. Both entry points build one
/// of these — the focus-scoped `.onKeyPress` surface (`KeyboardSurface`) and the menu bar's
/// plain-key `Commands` items — so there is exactly one dispatch table and no `NSEvent` anywhere.
struct KeyInput: Equatable, Sendable {
    enum Arrow: Equatable, Sendable { case left, right, up, down }

    enum Key: Equatable, Sendable {
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

    init(_ key: Key, modifiers: EventModifiers = [], phase: Phase = .down) {
        self.key = key
        self.modifiers = modifiers.intersection(Self.significantModifiers)
        self.phase = phase
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
    /// Tracks the Command+Backslash key-down independently of modifier flags on key-up. Users can
    /// release Command before Backslash, but the temporary Original presentation must still end.
    private(set) var commandBackslashIsHeld = false

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
        if !input.isDown, commandBackslashIsHeld, input.key == .character("\\") {
            commandBackslashIsHeld = false
            _ = vm.showOriginal(false)
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

    /// Command-C opens Selective Copy and Command-A selects the grid; both are delivered by the
    /// standard Edit-menu commands (`onCopyCommand`, `onCommand(selectAll:)`) so a focused text
    /// field keeps its normal copy and select-all. Command-Backslash is a hold gesture and arrives
    /// through the key surface.
    private func handleCommandBackslash(_ input: KeyInput, vm: AppViewModel) -> Bool {
        // A key-up without an accepted key-down is not ours (for example, if focus changed while
        // the key was pressed), so do not disturb another transient gesture.
        guard input.isDown else { return false }
        guard vm.sourceImage != nil, vm.isComparisonAvailable, !vm.isSideBySide else {
            return false
        }
        commandBackslashIsHeld = true
        _ = vm.showOriginal(true)
        return true
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
        if input.isDown, vm.isRetouchCanvasActive,
           vm.retouchInteractionState.selectedSpotID != nil {
            vm.retouchWorkflow.deleteSelected()
            return true
        }
        // Remove the Library selection after confirmation. Outside the grid the Delete menu
        // command (File ▸ Delete Selected Photos) is the only owner.
        guard input.isDown, vm.navigation.isGrid else { return false }
        vm.requestDeleteSelectedLibraryItems()
        return true
    }

    /// Cancel crop first, then deselect/exit the active canvas tool.
    private func handleEscape(_ input: KeyInput, vm: AppViewModel) -> Bool {
        guard !input.hasSystemModifier, input.isDown else { return false }
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
        } else {
            return false
        }
        return true
    }

    /// Hold Space to compare the original (or pan while a canvas tool is active).
    private func handleSpace(_ input: KeyInput, vm: AppViewModel) -> Bool {
        guard input.isPlain else { return false }
        let isDown = input.isDown
        if vm.isRetouchCanvasActive {
            vm.retouchInteractionState.setSpacePanning(isDown)
            return true
        }
        if vm.inspectorState.isMaskingWorkspacePresented,
           vm.maskInteractionState.activeTool != .selection {
            vm.maskInteractionState.setSpacePanning(isDown)
            return true
        }
        // A one-off or untouched photo has no meaningful before/after surface. Let Space continue
        // through in that state instead of consuming a key that did nothing. Side-by-side already
        // exposes both surfaces; Space is reserved for the temporary Original view in single mode.
        guard vm.isComparisonAvailable && !vm.isSideBySide else { return false }
        _ = vm.showOriginal(isDown)
        return true
    }

    /// Apply crop, or open the active grid item in Edit.
    private func handleReturn(_ input: KeyInput, vm: AppViewModel) -> Bool {
        guard !input.hasSystemModifier, input.isDown else { return false }
        if vm.isCropToolActive {
            vm.commitCrop()
            return true
        }
        if vm.navigation.isGrid {
            vm.openLibraryImageForEditing()
            return true
        }
        return false
    }

    // MARK: - Character keys

    private func handleCharacter(_ characters: String, input: KeyInput, vm: AppViewModel) -> Bool {
        if characters == "\\", input.modifiers == .command {
            return handleCommandBackslash(input, vm: vm)
        }
        // Option/Control/Command-modified characters belong to AppKit, input sources and the
        // menu bar. They are never Kromora's character shortcuts.
        guard input.isDown, !input.hasSystemModifier else { return false }
        let mods = input.modifiers

        if let command = LibraryCullingCommand.parse(
            characters: characters, hasModifiers: !mods.isEmpty
        ) {
            // Culling belongs to a browsable collection. A one-off image opened outside the
            // library should not swallow P/X/rating keys when there is no focused asset to edit.
            guard vm.collection.isActive else { return false }
            vm.perform(command)
            return true
        }
        switch characters {
        case "a":
            guard vm.isRetouchCanvasActive, input.isPlain else { return false }
            vm.toggleRetouchVisualization()
        case "i":
            // Plain I is a preview-only presentation toggle; Command-I stays the Info Inspector.
            guard input.isPlain, vm.sourceImage != nil else { return false }
            NotificationCenter.default.post(name: .toggleCaptureMetadataOverlay, object: nil)
        case "c":
            // Crop is an editor command: unavailable without a current image.
            guard input.isPlain, vm.sourceImage != nil else { return false }
            vm.toggleCropTool()
        case "q":
            guard input.isPlain, vm.sourceImage != nil, vm.navigation.isEdit else { return false }
            if vm.isRetouchCanvasActive {
                vm.retouchWorkflow.setArmed(false)
                vm.inspectorState.select(.info)
            } else {
                vm.retouchWorkflow.setArmed(true)
            }
        case "g":
            return vm.navigate(to: .grid)
        case "e":
            if vm.inspectorState.isMaskingWorkspacePresented {
                vm.setMaskTool(.erase)
                return true
            }
            return vm.navigate(to: .edit)
        case "o":
            // Lightroom's key for the mask overlay: show or hide it while masking.
            guard vm.inspectorState.isMaskingWorkspacePresented, input.isPlain else { return false }
            vm.maskInteractionState.toggleOverlay()
        case "/":
            guard vm.isRetouchCanvasActive else { return false }
            vm.retouchWorkflow.nextSource()
        case "h":
            guard vm.isRetouchCanvasActive, input.isPlain else { return false }
            vm.retouchInteractionState.cycleOverlayPolicy()
        case "b":
            guard vm.inspectorState.isMaskingWorkspacePresented else { return false }
            vm.setMaskTool(.brush)
        case "l":
            guard vm.inspectorState.isMaskingWorkspacePresented else { return false }
            vm.setMaskTool(.linear)
        case "r":
            guard vm.inspectorState.isMaskingWorkspacePresented else { return false }
            vm.setMaskTool(.radial)
        case "v":
            guard input.isPlain else { return false }
            return vm.toggleSideBySide()
        case "[":
            return handleBracket(increase: false, shift: mods.contains(.shift), vm: vm)
        case "]":
            return handleBracket(increase: true, shift: mods.contains(.shift), vm: vm)
        default:
            return false
        }
        return true
    }

    /// `[` / `]`: rotate in crop, brush size/feather in masking, spot size/feather in retouch,
    /// otherwise previous/next photo.
    private func handleBracket(increase: Bool, shift: Bool, vm: AppViewModel) -> Bool {
        let sign: Double = increase ? 1 : -1
        if vm.isCropToolActive {
            if increase { vm.rotateClockwise() } else { vm.rotateCounterClockwise() }
            return true
        }
        if vm.inspectorState.isMaskingWorkspacePresented,
           vm.maskInteractionState.activeTool == .brush
            || vm.maskInteractionState.activeTool == .erase {
            if shift {
                vm.maskInteractionState.adjustBrushFeather(by: 0.05 * sign)
            } else {
                vm.maskInteractionState.adjustBrushRadius(by: 0.005 * sign)
            }
            return true
        }
        if vm.isRetouchCanvasActive {
            if shift {
                let feather = vm.retouchInteractionState.feather + 0.05 * sign
                vm.retouchInteractionState.feather = increase ? min(1, feather) : max(0, feather)
            } else {
                let radius = vm.retouchInteractionState.radius + 0.002 * sign
                vm.retouchInteractionState.radius = increase ? min(0.25, radius) : max(0.0005, radius)
            }
            return true
        }
        guard vm.collection.isActive else { return false }
        switch (vm.navigation.isGrid, increase) {
        case (true, false): vm.selectPreviousPortableInGrid()
        case (true, true): vm.selectNextPortableInGrid()
        case (false, false): vm.selectPreviousImage()
        case (false, true): vm.selectNextImage()
        }
        return true
    }
}
