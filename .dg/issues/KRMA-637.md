---
id: KRMA-637
title: "Pre-existing failure: AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent"
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: swift test --filter AutoEnhancementCoordinatorTests passes on scripts/ci-tests.sh fast
      result: pass
      notes: All 19 tests in AutoEnhancementCoordinatorTests pass, including testFrozenTargetsPreserveLowKeyIntent, confirming the fix already present at HEAD (90811f0, 'Fix pre-existing test failures').
  checks_run:
    - swift test --filter AutoEnhancementCoordinatorTests (19/19 passed)
    - scripts/ci-tests.sh fast (run twice; first run failed only on an unrelated, non-reproducible LibraryGridTests flake, second run passed with exit 0)
    - swift test --filter LibraryGridTests in isolation (13/13 passed)
  findings:
    - LibraryGridTests.swift:239 testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding failed once under the full scripts/ci-tests.sh fast lane but passed in isolation and on a repeat full run, indicating a timing-sensitive flake unrelated to KRMA-637's Auto Light/Color scope. Filed as backlog child ticket KRMA-641.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T21:21:44.243Z
  session: 01MUIW162DSQHVAHZ5
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-26T17:25:12.944Z
updated: 2026-09-26T21:21:44.246Z
parent: KRMA-631
blockers: []
order: a0
board: product
---

## Objective

Pre-existing failure: AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent

## Context

Found while verifying KRMA-631 (capture metadata preview overlay). Confirmed on a clean
checkout of HEAD (91c485c, no uncommitted changes) that
`testFrozenTargetsPreserveLowKeyIntent` fails deterministically:
`XCTAssertEqualWithAccuracy failed: ("0.48") is not equal to ("0.25") +/- ("1e-06")`
at `AutoEnhancementCoordinatorTests.swift:207`. Unrelated to the KRMA-631 diff (which only
touches `ImageMetadata.swift`, `KeyboardShortcuts.swift`, `MenuCommands.swift`,
`PreviewView.swift`); likely a regression from a recent Auto Light/Color calibration change
(see "Calibrate Auto Light and Color regressions" in recent history).

## Acceptance criteria

- [ ] `swift test --filter AutoEnhancementCoordinatorTests` passes on `scripts/ci-tests.sh fast`.

## Implementation notes

Reproduce with a clean worktree at HEAD to rule out local uncommitted state before debugging.

### Comment — codex @ 2026-09-26T21:14:25.139Z

Verified resolved by the existing HEAD change in 90811f0: decisive low-key intent now suppresses the dark-spread underexposure cue. Reproduced the failure on clean 91c485c; the focused AutoEnhancementCoordinatorTests pass on clean HEAD, and scripts/ci-tests.sh fast passes (exit 0). No duplicate code change was needed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-26T21:21:44.244Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] swift test --filter AutoEnhancementCoordinatorTests passes on scripts/ci-tests.sh fast (pass) — All 19 tests in AutoEnhancementCoordinatorTests pass, including testFrozenTargetsPreserveLowKeyIntent, confirming the fix already present at HEAD (90811f0, 'Fix pre-existing test failures').
Checks run:
- swift test --filter AutoEnhancementCoordinatorTests (19/19 passed)
- scripts/ci-tests.sh fast (run twice; first run failed only on an unrelated, non-reproducible LibraryGridTests flake, second run passed with exit 0)
- swift test --filter LibraryGridTests in isolation (13/13 passed)
Findings:
- LibraryGridTests.swift:239 testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding failed once under the full scripts/ci-tests.sh fast lane but passed in isolation and on a repeat full run, indicating a timing-sensitive flake unrelated to KRMA-637's Auto Light/Color scope. Filed as backlog child ticket KRMA-641.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUIW162DSQHVAHZ5
Summary: Independently reproduced the fix: AutoEnhancementCoordinatorTests (19/19, incl. testFrozenTargetsPreserveLowKeyIntent) passes at HEAD. Filed KRMA-641 (backlog, verification label) for an unrelated LibraryGridTests flake observed once under the full fast lane.
