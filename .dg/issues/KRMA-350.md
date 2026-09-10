---
id: KRMA-350
title: Integrate content-aware Auto with atomic apply, undo, cancellation, and status UI
type: feature
status: ready
priority: high
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - editor
  - integration
created: 2026-09-10T14:40:09.265Z
updated: 2026-09-10T14:53:43.752Z
depends_on:
  - KRMA-347
  - KRMA-349
order: zz
board: product
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Wire the candidate engine and durable result into the existing Auto action and editor lifecycle. One user invocation must be atomic, cancellable, reviewable, and undoable as one operation.

## Scope

- Replace or extend the current `runAutoAdjustment()` path with the content-aware coordinator while retaining global-only fallback when semantic analysis is unavailable.
- Capture source/document/revision guards before work; navigation, manual editing, close, or superseding Auto cancels stale work.
- Show progress through analysis, candidate rendering, validation, and apply; provide a short result description and reasons.
- Apply the accepted document atomically through existing persistence and undo APIs as one Auto operation.
- Leave the document unchanged on analysis/render/validation failure, cancellation, or stale revision.
- Show `No further improvement found` when unchanged wins and avoid a persistence write for that no-op.
- Keep the existing action availability and failure/loading state from getting stuck.

## Acceptance criteria

- [ ] The user-facing Auto action invokes the content-aware path and falls back to global-only candidates when optional semantic analysis fails.
- [ ] One invocation produces exactly one undoable history operation, including generated layers and global changes.
- [ ] Revision guards prevent stale analysis from applying after navigation or manual edits; cancellation completes without a late write.
- [ ] Progress/status text distinguishes analysis, rendering candidates, validating, applied, no-op, cancelled, and failed states.
- [ ] Render/validation failure leaves the previous document and ownership untouched and clears all transient loading state.
- [ ] Repeating Auto on an unchanged successful result reports no further improvement and does not create a duplicate history entry or persistence write.
- [ ] Undo/redo, save/reopen, thumbnail navigation, cancellation during work, and manual edits during work are covered by regression tests.
- [ ] Existing Auto action compatibility remains intact for unsupported images and the global-only fallback.

## Non-goals

- Do not add new inspector controls for every rationale field.
- Do not make batch Auto part of this ticket.
- Do not change export behavior outside the accepted document path.

## Likely files

- `Sources/KromoraKit/ViewModels/AppViewModel+Light.swift`
- `Sources/KromoraKit/ViewModels/AppViewModel.swift`
- `Sources/KromoraKit/ViewModels/EditPersistenceCoordinator.swift`
- `Sources/KromoraKit/Models/EditHistory.swift`
- `Sources/KromoraKit/Models/AutoAdjustment.swift`
- `Sources/KromoraKit/Models/ImageWorkScheduler.swift`
- `Sources/KromoraKit/Views/LightInspectorView.swift`
- `Sources/KromoraKit/Views/StatusBar.swift`
- `Tests/KromoraKitTests/Auto*Tests.swift`

## Verification

Run focused AppViewModel/history/persistence/cancellation tests, then the repository fast lane. Exercise both a real generated fixture and injected failure paths.
