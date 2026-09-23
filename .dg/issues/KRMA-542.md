---
id: KRMA-542
title: Fast lane has untracked pre-existing failures beyond KRMA-538..541
type: task
status: claimed
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-22T19:34:05.202Z
updated: 2026-09-23T03:04:02.324Z
parent: KRMA-537
order: zzz8
board: product
claim:
  actor: codex
  session: 01MUDIR6Z8TVC53DJR
  claimed_at: 2026-09-23T03:04:02.323Z
  expires_at: 2026-09-23T04:04:02.323Z
  model: gpt-6-luna
  stage: implementation
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

- [x] Each of the listed failing suites is either fixed, or has its own tracking ticket
      (verify KRMA-536's `done` status against the current failure before assuming duplication). (pass) — Re-ran the fast lane; all observed failures are covered by open ticket KRMA-548. The repeated CanvasObservationTests, LibraryScanTests, and ThumbnailSwitchLifecycleTests cases are also recorded in KRMA-547.
- [x] The fast lane (`scripts/ci-tests.sh fast`) exit status and remaining known-red suites are
      reconciled against open tickets so there is no untracked fast-lane red. (pass) — `scripts/ci-tests.sh fast` exited 1 in `deterministic-parallel`. The 21 distinct failing tests across AppViewModelTests, AutoAdjustmentTests, CanvasObservationTests, CopyPasteTests, DevelopInspectorTests, EmbeddedFirstFrameTests, ImageDropTests, LibraryCullingTests, LibraryDeletionTests, LibraryScanTests, and ThumbnailSwitchLifecycleTests are all enumerated in KRMA-548; KRMA-547 overlaps three of them. KRMA-536's completed timeout coverage concerned different tests; the current `testSequentialOpenPresentsReplacementWithoutAnotherUserAction` failure is explicitly tracked in KRMA-547 and KRMA-548.

## Implementation notes

Re-run `scripts/ci-tests.sh fast` to reproduce and capture per-suite failure detail before
triaging; some failures may be flaky/order-dependent rather than deterministic.

### Triage — codex, 2026-09-22

Reproduction: `scripts/ci-tests.sh fast` exited 1 at `FAILED CI_TEST_LANE=deterministic-parallel`.
The failing test cases from this run are documented in open ticket KRMA-548, including the
AppViewModel, AutoAdjustment, CanvasObservation, CopyPaste, DevelopInspector, EmbeddedFirstFrame,
ImageDrop, LibraryCulling, LibraryDeletion, LibraryScan, and ThumbnailSwitchLifecycle suites.
KRMA-547 independently tracks the CanvasObservation, unreadable-image scan, and sequential-open
thumbnail failures. The thumbnail test is distinct from KRMA-536's completed tests, so the done
status does not cover the present failure. No failure from this reproduced run remains untracked;
fixes and any quarantine decision belong to KRMA-548/KRMA-547.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
