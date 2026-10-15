---
id: KRMA-922
title: "Release readiness 2026-10-13: tracking epic"
type: task
status: backlog
priority: high
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - epic
created: 2026-10-13T14:47:33.325Z
updated: 2026-10-14T16:11:00.787Z
blockers: []
order: 5mhzzzzv
board: product
---

## Objective

Track every finding from the dated release-readiness review (`.context/2026-10-13-release-readiness-review.md`, written against `main` at
`ccc575c2`) until each is either fixed, explicitly decided, or consciously declined.

## Context

The review sorted findings into Must fix (KRMA-923-M6), Should fix (KRMA-940-S11) and Nice to have. Each finding
has one or more child tickets labelled `release-readiness`. The review is a dated snapshot, not a
roadmap: before acting on any child ticket, re-verify the cited file/line still matches (line numbers
drift) and say so in your comment if it does not.

## Acceptance criteria

- [ ] Every child ticket is `done`, or has a recorded decision explaining why it was declined.
- [ ] No child labelled `must-fix` remains open.
- [ ] `scripts/ci-tests.sh fast`, `serial` and `warning-gate` exit 0 on `main`.

## Implementation notes

Do not implement anything under this ticket directly; it only tracks children. Child naming:
`must-fix` = review section M, `should-fix` = section S, `nice-to-have` = remainder.


### Comment — cursor @ 2026-10-14T16:11:00.786Z

The 2026-10-14 review is tracked by KRMA-994. KRMA-941, KRMA-942, KRMA-952, KRMA-953, KRMA-954, KRMA-959, KRMA-960, and KRMA-963 were updated in place and remain children of this epic. Do not close them only because the newer review exists.
