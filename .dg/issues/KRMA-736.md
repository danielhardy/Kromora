---
id: KRMA-736
title: "KRMA-733 follow-up: add launch-hint hydration tests and first-publication metrics"
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add launch-hint hydration tests and first-publication metrics
      result: pass
      notes: Coordinator-level tests cover partial indexing, bounded reads, invalid hints, supersession; metrics emitted once.
  checks_run:
    - swift test --filter LibraryBrowsingCoordinatorTests (11 passed)
    - swift test --filter LaunchHintsTests|ImageCollection (3 passed)
    - code review of 986e73b
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-30T21:27:17.822Z
  session: 01MUOM8HSX89MZXHCH
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-30T20:10:23.076Z
updated: 2026-09-30T21:27:17.824Z
blockers: []
order: n
board: product
---

## Objective

KRMA-733 follow-up: add launch-hint hydration tests and first-publication metrics

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [x] Add launch-hint hydration tests and first-publication metrics.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-30T21:26:44.675Z

Added coordinator-level launch-hint hydration coverage for partial indexing, bounded background reads, useful frame publication, invalid/wrong-library hints, viewport supersession, and first-publication metrics. Fixed repeat metric emission and stale source identity acceptance for hinted frames. Checks: focused suites (46 passed), ci-tests fast (1,454 passed; exit 0), ci-tests identity (4 passed; exit 0), dg validate, git diff --check. Commit: 986e73b.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-30T21:27:17.822Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add launch-hint hydration tests and first-publication metrics (pass) — Coordinator-level tests cover partial indexing, bounded reads, invalid hints, supersession; metrics emitted once.
Checks run:
- swift test --filter LibraryBrowsingCoordinatorTests (11 passed)
- swift test --filter LaunchHintsTests|ImageCollection (3 passed)
- code review of 986e73b
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUOM8HSX89MZXHCH
Summary: Verified: hydration tests and metrics are correct; repeat-metric emission and stale-identity fixes are sound.
