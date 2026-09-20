---
id: KRMA-464
title: "Stage 0: Move thin AppViewModel navigation façades into extensions"
type: task
status: backlog
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
updated: 2026-09-19T16:27:02.703Z
order: m
board: product
---

Parent: KRMA-460

## Objective

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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
