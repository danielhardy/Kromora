---
id: KRMA-586
title: "Stage 6: Extract Photos import batch presentation state from AppViewModel"
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - architecture
  - maintainability
  - appviewmodel
created: 2026-09-25T05:51:26.616Z
updated: 2026-09-25T05:51:26.616Z
blockers: []
order: zzzy
board: product
depends_on:
  - KRMA-469
context:
  files:
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/ViewModels/PhotosImportCoordinator.swift
    - Sources/KromoraKit/ViewModels/LibraryImportCoordinator.swift
    - Tests/KromoraKitTests/PhotosImportTests.swift
  docs:
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-460
    - KRMA-469
    - KRMA-551
  commands:
    - swift build
    - swift test --filter 'PhotosImportTests|LibraryImportCoordinatorTests'
    - scripts/ci-tests.sh fast
    - dg validate
    - git diff --check
---

Parent: KRMA-460

## Objective

Move the remaining Photos package-import batch state and its finish sequencing out of
`AppViewModel`. Keep the existing `PhotosImportCoordinator` as the provider/progress owner and
`LibraryImportCoordinator` as the package-write owner; this follow-up owns only the batch bridge
between their results and the library/editor presentation.

## Context

The root inventory in KRMA-469 found a multi-call batch lifecycle still stored in
`AppViewModel.swift` under `Photo import`. The root retains
`didPresentInspectorForPhotosImport`, `isPortablePhotosImportActive`,
`portablePhotosImportNeedsRefresh`, `portablePhotosImportWasEmpty`, and
`portablePhotosImportFirstAssetID`. `preparePhotosImport`, `insertPhotosImport`,
`insertPhotosImportAsync`, `presentInspectorForFirstPhotosImportItem`, and
`finishPhotosImportDestination` coordinate those values across item callbacks and batch completion.

The async and synchronous insertion methods duplicate result mapping and presentation updates.
This state determines whether to defer the package index refresh, which first imported asset to
open, and when to present the inspector. Moving it behind a fakeable owner makes that batch contract
independently testable without constructing `AppViewModel` or PhotoKit.

## Acceptance criteria

- [ ] A focused Photos batch owner holds the batch flags and first-asset/inspector-once state; it
  does not store `AppViewModel`, a second library/document store, or a package import worker.
- [ ] Sync and async item insertion publish the same inserted/duplicate/failure outcome and update
  the batch state consistently.
- [ ] Batch finish commits at most one coalesced library refresh, opens the first accepted asset
  only when the package was empty at batch start, and presents the inspector at most once.
- [ ] Empty batches, failures, duplicates, cancellation, and refresh errors close/reset the batch
  without leaving stale flags for the next Photos operation.
- [ ] Existing source/document revision and import-operation fences remain intact; stale callbacks
  cannot refresh the collection or open an asset for a superseded operation.
- [ ] Fake-based owner tests cover batch initialization, result mapping, coalesced finish, first
  asset/inspector behavior, and stale or failed completion. Existing Photos/AppViewModel integration
  coverage remains green.
- [ ] `swift build`, the focused Photos/import suites, the fast CI lane, `dg validate`, and
  `git diff --check` pass.

## Implementation notes

### Suggested symbols and boundaries

- Move the batch fields listed above and the batch lifecycle methods into a narrowly scoped
  `PhotosImportBatchCoordinator` (or an equivalently named focused owner).
- Keep `AppViewModel` as a thin `PhotosImportDestination` adapter for `collection` state, source
  opening, inspector presentation, user-visible errors, and the existing
  `LibraryImportCoordinator` calls.
- Keep package copying, hashing, durability, and index mutation in `LibraryImportCoordinator`.
  Keep Photos enumeration, provider task/progress, and source payload lifetime in
  `PhotosImportCoordinator`.
- Use an operation/generation fence so a superseded batch cannot publish its final collection
  refresh or source handoff. Preserve the current contract that a package batch does one final
  index/window refresh after imported items have been accepted.
- Add `PhotosImportBatchCoordinatorTests.swift` with fakes; retain integration coverage in
  `PhotosImportTests` and relevant `AppViewModelTests`.

### Out of scope

- Re-extracting the PhotoKit provider loop or changing its cancellation contract.
- Changing durable package-import semantics, duplicate policy, progress wording, or import results.
- Moving `load`, `openPortableAsset`, `updateDocument`, editor sessions, or collection ownership.
- A second package importer, document store, event bus, or render/scheduler resource.
- Broad import/deletion cleanup beyond this Photos batch lifecycle.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
