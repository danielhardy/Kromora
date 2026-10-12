---
id: KRMA-752
title: Flaky SmartMaskTests.testForegroundAndBackgroundRequestsShareOneSegmentationTask under load
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Test passes 20/20 under CPU load.
      result: pass
      notes: swift test --skip-build --filter SmartMaskTests.testForegroundAndBackgroundRequestsShareOneSegmentationTask passed 20/20 with eight concurrent yes busy-loop workers.
  checks_run:
    - "swift test --filter SmartMaskTests.testForegroundAndBackgroundRequestsShareOneSegmentationTask: 1 test passed; build succeeded"
    - "swift test --skip-build --filter SmartMaskTests.testForegroundAndBackgroundRequestsShareOneSegmentationTask repeated 20 times under eight CPU load workers: 20/20 passed"
    - "swift test --skip-build --filter SmartMaskTests: 10 tests passed"
    - "git diff --check 15cd62ab^ 15cd62ab -- Tests/KromoraKitTests/SmartMaskTests.swift: clean"
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T01:43:44.630Z
  session: 01MV4L7226YRTZ41XH
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - testing
created: 2026-10-01T21:07:01.163Z
updated: 2026-10-12T01:43:44.634Z
parent: KRMA-734
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-12T01:42:00.058Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

`SmartMaskTests.testForegroundAndBackgroundRequestsShareOneSegmentationTask` (SmartMaskTests.swift:153) asserts the provider is called once for concurrent foreground and background mask requests, but observed 2 calls in one full `scripts/ci-tests.sh fast` run during KRMA-734 verification (HEAD 1145f266). It passed in the other runs and in isolation, and it is unrelated to the last-known-frame work.

## Work

Determine whether the coalescing in `PhotoAnalysisCoordinator.mask` depends on task start ordering (the two `group.addTask` children can start sequentially if the first completes before the second begins) and make the test or coalescing deterministic, for example by gating the provider until both requests have registered.

## Acceptance criteria

- [ ] Test passes 20/20 under CPU load.


### Comment — claude @ 2026-10-01T22:02:38.376Z

Not reproduced: testForegroundAndBackgroundRequestsShareOneSegmentationTask passed in both full fast-lane runs on 4bbc5c5f (and the earlier run at 1145f266 plus b83a4cd9 after the first failure). It is an unrelated pre-existing flake, low priority, and does not block KRMA-734. Left ready for whoever wants to make the coalescing deterministic.


### Comment — claude @ 2026-10-01T22:46:50.692Z

Parked in backlog while pickup verifies the last-known-frame chain: it is an unrelated low-priority flake that was not reproduced in two full fast-lane runs, and a ready ticket would take the shared working tree between verifications. Promote it when convenient.


### Comment — claude @ 2026-10-12T01:42:03.036Z

Fixed in 15cd62ab. Cause: background requests re-enter mask() for foreground; if the first foreground task had already left inFlightMasks, SmartTestProvider (no MaskStore lookup, unlike the production provider) counted a second call. The test provider now returns store hits. SmartMaskTests 10/10; the target test passed 20/20 under 8 busy-loop CPU load. No product code changed.

## Agent log

- 2026-10-12T01:43:44.630Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Test passes 20/20 under CPU load. (pass) — swift test --skip-build --filter SmartMaskTests.testForegroundAndBackgroundRequestsShareOneSegmentationTask passed 20/20 with eight concurrent yes busy-loop workers.
Checks run:
- swift test --filter SmartMaskTests.testForegroundAndBackgroundRequestsShareOneSegmentationTask: 1 test passed; build succeeded
- swift test --skip-build --filter SmartMaskTests.testForegroundAndBackgroundRequestsShareOneSegmentationTask repeated 20 times under eight CPU load workers: 20/20 passed
- swift test --skip-build --filter SmartMaskTests: 10 tests passed
- git diff --check 15cd62ab^ 15cd62ab -- Tests/KromoraKitTests/SmartMaskTests.swift: clean
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV4L7226YRTZ41XH
Summary: Verified: target test passed 20/20 under eight CPU load workers; all 10 SmartMaskTests passed.
