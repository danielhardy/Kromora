---
id: KRMA-722
title: Investigate flaky histogram settling after repeated filmstrip selection
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce or characterize the failure
      result: pass
      notes: "Cause characterized as test synchronization: stale non-nil histogram satisfied wait."
    - criterion: Update wait condition to observe selected-source completion
      result: pass
      notes: Test now awaits histogramCompleted for second URL then settled non-loading state; reader created before actions so no missed event.
    - criterion: Product fix if lifecycle incorrect
      result: pass
      notes: Not applicable; no product defect found.
    - criterion: Run focused test repeatedly and related suites
      result: pass
      notes: Focused test 6/6 passes; ThumbnailSwitchLifecycleTests+HistogramTests 27 pass.
  checks_run:
    - swift test --filter testFilmstripSelectionPresentsRepeatedSelectionAndSettlesHistogram x6
    - swift test --filter ThumbnailSwitchLifecycleTests|HistogramTests (27 passed)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T20:22:38.557Z
  session: 01MUN4H4KU4M4SJZRD
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - histogram
  - filmstrip
  - flaky-test
created: 2026-09-29T18:46:11.418Z
updated: 2026-09-29T20:22:38.559Z
blockers: []
order: a0
board: product
---

## Objective

Determine whether repeated filmstrip selection can leave histogram work loading after the selected photo is presented, and make the regression deterministic.

## Context

A full KromoraKitTests run on 2026-09-29 failed `ThumbnailSwitchLifecycleTests.testFilmstripSelectionPresentsRepeatedSelectionAndSettlesHistogram` at line 397: `XCTAssertFalse(viewModel.isHistogramLoading)` failed. The test waits until the second source and preview are ready and `histogram != nil`, then immediately expects histogram loading to be false. Because the previous histogram may remain non-nil during the new request, that wait condition may be satisfied before the selected photo histogram settles. A prior full-suite run recorded in KRMA-697 had the same test fail once, then pass in isolated and full-suite reruns. Treat this as a possible test synchronization race until reproduced as a product defect.

## Acceptance criteria

- [ ] Reproduce or characterize the failure with focused repeated runs and identify whether the cause is test synchronization or product histogram lifecycle behavior.
- [ ] If the test can pass before the current selection histogram settles, update its wait condition to observe completion for the selected source or request generation, then verify it repeatedly.
- [ ] If product behavior is incorrect, fix the lifecycle so the latest selected photo reaches a terminal histogram state and loading clears; add regression coverage.
- [ ] Run the focused test repeatedly and the relevant histogram and thumbnail lifecycle tests; record the results.

## Implementation notes

Relevant test: `Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift`, `testFilmstripSelectionPresentsRepeatedSelectionAndSettlesHistogram`.

The output provided with this ticket contains this assertion failure, but not the other failure details from the run summary.


### Comment — codex @ 2026-09-29T20:21:50.484Z

The failure was a test synchronization race: histogram data is intentionally retained across photo switches, so the old non-nil value could satisfy the wait before the selected photo finished. The test now waits for the second photo's histogram completion event and settled view-model state. Verification: focused test passed 12 baseline and 15 post-change runs; ThumbnailSwitchLifecycleTests (17), PreviewCutoverTests (16 passed, 1 local RAW skip), and HistogramTests (10) passed. Commit: 7c76d99.

## Agent log

- 2026-09-29T20:22:38.557Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce or characterize the failure (pass) — Cause characterized as test synchronization: stale non-nil histogram satisfied wait.
- [x] Update wait condition to observe selected-source completion (pass) — Test now awaits histogramCompleted for second URL then settled non-loading state; reader created before actions so no missed event.
- [x] Product fix if lifecycle incorrect (pass) — Not applicable; no product defect found.
- [x] Run focused test repeatedly and related suites (pass) — Focused test 6/6 passes; ThumbnailSwitchLifecycleTests+HistogramTests 27 pass.
Checks run:
- swift test --filter testFilmstripSelectionPresentsRepeatedSelectionAndSettlesHistogram x6
- swift test --filter ThumbnailSwitchLifecycleTests|HistogramTests (27 passed)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUN4H4KU4M4SJZRD
Summary: Verified: test race fixed by waiting on second-photo histogramCompleted event and settled state; stable across repeated runs.
