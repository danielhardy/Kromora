---
id: KRMA-542
title: Fast lane has untracked pre-existing failures beyond KRMA-538..541
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Each of the listed failing suites is either fixed, or has its own tracking ticket (verify KRMA-536's done status against the current failure before assuming duplication).
      result: pass
      notes: Independent fast-lane re-run observed 20 failing tests across 10 suites; every one is enumerated in open ticket KRMA-548 (which lists 21 tests; the 21st, AutoAdjustmentTests/testAutoAvailabilityRefreshesWhenNavigatingBetweenPhotos, did not fail in this run, consistent with the flaky/order-dependent behavior noted in the issue). CanvasObservation high-frequency, LibraryScan unreadable-image, and ThumbnailSwitch sequential-open failures are additionally recorded in open KRMA-547. KRMA-536 (done) fixed a suite-wide hang/timeout verified at 16/16 ThumbnailSwitchLifecycle + 7/7 WorkspaceNavigation; in this run only the single testSequentialOpenPresentsReplacementWithoutAnotherUserAction thumbnail test failed and WorkspaceNavigation was clean, so the current failure is distinct and is explicitly tracked in KRMA-547/KRMA-548.
    - criterion: The fast lane (scripts/ci-tests.sh fast) exit status and remaining known-red suites are reconciled against open tickets so there is no untracked fast-lane red.
      result: pass
      notes: scripts/ci-tests.sh fast exited non-zero (FAILED CI_TEST_LANE=deterministic-parallel) in the verification re-run. All 20 observed failing tests are a subset of KRMA-548's enumerated list; no failure falls outside open tracking tickets. MediaVolumeImportTests (KRMA-537 scope) was clean, matching the implementation claim.
  checks_run:
    - scripts/ci-tests.sh fast (full re-run; exit non-zero as expected; extracted 20 distinct failing tests across 10 suites and reconciled each against KRMA-548/KRMA-547)
    - dg issue show KRMA-548 / KRMA-547 / KRMA-536 / KRMA-538..541 (confirmed KRMA-548 enumerates all 11 suites incl. DevelopInspectorTests; KRMA-547 overlaps the 3 claimed cases; KRMA-536 done covers the suite-wide hang fix; KRMA-538..541 are done and cover different suites)
    - "git show e4bb65e (implementation change is docs-only: .dg/issues/KRMA-542.md, 26 insertions/8 deletions; no product code touched)"
    - dg validate (only pre-existing unknown-model warnings for unrelated issues)
  findings:
    - "No untracked fast-lane red: all 20 verification-run failures are enumerated in open KRMA-548; KRMA-547 overlaps three of them as claimed."
    - AutoAdjustmentTests/testAutoAvailabilityRefreshesWhenNavigatingBetweenPhotos (listed in KRMA-548) passed in this run, supporting the issue's flaky/order-dependent characterization; it remains tracked regardless.
    - The working tree contains pre-existing unrelated modifications (40 modified, 13 untracked) from other work; none belong to KRMA-542 and none were touched during verification.
  fixes: []
  verification_commits: []
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-23T06:18:43.810Z
  session: 01MUDPIHHXONL1DWTL
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-22T19:34:05.202Z
updated: 2026-09-23T06:18:43.812Z
parent: KRMA-537
order: zq
board: product
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

### Comment — codex @ 2026-09-23T03:07:16.649Z

Triage complete: reproduced the fast-lane failure and reconciled all 21 failing tests across 11 suites to open tracking tickets KRMA-548 and KRMA-547. KRMA-536's done status covers different tests; the current sequential-open thumbnail failure is tracked. Recorded the run and suite mapping in the issue; committed as e4bb65e.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-23T06:18:43.810Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Each of the listed failing suites is either fixed, or has its own tracking ticket (verify KRMA-536's done status against the current failure before assuming duplication). (pass) — Independent fast-lane re-run observed 20 failing tests across 10 suites; every one is enumerated in open ticket KRMA-548 (which lists 21 tests; the 21st, AutoAdjustmentTests/testAutoAvailabilityRefreshesWhenNavigatingBetweenPhotos, did not fail in this run, consistent with the flaky/order-dependent behavior noted in the issue). CanvasObservation high-frequency, LibraryScan unreadable-image, and ThumbnailSwitch sequential-open failures are additionally recorded in open KRMA-547. KRMA-536 (done) fixed a suite-wide hang/timeout verified at 16/16 ThumbnailSwitchLifecycle + 7/7 WorkspaceNavigation; in this run only the single testSequentialOpenPresentsReplacementWithoutAnotherUserAction thumbnail test failed and WorkspaceNavigation was clean, so the current failure is distinct and is explicitly tracked in KRMA-547/KRMA-548.
- [x] The fast lane (scripts/ci-tests.sh fast) exit status and remaining known-red suites are reconciled against open tickets so there is no untracked fast-lane red. (pass) — scripts/ci-tests.sh fast exited non-zero (FAILED CI_TEST_LANE=deterministic-parallel) in the verification re-run. All 20 observed failing tests are a subset of KRMA-548's enumerated list; no failure falls outside open tracking tickets. MediaVolumeImportTests (KRMA-537 scope) was clean, matching the implementation claim.
Checks run:
- scripts/ci-tests.sh fast (full re-run; exit non-zero as expected; extracted 20 distinct failing tests across 10 suites and reconciled each against KRMA-548/KRMA-547)
- dg issue show KRMA-548 / KRMA-547 / KRMA-536 / KRMA-538..541 (confirmed KRMA-548 enumerates all 11 suites incl. DevelopInspectorTests; KRMA-547 overlaps the 3 claimed cases; KRMA-536 done covers the suite-wide hang fix; KRMA-538..541 are done and cover different suites)
- git show e4bb65e (implementation change is docs-only: .dg/issues/KRMA-542.md, 26 insertions/8 deletions; no product code touched)
- dg validate (only pre-existing unknown-model warnings for unrelated issues)
Findings:
- No untracked fast-lane red: all 20 verification-run failures are enumerated in open KRMA-548; KRMA-547 overlaps three of them as claimed.
- AutoAdjustmentTests/testAutoAvailabilityRefreshesWhenNavigatingBetweenPhotos (listed in KRMA-548) passed in this run, supporting the issue's flaky/order-dependent characterization; it remains tracked regardless.
- The working tree contains pre-existing unrelated modifications (40 modified, 13 untracked) from other work; none belong to KRMA-542 and none were touched during verification.
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: unknown
Pickup session: 01MUDPIHHXONL1DWTL
Summary: Counterpoint verification passes: re-ran the fast lane (FAILED deterministic-parallel, 20 failing tests across 10 suites) and confirmed every failure is enumerated in open KRMA-548 with the three-way overlap in open KRMA-547; KRMA-536 done status covers the earlier suite-wide hang fix, not the currently tracked single sequential-open failure. Implementation is docs-only (e4bb65e). No fixes or child tickets needed.
