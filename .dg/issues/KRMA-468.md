---
id: KRMA-468
title: "Stage 4: Extract the AppViewModel masking workspace owner"
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
created: 2026-09-19T16:27:25.201Z
updated: 2026-09-20T02:20:19.291Z
depends_on:
  - KRMA-467
order: y8
board: product
---

Parent: KRMA-460

## Objective

Replace the 1,310-line `AppViewModel+Masking.swift` feature boundary with a testable masking workspace collaborator. Keep committed recipes on the root's single document commit path.

## Ownership contract

- State owned: gesture drafts, smart-mask task/retry context, and overlay request identity needed by the masking workspace.
- Admitted commands: begin/update/cancel/commit masking gestures, request/retry smart masks, and request overlay updates.
- Published values: draft interaction state and narrow overlay/workflow values as `Sendable` snapshots; committed recipes are returned to `AppViewModel`, which alone publishes and applies the active `EditDocument`.
- Revision checks: source/document revision, mask request identity, gesture generation, and overlay generation must drop stale completions and prevent late writes.
- Task handles: bounded smart-mask and overlay request tasks with explicit cancellation on supersession, source/document change, leaving masking, and shutdown.
- Shutdown behavior: cancel in-flight Vision/mask/overlay work and release retained request context; committed document persistence remains root-owned.
- Resource limits: reuse `MaskInteractionState`, existing mask providers/stores, and overlay renderer contracts; no GPU setup for non-render tests, no duplicate mask cache/provider, and no unbounded gesture history.

## Scope and acceptance

- [ ] Existing masking UI contracts and overlay coordinate behavior are preserved.
- [ ] Recipes are committed only through `updateDocument`; no second document store or broad root back-reference is added.
- [ ] Collaborator tests with fakes cover gesture drafts, smart-mask retry/cancellation, stale results, and non-render overlay requests.
- [ ] AppViewModel integration coverage remains for committed edits, undo/redo, navigation, persistence failure, and shutdown.
- [ ] No `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency` is introduced.
- [ ] Focused tests, `swift build`, the relevant fast CI lane, `dg validate`, and `git diff --check` pass.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
