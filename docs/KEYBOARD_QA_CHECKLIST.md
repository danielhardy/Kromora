# Keyboard QA checklist

Hands-on verification of the KRMA-920 keyboard rework in the signed, sandboxed app (KRMA-926).
The rows are generated from `KeyboardShortcutCatalog.all`
(`Sources/KromoraKit/Views/KeyboardShortcutCatalog.swift`); `KeyboardShortcutCatalogTests`
fails when this table and the catalog disagree. Add a row here whenever a shortcut is added.

- **Build under test:** `Kromora` scheme run from `Xcode/Kromora.xcodeproj` (signed, App Sandbox), on `efe50615` plus uncommitted working-tree changes
- **Date:** 2026-10-13
- **Heard any system alert beep during the run?** No

## Results (2026-10-13 spot check)

This was a hands-on spot check of clicking around and using the keyboard in the signed build, not a
cell-by-cell run of the grid below. The per-cell result columns were not filled in, and the
requirement to fill them in was waived by the human on 2026-10-13 (KRMA-926). The grid remains
available as an optional aid for future keyboard changes.

1. `keyboardRouter` resolves in the real scene: **yes**. Photo and Tools menu items are enabled and
   shortcuts run. This agrees with the KRMA-920 by-ear confirmation.
2. Plain ⌘V: **keep**. KRMA-966 (`bfa146d4`) restored ⌘V as a standard Paste command, so it pastes
   copied edits in the editor while a focused text field keeps its own paste. The KRMA-920 deviation
   no longer applies.
3. Failure found: **Esc does not cancel the crop tool**. Tracked in KRMA-969.
4. Unrelated polish found: the top-right toolbar buttons are all bronze. Tracked in KRMA-970.

## How to run

Open a collection with several photos, then for each focus state put the focus there and press the
key. Record **P** (matches expected), **F** (differs; note what happened), **B** (correct but the
system beep sounded) or **-** (not applicable). Every cell must also be silent.

Menu items are always enabled by design, so a command that is unavailable in the current context
(for example `H` outside Retouch, a rating with no active collection) is a silent no-op, not a beep.
Where a cell says "runs" the command must run only if it is available in that context; otherwise
it must do nothing, silently.

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
| Refresh library | ⌘R | Library | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
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
| Export edited photo | ⌘S | Edit | standardMenu | runs (menu) | runs (menu) | runs (menu) | runs (menu) | menu/field default | runs (menu) | suppressed or sheet default |
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

## Results

Replace each expected-result cell above with P / F / B and a note, or record failures here:

| Shortcut | Focus state | Result | Notes / child ticket |
| --- | --- | --- | --- |
| | | | |

Every failing cell needs a fix commit referencing KRMA-926 or a child ticket labelled
`release-readiness,must-fix`.
