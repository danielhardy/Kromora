---
id: KRMA-952
title: "Optional: improve warm Edit and Library navigation latency"
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - performance
created: 2026-10-13T14:48:02.806Z
updated: 2026-10-24T14:25:58.275Z
blockers: []
order: cis69e34
board: product
context:
  files: []
  docs:
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-922
    - KRMA-994
    - KRMA-1002
    - KRMA-748
  commands: []
---

## Objective

Improve warm entry to Edit and return to the Library grid as optional, non-gating performance polish. Use the existing KRMA-1002 profile to focus the work on measured costs while preserving correct photo presentation and navigation behavior. There is no release deadline for this work.

## Context

- The 2026-10-14 supervised Release capture recorded warm Edit first-pixel p95 of 286 ms and warm 30-cell grid re-entry p95 of 247 ms on an M1 Pro. The historical targets were 50 ms and 100 ms. Keep the machine, commit, and capture method with those numbers; do not blend them with the 2026-10-11 M4 Pro capture.
- KRMA-1002 profiled the path without a window on an M4 Pro. It found about 28 ms for the first mount/layout pass and about 53 ms for frame hydration; drawable presentation could not be measured without a window. State publication was small, and the profile did not show repeated document invalidations.
- The prior 50/100 ms budgets were closed as non-gating polish after the Release build felt fast. This ticket records the owner's choice to revisit navigation performance later as optional work.
- Use `docs/TESTING.md`, KRMA-1002, and the earlier work in KRMA-748/749/750 as the starting point. Do not repeat a display-bound capture for routine implementation work.

## Acceptance criteria

- [ ] Select a focused change based on the existing profile; avoid broad Observation or view-lifecycle changes without measurements that support them.
- [ ] Demonstrate before/after change in the same deterministic, window-independent profile for the affected phase, and record the machine and configuration.
- [ ] Preserve correct-photo presentation, selection and cancellation behavior, and avoid visible thumbnail swaps or unnecessary render admissions.
- [ ] Keep this work optional and non-gating. The historical 50 ms and 100 ms numbers are context, not hard release or merge thresholds.
- [ ] Do not run a new display-bound capture for routine verification. If later work requires new user-visible latency numbers, it must be explicitly scoped as a supervised performance task under `CLAUDE.md`.

## Implementation notes

This is a future performance improvement, not a decision ticket. Do not block for a human choice about reopening the old budgets. Record evidence and hand off focused work normally.

### Historical comment — cursor @ 2026-10-14T16:11:01.014Z

Updated for the 2026-10-14 review. The recorded M1 Pro numbers are warm Edit p95 286 ms and warm grid p95 247 ms at commit aef050e8. This decision now depends on the KRMA-1002 breakdown. Do not change product code here, and do not rerun the display capture.


### Comment — codex @ 2026-10-15T02:34:30.407Z

Per owner direction, this is now optional future performance work rather than a decision ticket. The historical 50/100 ms budgets are non-gating context; use the KRMA-1002 profile and same-configuration deterministic measurements when the work is picked up.
