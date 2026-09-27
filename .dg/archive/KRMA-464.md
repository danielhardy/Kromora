---
id: KRMA-464
title: "Withdrawn: Stage 0 AppViewModel façade file split is not needed"
type: task
status: done
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - architecture
  - maintainability
  - appviewmodel
  - stage-0
created: 2026-09-19T16:27:02.703Z
updated: 2026-09-24T01:13:24.241Z
blockers: []
order: zzzzzzzv
board: product
---

Parent: KRMA-460

## Disposition — do not implement (reviewed 2026-09-23)

Withdrawn. Leave the code as it is. This ticket was optional navigation-only file splitting, and the moves it names are either already done or unsafe.

Evidence an agent should trust instead of re-deriving this:

- Crop, rotation, and canvas commands are already one-line forwarders to `CanvasWorkflowCoordinator` (KRMA-552). See `AppViewModel.swift` MARK “Crop and rotation workflow façade” and “Canvas navigation façade” (about lines 4408–4477). `beginCanvasInteraction` / `endCanvasInteraction` are intentionally not `beginPreviewInteraction`: pinch-zoom must not open an undo group. Do not relocate them.
- `presentError` (MARK “Error presentation”, about line 1436) is one private function.
- Photo import (about lines 2596–2801) still sequences `LibraryImportCoordinator` and Photos presentation. Package-write ownership already moved in KRMA-551. It is not a passthrough.
- MARK “Look folder” (about line 5299 through end of file) is a mislabeled remainder. `chooseLookFolder`, `chooseLookFile`, `importLook`, and `refreshLooks` sit beside `saveActiveDocument`, `queuePersistence`, `flushPendingWrites`, `discardPendingWrites`, `shutdown()`, and `extension AppViewModel: CanvasWorkflowDestination`. Moving that MARK would move `shutdown()`, which this ticket forbids.
- Export dialogs (about lines 5116–5261) build requests and call `ExportCoordinator`. A new `AppViewModel+Export.swift` would not change ownership.

Closing this ticket is the successful outcome. Do not open a replacement file-split ticket.

## Original objective

Move only already-thin, behavior-preserving AppViewModel façade sections into `AppViewModel+*.swift` files after confirming they contain no workflow ownership. This is optional navigation cleanup and must not be used to hide state machines.

## Scope

- Photo import façade.
- Export façade.
- Look folder / Look file import panels, routing new panels through `FileDialogProviding`.
- Crop / rotation / canvas passthroughs.
- Error presentation helpers.

Do not add raw `NSOpenPanel` usage to the root. Do not move Auto, `load()`, preview scheduling, edited thumbnails, histogram admission, undo/history apply, masking, or `shutdown()`.

## Ownership contract

- State owned: none; no mutable workflow state or task handles move.
- Admitted commands: existing public façade methods only.
- Published values: unchanged; `AppViewModel` remains the sole published document owner.
- Revision checks: unchanged because no asynchronous ownership moves.
- Task handles: none introduced or relocated.
- Shutdown behavior: unchanged; composition and shutdown stay on `AppViewModel`.
- Resource limits: no new workers, caches, renderers, or retained resources.

## Acceptance criteria

- [ ] Public APIs and behavior are unchanged.
- [ ] The diff consists of method moves plus extension/file headers and any required access-control adjustments.
- [ ] No forbidden workflow block is relocated.
- [ ] Focused tests, fast CI, `swift build`, `dg validate`, and `git diff --check` pass.

### Comment — cursor @ 2026-09-24T01:13:23.537Z

Triage 2026-09-23: withdrawn. Stage 0 file splits are either already one-line forwarders (KRMA-552) or would move shutdown() with the Look-folder MARK. No implementation.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
