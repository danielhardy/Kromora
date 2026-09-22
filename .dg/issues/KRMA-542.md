---
id: KRMA-542
title: Fast lane has untracked pre-existing failures beyond KRMA-538..541
type: task
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-22T19:34:05.202Z
updated: 2026-09-22T19:34:05.202Z
order: zzzzq
board: product
parent: KRMA-537
---

## Objective

Triage and either fix or ticket the fast-lane suite failures observed during KRMA-537
verification that are not covered by the existing KRMA-538..541 tracking tickets.

## Context

While verifying KRMA-537 (managed-library source preservation for MediaVolumeImportTests),
a full `scripts/ci-tests.sh fast` run was executed to confirm the target suite no longer
reports. MediaVolumeImportTests passed cleanly (8/8, no failures logged for that suite), but
the overall fast lane still exited non-zero (`FAILED CI_TEST_LANE=deterministic-parallel`)
due to failures in suites that do not match any currently open ticket by name:
CopyPasteTests, LibraryScanTests, ThumbnailSwitchLifecycleTests, AppViewModelTests,
AutoAdjustmentTests, CanvasObservationTests, EmbeddedFirstFrameTests, ImageDropTests,
LibraryCullingTests, and LibraryDeletionTests. Notably ThumbnailSwitchLifecycleTests failing
here is surprising given KRMA-536 ("Fast-lane ThumbnailSwitchLifecycleTests/WorkspaceNavigationTests
hang/timeout predates KRMA-521") is already marked `done`.

None of these failures are attributable to the KRMA-537 change set, which only touches
test-only compatibility fixtures (`Tests/KromoraKitTests/MediaVolumeTests.swift`,
`PackageFixtureCompatibility.swift`, `PhotosImportCompatibilityTestSupport.swift`,
`Fixtures.swift`) plus unrelated files bundled into the same WIP recovery commit (20cf4cb).

## Acceptance criteria

- [ ] Each of the listed failing suites is either fixed, or has its own tracking ticket
      (verify KRMA-536's `done` status against the current failure before assuming duplication).
- [ ] The fast lane (`scripts/ci-tests.sh fast`) exit status and remaining known-red suites are
      reconciled against open tickets so there is no untracked fast-lane red.

## Implementation notes

Re-run `scripts/ci-tests.sh fast` to reproduce and capture per-suite failure detail before
triaging; some failures may be flaky/order-dependent rather than deterministic.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
