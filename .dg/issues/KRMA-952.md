---
id: KRMA-952
title: "DECISION: reopen the Edit-entry 50/100 ms latency budgets?"
type: task
status: backlog
priority: medium
human_review_required: true
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - decision
  - performance
parent: KRMA-922
created: 2026-10-13T14:48:02.806Z
updated: 2026-10-13T14:48:21.746Z
blockers: []
order: zi
board: product
---

## Objective

Decide with the human whether to reopen the Edit-entry latency budgets closed as won't-do, given the
product bar of "instant" entry, and (if yes) file the concrete tickets.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S9 (Edit half). Warm first pixel p95 is about 190 ms with an exact stored
frame and ZERO renders; the cost is SwiftUI mount cost (see the measured-state section of
`docs/TESTING.md`, 2026-10-11). The 50/100 ms budgets were closed as won't-do in KRMA-748, KRMA-749
and KRMA-750 (read those and `.dg/decisions/ADR-LKF-001`). `CLAUDE.md` says display-bound benchmarks
are rare release-time evidence; do not re-measure; cite the existing numbers.

## Acceptance criteria

- [ ] A one-page summary comment on this ticket: current numbers (cited from `docs/TESTING.md`), why the
      budgets were closed, what the remaining cost is made of, and 2-3 candidate approaches (e.g.
      keeping the Edit view hierarchy mounted and hidden, splitting the Edit view's first mount into a
      minimal canvas + deferred inspectors) with risks.
- [ ] The human's decision is recorded (`dg decision`): reopen with target X ms, or keep won't-do for
      the release.
- [ ] If reopened, child tickets are created with acceptance criteria that use deterministic,
      window-independent measurements (per `CLAUDE.md`), not the capture script.

## Implementation notes

Human decision: block with action "Decide whether to reopen the Edit-entry latency budgets and set the
target". Do not change source in this ticket.
