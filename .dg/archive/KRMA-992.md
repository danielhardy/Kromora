---
id: KRMA-992
title: Stabilize stored-adoption shutdown test under parallel CI
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Determine whether the failure is a product race or a test synchronization issue under parallel execution.
      result: pass
      notes: The previous assertion sampled a shared FakeRenderEngine counter that can include independent edited-thumbnail preparations. The test now checks the open path and post-shutdown model state directly; repeated parallel runs passed.
    - criterion: The focused test passes reliably when run as part of repeated scripts/ci-tests.sh fast runs.
      result: pass
      notes: Three full fast-lane repetitions passed before and three after the final synchronization change; the target test ran in each post-change repetition.
    - criterion: If the product path is already correct, make the test synchronization express the intended shutdown boundary without adding production delays.
      result: pass
      notes: Replaced the fixed 50 ms sleep with a wait for admissionIsShuttingDown. No production code changed.
  checks_run:
    - scripts/ci-tests.sh fast — three full repetitions before the final test synchronization change; all exited 0.
    - scripts/ci-tests.sh fast — three full repetitions after the final test synchronization change; all exited 0 and included the target test.
  findings: []
  fixes:
    - Use model shutdown state as the synchronization boundary instead of a fixed sleep.
    - Replace the unrelated shared preparation-count assertion with checks that the placeholder remains unresolved and no source image is published after shutdown.
  verification_commits:
    - 9277a781
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T07:39:00.706Z
  session: 01MV7S8HXM6DP6JAAN
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
  - tests
  - flaky
created: 2026-10-14T03:01:58.845Z
updated: 2026-10-14T07:39:00.710Z
parent: KRMA-973
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T07:22:24.341Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 9277a781
---

## Objective

Make `StoredEditAdoptionTests.testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult` deterministic in the parallel fast lane.

## Context

During counterpoint verification of KRMA-973, `scripts/ci-tests.sh fast` failed this test in two of three full runs at `StoredEditAdoptionTests.swift:355` (`sourcePreparationCount` was 1 instead of 0). The filtered test passed by itself, and the third full run passed it. KRMA-904 owns the product shutdown/materialization behavior; this follow-up should first determine whether the remaining failure is a production race or test synchronization issue. KRMA-935 recorded an earlier occurrence of the same parallel-only failure.

## Acceptance criteria

- [ ] Determine whether the failure is a product race or a test synchronization issue under parallel execution.
- [ ] The focused test passes reliably when run as part of repeated `scripts/ci-tests.sh fast` runs.
- [ ] If the product path is already correct, make the test synchronization express the intended shutdown boundary without adding production delays.

## Implementation notes

Keep any change limited to the test and its synchronization unless evidence demonstrates a product defect. Do not alter source-materialization behavior without a reproduced product failure.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-14T07:39:00.706Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Determine whether the failure is a product race or a test synchronization issue under parallel execution. (pass) — The previous assertion sampled a shared FakeRenderEngine counter that can include independent edited-thumbnail preparations. The test now checks the open path and post-shutdown model state directly; repeated parallel runs passed.
- [x] The focused test passes reliably when run as part of repeated scripts/ci-tests.sh fast runs. (pass) — Three full fast-lane repetitions passed before and three after the final synchronization change; the target test ran in each post-change repetition.
- [x] If the product path is already correct, make the test synchronization express the intended shutdown boundary without adding production delays. (pass) — Replaced the fixed 50 ms sleep with a wait for admissionIsShuttingDown. No production code changed.
Checks run:
- scripts/ci-tests.sh fast — three full repetitions before the final test synchronization change; all exited 0.
- scripts/ci-tests.sh fast — three full repetitions after the final test synchronization change; all exited 0 and included the target test.
Findings:
- None
Fixes:
- Use model shutdown state as the synchronization boundary instead of a fixed sleep.
- Replace the unrelated shared preparation-count assertion with checks that the placeholder remains unresolved and no source image is published after shutdown.
Verification commits:
- 9277a781
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7S8HXM6DP6JAAN
Summary: Parallel shutdown verification passed; corrected test synchronization and committed the localized test fix.
