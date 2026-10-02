---
id: KRMA-752
title: Flaky SmartMaskTests.testForegroundAndBackgroundRequestsShareOneSegmentationTask under load
type: bug
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - testing
created: 2026-10-01T21:07:01.163Z
updated: 2026-10-01T22:46:50.693Z
parent: KRMA-734
blockers: []
order: 4n
board: product
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
