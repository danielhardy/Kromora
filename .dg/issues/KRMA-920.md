---
id: KRMA-920
title: Replace global NSEvent key monitor with Commands + focus-scoped key handling (fix system alert beep on hotkeys)
type: task
status: backlog
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - keyboard
  - refactor
created: 2026-10-13T13:17:49.198Z
updated: 2026-10-13T13:19:01.621Z
depends_on:
  - KRMA-921
blockers: []
order: h
board: product
---

## Objective

Remove the app-wide `NSEvent.addLocalMonitorForEvents` key handler (`KeyMonitor` in `Sources/KromoraKit/Views/KeyboardShortcuts.swift`) and route every Kromora hotkey through the AppKit/SwiftUI mechanisms Apple apps use, so that pressing a hotkey (arrows, `C`, `V`, `I`, `P`/`X`/ratings, `[`/`]`, Space, Return, Esc, …) never plays the system alert sound ("boop"), and focus/text-field ownership is decided by the responder chain instead of hand-written guards.

## Context

**Root cause (code review, 2026-10-13).** The monitor consumes a key by returning `nil`; a key-down it returns (`return event`) and that nothing else claims reaches `NSResponder.keyDown` → `noop:` → `NSBeep`. It returns the event in two common situations:

1. `KeyMonitorPolicy.globalShortcutsOwnKeyboard` (KeyboardShortcuts.swift ~L314) defers *every* character shortcut whenever the first responder is any `NSControl` (toolbar picker, segmented control, culling menu, button, slider). Those controls keep focus after a click, so `C`, `V`, `I`, `Q`, `P`, `X`, `[` … beep. Arrow keys were patched separately (handled before that gate); character keys never were.
2. Dozens of `guard … else { return event }` branches decline a *recognized* key (e.g. `C` with no image, `V` when side-by-side is unavailable, culling keys with no active collection), which also beeps.

The filmstrip already carries a one-off workaround (`.focusable(false)` + `.onKeyPress(phases: .all)`), evidence that the monitor approach fights the focus system.

**Constraints discovered.**
- `MenuCommands.swift` documents that AppKit resolves menu key equivalents *before* the text-input focus policy, which is why Shift+A has no menu key equivalent. A menu-only approach for plain letters may steal typing from text fields. Phase 0 must settle this empirically; do not assume.
- `CLAUDE.md`: macOS 26+, Apple Silicon only, zero third-party deps, Swift 6 mode with zero escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency` are forbidden), no `#available` fallbacks.
- Hold-to-compare gestures (Space, ⌘\) need key-down *and* key-up, and ⌘\ must still end if ⌘ is released first.

**Shortcut inventory to preserve** (source: `KeyMonitor.handle` / `handleArrow`):
- Arrows: ←/→ previous/next photo (grid + edit; nudge selected mask when masking workspace open, ⇧ accelerates); ↑/↓ previous/next Look in edit, row up/down in grid; mask nudge.
- Edit/Canvas: `C` toggle crop, Return commit crop / open in Edit from grid, Esc cancel crop → retouch draft → deselect spot → mask draft → mask tool → close masking → disarm retouch, `[` `]` rotate in crop / brush radius+⇧feather in masking / retouch radius+⇧feather / otherwise prev/next photo, Delete/Fwd-Delete remove retouch spot or (grid) library items, `A` retouch visualization (retouch only), ⇧A auto adjust, `Q` retouch toggle/arm, `G` grid, `E` edit, `B`/`L`/`R` mask tools (when masking), `I` capture overlay, `V` side-by-side, `O`/`/`/`H` (read and preserve current behaviour of these branches), Space hold = compare original (or retouch/mask space-pan), ⌘\ hold = Original.
- Culling (active collection only): `P` pick, `X` reject, `U` clear flag, `0`–`5` rating.
- ⌘C opens Selective Copy, ⌘V pastes edits, ⌘A select all (grid), ⌘Z/⇧⌘Z undo/redo incl. `undoCullingChange` fallback.
- Suppressed while any sheet/dialog is presented (`derive`, `lookSave`, removable media, Photos picker, selective copy).

## Acceptance criteria

- [ ] **No monitor.** `NSEvent.addLocalMonitorForEvents`/`addGlobalMonitor` no longer appears in `Sources/`; `KeyMonitor`, `KeyMonitorAnchor`, the `KeyboardShortcuts` view modifier and `KeyMonitorPolicy` focus-ownership helpers are deleted. A structural test (modelled on `PackageSettingsTests`) fails if a key monitor is reintroduced.
- [ ] **No alert beep.** For every key in the inventory above, in each first-responder state — canvas/surface, toolbar workspace picker (`NSSegmentedControl`), `NSPopUpButton`/culling menu, a focused `NSButton`, a list/outline — the key is either claimed by the app (command runs or an intentional no-op is reported as handled) or deliberately left to a value-editing control/text field. A serial-lane test with a real `NSWindow` drives key events through `NSWindow.sendEvent` and asserts that no inventory key reaches the terminal default `NSResponder.keyDown` implementation (the beep path) in any of those states. The user confirms by ear in the running app (state this check explicitly in the review comment; it cannot be automated).
- [ ] **Behavior parity.** Every inventory shortcut keeps its existing behavior, including precedence rules (Esc ladder, `[`/`]` context dispatch, arrows in masking), culling gated on an active collection, and sheet suppression. Existing `KeyMonitorTests` scenarios are ported to the new entry point (not deleted), keeping their assertions.
- [ ] **Text fields stay typeable.** With a text field/field editor focused (Look name, search, rename, numeric fields), letters, digits, `[`, `]`, Space, Delete and arrows edit text and never fire a shortcut. ⇧A and plain-letter shortcuts are covered explicitly (see Constraints). Sliders/steppers keep their arrow-key value editing.
- [ ] **Hold gestures.** Space and ⌘\ show Original on key-down and restore on key-up; auto-repeat key-downs do not retrigger; ⌘\ restores if ⌘ is released first or focus moves; Space pan in retouch/mask tools still works.
- [ ] **Menu integration.** Discrete commands (crop, rotate, side-by-side, capture overlay, Looks previous/next, photo previous/next, culling flags/ratings, retouch toggle, Selective Copy/Paste Edits, Auto) appear in the menu bar with their key equivalents and correct enabled/disabled state, driven by `focusedSceneValue`/`@FocusedValue` (or equivalent) rather than `NotificationCenter` for any *new* command. Existing notification-based File-menu items are left alone unless trivially migrated.
- [ ] **Single source of truth.** One declarative shortcut table (pure model, unit-tested) feeds the menu bindings, the key handler, and `KeyboardShortcutReferenceView`; a test fails if the reference sheet and the actual bindings disagree.
- [ ] **Quality bar.** Swift 6 mode with zero diagnostics and zero escape hatches (`PackageSettingsTests` passes); no `#available` branches; `swift build` is warning-free; `scripts/ci-tests.sh fast` and `scripts/ci-tests.sh serial` exit 0.
- [ ] **Docs.** `docs/ENGINEERING_GUIDE.md` (keyboard/focus invariants) and `docs/TESTING.md` updated; the stale `.onKeyPress`/monitor rationale comments removed or rewritten; filmstrip `.focusable(false)` workaround re-evaluated and removed if no longer needed.

## Implementation notes

Design decided by the KRMA-921 spike (see its comment; evidence in `KeyRoutingProbeTests`, which provides the `NSWindow.noResponder(for:)` no-beep seam):

- **Layer A – `Commands` menu key equivalents** for plain letters, digits and brackets (`c v i q g e b l r p x u 0–5 [ ]`) and all modified commands (⇧A, ⌘C/⌘V selective copy/paste, ⌘A, ⌘\ is hold so Layer B). AppKit treats an unmodified menu key equivalent as the last chance before the beep: it fires from buttons/segmented controls/sliders, does not fire while a text field is editing, and a disabled item still swallows the key. Enabled state comes from `focusedSceneValue` of the active editor/library context. The stale comment in `MenuCommands.swift` claiming menu key equivalents beat text fields is wrong and must be corrected.
- **Layer B – focus-scoped `.onKeyPress(phases: .all)`** on a focusable Library/Edit surface (`.focusable()`, `.focusEffectDisabled()`, `@FocusState`/`.defaultFocus`) for arrows (arrow menu equivalents would steal caret movement from text fields), Space hold, Esc ladder, Return, Delete/Forward Delete, ⌘\ hold. Always return `.handled` for keys the app owns (`.ignored` beeps). Pure-click toolbar controls (workspace picker, culling menu) refuse first responder (`.focusable(false)`) so keys are not stranded on an `NSControl`; slider/stepper/text input stay focusable.
- Residual risk: arrows while a toolbar `NSControl` holds AppKit focus in the real app. Verify with the real-window probe; fallback is arrow menu equivalents gated by a text-input-active focused value.

Plan:
1. **Model**: pure shortcut table (`KeyboardCommand`, key, modifiers, layer, context predicate, phase) migrated from the `switch` tables; port `LibraryCullingCommand.parse`; unit tests first; reference sheet reads from it.
2. **Handler**: command dispatcher on the view model preserving precedence (Esc ladder, `[`/`]` dispatch, masking arrows, culling gate, sheet suppression) — shared by Layer A and B.
3. **Layer A**: `Commands` items + focused scene values + enablement.
4. **Layer B**: key-handling surface modifier, focus reclamation, toolbar controls refuse focus; remove filmstrip workaround if redundant.
5. **Delete** `KeyMonitor`, `KeyMonitorAnchor`, `KeyboardShortcuts`, `KeyMonitorPolicy` focus helpers; add structural no-monitor test.
6. **Tests**: port `KeyMonitorTests`; real-window no-beep matrix (every inventory key × focus states) using the probe seam; text-field matrix.
7. **Docs**, `swift build`, `scripts/ci-tests.sh fast` + `serial`, hand off to review with the explicit "needs ear-check" note.

Do not run the display-bound capture benchmarks (see CLAUDE.md).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
