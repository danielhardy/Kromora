---
id: KRMA-465
title: "Superseded by KRMA-528: Auto invocation owner already extracted"
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
created: 2026-09-19T16:27:22.524Z
updated: 2026-09-24T01:13:24.569Z
blockers: []
order: zzzzzzzx
board: product
---

Parent: KRMA-460

## Disposition — do not implement (reviewed 2026-09-23)

Superseded by **KRMA-528** (`done`). That ticket extracted `AutoWorkflowCoordinator` and kept result application on `AppViewModel`.

Already in the tree:

- `Sources/KromoraKit/Models/PhotoAnalysis/AutoWorkflowCoordinator.swift` owns invocation revision, cancellation, preview gating, and progress. `ProductionAutoWorkflow` owns the content-aware path and the explicit degraded histogram fallback.
- `Tests/KromoraKitTests/AutoWorkflowCoordinatorTests.swift` covers success, cancellation, supersession, the no-preview gate, fences, and the fallback reason without constructing `AppViewModel`.
- `AppViewModel.runAutoAdjustment()` (MARK “Auto adjustment”, about lines 1441–1571) only builds an `AutoWorkflowRequest`, checks source/document fences in the completion, and applies an improved result through `updateDocument(preservingAutoResult:)`. `cancelAutoAdjustment`, `waitForAutoAdjustmentCompletion`, and `resetAutoAdjustmentForLifecycle` forward to the coordinator. `shutdown()` calls `autoWorkflowCoordinator.invalidate`.

Re-extracting this MARK would duplicate that owner. The acceptance criteria below are already satisfied by KRMA-528. Do not start a second Auto coordinator.

## Original objective

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

### Comment — cursor @ 2026-09-24T01:13:23.759Z

Triage 2026-09-23: superseded by KRMA-528. AutoWorkflowCoordinator already owns invocation, progress, and cancellation. The remaining AppViewModel Auto MARK is the apply façade and stays there.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
