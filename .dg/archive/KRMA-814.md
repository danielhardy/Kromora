---
id: KRMA-814
title: Add a keyboard shortcut for applying Auto edits
type: task
status: done
priority: urgent
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Keyboard command invokes existing Auto edit behavior
      result: pass
      notes: KeyMonitor calls vm.runAutoAdjustment()
    - criterion: Discoverable, conflict-checked shortcut
      result: pass
      notes: Shift+A handled after text-responder deferral; skipped in retouch canvas (plain A conflict); menu title shows hint without key equivalent
    - criterion: Listed in keyboard shortcut reference
      result: pass
    - criterion: Focused coverage for routing and discoverability
      result: pass
      notes: KeyMonitorTests cover NSTextView/NSTextField deferral, run on editable photo, no-photo and retouch-canvas cases, modifier policy
  checks_run:
    - swift test --filter MenuCommandTests|KeyMonitorTests (34 passed)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T15:53:56.187Z
  session: 01MUU033BO0NIESE0R
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
created: 2026-10-04T02:34:50.644Z
updated: 2026-10-04T15:53:56.191Z
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T15:11:53.624Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Expose the existing Auto edit operation as a keyboard command so users can apply automatic adjustments without leaving the keyboard workflow.

## Acceptance criteria

- Add a keyboard command that invokes the existing Auto edit behavior for the active photo; do not introduce new adjustment semantics.
- Choose and document a discoverable shortcut (consider `A` or `Shift+A`) after checking for conflicts and following macOS keyboard conventions.
- Include the command and shortcut in the app’s existing keyboard shortcut reference so users can discover it.
- Add or update focused coverage for command routing and shortcut discoverability.


### Comment — codex @ 2026-10-04T15:11:50.849Z

Implemented the Auto edit command on Shift+A and added it to the keyboard shortcut reference. The command routes through the existing runAutoAdjustment() behavior. Verification: swift test --filter MenuCommandTests passed (12 tests). Commit: 65c81a32.

## Verification blocker (claude, 2026-10-04)

**What failed:** `Apply Auto Edits` is a bare-Shift SwiftUI menu `keyboardShortcut("a", [.shift])`. Menu key equivalents are resolved before the responder chain, so typing a capital "A" in any text field or text view (rename, search, keywords, notes) will trigger Auto instead of inserting the character. The repo's `KeyMonitor` exists precisely to defer plain-character shortcuts to `NSText`/`NSControl` first responders (`KeyMonitorPolicy.globalShortcutsOwnKeyboard`), and the neighbouring plain `A` retouch toggle uses it. The menu route bypasses that contract. The test is also string-grep over source files and does not exercise routing or focus behavior.

**What must change:** Route Shift+A through `KeyMonitor` (guarded by `KeyMonitorPolicy` so focused text input/controls keep the keystroke, only when an editable image is active and not in the retouch canvas conflict) and call `runAutoAdjustment()`. Keep the menu item for discoverability without a bare-letter key equivalent (or show the hint in the title only). Replace source-grep assertions with a `KeyMonitorPolicy`/routing test: Shift+A with a text responder is not consumed; with no text focus it invokes Auto.

**How to verify:** `swift test --filter MenuCommandTests` plus the KeyMonitor policy tests; manually confirm typing "A" in a text field does not run Auto.

### Comment — codex @ 2026-10-04T15:53:15.683Z

Implemented Shift+A through KeyMonitor, which defers to text views and fields, requires a ready photo, and skips the retouch canvas. The menu title and keyboard shortcut reference display ⇧A without a menu key equivalent. Replaced source-grep routing assertions with policy and event-routing coverage. Verification: swift test --filter 'MenuCommandTests|KeyMonitorTests' (34 passed); git diff --check clean. Commit: 5c7f9026.

## Agent log

- 2026-10-04T15:12:41.879Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Keyboard command invokes existing Auto edit behavior (pass) — Routes to runAutoAdjustment()
- [ ] Discoverable, conflict-checked shortcut (fail) — Bare Shift+A menu key equivalent bypasses KeyMonitor text-input deferral and will intercept typing capital A in text fields
- [x] Listed in keyboard shortcut reference (pass)
- [ ] Focused coverage for routing and discoverability (fail) — Test greps source text; does not test routing or focus policy
Checks run:
- swift test --filter MenuCommandTests (12 passed)
Findings:
- Bare-letter menu shortcut steals keystrokes from text inputs
- Source-grep test gives false confidence
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUTYLT7DAKMUBKM7
Summary: Bare Shift+A menu shortcut steals capital A from text inputs; route through KeyMonitor with focus policy and replace grep-based test.

- 2026-10-04T15:53:56.187Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Keyboard command invokes existing Auto edit behavior (pass) — KeyMonitor calls vm.runAutoAdjustment()
- [x] Discoverable, conflict-checked shortcut (pass) — Shift+A handled after text-responder deferral; skipped in retouch canvas (plain A conflict); menu title shows hint without key equivalent
- [x] Listed in keyboard shortcut reference (pass)
- [x] Focused coverage for routing and discoverability (pass) — KeyMonitorTests cover NSTextView/NSTextField deferral, run on editable photo, no-photo and retouch-canvas cases, modifier policy
Checks run:
- swift test --filter MenuCommandTests|KeyMonitorTests (34 passed)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUU033BO0NIESE0R
Summary: Shift+A now routes through KeyMonitor with text-input deferral, ready-photo and retouch-canvas guards; menu item has no bare key equivalent; behavioral tests replace source grep.
