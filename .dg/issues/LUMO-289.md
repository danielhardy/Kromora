---
id: LUMO-289
title: "Epic: single-view load performance with masks and edits"
type: feature
status: done
priority: urgent
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
labels:
  - performance
  - preview
  - masks
  - epic
created: 2026-09-08T23:47:30.392Z
updated: 2026-09-09T00:17:48.389Z
order: a0
board: product
commits:
  - ef9af97
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Single-view open of an edited photo submits one settled preview, not two.
      result: pass
      notes: "install() no longer calls schedulePreview(); the first pixel request is admitted only in adoptStoredEdits once the disk document resolves, guarded by previewScheduledSourceRevision (set by schedulePreview, cleared in install). A mid-load user edit still converges: shouldAdopt goes false and the single admitted preview publishes the user's current document."
    - criterion: Slider drags submit previews only; at most one trailing thumbnail render per pause.
      result: pass
      notes: updateDocument/applyHistoryDocument no longer force-enqueue edited thumbnails. scheduleEditedThumbnailAfterSettle debounces 500ms, is suppressed while isPreviewInteractionActive or a preview debounce is pending, coalesces bursts into one task per asset (cancel-and-replace), and trails via pendingEditedThumbnailAssetID on settle (debounce task) and endPreviewInteraction. Navigation cancels the prior asset's debounce and scheduler job.
    - criterion: Masked-photo first pixels no longer wait on a wasted pre-edit render.
      result: pass
      notes: "Two factors verified: (a) the wasted pristine-document render is gone per criterion 1, so Vision no longer runs twice per open; (b) PreviewCoordinator.render publishes a deferSemantic base frame first when document.hasSemanticMasks (procedural/brush masks still applied; semantic components skipped in RenderEngine.resolvedLocalMasks via resolveSemanticMasks=false), then refines with the resolved render under the existing token/revision staleness fence. Superseded mask work is fenced by source+document-identity+revision (noteMaskRequest/isCurrentMaskRequest), so a lagging Vision result for an older document can never publish."
    - criterion: Benchmarks show the improvement (see verification ticket).
      result: pass
      notes: "The epic text explicitly delegates quantitative proof to its verification ticket: LUMO-297 (Verify single-view performance gains and lock in regression tests) exists and is backlog. This commit contains no benchmark numbers (tests only), so numeric proof is still owed there; no code in this epic blocks it. Not a blocker for the admission-behavior acceptance above."
  checks_run:
    - scripts/ci-tests.sh fast (642 tests, 0 failures)
    - swift test --filter LocalMaskRenderingTests|InfoSemanticMaskRenderingTests (25 tests, 0 failures, 1 pre-existing opt-in benchmark skip)
    - git diff --check (clean)
    - dg validate (OK; only low-context-completeness warnings on child tickets LUMO-291..295)
    - "Source scan: no new @unchecked Sendable / nonisolated(unsafe) / @preconcurrency (Swift 6 zero-opt-out holds; single comment mention only)"
  findings:
    - "Non-blocking: RenderEngine.trimMaskRequestState evicts an arbitrary source (Dictionary.first, despite the local name oldestSource) once >16 sources are tracked; per-request eviction correctly uses min(by:). A wrong eviction only causes a spurious .cancelled for an in-flight render (one dropped frame, next tick re-renders). Filed as LUMO-298 (verification, low, parent LUMO-289)."
    - "Considered but intentionally left unchanged: scheduleInteractivePreview does not set previewScheduledSourceRevision, so an edit made while stored edits are still loading (interactive path) still admits one settled preview in adoptStoredEdits. That extra render publishes the user's actual edit and is correct; setting the marker there would risk suppressing the only settled publication of a mid-load edit."
    - "Serial lane could not be re-verified end-to-end: the repo runner exits with the pre-existing shell error run_lane:8: read-only variable: status (also reported by the implementer). Fast lane (642 tests) plus the focused mask suites cover every file this commit touches."
  fixes: []
  verification_commits:
    - ef9af97
  actor: pi
  resolved_model: openrouter/meta/muse-spark-1.3-contributor
  completed_at: 2026-09-09T00:17:48.386Z
  session: 01MTTCKKCPWYM5QZ4S
---

## Objective

Restore fast single-view loads, including for photos with masks and/or edits, by eliminating redundant full-pipeline renders serialized on the single RenderEngine actor.

## Context

All GPU work (preview makeCIImage, edited thumbnails, histogram, prefetch) funnels through one actor RenderEngine (Sources/LumoKit/Models/RenderEngine.swift). Scheduler lanes isolate queues, not execution. Three sources of redundant work were found in review (Sept 2026):

1. Every open of an edited photo renders the settled preview twice: install() schedules with a pristine EditDocument, then adoptStoredEdits re-schedules with the disk document (Sources/LumoKit/ViewModels/AppViewModel.swift, prepareAndInstall/install/adoptStoredEdits).
2. Every edit tick (including slider-drag ticks) force-enqueues a full edited-thumbnail render that alternates with the preview on the actor (updateDocument/applyHistoryDocument, requestEditedThumbnail force:true). Regression from b6df9a3 (edited library thumbnails).
3. Semantic-mask Vision runs before first pixels publish (buildImage -> resolvedLocalMasks -> PhotoAnalysisCoordinator.mask), multiplied by (1) and (2).

The caches themselves (developedSourceCache, processingPrefixCache, localMaskCache shared across preview/thumbnail, ResolutionPlanner, presentation-gated histogram) are sound. The problem is admission of redundant work, not caching.

## Stages

- Stage 1: defer first preview until stored edits resolve; debounce/coalesce edited thumbnails and skip during interaction.
- Stage 2: two-phase masked preview (publish unmasked base fast, refine when masks resolve); prompt cancellation of superseded Vision mask work.
- Stage 3: prefetch stored-edit awareness; thumbnail raster path without PNG/MainActor round-trip.
- Close with a measurement/verification ticket proving open/settle latency improvements.

## Acceptance

- Single-view open of an edited photo submits one settled preview, not two.
- Slider drags submit previews only; at most one trailing thumbnail render per pause.
- Masked-photo first pixels no longer wait on a wasted pre-edit render.
- Benchmarks show the improvement (see verification ticket).


### Comment — codex @ 2026-09-09T00:15:23.828Z

Implemented single-view render admission optimizations in ef9af97: stored-edit-gated first previews, coalesced active thumbnail work after interaction settles, progressive semantic-mask previews with cancellation fencing, stored-edit-aware adjacent prefetch, and direct actor-local thumbnail rasterization. Verification: scripts/ci-tests.sh fast passed all 642 required tests; focused LocalMaskRenderingTests and InfoSemanticMaskRenderingTests passed (one existing benchmark skip). The serial lane executed its 277 tests but the repository runner then exited on its existing shell error: run_lane:8: read-only variable: status; the earlier two mask failures were fixed and the focused rerun passes.

## Agent log

- 2026-09-09T00:17:48.387Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Single-view open of an edited photo submits one settled preview, not two. (pass) — install() no longer calls schedulePreview(); the first pixel request is admitted only in adoptStoredEdits once the disk document resolves, guarded by previewScheduledSourceRevision (set by schedulePreview, cleared in install). A mid-load user edit still converges: shouldAdopt goes false and the single admitted preview publishes the user's current document.
- [x] Slider drags submit previews only; at most one trailing thumbnail render per pause. (pass) — updateDocument/applyHistoryDocument no longer force-enqueue edited thumbnails. scheduleEditedThumbnailAfterSettle debounces 500ms, is suppressed while isPreviewInteractionActive or a preview debounce is pending, coalesces bursts into one task per asset (cancel-and-replace), and trails via pendingEditedThumbnailAssetID on settle (debounce task) and endPreviewInteraction. Navigation cancels the prior asset's debounce and scheduler job.
- [x] Masked-photo first pixels no longer wait on a wasted pre-edit render. (pass) — Two factors verified: (a) the wasted pristine-document render is gone per criterion 1, so Vision no longer runs twice per open; (b) PreviewCoordinator.render publishes a deferSemantic base frame first when document.hasSemanticMasks (procedural/brush masks still applied; semantic components skipped in RenderEngine.resolvedLocalMasks via resolveSemanticMasks=false), then refines with the resolved render under the existing token/revision staleness fence. Superseded mask work is fenced by source+document-identity+revision (noteMaskRequest/isCurrentMaskRequest), so a lagging Vision result for an older document can never publish.
- [x] Benchmarks show the improvement (see verification ticket). (pass) — The epic text explicitly delegates quantitative proof to its verification ticket: LUMO-297 (Verify single-view performance gains and lock in regression tests) exists and is backlog. This commit contains no benchmark numbers (tests only), so numeric proof is still owed there; no code in this epic blocks it. Not a blocker for the admission-behavior acceptance above.
Checks run:
- scripts/ci-tests.sh fast (642 tests, 0 failures)
- swift test --filter LocalMaskRenderingTests|InfoSemanticMaskRenderingTests (25 tests, 0 failures, 1 pre-existing opt-in benchmark skip)
- git diff --check (clean)
- dg validate (OK; only low-context-completeness warnings on child tickets LUMO-291..295)
- Source scan: no new @unchecked Sendable / nonisolated(unsafe) / @preconcurrency (Swift 6 zero-opt-out holds; single comment mention only)
Findings:
- Non-blocking: RenderEngine.trimMaskRequestState evicts an arbitrary source (Dictionary.first, despite the local name oldestSource) once >16 sources are tracked; per-request eviction correctly uses min(by:). A wrong eviction only causes a spurious .cancelled for an in-flight render (one dropped frame, next tick re-renders). Filed as LUMO-298 (verification, low, parent LUMO-289).
- Considered but intentionally left unchanged: scheduleInteractivePreview does not set previewScheduledSourceRevision, so an edit made while stored edits are still loading (interactive path) still admits one settled preview in adoptStoredEdits. That extra render publishes the user's actual edit and is correct; setting the marker there would risk suppressing the only settled publication of a mid-load edit.
- Serial lane could not be re-verified end-to-end: the repo runner exits with the pre-existing shell error run_lane:8: read-only variable: status (also reported by the implementer). Fast lane (642 tests) plus the focused mask suites cover every file this commit touches.
Fixes:
- None
Verification commits:
- ef9af97
Actor: pi
Resolved model: openrouter/meta/muse-spark-1.3-contributor
Pickup session: 01MTTCKKCPWYM5QZ4S
Summary: Verified: stored-edit-gated first preview, coalesced post-settle thumbnails, two-phase semantic-mask preview with document-identity cancellation fencing, stored-edit-aware prefetch, and direct thumbnail rasterization all hold per acceptance. No blockers; one non-blocking nit filed as LUMO-298; benchmark proof tracked in LUMO-297.
