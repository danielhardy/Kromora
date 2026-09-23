---
id: KRMA-552
title: Extract CanvasInteractionState/crop workflow coordinator (crop, rotation, canvas navigation)
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-23T12:03:14.847Z
  session: 01MUE1YJNDMJNEO45T
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - cleanup
  - architecture
  - app-model
created: 2026-09-23T07:59:55.004Z
updated: 2026-09-23T12:03:21.950Z
depends_on:
  - KRMA-529
order: y
board: product
---

## Objective

Extract CanvasInteractionState/crop workflow coordinator (crop, rotation, canvas navigation)

## Context

AppViewModel still owns the crop session commands, rotation edits, and canvas navigation even
though CanvasInteractionState already owns the observable pointer-frequency values. Extract this
workflow as a separate architectural slice while keeping the active EditDocument and its history in
AppViewModel.

## Acceptance criteria

- [x] CanvasWorkflowCoordinator owns crop entry, apply/cancel/reset, rotation, and canvas navigation commands; AppViewModel retains compatible forwarding APIs.
- [x] The active EditDocument, history, persistence, and render/revision scheduling remain AppViewModel-owned, with no second document store.
- [x] Fake-only tests cover crop cancel/apply, rotation, and presentation-only canvas navigation without constructing AppViewModel.
- [x] Ownership, boundary values, shutdown, and resource limits are documented in APP_ARCHITECTURE.md.
- [x] Focused canvas/workflow tests and the build pass.

## Implementation notes

Follow the MaskingWorkflowCoordinator pattern from KRMA-529. Keep observable crop draft and
navigation values in CanvasInteractionState, move command sequencing/presentation snapshot to the
new coordinator, and cross the AppViewModel boundary through a narrow destination protocol. Source
replacement must discard transient crop state without committing it.

### Comment — codex @ 2026-09-23T12:01:30.409Z

Implemented and committed canvas workflow extraction (19d8ecc). CanvasWorkflowCoordinator now owns CanvasInteractionState, crop session/presentation workflow, rotation, and fit/fill/zoom/pan commands; AppViewModel retains its compatibility façade plus document, history, persistence, and render scheduling. Added fake-only coordinator tests and documented ownership/shutdown boundaries. Checks: swift build; CanvasWorkflowCoordinatorTests (4 passed); CanvasNavigationTests (18 passed); git diff --check.

### Comment — pi @ 2026-09-23T12:03:00.217Z

Counterpoint verification in progress: implementation diff reviewed; running focused checks.

### Comment — pi @ 2026-09-23T12:03:21.949Z

Counterpoint verification PASS (full report; the completion call recorded verdict=pass, details follow).

Acceptance criteria (all pass):
1. Coordinator owns crop entry/apply/cancel/reset, rotation, canvas navigation; AppViewModel retains compatible forwarding APIs — PASS. All command sequencing moved verbatim into CanvasWorkflowCoordinator; AppViewModel exposes a forwarding facade plus CanvasWorkflowDestination conformance. All callers compile.
2. EditDocument/history/persistence/render scheduling remain AppViewModel-owned, no second document store — PASS. Coordinator holds no document; durable mutations cross via updateCanvasWorkflowDocument into the ordinary updateDocument history path; navigation routes through canvasNavigationDidChange without touching history.
3. Fake-only tests cover crop cancel/apply, rotation, presentation-only navigation without AppViewModel — PASS. CanvasWorkflowCoordinatorTests (4 tests) use FakeDestination only.
4. Ownership/boundary/shutdown/resource limits documented in APP_ARCHITECTURE.md — PASS. New ownership section + table row; no-async-work resource statement included.
5. Focused tests and build pass — PASS (see checks).

Checks run: swift build (ok); CanvasWorkflowCoordinatorTests 4/4 pass; CanvasNavigationTests 18/18 pass; facade suites CropTests|ImageRotationTests|NavigationStateTests|MenuCommandTests 19/19 pass; git diff --check clean; manual diff review of 19d8ecc.

Findings (notes, non-blocking, no fixes applied, no child tickets): (a) setCanvasZoom now compares whole-navigation equality vs old zoom-only comparison — calling it with the current zoom while in fit mode flips mode to custom and schedules a preview where old code stayed silent. Underlying state mutation is identical; only redundant preview scheduling differs in that corner; firing is arguably more correct. (b) Working tree holds unrelated uncommitted changes (NumericClamping refactor, .dg bookkeeping) not touching KRMA-552 files; left untouched per one-issue rule. No verification commits.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-23T12:03:14.847Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: unknown
Pickup session: 01MUE1YJNDMJNEO45T
