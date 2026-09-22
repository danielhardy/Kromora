---
id: KRMA-529
title: Continue AppViewModel decomposition by extracting workflow coordinators
type: task
status: ready
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
updated: 2026-09-22T15:05:22.632Z
depends_on:
  - KRMA-520
  - KRMA-528
estimate: 13
order: zzh
board: product
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
