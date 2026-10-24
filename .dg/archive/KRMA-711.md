---
id: KRMA-711
title: Show current zoom percentage in edit toolbar zoom control
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The edit toolbar zoom control visibly shows the current zoom percentage alongside its icon.
      result: pass
      notes: Label already contained the percent; .labelStyle(.titleAndIcon) on the inner Label overrides the parent .iconOnly style (line 398), so title and icon both render.
  checks_run:
    - swift build (passed)
    - code review of b602e4a
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T04:18:20.872Z
  session: 01MUM61HZ5SJO5V6QT
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - toolbar
  - ui
created: 2026-09-29T03:54:41.749Z
updated: 2026-09-29T04:18:20.874Z
blockers: []
order: a0
board: product
---

## Objective

Show current zoom percentage in edit toolbar zoom control

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] The edit toolbar zoom control visibly shows the current zoom percentage alongside its icon.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-29T04:17:57.981Z

The edit toolbar zoom menu now overrides the parent icon-only label style so its current percentage is visible beside the magnifier. Acceptance criterion: the current zoom percentage is visible in the edit toolbar control. Verification: swift build passed. Commit: b602e4a.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T04:18:20.872Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The edit toolbar zoom control visibly shows the current zoom percentage alongside its icon. (pass) — Label already contained the percent; .labelStyle(.titleAndIcon) on the inner Label overrides the parent .iconOnly style (line 398), so title and icon both render.
Checks run:
- swift build (passed)
- code review of b602e4a
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUM61HZ5SJO5V6QT
