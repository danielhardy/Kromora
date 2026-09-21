---
id: KRMA-361
title: Add a Command-Backslash shortcut to flash the original photo view
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Command+Backslash is recognized and bare Backslash is not registered
      result: pass
      notes: KeyMonitor routes only key code 42 with exactly the Command modifier; bare, shifted, option, control, and other key variants pass through.
    - criterion: Key-down shows Original and key-up restores Edited in single-image view
      result: pass
      notes: The monitor tracks the accepted hold and restores on matching key-up even when Command is released first; focused tests cover both events.
    - criterion: Focus-safe editor and inspector behavior
      result: pass
      notes: Existing global focus policy continues to defer to NSText and NSControl responders, while canvas/ordinary editor views route the shortcut; system-modified variants remain untouched.
    - criterion: Unavailable/no-source and side-by-side behavior is safe
      result: pass
      notes: The shortcut is not consumed without a source or meaningful comparison and is not consumed in side-by-side mode; no side-by-side preference or pane changes occur.
    - criterion: Visible affordance documents Show Original as Command+Backslash
      result: pass
      notes: StatusBar shows ⌘\ / show original for meaningful single-view comparisons, ContentView help documents it alongside Space, and COMPARISON_MODE.md records the interaction contract.
    - criterion: Lifecycle cleanup prevents a stuck transient Original preview
      result: pass
      notes: Accepted key-up is tracked independently of modifier flags; existing photo-switch, reset, undo/redo, and view-mode cleanup remains in force, with comparison-mode tests green.
    - criterion: Automated coverage exercises new paths and existing comparison tests remain green
      result: pass
      notes: KeyMonitorTests covers policy, key-down/key-up, unavailable, and bare Backslash paths; all 15 ComparisonModeTests pass.
    - criterion: Comparison remains non-destructive and existing Space/V/render/export semantics remain unchanged
      result: pass
      notes: Only presentation routing and documentation changed; full test suite passed with no comparison/render/export regressions.
  checks_run:
    - swift test --filter KeyMonitorTests|ComparisonModeTests (23 passed)
    - swift test (1263 passed, 48 expected skips)
    - git diff --check
    - dg validate
  findings: []
  fixes: []
  verification_commits:
    - 3c9b10b
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-11T20:50:04.467Z
  session: 01MTXFCDV9PPVTL0W6
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ux
  - comparison
  - editor
  - keyboard
created: 2026-09-11T20:03:00.049Z
updated: 2026-09-11T20:50:04.469Z
order: a0
board: product
commits:
  - 3c9b10b
---

## Objective

Add a dedicated macOS keyboard shortcut for quickly comparing the current edit with the photo as it started. Choose `⌘\\` (Command + Backslash); do not add a second bare `\\` binding.

## Chosen interaction

- In single-image view, pressing and holding `⌘\\` temporarily replaces the Edited preview with the Original/comparison-baseline preview.
- Releasing `⌘\\` restores the Edited preview, matching the existing Space-to-flash behavior.
- The shortcut is presentation-only: it must not create edit history, change the saved document, affect export output, or persist transient original-view state.
- If there is no meaningful comparison, the shortcut is unavailable and must leave the current view unchanged.
- In side-by-side view, both versions are already visible; the shortcut should not hide either pane or change the side-by-side preference.

## Why this shortcut

Kromora is a native macOS editor, so `⌘\\` is explicit and discoverable without consuming the bare backslash key during text entry. It also keeps the existing Space gesture intact while giving users a dedicated, easy-to-remember before/after action.

## Acceptance criteria

- [ ] `⌘\\` is recognized in the editor and no bare `\\` shortcut is registered.
- [ ] With a meaningful comparison in single-image view, key-down shows the Original preview and key-up restores the Edited preview.
- [ ] The behavior is focus-safe: it works from the editor canvas and inspector, while not interfering with text-field editing or standard system shortcuts.
- [ ] The shortcut is unavailable/no-op when no source or comparison baseline exists, and it does not disturb side-by-side mode.
- [ ] A visible help/status/menu affordance documents the shortcut as `⌘\\` / “Show Original”.
- [ ] Photo switching, reset-to-identity, undo/redo, and view-mode changes cannot leave the app stuck showing the transient Original preview.
- [ ] Automated coverage exercises key-down/key-up and cleanup/unavailable paths; existing comparison-mode tests remain green.
- [ ] Comparison presentation remains non-destructive and existing Space, `V`, baseline, rendering, and export semantics remain unchanged.

## Implementation notes

Likely touch points are `Sources/KromoraKit/Views/KeyboardShortcuts.swift`, the comparison state in `AppViewModel`, `Sources/KromoraKit/Views/StatusBar.swift` or the relevant View menu, `docs/COMPARISON_MODE.md`, and the comparison/keyboard test suites. Follow the interaction contract established by KRMA-358.

## Agent log

- 2026-09-11T20:50:04.467Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Command+Backslash is recognized and bare Backslash is not registered (pass) — KeyMonitor routes only key code 42 with exactly the Command modifier; bare, shifted, option, control, and other key variants pass through.
- [x] Key-down shows Original and key-up restores Edited in single-image view (pass) — The monitor tracks the accepted hold and restores on matching key-up even when Command is released first; focused tests cover both events.
- [x] Focus-safe editor and inspector behavior (pass) — Existing global focus policy continues to defer to NSText and NSControl responders, while canvas/ordinary editor views route the shortcut; system-modified variants remain untouched.
- [x] Unavailable/no-source and side-by-side behavior is safe (pass) — The shortcut is not consumed without a source or meaningful comparison and is not consumed in side-by-side mode; no side-by-side preference or pane changes occur.
- [x] Visible affordance documents Show Original as Command+Backslash (pass) — StatusBar shows ⌘\ / show original for meaningful single-view comparisons, ContentView help documents it alongside Space, and COMPARISON_MODE.md records the interaction contract.
- [x] Lifecycle cleanup prevents a stuck transient Original preview (pass) — Accepted key-up is tracked independently of modifier flags; existing photo-switch, reset, undo/redo, and view-mode cleanup remains in force, with comparison-mode tests green.
- [x] Automated coverage exercises new paths and existing comparison tests remain green (pass) — KeyMonitorTests covers policy, key-down/key-up, unavailable, and bare Backslash paths; all 15 ComparisonModeTests pass.
- [x] Comparison remains non-destructive and existing Space/V/render/export semantics remain unchanged (pass) — Only presentation routing and documentation changed; full test suite passed with no comparison/render/export regressions.
Checks run:
- swift test --filter KeyMonitorTests|ComparisonModeTests (23 passed)
- swift test (1263 passed, 48 expected skips)
- git diff --check
- dg validate
Findings:
- None
Fixes:
- None
Verification commits:
- 3c9b10b
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTXFCDV9PPVTL0W6
Summary: Added hold-to-flash Command+Backslash original preview shortcut with focus-safe routing, cleanup tracking, status/help documentation, and automated key-down/key-up/unavailable coverage.
