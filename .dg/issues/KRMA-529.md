---
id: KRMA-529
title: Continue AppViewModel decomposition by extracting workflow coordinators
type: task
status: claimed
priority: medium
agent: claude
verification_agent: codex
model: sonnet
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - architecture
  - app-model
created: 2026-09-21T20:33:09.664Z
updated: 2026-09-23T08:01:18.567Z
depends_on:
  - KRMA-520
  - KRMA-528
estimate: 13
order: zzh
board: product
claim:
  actor: claude
  session: 01MUDS0KK0VVJWIKFJ
  claimed_at: 2026-09-23T07:23:16.367Z
  expires_at: 2026-09-23T08:43:16.455Z
  model: sonnet
  stage: implementation
---

## Objective

Reduce AppViewModel's remaining workflow ownership by extracting one coherent coordinator per cluster, with explicit state ownership, revision fences, task/shutdown behavior, and fake-only tests.

## Context and evidence

After package-mode cleanup and Auto extraction, AppViewModel remains about 5,464 lines with 31 @Published properties, 28 task references, and roughly 200 functions. Remaining clusters are package import orchestration, edit-aware thumbnails, copy/paste and undo/history, crop/rotation/canvas navigation, and the 1,310-line masking extension.

## Scope and staging rules

Do one extraction per PR/ticket follow-up, preserving behavior after each slice:

- LibraryImportCoordinator for all package import entry points, built on CQ-02/03.
- EditedThumbnailCoordinator for edit-aware thumbnails and visible-window scheduling.
- EditorDocumentCoordinator for copy/paste, undo/reset, and history application; it already owns sessions.
- CanvasInteractionState/crop workflow for crop, rotation, and canvas navigation.
- MaskingWorkflowCoordinator for draft versus committed mask recipes.
- For each owner, document owned state, commands, published values, revision fences, tasks, shutdown, and resource limits in APP_ARCHITECTURE.md.
- Add fake-only tests for moved logic; keep AppViewModel integration tests green.
- Do not introduce a second document store or generic event bus.

## Acceptance criteria

- [ ] Each extraction lands as a separately reviewable slice with a responsibility inventory.
- [ ] Moved workflows have tests that do not construct AppViewModel and cover cancellation/supersession where applicable.
- [ ] Existing integration, fast, serial, and packaged-app smoke tests remain green after every slice.
- [ ] AppViewModel's published API and document ownership remain compatible; no duplicate store or event bus is introduced.
- [ ] Shutdown and resource limits are explicit for every new coordinator.

## Dependencies and coordination

Depends on CQ-05 and CQ-13. Use CQ-02/03 results for import extraction. Serialize with UI work touching AppViewModel and ContentView.

## Likely files and checks

AppViewModel.swift and extensions, EditorDocumentCoordinator, new workflow coordinators, CanvasInteractionState, masking models, APP_ARCHITECTURE.md, and focused coordinator tests.


### Comment — claude @ 2026-09-23T08:01:18.566Z

Delivered this ticket's slice: MaskingWorkflowCoordinator (layer/component selection, transient
creation gestures, smart-mask analysis invocation/cancellation/retry, person-signal warm-up).
AppViewModel keeps every masking entry point as a one-line forwarder in AppViewModel+Masking.swift;
MaskingWorkflowDestination is the narrow @MainActor seam back into AppViewModel's document/undo/
preview/inspector state, and PhotoAnalysisCoordinator is injected behind MaskAnalysisProviding so
MaskingWorkflowCoordinatorTests (9 tests, including createSmartMask cancellation and supersession)
construct the coordinator without AppViewModel. Documented in docs/APP_ARCHITECTURE.md under a new
"Masking-workflow ownership" section.

Filed the two other untracked clusters from this ticket's scope as separate backlog follow-ups,
per "one extraction per PR/ticket follow-up" — EditedThumbnailCoordinator is already tracked
separately as KRMA-466:
- KRMA-551: LibraryImportCoordinator for package import entry points (openImages,
  importFromPhotos, importFromRemovableMedia, openSourceFolder).
- KRMA-552: CanvasInteractionState/crop workflow coordinator (crop, rotation, canvas navigation —
  beginCrop/commitCrop/cancelCrop, rotateClockwise/CounterClockwise, fitCanvas/zoomCanvas/panCanvas).

Both depend on this ticket. Their bodies are currently title-only: my session's write access is
scoped to this claimed issue, so `dg issue update`/`edit` on the new tickets failed with "Claim
session ... no longer owns" even immediately after creation. Whoever picks up KRMA-551/552 should
flesh out acceptance criteria from the corresponding bullet in this ticket's "Scope and staging
rules" section and the MaskingWorkflowCoordinator/AutoWorkflowCoordinator precedent.

The remaining "EditorDocumentCoordinator for copy/paste, undo/reset, and history application" item
did not need a new extraction: EditorDocumentCoordinator already owns sessions/history/clipboard as
value state, and AppViewModel's copyAllEdits/pasteEdits/undo/redo are already thin delegates to it.

Verification: swift build (clean), swift build --build-tests -Xswiftc -warnings-as-errors (clean),
focused masking/coordinator suite (97 tests, 0 failures), scripts/ci-tests.sh verify (lane
partition clean, 1624 tests), scripts/ci-tests.sh fast (failures are exactly the KRMA-547/KRMA-548
documented pre-existing baseline debt: CopyPasteTests.testMultiPasteUpdatesOnlySelectedPhotosAnd...,
LibraryDeletionTests x3, LibraryScanTests x4, ThumbnailSwitchLifecycleTests — all independently
reproduced on clean HEAD by prior agents, none touch masking/AppViewModel+Masking.swift/
MaskingWorkflowCoordinator).
