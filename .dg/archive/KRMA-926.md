---
id: KRMA-926
title: Hands-on verification of the KRMA-920 keyboard rework in the signed sandboxed app
type: task
status: done
priority: urgent
human_review_required: true
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Signed sandboxed app spot check confirms keyboardRouter resolves in the real scene and Photo/Tools shortcuts work.
      result: pass
      notes: Human recorded yes in docs/KEYBOARD_QA_CHECKLIST.md on 2026-10-13; prior KRMA-920 real-window inventory matrix also passes.
    - criterion: Keyboard shortcuts are silent in the signed app; the required human by-ear check is complete.
      result: pass
      notes: Human recorded no alert beeps during the 2026-10-13 signed-build spot check; KRMA-920 verification records the real-window inventory matrix as having no unclaimed inventory key.
    - criterion: Plain Command-V behavior has an explicit decision and works as intended.
      result: pass
      notes: Human chose keep; KRMA-966 restored Command-V Paste Edits while text-field paste remains available.
    - criterion: The crop Escape failure found during hands-on QA is resolved and tracked to completion.
      result: pass
      notes: KRMA-969 is done and labeled release-readiness and must-fix; focused crop responder tests pass.
    - criterion: Keyboard QA evidence is committed, and the human waiver for the per-cell grid is recorded.
      result: pass
      notes: Commit 6b9fcd2f records the dated signed-build spot check; the human explicitly waived the per-cell grid, relying on the KRMA-920/KRMA-966 real-window matrix.
  checks_run:
    - swift test --filter KeyboardShortcutCatalogTests — passed (10 tests, 0 failures).
    - swift test --filter CropKeyboardWindowTests — passed (2 tests, 0 failures).
    - git diff --check 6b9fcd2f^ 6b9fcd2f — passed.
    - Reviewed docs/KEYBOARD_QA_CHECKLIST.md, KRMA-920 verification, KRMA-969 verification and labels, and KRMA-926 amended acceptance notes.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T19:26:03.063Z
  session: 01MV72LX0R3DV060F6
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - keyboard
  - manual-qa
created: 2026-10-13T14:47:37.130Z
updated: 2026-10-24T13:05:06.696Z
parent: KRMA-922
depends_on:
  - KRMA-969
blockers:
  - id: evt_mv6zuspk_1dgbnp
    type: human
    reason: docs/KEYBOARD_QA_CHECKLIST.md is ready; the ear-check and real-scene focus checks need a human at the keyboard.
    action: "Run the keyboard QA checklist on the signed build and fill in the result column; answer 'keyboardRouter resolves in the real scene' and the plain-⌘V keep/restore decision (note: KRMA-920 human comment already reports no beeps and enabled Photo/Tools items on canvas/toolbar focus)."
    created_at: 2026-10-13T18:08:03.032Z
    resolved_at: 2026-10-13T18:31:22.256Z
    resolved_by: cli
  - id: evt_mv70sr8g_9yu1dn
    type: human
    reason: The signed-build spot check confirms keyboardRouter resolves, no alert beeps were heard, and plain ⌘V should remain; however, the required per-shortcut, per-focus-state grid was explicitly not run. The spot check found Esc does not cancel crop (tracked in dependency KRMA-969).
    action: Run and record the remaining per-cell keyboard QA grid in docs/KEYBOARD_QA_CHECKLIST.md on the signed sandboxed Kromora build, including pass/fail and beep results for every key/focus state; also confirm KRMA-969 carries the required release-readiness and must-fix labels before resuming KRMA-926 verification.
    created_at: 2026-10-13T18:34:27.424Z
    resolved_at: 2026-10-13T19:25:05.703Z
    resolved_by: cli
order: z3
board: product
blocked_reason: The signed-build spot check confirms keyboardRouter resolves, no alert beeps were heard, and plain ⌘V should remain; however, the required per-shortcut, per-focus-state grid was explicitly not run. The spot check found Esc does not cancel crop (tracked in dependency KRMA-969).
blocked_action: Run and record the remaining per-cell keyboard QA grid in docs/KEYBOARD_QA_CHECKLIST.md on the signed sandboxed Kromora build, including pass/fail and beep results for every key/focus state; also confirm KRMA-969 carries the required release-readiness and must-fix labels before resuming KRMA-926 verification.
blocked_from_status: verification
---

## Objective

Prove, in the running signed App Sandbox build, that every keyboard shortcut works in every focus
state and never plays the system alert beep. Fix or file a child ticket for each failure.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M3. KRMA-920 replaced the global `NSEvent` key monitor with `Commands` key
equivalents plus a focus-scoped key surface. Unit/real-window tests pass, but three things are
unverified in the real app:

1. Photo/Tools menu items are `.disabled(keyboardRouter == nil)` (`Sources/KromoraKit/Views/
   MenuCommands.swift` ~L164). If `@FocusedValue(\.keyboardRouter)` does not resolve in the real
   scene, every plain-key shortcut (C, V, I, P, X, 1-5, `[`, `]` …) is dead.
2. Menu items are always enabled by design, so unavailable commands are silent no-ops.
3. Plain ⌘V no longer pastes edits (only ⌥⌘V). Confirm this is intended (see the KRMA-920 ticket
   and `KromoraEditTransferShortcuts`); if it is a regression, fix it or ask the human.
4. The "no alert beep" acceptance check (by ear) was never performed.

The authoritative shortcut inventory is in `.dg/issues/KRMA-920.md` (section "Shortcut inventory to
preserve") and `Sources/KromoraKit/Views/KeyboardShortcuts.swift` / `KeyboardShortcutReferenceView`.

## Acceptance criteria

- [ ] An agent first writes `docs/KEYBOARD_QA_CHECKLIST.md`: a table with one row per inventory key
      and one column per focus state (canvas focused, toolbar workspace picker focused, culling menu
      focused, a focused button, a text field editing, a slider focused, a sheet open). Each cell is
      "expected result". Generate it from the shortcut table in code, not from memory.
- [x] A HUMAN exercises the signed sandboxed build (`open Xcode/Kromora.xcodeproj`, run the
      `Kromora` scheme) and records whether any beep was heard. **Waived by the human on 2026-10-13:**
      the per-cell grid is not required. A hands-on spot check replaces it, backed by the KRMA-920 and
      KRMA-966 real-window inventory matrix. The checklist stays in the repo as an optional aid.
- [x] Every failing case has either a fix commit referencing this ticket or a new child ticket
      labelled `release-readiness,must-fix`. (Esc in crop: KRMA-969, done.)
- [x] Item 1 above is explicitly answered ("`keyboardRouter` resolves in the real scene: yes").
- [x] Item 3 above is explicitly answered with the human's decision (keep ⌘V; restored by KRMA-966).
- [x] Results are committed in `docs/KEYBOARD_QA_CHECKLIST.md` with date and build (`6b9fcd2f`).

## Implementation notes

This ticket needs a human at the keyboard: an agent cannot hear a beep or drive the signed sandboxed
app. The agent's part is the checklist and wiring up any fixes. Use `dg issue block` with the human
action "Run the keyboard QA checklist on the signed build and fill in the result column" once the
checklist exists. Do not run display-bound benchmark scripts.


### Comment — claude @ 2026-10-13T18:31:21.945Z

Human spot check done in the signed Xcode build (2026-10-13), recorded in docs/KEYBOARD_QA_CHECKLIST.md (6b9fcd2f). keyboardRouter resolves in the real scene: yes. No beeps. Plain ⌘V: keep (restored by KRMA-966, pastes edits as expected). Full per-cell grid was intentionally not run; this was a spot check. One failing case found: Esc does not cancel the crop tool, filed as KRMA-969. Unrelated polish filed as KRMA-970 (toolbar buttons all bronze).


### Comment — claude @ 2026-10-13T19:25:05.496Z

Human waived the per-cell keyboard checklist grid (2026-10-13). Acceptance criteria amended to match: hands-on spot check in the signed build plus the KRMA-920/KRMA-966 real-window matrix. Esc-in-crop failure is KRMA-969 (done, now labelled release-readiness,must-fix). Please verify against the amended criteria; do not require the per-cell grid.

## Agent log

- 2026-10-13T19:26:03.063Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Signed sandboxed app spot check confirms keyboardRouter resolves in the real scene and Photo/Tools shortcuts work. (pass) — Human recorded yes in docs/KEYBOARD_QA_CHECKLIST.md on 2026-10-13; prior KRMA-920 real-window inventory matrix also passes.
- [x] Keyboard shortcuts are silent in the signed app; the required human by-ear check is complete. (pass) — Human recorded no alert beeps during the 2026-10-13 signed-build spot check; KRMA-920 verification records the real-window inventory matrix as having no unclaimed inventory key.
- [x] Plain Command-V behavior has an explicit decision and works as intended. (pass) — Human chose keep; KRMA-966 restored Command-V Paste Edits while text-field paste remains available.
- [x] The crop Escape failure found during hands-on QA is resolved and tracked to completion. (pass) — KRMA-969 is done and labeled release-readiness and must-fix; focused crop responder tests pass.
- [x] Keyboard QA evidence is committed, and the human waiver for the per-cell grid is recorded. (pass) — Commit 6b9fcd2f records the dated signed-build spot check; the human explicitly waived the per-cell grid, relying on the KRMA-920/KRMA-966 real-window matrix.
Checks run:
- swift test --filter KeyboardShortcutCatalogTests — passed (10 tests, 0 failures).
- swift test --filter CropKeyboardWindowTests — passed (2 tests, 0 failures).
- git diff --check 6b9fcd2f^ 6b9fcd2f — passed.
- Reviewed docs/KEYBOARD_QA_CHECKLIST.md, KRMA-920 verification, KRMA-969 verification and labels, and KRMA-926 amended acceptance notes.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV72LX0R3DV060F6
Summary: Verification passed. Signed-build spot check and explicit grid waiver are recorded; focused keyboard catalog and crop responder tests pass; KRMA-969 is done.
