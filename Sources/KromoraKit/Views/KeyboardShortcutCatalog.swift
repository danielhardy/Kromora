import SwiftUI

/// What a plain-key shortcut does. The router executes it, the catalog binds it to a key, and
/// `isAvailable(in:)` is the one predicate behind both the menu item's enabled state and the
/// router's "claim it as a no-op" decision.
enum KeyboardCommand: Equatable, Sendable {
    case showLibrary
    case showEdit
    case cull(LibraryCullingCommand)
    case toggleComparison
    case toggleCaptureOverlay
    case toggleCrop
    /// `[` / `]`; `feather` is the Shift variant.
    case step(increase: Bool, feather: Bool)
    case toggleRetouch
    case toggleRetouchVisualization
    case cycleRetouchOverlay
    case nextRetouchSource
    case maskBrush
    case maskLinear
    case maskRadial
    case toggleMaskOverlay

    func isAvailable(in context: KeyboardContext) -> Bool {
        switch self {
        case .showLibrary, .showEdit:
            return true
        case .cull:
            // Culling belongs to a browsable collection, not a one-off opened image.
            return context.collectionActive
        case .toggleComparison, .toggleCaptureOverlay, .toggleCrop:
            return context.hasImage
        case .step:
            return context.cropActive || context.brushMaskToolActive
                || context.retouchActive || context.collectionActive
        case .toggleRetouch:
            return context.hasImage && context.isEdit
        case .toggleRetouchVisualization, .cycleRetouchOverlay, .nextRetouchSource:
            return context.retouchActive
        case .maskBrush, .maskLinear, .maskRadial, .toggleMaskOverlay:
            return context.maskingActive
        }
    }
}

/// Declarative list of Kromora's keyboard shortcuts. It is the single source for the menu bar's
/// plain-key items (`KromoraCommands`), the router's character dispatch, the Keyboard Shortcuts
/// reference sheet, and the tests that keep them in agreement.
struct KeyboardShortcutSpec: Identifiable, Equatable {
    enum Menu: String, Equatable {
        case photo = "Photo"
        case tools = "Tools"
        case view = "View"
    }

    /// How a shortcut reaches the app.
    enum Delivery: Equatable {
        /// A menu item with a key equivalent whose action calls `KeyboardCommandRouter`. Plain and
        /// Shift-modified keys are AppKit's last chance before the system alert, and a focused text
        /// field edits first, so typing is never stolen.
        case menuKey(Menu, key: KeyEquivalent, modifiers: EventModifiers, command: KeyboardCommand)
        /// Delivered by `KeyboardChainTail` (the window responder-chain tail): arrows (a menu equivalent would steal
        /// caret movement), Space/Esc/Return/Delete and hold-to-compare gestures. The router claims
        /// every listed key, even as a no-op, so none reaches the system alert.
        case surface([KeyInput])
        /// Defined elsewhere (File/Edit menu commands); listed for the reference sheet only.
        case standardMenu
    }

    let action: String
    let keys: String
    let area: String
    let delivery: Delivery
    var id: String { action }
}

/// One menu-bar item built from the catalog.
struct KeyboardMenuBinding: Identifiable {
    let title: String
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let command: KeyboardCommand
    var id: String { title }
    var input: KeyInput { KeyInput(.character(String(key.character)), modifiers: modifiers) }
}

enum KeyboardShortcutCatalog {
    private static func menuKey(
        _ action: String, _ menu: KeyboardShortcutSpec.Menu, _ key: KeyEquivalent,
        modifiers: EventModifiers = [], _ command: KeyboardCommand, area: String, display: String
    ) -> KeyboardShortcutSpec {
        KeyboardShortcutSpec(
            action: action, keys: display, area: area,
            delivery: .menuKey(menu, key: key, modifiers: modifiers, command: command)
        )
    }

    private static let leftArrowKeys = [KeyInput(.arrow(.left)), KeyInput(.arrow(.right))]
    private static let upDownKeys = [KeyInput(.arrow(.up)), KeyInput(.arrow(.down))]

    static let all: [KeyboardShortcutSpec] = [
        // Library
        .init(action: "Open photos", keys: "⌘O", area: "Library", delivery: .standardMenu),
        .init(action: "Import from Photos", keys: "⌘⇧I", area: "Library", delivery: .standardMenu),
        .init(action: "Open source folder", keys: "⌘⌥I", area: "Library", delivery: .standardMenu),
        .init(action: "Rebuild library index", keys: "⌘R", area: "Library", delivery: .standardMenu),
        .init(
            action: "Delete selected photos", keys: "Delete", area: "Library",
            delivery: .surface([KeyInput(.delete), KeyInput(.forwardDelete)])
        ),
        // Navigation
        menuKey("Library workspace", .view, "g", .showLibrary, area: "Navigation", display: "G"),
        menuKey("Edit workspace / erase mask tool", .view, "e", .showEdit, area: "Navigation", display: "E"),
        .init(action: "Select previous / next photo", keys: "← / →", area: "Library and Edit", delivery: .surface(leftArrowKeys)),
        .init(action: "Previous / next Look, or grid row", keys: "↑ / ↓", area: "Library and Edit", delivery: .surface(upDownKeys)),
        .init(action: "Open the selected photo in Edit", keys: "Return", area: "Library", delivery: .surface([KeyInput(.return)])),
        // Culling
        menuKey("Pick photo", .photo, "p", .cull(.pick), area: "Library", display: "P"),
        menuKey("Reject photo", .photo, "x", .cull(.reject), area: "Library", display: "X"),
        menuKey("Clear flag", .photo, "u", .cull(.clearFlag), area: "Library", display: "U"),
        menuKey("Clear rating", .photo, "0", .cull(.clearRating), area: "Library", display: "0"),
        menuKey("Rate 1 star", .photo, "1", .cull(.rating(1)), area: "Library", display: "1"),
        menuKey("Rate 2 stars", .photo, "2", .cull(.rating(2)), area: "Library", display: "2"),
        menuKey("Rate 3 stars", .photo, "3", .cull(.rating(3)), area: "Library", display: "3"),
        menuKey("Rate 4 stars", .photo, "4", .cull(.rating(4)), area: "Library", display: "4"),
        menuKey("Rate 5 stars", .photo, "5", .cull(.rating(5)), area: "Library", display: "5"),
        // Edit
        .init(action: "Undo / redo edit", keys: "⌘Z / ⇧⌘Z", area: "Edit", delivery: .standardMenu),
        .init(action: "Reset photo", keys: "⇧⌘R", area: "Edit", delivery: .standardMenu),
        .init(
            action: KromoraAutoAdjustmentShortcut.referenceAction,
            keys: KromoraAutoAdjustmentShortcut.displayString, area: "Edit", delivery: .standardMenu
        ),
        .init(action: "Copy edits", keys: "⌘C", area: "Edit", delivery: .standardMenu),
        .init(action: "Paste edits", keys: "⌘V or ⌥⌘V", area: "Edit", delivery: .standardMenu),
        .init(
            action: "Show original (hold)", keys: "Space or ⌘\\", area: "Edit",
            delivery: .surface([KeyInput(.space), KeyInput(.character("\\"), modifiers: .command)])
        ),
        menuKey("Toggle comparison", .view, "v", .toggleComparison, area: "Edit", display: "V"),
        menuKey("Toggle capture information overlay", .view, "i", .toggleCaptureOverlay, area: "Edit", display: "I"),
        .init(
            action: "Export selected photos or active photo", keys: "⌘S", area: "Library and Edit",
            delivery: .standardMenu
        ),
        // Crop and tools
        menuKey("Crop", .tools, "c", .toggleCrop, area: "Edit", display: "C"),
        .init(action: "Apply or cancel crop", keys: "Return / Esc", area: "Crop", delivery: .surface([KeyInput(.return), KeyInput(.escape)])),
        menuKey("Previous photo / rotate left / smaller brush", .tools, "[", .step(increase: false, feather: false), area: "Edit", display: "["),
        menuKey("Next photo / rotate right / larger brush", .tools, "]", .step(increase: true, feather: false), area: "Edit", display: "]"),
        menuKey("Smaller brush or spot feather", .tools, "[", modifiers: .shift, .step(increase: false, feather: true), area: "Masks and Retouch", display: "⇧["),
        menuKey("Larger brush or spot feather", .tools, "]", modifiers: .shift, .step(increase: true, feather: true), area: "Masks and Retouch", display: "⇧]"),
        menuKey("Retouch tool", .tools, "q", .toggleRetouch, area: "Edit", display: "Q"),
        menuKey("Retouch visualization", .tools, "a", .toggleRetouchVisualization, area: "Retouch", display: "A"),
        menuKey("Cycle retouch overlay", .tools, "h", .cycleRetouchOverlay, area: "Retouch", display: "H"),
        menuKey("Next retouch source", .tools, "/", .nextRetouchSource, area: "Retouch", display: "/"),
        menuKey("Brush mask tool", .tools, "b", .maskBrush, area: "Masks", display: "B"),
        menuKey("Linear mask tool", .tools, "l", .maskLinear, area: "Masks", display: "L"),
        menuKey("Radial mask tool", .tools, "r", .maskRadial, area: "Masks", display: "R"),
        menuKey("Show or hide mask overlay", .tools, "o", .toggleMaskOverlay, area: "Masks", display: "O"),
        .init(action: "Nudge selected mask", keys: "← → ↑ ↓ (⇧ to accelerate)", area: "Masks", delivery: .surface(leftArrowKeys + upDownKeys))
    ]

    /// Every menu-bar plain-key item, in menu order.
    static func menuItems(in menu: KeyboardShortcutSpec.Menu) -> [KeyboardMenuBinding] {
        all.compactMap { spec in
            guard case .menuKey(let owner, let key, let modifiers, let command) = spec.delivery,
                  owner == menu else { return nil }
            return KeyboardMenuBinding(title: spec.action, key: key, modifiers: modifiers, command: command)
        }
    }

    /// The command a character key press resolves to, or nil when the catalog does not bind it.
    /// Modifiers must match exactly, so Command/Option/Control combinations never resolve.
    static func command(for input: KeyInput) -> KeyboardCommand? {
        guard case .character(let characters) = input.key else { return nil }
        for spec in all {
            guard case .menuKey(_, let key, let modifiers, let command) = spec.delivery,
                  String(key.character) == characters, modifiers == input.modifiers else { continue }
            return command
        }
        return nil
    }

    /// Every key the surface owns, for dispatch-parity checks.
    static var surfaceInputs: [KeyInput] {
        all.flatMap { spec -> [KeyInput] in
            if case .surface(let inputs) = spec.delivery { return inputs }
            return []
        }
    }
}
