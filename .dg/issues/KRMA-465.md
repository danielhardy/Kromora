---
id: KRMA-465
title: "Stage 1: Extract AppViewModel auto-adjustment invocation owner"
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
created: 2026-09-19T16:27:22.524Z
updated: 2026-09-19T16:27:22.524Z
order: t
board: product
---

Parent: KRMA-460

## Objective

Extract Auto invocation, progress, cancellation, and apply sequencing from `AppViewModel` into a testable collaborator. Keep existing analysis/scoring policy in `PhotoAnalysisCoordinator`, `ContentAwareAutoEngine`, and the existing Auto engines.

## Ownership contract

- State owned: `autoAdjustmentTask`, invocation revision, progress state, and cancellation state needed only while an Auto run is admitted.
- Admitted commands: start Auto for the current source/document and cancel Auto; the collaborator returns a value result rather than mutating the root document.
- Published values: a narrow `Sendable` progress/result value only; `AppViewModel` remains the publisher of the active `EditDocument`, status, and user-facing errors.
- Revision checks: source identity, document revision, and invocation revision must be checked before returning an applicable result; stale/cancelled work must not write.
- Task handles: one bounded Auto task per active invocation; superseding invocation cancels the previous task and no detached/unbounded task is introduced.
- Shutdown behavior: cancellation is idempotent and called from load, undo/redo replacement, and shutdown before collaborators are torn down.
- Resource limits: reuse existing analysis/render schedulers and histogram fallback; no second renderer, event bus, document store, or unbounded candidate fan-out.

## Scope and acceptance

- [ ] Root applies the returned `AutoEnhancementResult` through the existing `updateDocument` / undo / persistence path.
- [ ] Existing Auto policy/scoring and histogram fallback semantics are preserved.
- [ ] Collaborator-level fake-based tests plus AppViewModel integration coverage exist for Auto, navigation during work, undo grouping, persistence failure, and shutdown.
- [ ] No `AppViewModel` back-reference or Swift 6 concurrency escape hatch is introduced.
- [ ] Focused tests, `swift build`, the relevant fast CI lane, `dg validate`, and `git diff --check` pass.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
