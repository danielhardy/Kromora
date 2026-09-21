---
id: KRMA-484
title: "Flaky: PortablePackageMaintenanceTests retry-after-scheduler-rejection times out in parallel fast lane"
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The retry-after-scheduler-rejection test no longer loses the blocker release under parallel load.
      result: pass
      notes: The test now waits for the detached blocker operation to enter Gate.wait() before releaseAll(); this removes the race where releaseAll could run before the continuation was installed.
    - criterion: The timeout diagnostic identifies the wait that expired.
      result: pass
      notes: waitUntil now interpolates the description in its XCTFail message.
    - criterion: Five consecutive fast-lane runs are green.
      result: pass
      notes: Restarted after an unrelated pre-sequence CanvasObservationTests failure; five consecutive scripts/ci-tests.sh fast runs passed, each covering 1,095 tests.
  checks_run:
    - swift test --filter PortablePackageMaintenanceTests/testMaintenanceCoordinatorRetriesSchedulerRejectionAfterQueueDrains
    - swift build
    - swift test (1,540 tests, 55 expected skips, 0 failures)
    - scripts/ci-tests.sh fast (five consecutive green runs, 1,095 tests each)
    - scripts/ci-tests.sh serial (394 tests, 1 expected local-RAW skip, 0 failures)
    - dg validate
    - git diff --check
  findings: []
  fixes: []
  verification_commits:
    - 211a1a0
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-20T20:00:43.335Z
  session: 01MUA8D8M1G8GM2BSR
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-20T17:43:33.717Z
updated: 2026-09-20T20:00:43.336Z
order: a0
board: product
commits:
  - 211a1a0
---

## Objective

Flaky: PortablePackageMaintenanceTests retry-after-scheduler-rejection times out in parallel fast lane

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — claude @ 2026-09-20T17:43:50.941Z

Child of KRMA-482 (found during its verification; unrelated to that change). scripts/ci-tests.sh fast failed twice in the main tree and once in a clean worktree at 3c942c8 with "timed out waiting for (description)" at PortablePackageMaintenanceTests.swift:234 (testMaintenanceCoordinatorRetriesSchedulerRejectionAfterQueueDrains). The same lane passed on 638d35f and on a later main-tree run, and the test passes in isolation (~0.2s), so it is load/timing-sensitive. The XCTFail message lacks interpolation ("(description)" instead of "\(description)"), so it does not say which wait timed out. Acceptance: fix the interpolation, find which wait times out under load and remove the timing dependence, then 5 consecutive green fast-lane runs.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-20T20:00:43.335Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The retry-after-scheduler-rejection test no longer loses the blocker release under parallel load. (pass) — The test now waits for the detached blocker operation to enter Gate.wait() before releaseAll(); this removes the race where releaseAll could run before the continuation was installed.
- [x] The timeout diagnostic identifies the wait that expired. (pass) — waitUntil now interpolates the description in its XCTFail message.
- [x] Five consecutive fast-lane runs are green. (pass) — Restarted after an unrelated pre-sequence CanvasObservationTests failure; five consecutive scripts/ci-tests.sh fast runs passed, each covering 1,095 tests.
Checks run:
- swift test --filter PortablePackageMaintenanceTests/testMaintenanceCoordinatorRetriesSchedulerRejectionAfterQueueDrains
- swift build
- swift test (1,540 tests, 55 expected skips, 0 failures)
- scripts/ci-tests.sh fast (five consecutive green runs, 1,095 tests each)
- scripts/ci-tests.sh serial (394 tests, 1 expected local-RAW skip, 0 failures)
- dg validate
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- 211a1a0
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUA8D8M1G8GM2BSR
Summary: Stabilized the scheduler-rejection retry test by synchronizing on blocker admission, and fixed the timeout diagnostic interpolation.
