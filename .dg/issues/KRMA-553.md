---
id: KRMA-553
title: EditPackageFixture leaks temp library packages without cleanup
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Fixture packages are created under the owning test case's temp directory (or tracked for removal in tearDown).
      result: pass
      notes: EditPackageFixture(at:) now requires an explicit URL; TempDirectoryTestCase.makeEditPackageFixture() constructs it under tempDirectory, and every call site (AppViewModelTests, ComparisonModeTests, CoordinatorBoundaryTests, FilmstripNavigationTests, EditClipboardTests, ExportCoordinatorTests, LibraryDeletionTests, LibraryDeletionCoordinatorTests, MaskingWorkspaceTests, PortablePackageEndToEndRegressionTests, SingleViewLatencyBenchmark) uses the helper; no remaining direct `EditPackageFixture(...)` calls outside Fixtures.swift.
    - criterion: A full run of the KRMA-549 suite set leaves no KromoraEditFixture-* residue in the system temp dir.
      result: pass
      notes: System-temp KromoraEditFixture-* count was 7625 before and after running the affected suites (114 tests across AppViewModelTests, LibraryDeletionCoordinatorTests, LibraryDeletionTests, MaskingWorkspaceTests, ComparisonModeTests, EditPersistenceIntegrationTests, LUTWorkflowTests) — count is unchanged, confirming no new leaks; the 7625 is pre-existing residue from before this fix, consistent with the implementer's note.
    - criterion: No product behavior, public API, or schema changes.
      result: pass
      notes: Diff in 64fb166 touches only Tests/KromoraKitTests/*.swift.
  checks_run:
    - swift build (clean)
    - swift test --filter 'KromoraKitTests.(AppViewModelTests|LibraryDeletionCoordinatorTests|LibraryDeletionTests|MaskingWorkspaceTests)' — 80/80 passed
    - swift test --filter 'KromoraKitTests.(ComparisonModeTests|EditPersistenceIntegrationTests|LUTWorkflowTests)' — 34/34 passed
    - grep for stray EditPackageFixture(...) call sites bypassing the new helper — none found
    - KromoraEditFixture-* temp dir count compared before/after test runs — stable at 7625
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-23T16:38:03.824Z
  session: 01MUEBRXSI5DUNZ3DO
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - verification
created: 2026-09-23T12:39:30.292Z
updated: 2026-09-23T16:38:03.826Z
parent: KRMA-549
order: zv
board: product
---

## Objective

Give EditPackageFixture (Tests/KromoraKitTests/Fixtures.swift, introduced by KRMA-549) a deterministic cleanup path so package-backed edit-store tests do not accumulate orphaned `KromoraEditFixture-*.kromoralibrary` directories in the system temp dir.

## Context

KRMA-549 counterpoint verification finding (non-blocking): every `EditPackageFixture()` creates a uniquely-named package under `FileManager.default.temporaryDirectory` and acquires a writer lease, but nothing ever removes it. `TempDirectoryTestCase` cleans only its own `tempDirectory`. Dozens of tests across LUT/Comparison/Crop/EditPersistence/Masking/LibraryDeletion suites instantiate fixtures, so repeated runs leak packages (each with a stale lease file) into tmp.

## Acceptance criteria

- [ ] Fixture packages are created under the owning test case's temp directory (or tracked for removal in tearDown).
- [ ] A full run of the KRMA-549 suite set leaves no `KromoraEditFixture-*` residue in the system temp dir.
- [ ] No product behavior, public API, or schema changes.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-23T16:36:16.179Z

Implemented in 64fb166. EditPackageFixture now requires an explicit package URL; TempDirectoryTestCase creates all edit fixtures under its owned scratch directory, and teardown removes them after model shutdown. Removed unscoped global fixture factories. Verified the KRMA-549 regression selection: 147/147 tests pass; system-temp matching package count remained at 7,625 (pre-existing residue).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-23T16:38:03.824Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Fixture packages are created under the owning test case's temp directory (or tracked for removal in tearDown). (pass) — EditPackageFixture(at:) now requires an explicit URL; TempDirectoryTestCase.makeEditPackageFixture() constructs it under tempDirectory, and every call site (AppViewModelTests, ComparisonModeTests, CoordinatorBoundaryTests, FilmstripNavigationTests, EditClipboardTests, ExportCoordinatorTests, LibraryDeletionTests, LibraryDeletionCoordinatorTests, MaskingWorkspaceTests, PortablePackageEndToEndRegressionTests, SingleViewLatencyBenchmark) uses the helper; no remaining direct `EditPackageFixture(...)` calls outside Fixtures.swift.
- [x] A full run of the KRMA-549 suite set leaves no KromoraEditFixture-* residue in the system temp dir. (pass) — System-temp KromoraEditFixture-* count was 7625 before and after running the affected suites (114 tests across AppViewModelTests, LibraryDeletionCoordinatorTests, LibraryDeletionTests, MaskingWorkspaceTests, ComparisonModeTests, EditPersistenceIntegrationTests, LUTWorkflowTests) — count is unchanged, confirming no new leaks; the 7625 is pre-existing residue from before this fix, consistent with the implementer's note.
- [x] No product behavior, public API, or schema changes. (pass) — Diff in 64fb166 touches only Tests/KromoraKitTests/*.swift.
Checks run:
- swift build (clean)
- swift test --filter 'KromoraKitTests.(AppViewModelTests|LibraryDeletionCoordinatorTests|LibraryDeletionTests|MaskingWorkspaceTests)' — 80/80 passed
- swift test --filter 'KromoraKitTests.(ComparisonModeTests|EditPersistenceIntegrationTests|LUTWorkflowTests)' — 34/34 passed
- grep for stray EditPackageFixture(...) call sites bypassing the new helper — none found
- KromoraEditFixture-* temp dir count compared before/after test runs — stable at 7625
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUEBRXSI5DUNZ3DO
