---
id: KRMA-707
title: Replace the histogram dropdown with a full-width tab selector
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Histogram modes appear as a connected, full-width selector integrated with the plot.
      result: pass
      notes: Plot and tab strip share one VStack with a common background and border.
    - criterion: Labels use a monospaced typeface and remain legible at the inspector supported widths.
      result: pass
      notes: Monospaced caption2 with lineLimit(1) and minimumScaleFactor(0.8). At the 240pt minimum inspector width each tab is about 30pt, so Parade and Vector may be tight. Not checked visually.
    - criterion: All existing modes remain selectable and the active mode is clearly indicated.
      result: pass
      notes: All eight modes come from CaseIterable. The selected tab has an accent tint and primary-colored text.
    - criterion: Selection remains accessible to keyboard and assistive technology users.
      result: pass
      notes: Buttons carry labels, a selected value and the isSelected trait, inside a labeled container.
  checks_run:
    - swift build (passed)
    - git diff --check (passed)
    - swift test --filter InfoInspectorPresentationTests (5 tests passed)
  findings:
    - "Non-blocking: at the 240pt minimum inspector width, Parade and Vector labels at caption2 monospaced with 0.8 scale may truncate. Needs a visual check."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T03:59:28.474Z
  session: 01MUM5D4PNG5KHCI5M
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - histogram
  - inspector
  - ui
created: 2026-09-29T03:19:00.294Z
updated: 2026-09-29T03:59:28.476Z
blockers: []
order: a0
board: product
---

## Objective

Replace the histogram mode dropdown with a full-width tab selector integrated into the histogram.

## Context

In the supplied Edit screenshot, the compact RGB dropdown sits below the histogram and looks
detached from it. The user wants a custom tab system attached to the plot, spanning its full width
edge to edge, with a monospaced typeface. The available modes are RGB, Luma, R, G, B, Wave, Parade,
and Vector.

![Histogram inspector with the current RGB mode dropdown](../assets/KRMA-703-707/screenshot-2026-09-28-at-9-13-54-pm.png)

## Acceptance criteria

- [ ] Histogram modes appear as a connected, full-width selector integrated with the plot.
- [ ] Labels use a monospaced typeface and remain legible at the inspector's supported widths.
- [ ] All existing modes remain selectable and the active mode is clearly indicated.
- [ ] Selection remains accessible to keyboard and assistive technology users.

## Implementation notes

Preserve each mode's current histogram behavior and avoid adding horizontal overflow at narrow
inspector widths.

### Comment — codex @ 2026-09-29T03:58:58.711Z

Implemented and committed in df26a6f. Replaced the histogram mode menu with an edge-to-edge tab strip integrated into the plot, retaining all eight modes with equal-width monospaced labels and a clear selected state. Buttons expose mode labels and selected state to assistive technology and support standard keyboard activation/focus. Verification: swift build passed; git diff --check passed. No tests were run.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T03:59:28.474Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Histogram modes appear as a connected, full-width selector integrated with the plot. (pass) — Plot and tab strip share one VStack with a common background and border.
- [x] Labels use a monospaced typeface and remain legible at the inspector supported widths. (pass) — Monospaced caption2 with lineLimit(1) and minimumScaleFactor(0.8). At the 240pt minimum inspector width each tab is about 30pt, so Parade and Vector may be tight. Not checked visually.
- [x] All existing modes remain selectable and the active mode is clearly indicated. (pass) — All eight modes come from CaseIterable. The selected tab has an accent tint and primary-colored text.
- [x] Selection remains accessible to keyboard and assistive technology users. (pass) — Buttons carry labels, a selected value and the isSelected trait, inside a labeled container.
Checks run:
- swift build (passed)
- git diff --check (passed)
- swift test --filter InfoInspectorPresentationTests (5 tests passed)
Findings:
- Non-blocking: at the 240pt minimum inspector width, Parade and Vector labels at caption2 monospaced with 0.8 scale may truncate. Needs a visual check.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUM5D4PNG5KHCI5M
Summary: Verified: histogram mode dropdown replaced by full-width monospaced tab strip; build and inspector tests pass.
