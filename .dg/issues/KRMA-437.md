---
id: KRMA-437
title: Add direct collaborator-level tests for LibraryDeletionCoordinator, ApplicationShellCoordinator, and PreviewPresentationCoordinator
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: LibraryDeletionCoordinatorTests covers flush failure, per-item analysis-cache failure, managed-vs-referenced deletion, portable-library removal, and trash-rollback on editStore.delete failure
      result: pass
      notes: "5 tests: testFlushFailureLeavesTheCandidateUntouched, testAnalysisCacheFailureSkipsDeletionForThatItem, testManagedAndReferencedSourcesFollowOwnershipPolicy, testPortableLibraryRemovalUsesThePortableSession, testTrashIsRestoredWhenEditDeletionFails"
    - criterion: ApplicationShellCoordinatorTests covers mount/unmount debounced refresh, activation refresh + maintenance admission, admission guards (missing package, already-enqueued job), and shutdown teardown
      result: pass
      notes: 4 tests exercise debounce, activation+admission, both admission guards in one test, and shutdown cancellation/observer removal
    - criterion: PreviewPresentationCoordinatorTests covers generation fencing, resolution-planner reset, cache-key derivation, and canonical-write gating (quality==.preview && sourceROI==nil)
      result: pass
      notes: 4 tests cover independent generation counters, planner reset equivalence, full cache-key component derivation, and canonical-write gating across quality/ROI combinations
  checks_run:
    - swift build
    - swift test --filter LibraryDeletionCoordinatorTests|ApplicationShellCoordinatorTests|PreviewPresentationCoordinatorTests (13/13 passed)
    - scripts/ci-tests.sh fast (1052/1052 passed)
    - scripts/ci-tests.sh serial (381/381 passed)
    - scripts/check-swift-format.sh (clean)
    - dg validate --json (ok:true, only pre-existing unrelated model-name warnings)
    - git status --porcelain (clean tree aside from expected dg bookkeeping)
  findings:
    - Three temp-directory names used the literal string "(UUID().uuidString)" instead of string-interpolated "\(UUID().uuidString)" in LibraryDeletionCoordinatorTests.swift (2 occurrences) and PreviewPresentationCoordinatorTests.swift (1 occurrence). Harmless in practice because TempDirectoryTestCase already gives each test a unique root, but it defeats the evident intent of unique per-call subdirectories. Fixed.
  fixes:
    - Corrected the three broken string interpolations to \(UUID().uuidString) in LibraryDeletionCoordinatorTests.swift and PreviewPresentationCoordinatorTests.swift
  verification_commits:
    - 5f9bc56
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-14T13:56:13.335Z
  session: 01MU1AXWLNO0DY5XZ9
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - library
  - testing
created: 2026-09-14T10:58:41.190Z
updated: 2026-09-14T13:56:13.337Z
depends_on:
  - KRMA-433
order: a0
board: product
commits:
  - 5f9bc56
---

Parent: KRMA-433 (verification finding, non-blocking)

## Objective

Add direct collaborator-level tests for `LibraryDeletionCoordinator`, `ApplicationShellCoordinator`,
and `PreviewPresentationCoordinator`.

## Context

KRMA-433 extracted five collaborators from `AppViewModel`: `LibraryMediaWorkflowCoordinator`,
`LibraryDeletionCoordinator`, `ApplicationShellCoordinator`, `SourceSessionCoordinator`, and
`PreviewPresentationCoordinator`. The issue's acceptance criteria called for "collaborator-level
tests using fake file dialogs, workspace/media providers, collections, package stores, schedulers,
and render engines" for the new boundaries. Only two of the five collaborators got dedicated test
files (`LibraryMediaWorkflowCoordinatorTests.swift`, `SourceSessionCoordinatorTests.swift`).

`LibraryDeletionCoordinator` is currently exercised only indirectly, through
`LibraryDeletionTests.swift`'s calls to `AppViewModel.deleteSelectedLibraryItems()`.
`ApplicationShellCoordinator` (mount/unmount observers, activation observers, debounced media
refresh, maintenance admission, shutdown/teardown ordering) has no direct or indirect test coverage
that exercises its own observer wiring — existing tests cover the underlying
`PortablePackageMaintenance` and `MediaVolume` logic, not the coordinator's admission/debounce
behavior. `PreviewPresentationCoordinator` (generation fencing, resolution-planner hysteresis, cache
key/writes) is covered only indirectly via `ThumbnailSwitchLifecycleTests` and similar integration
suites.

This is a test-coverage gap, not a behavior defect: the full test suite (1,031 fast + 378 serial)
passes, and the extraction preserved the original deletion/observer semantics by inspection.

## Acceptance criteria

- [ ] Add a `LibraryDeletionCoordinatorTests.swift` using a fake/in-memory `ImageCollection`,
      `EditPersistenceCoordinator`, `EditDocumentStore`, `PhotoAnalysisCoordinator`, and
      `PortableLibrarySession`/`nil` that directly exercises flush failure, per-item analysis-cache
      failure, managed-vs-referenced deletion, portable-library removal, and the trash-rollback path
      on `editStore.delete` failure.
- [ ] Add an `ApplicationShellCoordinatorTests.swift` using fake `NotificationCenter`s, an
      `ImageWorkScheduler`, and a fake/injectable `PortablePackageMaintenance` that exercises
      mount/unmount debounced refresh, app-activation refresh + maintenance admission, maintenance
      admission guards (missing package, already-enqueued job), and shutdown observer/task teardown.
- [ ] Add a `PreviewPresentationCoordinatorTests.swift` using a temporary `PreviewDiskCache` that
      exercises generation fencing across surfaces, resolution-planner reset, cache key derivation,
      and canonical-write gating (`quality == .preview && sourceROI == nil`).

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-14T13:51:52.061Z

Implemented in commit 54dbdf6: added direct LibraryDeletionCoordinator, ApplicationShellCoordinator, and PreviewPresentationCoordinator coverage for failure/ownership/rollback, portable removal, observer debounce/admission/teardown, generation/planner reset, cache-key derivation, and canonical-write gating. Verification: focused suites 13/13; scripts/ci-tests.sh fast 1052/1052; scripts/ci-tests.sh serial 381/381; scripts/ci-tests.sh verify; scripts/check-swift-format.sh; dg validate --json; git diff --cached --check.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-14T13:56:13.335Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] LibraryDeletionCoordinatorTests covers flush failure, per-item analysis-cache failure, managed-vs-referenced deletion, portable-library removal, and trash-rollback on editStore.delete failure (pass) — 5 tests: testFlushFailureLeavesTheCandidateUntouched, testAnalysisCacheFailureSkipsDeletionForThatItem, testManagedAndReferencedSourcesFollowOwnershipPolicy, testPortableLibraryRemovalUsesThePortableSession, testTrashIsRestoredWhenEditDeletionFails
- [x] ApplicationShellCoordinatorTests covers mount/unmount debounced refresh, activation refresh + maintenance admission, admission guards (missing package, already-enqueued job), and shutdown teardown (pass) — 4 tests exercise debounce, activation+admission, both admission guards in one test, and shutdown cancellation/observer removal
- [x] PreviewPresentationCoordinatorTests covers generation fencing, resolution-planner reset, cache-key derivation, and canonical-write gating (quality==.preview && sourceROI==nil) (pass) — 4 tests cover independent generation counters, planner reset equivalence, full cache-key component derivation, and canonical-write gating across quality/ROI combinations
Checks run:
- swift build
- swift test --filter LibraryDeletionCoordinatorTests|ApplicationShellCoordinatorTests|PreviewPresentationCoordinatorTests (13/13 passed)
- scripts/ci-tests.sh fast (1052/1052 passed)
- scripts/ci-tests.sh serial (381/381 passed)
- scripts/check-swift-format.sh (clean)
- dg validate --json (ok:true, only pre-existing unrelated model-name warnings)
- git status --porcelain (clean tree aside from expected dg bookkeeping)
Findings:
- Three temp-directory names used the literal string "(UUID().uuidString)" instead of string-interpolated "\(UUID().uuidString)" in LibraryDeletionCoordinatorTests.swift (2 occurrences) and PreviewPresentationCoordinatorTests.swift (1 occurrence). Harmless in practice because TempDirectoryTestCase already gives each test a unique root, but it defeats the evident intent of unique per-call subdirectories. Fixed.
Fixes:
- Corrected the three broken string interpolations to \(UUID().uuidString) in LibraryDeletionCoordinatorTests.swift and PreviewPresentationCoordinatorTests.swift
Verification commits:
- 5f9bc56
Actor: claude
Resolved model: sonnet
Pickup session: 01MU1AXWLNO0DY5XZ9
Summary: Verified KRMA-437: all three acceptance criteria met; fixed a broken UUID-interpolation typo (missing backslash) in three temp-directory names across the new test files; full fast (1052) and serial (381) suites pass, format check and dg validate clean.
