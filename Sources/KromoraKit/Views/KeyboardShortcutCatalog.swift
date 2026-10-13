import SwiftUI

/// Declarative list of Kromora's keyboard shortcuts. It is the single source for the menu bar's
/// plain-key items (`KromoraCommands`), the Keyboard Shortcuts reference sheet, and the tests that
/// keep the two in agreement.
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
        case menuKey(Menu, key: KeyEquivalent, modifiers: EventModifiers)
        /// Delivered by `KeyboardSurface` (`.onKeyPress`): arrows (a menu equivalent would steal
        /// caret movement), Space/Esc/Return/Delete and hold-to-compare gestures.
        case surface
        /// Defined elsewhere (File/Edit menu commands); listed for the reference sheet only.
        case standardMenu
    }

    let action: String
    let keys: String
    let area: String
    let delivery: Delivery
    var id: String { action }
}

enum KeyboardShortcutCatalog {
    private static func menuKey(
        _ action: String, _ menu: KeyboardShortcutSpec.Menu, _ key: KeyEquivalent,
        modifiers: EventModifiers = [], area: String, display: String
    ) -> KeyboardShortcutSpec {
        KeyboardShortcutSpec(
            action: action, keys: display, area: area,
            delivery: .menuKey(menu, key: key, modifiers: modifiers)
        )
    }

    static let all: [KeyboardShortcutSpec] = [
        // Library
        .init(action: "Open photos", keys: "⌘O", area: "Library", delivery: .standardMenu),
        .init(action: "Import from Photos", keys: "⌘⇧I", area: "Library", delivery: .standardMenu),
        .init(action: "Open source folder", keys: "⌘⌥I", area: "Library", delivery: .standardMenu),
        .init(action: "Refresh library", keys: "⌘R", area: "Library", delivery: .standardMenu),
        .init(action: "Delete selected photos", keys: "Delete", area: "Library", delivery: .standardMenu),
        // Navigation
        menuKey("Library workspace", .view, "g", area: "Navigation", display: "G"),
        menuKey("Edit workspace / erase mask tool", .view, "e", area: "Navigation", display: "E"),
        .init(action: "Select previous / next photo", keys: "← / →", area: "Library and Edit", delivery: .surface),
        .init(action: "Previous / next Look, or grid row", keys: "↑ / ↓", area: "Library and Edit", delivery: .surface),
        .init(action: "Open the selected photo in Edit", keys: "Return", area: "Library", delivery: .surface),
        // Culling
        menuKey("Pick photo", .photo, "p", area: "Library", display: "P"),
        menuKey("Reject photo", .photo, "x", area: "Library", display: "X"),
        menuKey("Clear flag", .photo, "u", area: "Library", display: "U"),
        menuKey("Clear rating", .photo, "0", area: "Library", display: "0"),
        menuKey("Rate 1 star", .photo, "1", area: "Library", display: "1"),
        menuKey("Rate 2 stars", .photo, "2", area: "Library", display: "2"),
        menuKey("Rate 3 stars", .photo, "3", area: "Library", display: "3"),
        menuKey("Rate 4 stars", .photo, "4", area: "Library", display: "4"),
        menuKey("Rate 5 stars", .photo, "5", area: "Library", display: "5"),
        // Edit
        .init(action: "Undo / redo edit", keys: "⌘Z / ⇧⌘Z", area: "Edit", delivery: .standardMenu),
        .init(action: "Reset photo", keys: "⇧⌘R", area: "Edit", delivery: .standardMenu),
        .init(
            action: KromoraAutoAdjustmentShortcut.referenceAction,
            keys: KromoraAutoAdjustmentShortcut.displayString, area: "Edit", delivery: .standardMenu
        ),
        .init(action: "Show original (hold)", keys: "Space or ⌘\\", area: "Edit", delivery: .surface),
        menuKey("Toggle comparison", .view, "v", area: "Edit", display: "V"),
        menuKey("Toggle capture information overlay", .view, "i", area: "Edit", display: "I"),
        .init(action: "Export edited photo", keys: "⌘S", area: "Edit", delivery: .standardMenu),
        // Crop and tools
        menuKey("Crop", .tools, "c", area: "Edit", display: "C"),
        .init(action: "Apply or cancel crop", keys: "Return / Esc", area: "Crop", delivery: .surface),
        menuKey("Previous photo / rotate left / smaller brush", .tools, "[", area: "Edit", display: "["),
        menuKey("Next photo / rotate right / larger brush", .tools, "]", area: "Edit", display: "]"),
        menuKey("Smaller brush or spot feather", .tools, "[", modifiers: .shift, area: "Masks and Retouch", display: "⇧["),
        menuKey("Larger brush or spot feather", .tools, "]", modifiers: .shift, area: "Masks and Retouch", display: "⇧]"),
        menuKey("Retouch tool", .tools, "q", area: "Edit", display: "Q"),
        menuKey("Retouch visualization", .tools, "a", area: "Retouch", display: "A"),
        menuKey("Cycle retouch overlay", .tools, "h", area: "Retouch", display: "H"),
        menuKey("Next retouch source", .tools, "/", area: "Retouch", display: "/"),
        .init(action: "Delete selected retouch spot", keys: "Delete", area: "Retouch", delivery: .surface),
        menuKey("Brush mask tool", .tools, "b", area: "Masks", display: "B"),
        menuKey("Linear mask tool", .tools, "l", area: "Masks", display: "L"),
        menuKey("Radial mask tool", .tools, "r", area: "Masks", display: "R"),
        menuKey("Show or hide mask overlay", .tools, "o", area: "Masks", display: "O"),
        .init(action: "Nudge selected mask", keys: "← → ↑ ↓ (⇧ to accelerate)", area: "Masks", delivery: .surface)
    ]

    /// Every menu-bar plain-key item, in menu order.
    static func menuItems(in menu: KeyboardShortcutSpec.Menu) -> [KeyboardShortcutSpec] {
        all.filter {
            if case .menuKey(let owner, _, _) = $0.delivery { return owner == menu }
            return false
        }
    }
}
