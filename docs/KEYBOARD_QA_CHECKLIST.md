# Keyboard shortcut matrix

Expected behavior of every keyboard shortcut in each focus state. Rows come from
`KeyboardShortcutCatalog.all` (`Sources/KromoraKit/Views/KeyboardShortcutCatalog.swift`);
`KeyboardShortcutCatalogTests` fails when this table and the catalog disagree, so add a row here
whenever a shortcut is added.

## Checking a change by hand

Open a library with several photos, put focus in each state below, and press the key. The result
must match the expected cell, and no key may sound a system alert beep. Run the affected rows in the
signed, sandboxed app (`Kromora` scheme in `Kromora.xcodeproj`) after changing key handling.

Menu commands follow the availability gates in `MenuCommands.swift` (`MenuCommandAvailability` and
the keyboard context). A command that is unavailable in the current context (for example `H`
outside Retouch, or a rating with no active selection) is a disabled or silent no-op, not a beep.
Where a cell says "runs" the command runs only if it is available in that context; otherwise it does
nothing, silently.

## Focus states

| Code | Focus state | How to get there |
| --- | --- | --- |
| CV | Canvas focused | Click the photo in Edit (or the grid in Library) |
| WP | Toolbar workspace picker focused | Click Library/Edit segmented control |
| CM | Culling menu focused | Click the culling/flag menu in the toolbar |
| BT | A focused button | Click any toolbar or panel button (or Tab to one) |
| TF | Text field editing | Click into Look name, search, rename or a numeric field |
| SL | Slider focused | Click a Develop slider |
| SH | Sheet open | Open Keyboard Shortcuts, Save Look, Selective Copy or the Photos picker |

## Expected results

Legend for expected results:

- **runs** - the command runs (if available) and nothing beeps.
- **types** - the key edits the text; no shortcut fires.
- **slider** - the slider adjusts by its own arrow handling; no photo/Look navigation.
- **suppressed** - nothing happens; sheet suppression; no beep.
- **activates** - the focused button handles Space itself.

| Shortcut | Keys | Area | Delivery | CV | WP | CM | BT | TF | SL | SH |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Open photos | ⌘O | Library | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
| Import from Photos | ⌘⇧I | Library | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
| Open source folder | ⌘⌥I | Library | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
| Rebuild library index | ⌘R | Library | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
| Delete selected photos | Delete | Library | surface | runs | runs | runs | runs | types | runs | suppressed |
| Library workspace | G | Navigation | menu key, view | runs | runs | runs | runs | types | runs | suppressed |
| Edit workspace / erase mask tool | E | Navigation | menu key, view | runs | runs | runs | runs | types | runs | suppressed |
| Select previous / next photo | ← / → | Library and Edit | surface | runs | runs | runs | runs | types | slider | suppressed |
| Previous / next Look, or grid row | ↑ / ↓ | Library and Edit | surface | runs | runs | runs | runs | types | slider | suppressed |
| Open the selected photo in Edit | Return | Library | surface | runs | runs | runs | runs (Return/Space on button activates it) | types | runs | suppressed |
| Pick photo | P | Library | menu key, photo | runs | runs | runs | runs | types | runs | suppressed |
| Reject photo | X | Library | menu key, photo | runs | runs | runs | runs | types | runs | suppressed |
| Clear flag | U | Library | menu key, photo | runs | runs | runs | runs | types | runs | suppressed |
| Clear rating | 0 | Library | menu key, photo | runs | runs | runs | runs | types | runs | suppressed |
| Rate 1 star | 1 | Library | menu key, photo | runs | runs | runs | runs | types | runs | suppressed |
| Rate 2 stars | 2 | Library | menu key, photo | runs | runs | runs | runs | types | runs | suppressed |
| Rate 3 stars | 3 | Library | menu key, photo | runs | runs | runs | runs | types | runs | suppressed |
| Rate 4 stars | 4 | Library | menu key, photo | runs | runs | runs | runs | types | runs | suppressed |
| Rate 5 stars | 5 | Library | menu key, photo | runs | runs | runs | runs | types | runs | suppressed |
| Undo / redo edit | ⌘Z / ⇧⌘Z | Edit | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
| Reset photo | ⇧⌘R | Edit | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
| Apply Auto edits | ⇧A | Edit | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
| Copy edits | ⌘C | Edit | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
| Paste edits | ⌘V or ⌥⌘V | Edit | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
| Show original (hold) | Space or ⌘\ | Edit | surface | runs | runs | runs | activates | types | runs | suppressed |
| Toggle comparison | V | Edit | menu key, view | runs | runs | runs | runs | types | runs | suppressed |
| Toggle capture information overlay | I | Edit | menu key, view | runs | runs | runs | runs | types | runs | suppressed |
| Export selected photos or active photo | ⌘S | Library and Edit | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
| Crop | C | Edit | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Apply or cancel crop | Return / Esc | Crop | surface | runs | runs | runs | runs (Return/Space on button activates it) | types | runs | suppressed |
| Previous photo / rotate left / smaller brush | [ | Edit | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Next photo / rotate right / larger brush | ] | Edit | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Smaller brush or spot feather | ⇧[ | Masks and Retouch | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Larger brush or spot feather | ⇧] | Masks and Retouch | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Retouch tool | Q | Edit | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Retouch visualization | A | Retouch | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Cycle retouch overlay | H | Retouch | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Next retouch source | / | Retouch | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Brush mask tool | B | Masks | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Linear mask tool | L | Masks | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Radial mask tool | R | Masks | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Show or hide mask overlay | O | Masks | menu key, tools | runs | runs | runs | runs | types | runs | suppressed |
| Nudge selected mask | ← → ↑ ↓ (⇧ to accelerate) | Masks | surface | runs | runs | runs | runs | types | slider | suppressed |
