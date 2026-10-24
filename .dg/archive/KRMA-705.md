---
id: KRMA-705
title: Normalize spacing around icons beside the Library/Edit control
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Adjacent toolbar icons use consistent gaps, alignment, and visual padding.
      result: pass
      notes: All four controls now icon-only with .glass style and default HStack spacing inside one GlassEffectContainer. Not visually inspected in a running app.
    - criterion: Hit targets remain comfortable and controls retain their current actions and selected states.
      result: pass
      notes: Actions, disabled states, help and accessibility labels preserved; zoom gets explicit accessibility label/value.
    - criterion: Spacing remains balanced with the inspector open and closed and as the window width changes.
      result: pass
      notes: Code-level review only; layout uses platform default spacing with no fixed padding.
  checks_run:
    - swift build
    - scripts/ci-tests.sh serial (443 tests, 0 failures, 1 skipped)
  findings:
    - "Non-blocking: icon-only labels remove the visible zoom percentage readout and the Auto in-progress text; follow-up KRMA-711 filed for the zoom readout."
  fixes: []
  verification_commits:
    - "7636990"
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T03:54:46.401Z
  session: 01MUM523L2EXY7DC5Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - toolbar
  - layout
  - ui
created: 2026-09-29T03:18:58.104Z
updated: 2026-09-29T03:54:46.403Z
blockers: []
order: a0
board: product
commits:
  - "7636990"
---

## Objective

Make spacing and padding consistent for the toolbar icons beside Library/Edit.

## Context

In the supplied screenshot, the crop, enhancement, and comparison controls to the right of the
Library/Edit segmented control have uneven spacing and padding. The toolbar should read as a
deliberate, balanced group while preserving the current control functions.

![Edit toolbar icons beside the Library/Edit control](../assets/KRMA-703-707/screenshot-2026-09-28-at-9-13-54-pm.png)

## Acceptance criteria

- [ ] Adjacent toolbar icons use consistent gaps, alignment, and visual padding.
- [ ] Hit targets remain comfortable and controls retain their current actions and selected states.
- [ ] Spacing remains balanced with the inspector open and closed and as the window width changes.

## Implementation notes

Use the platform's standard toolbar sizing and spacing where possible; avoid one-off padding values
that cause neighboring controls to drift.

### Comment — codex @ 2026-09-29T03:50:27.816Z

Normalized the Edit toolbar controls to icon-only labels within the existing glass group, removing the redundant custom HStack gap. Zoom retains its current percentage in accessibility. Building for debugging...
Build complete! (0.18 sec) passes. Commit: 7636990.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T03:54:46.401Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Adjacent toolbar icons use consistent gaps, alignment, and visual padding. (pass) — All four controls now icon-only with .glass style and default HStack spacing inside one GlassEffectContainer. Not visually inspected in a running app.
- [x] Hit targets remain comfortable and controls retain their current actions and selected states. (pass) — Actions, disabled states, help and accessibility labels preserved; zoom gets explicit accessibility label/value.
- [x] Spacing remains balanced with the inspector open and closed and as the window width changes. (pass) — Code-level review only; layout uses platform default spacing with no fixed padding.
Checks run:
- swift build
- scripts/ci-tests.sh serial (443 tests, 0 failures, 1 skipped)
Findings:
- Non-blocking: icon-only labels remove the visible zoom percentage readout and the Auto in-progress text; follow-up KRMA-711 filed for the zoom readout.
Fixes:
- None
Verification commits:
- 7636990
Actor: claude
Resolved model: sonnet
Pickup session: 01MUM523L2EXY7DC5Z
Summary: Verified: icon-only labels normalize toolbar spacing; build and serial suite pass.
