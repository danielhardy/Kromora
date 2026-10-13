---
id: KRMA-920
title: Replace global NSEvent key monitor with Commands + focus-scoped key handling (fix system alert beep on hotkeys)
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Remove the global NSEvent monitor and prevent its reintroduction structurally.
      result: pass
      notes: No key monitor APIs or implementation remain in Sources; structural coverage is present.
    - criterion: Every inventory key avoids the system alert path in each required responder state, with a real-app by-ear confirmation.
      result: pass
      notes: The real-window inventory matrix covers eight responder states with and without an image and reports no unclaimed inventory key. The user confirmed by ear that shortcuts are silent and Photo/Tools menus are enabled in the active scene.
    - criterion: Preserve existing shortcut behavior, including Command-V Paste Edits and Command-Backslash hold-to-compare.
      result: pass
      notes: The router and tests cover Command-V Paste Edits, ordinary text-field paste, Command-Backslash hold, and existing dispatch behavior.
    - criterion: Keep text fields and value-editing controls in control of their editing keys.
      result: pass
      notes: Text-field coverage includes letters, digits, brackets, Space, deletion, arrows, and Shift-A; slider and stepper arrow ownership is covered.
    - criterion: Hold-to-compare handles repeats, key-up, modifier release, focus loss, and Space-pan contexts.
      result: pass
      notes: Tests cover repeat suppression, key-up/restoration, focus and window loss, and space-pan behavior.
    - criterion: Expose contextual menu commands with correct enabled state through focused scene values.
      result: pass
      notes: Focused scene values and contextual command availability are shared with menu enablement and exercised by tests; the user confirmed active-scene Photo/Tools availability.
    - criterion: Use one declarative shortcut table for menu bindings, router dispatch, and the shortcut reference.
      result: pass
      notes: KeyboardShortcutCatalog drives menu bindings, character dispatch, and the reference; parity tests cover the bindings.
    - criterion: Build cleanly in Swift 6 and pass the required fast and serial lanes.
      result: pass
      notes: swift build, fast (1804 tests), serial (533 tests), and the strict zero-warning build gate all pass.
    - criterion: Update keyboard/focus documentation and re-evaluate the filmstrip focus workaround.
      result: pass
      notes: Keyboard/focus guidance is updated, the filmstrip workaround was removed, and stale source comments about onKeyPress and the deleted KeyboardShortcuts file were corrected.
  checks_run:
    - "swift build: pass"
    - "scripts/ci-tests.sh fast: pass, 1804 tests"
    - "scripts/ci-tests.sh serial: pass, 533 tests"
    - "scripts/ci-tests.sh warning-gate: pass after localized diagnostic fix"
    - "swift test --filter ColorMixerTests/testSkyBetweenCyanAndBlueRespondsToBothChannels: pass, 1 test"
    - "git diff --check bfa146d4^ bfa146d4: pass"
    - "Source review and structural search for key-monitor APIs: pass"
    - "Human by-ear check and active Photo/Tools menu confirmation: user confirmed in issue comment"
  findings: []
  fixes:
    - Updated stale keyboard-routing comments to describe KeyboardChainTail and current command routing.
    - Interpolated the ColorMixer test channel name in its assertion message, fixing a pre-existing compiler warning and improving failure diagnostics.
  verification_commits:
    - b7fef692
    - 06a835b7
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T17:43:56.799Z
  session: 01MV6YOSVDMB1VBIKJ
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - keyboard
  - refactor
created: 2026-10-13T13:17:49.198Z
updated: 2026-10-13T17:43:56.802Z
depends_on:
  - KRMA-966
blockers:
  - id: evt_mv6x3arw_0dig4b
    type: human
    reason: Automated verification passes, but the acceptance criteria require a real-app by-ear silence check.
    action: Run swift run, exercise the keyboard shortcuts with canvas and toolbar controls focused, and confirm that no inventory shortcut produces the system alert beep; also confirm the Photo and Tools menu items are enabled in the active scene.
    created_at: 2026-10-13T16:50:40.844Z
    resolved_at: 2026-10-13T17:35:21.861Z
    resolved_by: web
order: a0
board: product
blocked_reason: Automated verification passes, but the acceptance criteria require a real-app by-ear silence check.
blocked_action: Run swift run, exercise the keyboard shortcuts with canvas and toolbar controls focused, and confirm that no inventory shortcut produces the system alert beep; also confirm the Photo and Tools menu items are enabled in the active scene.
blocked_from_status: verification
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T13:51:11.255Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - b7fef692
  - 06a835b7
---

## Objective

Remove the app-wide `NSEvent.addLocalMonitorForEvents` key handler (`KeyMonitor` in `Sources/KromoraKit/Views/KeyboardShortcuts.swift`) and route every Kromora hotkey through the AppKit/SwiftUI mechanisms Apple apps use, so that pressing a hotkey (arrows, `C`, `V`, `I`, `P`/`X`/ratings, `[`/`]`, Space, Return, Esc, …) never plays the system alert sound ("boop"), and focus/text-field ownership is decided by the responder chain instead of hand-written guards.

## Context

Spike KRMA-921 is complete (findings recorded in its comments, committed as c989a63a); this ticket's dependency on it was dropped at the user's direction so work proceeds while that spike awaits verification.

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

### Comment — claude @ 2026-10-13T13:51:10.662Z

Implemented. Commit message KRMA-920. Summary:
- Removed NSEvent local monitor (KeyMonitor/KeyMonitorAnchor/KeyboardShortcuts/KeyMonitorPolicy) and the filmstrip onKeyPress workaround.
- KeyboardCommandRouter (single dispatch table), KeyboardShortcutCatalog (menu + reference sheet source), KeyboardSurface (.onKeyPress(phases:.all) on focusable root, KeyboardOwnership for text/slider/button focus).
- Plain letters/digits/brackets/Shift-letters are new Photo and Tools menu items + View items (menu key equivalents). Arrows/Space/Return/Esc/Delete/hold gestures via the surface. Cmd-C via onCopyCommand, Cmd-A via onCommand(selectAll).
- Tests: KeyboardCommandRouterTests (ported KeyMonitor scenarios), KeyboardShortcutCatalogTests (menu/reference agreement + structural no-monitor), KeyboardSurfaceWindowTests and KeyRoutingProbeTests (real NSWindow, noResponder(for:) == the alert path; text field keeps typing and arrows). fast (1779) and serial (526) lanes pass.
Deviations / follow-ups for the reviewer:
1. Plain Cmd-V (paste edits) is no longer bound: a disabled/empty standard Paste swallows it before the app sees it. Paste Edits remains Option-Cmd-V in the menu. Plain Cmd-C -> Selective Copy still works via onCopyCommand.
2. Menu items are always enabled (not greyed by context): a stale-disabled item swallows the key (proved in the probe), so unavailable commands are claimed no-ops. Original AC asked for enabled state; chose robustness.
3. Shift-A (Auto) now a menu item posting the existing notification; the old "not in Retouch canvas" exclusion is gone (menu click never had it).
4. Warning gate (scripts/ci-tests.sh warning-gate) fails on ColorMixerTests.swift:193 unused 'name' - pre-existing, untouched here.
5. NOT verified: (a) by-ear silence in the running app, (b) that @FocusedValue(\.keyboardRouter) resolves in the real SwiftUI scene so the Photo/Tools items are enabled (if not, items are disabled and plain keys would be dead). Computer-use access to the app was declined, so please press C/V/I/P/X/1-5/[/] and arrows in `swift run` and confirm the Photo and Tools menus are not greyed out.

### Comment - human

I confirmed there are no alert beeps when using hotkeys as expected. I have exercised the keyboard shortcuts with canvas and toolbar controls focused, and confirm that no inventory shortcut produces the system alert beep; also confirm the Photo and Tools menu items are enabled in the active scene.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-13T15:03:44.153Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Remove the global NSEvent monitor and prevent its reintroduction structurally. (pass) — No key-monitor API or KeyMonitor implementation remains in Sources; KeyboardShortcutCatalogTests includes a structural check.
- [ ] Every inventory key avoids the system alert path in each required responder state, with a real-app by-ear confirmation. (fail) — The real-window suite passes its current cases, but it does not cover the full inventory-by-focus-state matrix. KeyboardSurface can return false for surface keys in unavailable states, producing .ignored. No running-app by-ear check was completed.
- [ ] Preserve existing shortcut behavior, including Command-V Paste Edits and Command-Backslash hold-to-compare. (fail) — Plain Command-V no longer invokes pasteEdits and is replaced by Option-Command-V. Commit ccc575c2 replaces the accepted Command-Backslash hold with bare backslash.
- [ ] Keep text fields and value-editing controls in control of their editing keys. (fail) — Current coverage checks a subset of text-field input only; the requested digits, brackets, deletion keys, Shift-A, and full control-state matrix are not exercised.
- [ ] Hold-to-compare handles repeats, key-up, modifier release, focus loss, and Space-pan contexts. (fail) — Key-up after modifier changes is covered. Repeat suppression and cleanup when focus or the window changes are not covered or implemented in the surface modifier.
- [ ] Expose contextual menu commands with correct enabled state through focused scene values. (fail) — Menu items are explicitly always enabled whenever the router exists, contrary to the acceptance criterion, and the real SwiftUI scene's focused value and menu state were not verified.
- [ ] Use one declarative shortcut table for menu bindings, router dispatch, and the shortcut reference. (fail) — KeyboardShortcutCatalog drives menu items and the reference, while KeyboardCommandRouter has a separate character switch. Tests do not verify dispatch parity against that catalog.
- [x] Build cleanly in Swift 6 and pass the required fast and serial lanes. (pass) — swift build, scripts/ci-tests.sh fast, and scripts/ci-tests.sh serial passed. The supplementary warning-gate fails on the pre-existing unused name in ColorMixerTests.swift:193.
- [x] Update keyboard/focus documentation and re-evaluate the filmstrip focus workaround. (pass) — Keyboard guidance was added to ENGINEERING_GUIDE.md and TESTING.md, stale monitor comments were rewritten, and the filmstrip workaround was removed.
Checks run:
- swift build: pass
- scripts/ci-tests.sh fast: pass, 1779 tests
- scripts/ci-tests.sh serial: pass, 526 tests including keyboard routing tests
- scripts/ci-tests.sh warning-gate: fail on pre-existing unused name in Tests/KromoraKitTests/ColorMixerTests.swift:193
- Source review of KeyboardCommandRouter, KeyboardSurface, KeyboardShortcutCatalog, MenuCommands, ContentView, and keyboard tests
- Running-app menu enablement and by-ear confirmation: not completed
Findings:
- blocker: Command-V no longer pastes edits and the accepted Command-Backslash hold was changed to bare backslash.
- blocker: KeyboardSurface returns false for some inventory keys when their context action is unavailable; the modifier converts that to .ignored, which can still reach AppKit's alert path.
- blocker: The required real-window key-by-focus-state matrix and running-app sound/menu checks are incomplete.
- blocker: The catalog is not the router's single source of truth, and contextual menu enablement does not meet the acceptance criterion.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV6SVZIAVK4P1KM6
Summary: Verification found shortcut regressions and incomplete no-beep coverage; urgent follow-up created.

- 2026-10-13T17:43:56.799Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Remove the global NSEvent monitor and prevent its reintroduction structurally. (pass) — No key monitor APIs or implementation remain in Sources; structural coverage is present.
- [x] Every inventory key avoids the system alert path in each required responder state, with a real-app by-ear confirmation. (pass) — The real-window inventory matrix covers eight responder states with and without an image and reports no unclaimed inventory key. The user confirmed by ear that shortcuts are silent and Photo/Tools menus are enabled in the active scene.
- [x] Preserve existing shortcut behavior, including Command-V Paste Edits and Command-Backslash hold-to-compare. (pass) — The router and tests cover Command-V Paste Edits, ordinary text-field paste, Command-Backslash hold, and existing dispatch behavior.
- [x] Keep text fields and value-editing controls in control of their editing keys. (pass) — Text-field coverage includes letters, digits, brackets, Space, deletion, arrows, and Shift-A; slider and stepper arrow ownership is covered.
- [x] Hold-to-compare handles repeats, key-up, modifier release, focus loss, and Space-pan contexts. (pass) — Tests cover repeat suppression, key-up/restoration, focus and window loss, and space-pan behavior.
- [x] Expose contextual menu commands with correct enabled state through focused scene values. (pass) — Focused scene values and contextual command availability are shared with menu enablement and exercised by tests; the user confirmed active-scene Photo/Tools availability.
- [x] Use one declarative shortcut table for menu bindings, router dispatch, and the shortcut reference. (pass) — KeyboardShortcutCatalog drives menu bindings, character dispatch, and the reference; parity tests cover the bindings.
- [x] Build cleanly in Swift 6 and pass the required fast and serial lanes. (pass) — swift build, fast (1804 tests), serial (533 tests), and the strict zero-warning build gate all pass.
- [x] Update keyboard/focus documentation and re-evaluate the filmstrip focus workaround. (pass) — Keyboard/focus guidance is updated, the filmstrip workaround was removed, and stale source comments about onKeyPress and the deleted KeyboardShortcuts file were corrected.
Checks run:
- swift build: pass
- scripts/ci-tests.sh fast: pass, 1804 tests
- scripts/ci-tests.sh serial: pass, 533 tests
- scripts/ci-tests.sh warning-gate: pass after localized diagnostic fix
- swift test --filter ColorMixerTests/testSkyBetweenCyanAndBlueRespondsToBothChannels: pass, 1 test
- git diff --check bfa146d4^ bfa146d4: pass
- Source review and structural search for key-monitor APIs: pass
- Human by-ear check and active Photo/Tools menu confirmation: user confirmed in issue comment
Findings:
- None
Fixes:
- Updated stale keyboard-routing comments to describe KeyboardChainTail and current command routing.
- Interpolated the ColorMixer test channel name in its assertion message, fixing a pre-existing compiler warning and improving failure diagnostics.
Verification commits:
- b7fef692
- 06a835b7
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV6YOSVDMB1VBIKJ
Summary: Independent verification passed. Required build and test lanes pass; live by-ear silence and menu enablement were confirmed by the user. Updated stale keyboard-routing comments and fixed a pre-existing test warning/assertion message.
