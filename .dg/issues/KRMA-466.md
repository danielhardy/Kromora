---
id: KRMA-466
title: "Stage 2: Extract edited-thumbnail workflow ownership from AppViewModel"
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
created: 2026-09-19T16:27:23.427Z
updated: 2026-09-19T16:28:46.110Z
depends_on:
  - KRMA-465
order: w
board: product
---

Parent: KRMA-460

## Objective

Create an `EditedThumbnailCoordinator` that owns edited-thumbnail scheduling state, while `AppViewModel` keeps demand hooks and the published collection projection.

## Ownership contract

- State owned: per-asset generations, debounce tasks, job IDs, and cache-identity hashing needed to identify the latest edited thumbnail request.
- Admitted commands: request, debounce, cancel, and resolve an edited thumbnail for a specific asset/document snapshot; demand hooks remain in the root.
- Published values: thumbnail results and narrow status values crossing as `Sendable` values; no collaborator-owned published active document or collection store.
- Revision checks: asset/source identity, document revision, cache identity, and generation/job ID must fence late completions.
- Task handles: bounded per-asset debounce/work handles using existing `ImageWorkScheduler` lanes and cancellation IDs; superseded work is cancelled/dropped.
- Shutdown behavior: cancel all pending thumbnail work and release scheduler/cache references during shutdown and source teardown.
- Resource limits: reuse existing scheduler lanes and cache limits; no unbounded per-asset task retention or full-resolution render fan-out.

## Scope and acceptance

- [ ] Current thumbnail demand behavior for collection, filmstrip, and grid is preserved.
- [ ] Latest-wins behavior and crop-aware cache identity are preserved.
- [ ] Collaborator tests with fakes cover debounce, cancellation, stale completions, and cache identity; integration coverage remains for navigation and edit adoption.
- [ ] No second document store, generic event bus, root back-reference, or Swift 6 escape hatch is introduced.
- [ ] Focused tests, `swift build`, the relevant fast CI lane, `dg validate`, and `git diff --check` pass.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
