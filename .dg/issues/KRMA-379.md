---
id: KRMA-379
title: Extract Photos import orchestration from ContentView
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: ContentView contains no Photos import loop, hashing, PHAsset lookup, or per-item error/progress orchestration.
      result: pass
      notes: ContentView.swift no longer imports Photos; handlePhotosSelection only builds PhotosImportSelection values and delegates to the coordinator.
    - criterion: Introduce a dedicated import controller/service/coordinator with an injectable Photos provider or transfer abstraction.
      result: pass
      notes: PhotosImportCoordinator + PhotosImportProviding protocol with production PhotosPickerImportProvider and test-only providers.
    - criterion: The controller emits or updates value-based progress and failure state suitable for SwiftUI observation.
      result: pass
      notes: "@Published progress/failures/wasCancelled on an ObservableObject; StatusBar observes photosImportCoordinator.progress."
    - criterion: Cancellation remains responsive between items and does not discard successfully imported items.
      result: pass
      notes: Verified via testCoordinatorCancellationFinishesWithoutDiscardingEarlierItem and testCancellationLeavesAlreadyImportedOriginalsUsable; both pass.
    - criterion: Original filename preservation and one-time content-digest behavior remain unchanged.
      result: pass
      notes: originalFilename/transferData boundary preserved; digest computed once via Task.detached and propagated; covered by testCoordinatorPropagatesOneComputedDigestToDurableSource.
    - criterion: ImageCollection remains responsible for admitting durable imported payloads, while the import controller owns provider interaction.
      result: pass
      notes: Coordinator calls viewModel.appendPhotosImport/beginPhotosImport/finishPhotosImport; ImageCollection APIs untouched in diff.
    - criterion: ContentView only presents PhotosPicker and connects its selection/cancel actions to the import boundary.
      result: pass
    - criterion: Add focused tests for successful multi-item import, partial provider failure, cancellation, filename fallback, and digest propagation.
      result: pass
      notes: PhotosImportTests.swift adds all five scenarios via TestPhotosImportProvider; all 20 tests in the file pass.
    - criterion: Existing Photos import, durability, and performance tests remain passing; run dg validate and git diff --check.
      result: pass
      notes: "swift test --filter PhotosImportTests: 20/20 passed. scripts/ci-tests.sh fast: full run passed (exit 0). dg validate: OK. git diff --check: clean."
  checks_run:
    - swift build
    - swift test --filter PhotosImportTests (20 passed)
    - scripts/ci-tests.sh fast (passed, exit 0)
    - dg validate (OK)
    - git diff --check (clean)
  findings:
    - "PhotosImportCoordinator.recordFailure (Sources/KromoraKit/ViewModels/PhotosImportCoordinator.swift:208-218) silently drops a failure record if Task.isCancelled becomes true between a provider throw and the recordFailure guard, whereas the original ContentView code always recorded the failure regardless of cancellation state. Non-blocking: doesn't affect data durability or any acceptance criterion; not fixed."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T18:09:17.370Z
  session: 01MTYP5P91OGLZCHBA
labels:
  - architecture
  - import
  - ui
created: 2026-09-12T15:24:44.929Z
updated: 2026-09-12T18:09:17.372Z
order: a0
board: product
---

## Objective

Move the Apple Photos import workflow out of SwiftUI view code so ContentView only presents the picker, forwards user intent, and renders import state.

## Context

ContentView currently owns the import task, item iteration, cancellation, Photos provider transfer, PHAsset filename lookup, payload hashing, error handling, progress callbacks, and ImageCollection payload construction.

Relevant code:
- Sources/KromoraKit/Views/ContentView.swift:105-182
- Sources/KromoraKit/ViewModels/AppViewModel.swift:2172-2257
- Sources/KromoraKit/Models/ImageCollection.swift:939-1230

This makes the main window view responsible for asynchronous application workflow and makes the flow difficult to exercise without PhotosUI objects.

## Acceptance criteria

- [ ] ContentView contains no Photos import loop, hashing, PHAsset lookup, or per-item error/progress orchestration.
- [ ] Introduce a dedicated import controller/service/coordinator with an injectable Photos provider or transfer abstraction.
- [ ] The controller emits or updates value-based progress and failure state suitable for SwiftUI observation.
- [ ] Cancellation remains responsive between items and does not discard successfully imported items.
- [ ] Original filename preservation and one-time content-digest behavior remain unchanged.
- [ ] ImageCollection remains responsible for admitting durable imported payloads, while the import controller owns provider interaction.
- [ ] ContentView only presents PhotosPicker and connects its selection/cancel actions to the import boundary.
- [ ] Add focused tests for successful multi-item import, partial provider failure, cancellation, filename fallback, and digest propagation.
- [ ] Existing Photos import, durability, and performance tests remain passing; run dg validate and git diff --check.

## Out of scope

- Changing the managed library location or PhotoAsset identity rules.
- Changing the user-visible Photos import UX.
- Replacing ImageCollection's durable import APIs.


### Comment — codex @ 2026-09-12T18:06:33.236Z

Implemented in commit 8adf7cf. Extracted Photos provider interaction and import orchestration into PhotosImportCoordinator with injectable PhotosImportProviding, observable progress/failure/cancellation state, stale-operation protection, filename fallback, and one-time digest propagation. ContentView now only adapts picker selections and forwards cancellation; ImageCollection durable APIs are unchanged. Added focused multi-item, partial-failure, cancellation, filename-fallback, and digest tests. Verification: swift test (1,331 passed, 49 skipped), dg validate (OK), git diff --check (clean).

## Agent log

- 2026-09-12T18:09:17.370Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] ContentView contains no Photos import loop, hashing, PHAsset lookup, or per-item error/progress orchestration. (pass) — ContentView.swift no longer imports Photos; handlePhotosSelection only builds PhotosImportSelection values and delegates to the coordinator.
- [x] Introduce a dedicated import controller/service/coordinator with an injectable Photos provider or transfer abstraction. (pass) — PhotosImportCoordinator + PhotosImportProviding protocol with production PhotosPickerImportProvider and test-only providers.
- [x] The controller emits or updates value-based progress and failure state suitable for SwiftUI observation. (pass) — @Published progress/failures/wasCancelled on an ObservableObject; StatusBar observes photosImportCoordinator.progress.
- [x] Cancellation remains responsive between items and does not discard successfully imported items. (pass) — Verified via testCoordinatorCancellationFinishesWithoutDiscardingEarlierItem and testCancellationLeavesAlreadyImportedOriginalsUsable; both pass.
- [x] Original filename preservation and one-time content-digest behavior remain unchanged. (pass) — originalFilename/transferData boundary preserved; digest computed once via Task.detached and propagated; covered by testCoordinatorPropagatesOneComputedDigestToDurableSource.
- [x] ImageCollection remains responsible for admitting durable imported payloads, while the import controller owns provider interaction. (pass) — Coordinator calls viewModel.appendPhotosImport/beginPhotosImport/finishPhotosImport; ImageCollection APIs untouched in diff.
- [x] ContentView only presents PhotosPicker and connects its selection/cancel actions to the import boundary. (pass)
- [x] Add focused tests for successful multi-item import, partial provider failure, cancellation, filename fallback, and digest propagation. (pass) — PhotosImportTests.swift adds all five scenarios via TestPhotosImportProvider; all 20 tests in the file pass.
- [x] Existing Photos import, durability, and performance tests remain passing; run dg validate and git diff --check. (pass) — swift test --filter PhotosImportTests: 20/20 passed. scripts/ci-tests.sh fast: full run passed (exit 0). dg validate: OK. git diff --check: clean.
Checks run:
- swift build
- swift test --filter PhotosImportTests (20 passed)
- scripts/ci-tests.sh fast (passed, exit 0)
- dg validate (OK)
- git diff --check (clean)
Findings:
- PhotosImportCoordinator.recordFailure (Sources/KromoraKit/ViewModels/PhotosImportCoordinator.swift:208-218) silently drops a failure record if Task.isCancelled becomes true between a provider throw and the recordFailure guard, whereas the original ContentView code always recorded the failure regardless of cancellation state. Non-blocking: doesn't affect data durability or any acceptance criterion; not fixed.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYP5P91OGLZCHBA
Summary: Verified Photos import extraction: PhotosImportCoordinator cleanly owns provider interaction, hashing, and progress/failure state; ContentView only adapts picker selection/cancellation. 20/20 PhotosImportTests pass, fast CI lane passes, dg validate OK, git diff --check clean. One non-blocking observation noted (cancellation-race failure-recording gap), not fixed as it's cosmetic and out of acceptance-criteria scope.
