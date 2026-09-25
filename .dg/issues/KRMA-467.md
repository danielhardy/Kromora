---
id: KRMA-467
title: "Stage 3: Move remaining preview and histogram scheduling ownership"
type: task
status: review
priority: medium
verification_report:
  verdict: blocker
  acceptance_criteria:
    - criterion: RenderRequest / RenderEngine funnel semantics and preview quality/resource policies are preserved.
      result: pass
      notes: PreviewCoordinator remains the sole render-admission owner; PreviewAdmissionCoordinator.submit/scheduleInteractivePreview forward into it unchanged. Focused suite and fast CI lane pass.
    - criterion: Histogram parity and comparison retry behavior are preserved.
      result: pass
      notes: Histogram admission moved to PreviewAdmissionCoordinator.updateHistogram/cancelHistogram/refreshHistogramGate and behaves correctly (HistogramTests, DevelopInspectorTests histogram cases pass). Comparison-retry behavior still works, but the cluster was never actually moved off AppViewModel (see finding below) despite being explicitly in scope.
    - criterion: Collaborator-level fake-based admission/fence tests exist, with AppViewModel integration coverage for navigation, comparison, and histogram behavior.
      result: fail
      notes: "PreviewAdmissionCoordinatorTests.swift has only 1 of the 5 required cases (idle/adjacent-prefetch job-id independence). Missing: stale display revision/asset id drops a cache hit and histogram result; idle admission never calls the preview publication fake; comparison retry runs once per comparison revision; ROI requests do not adopt a canonical cache hit. AppViewModel integration coverage (FilmstripNavigationTests, ComparisonModeTests, ThumbnailSwitchLifecycleTests, PreviewDiskCacheTests) remains green."
    - criterion: load(), updateDocument(), applyHistoryDocument(), and shutdown() sequencing remain root-owned.
      result: pass
      notes: Verified in AppViewModel.swift; shutdown() calls previewAdmissionCoordinator.shutdown() at the same point the pre-extraction code cancelled debounce/idle/prefetch work, before previewCoordinator.shutdown()/workScheduler.cancelAllAndWait().
    - criterion: Focused tests, swift build, the relevant fast CI lane, dg validate, and git diff --check pass.
      result: pass
      notes: All five checks pass cleanly (see checks_run). This confirms the landed slice is functionally correct, not that the ticket's scope is complete.
  checks_run:
    - "swift build: pass"
    - "swift test --filter 'PreviewAdmissionCoordinatorTests|PreviewPresentationCoordinatorTests|FilmstripNavigationTests|HistogramTests|ComparisonModeTests|PreviewDiskCacheTests': 46/46 pass"
    - "scripts/ci-tests.sh fast: pass (exit 0)"
    - "dg validate: OK (only pre-existing unrelated model-name warnings)"
    - "git diff --check: pass"
  findings:
    - "Slice C's comparison-retry cluster (comparisonPreviewScheduledRevision, comparisonPreviewRetriedRevision, comparisonPreviewRetryTask, comparisonPreviewJobID, scheduleOriginalPreview, comparisonPreviewDidFail, cancelComparisonPreview) was never moved into PreviewAdmissionCoordinator; it remains entirely on AppViewModel (lines ~332-336, ~812, ~3891-4051). This contradicts the ticket's explicit ownership contract ('State owned: ... comparison retry ...') and the Slice C execution brief."
    - docs/APP_ARCHITECTURE.md was updated to state PreviewAdmissionCoordinator 'owns ... comparison-retry admission,' which is currently inaccurate given the above.
    - PreviewAdmissionCoordinatorTests.swift implements only 1 of the 5 fake-based test cases the ticket required (job-id independence); the stale-revision/asset-id fence, idle-admission-never-publishes, comparison-retry-once-per-revision, and ROI-no-canonical-adoption cases are all missing.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-24T03:55:55.273Z
  session: 01MUEZU4FBFZYXXGTZ
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - architecture
  - maintainability
  - appviewmodel
created: 2026-09-19T16:27:24.296Z
updated: 2026-09-24T03:55:55.333Z
depends_on:
  - KRMA-466
  - KRMA-562
blockers: []
order: v
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/ViewModels/PreviewPresentationCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewCoordinator.swift
    - Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift
    - Tests/KromoraKitTests/PreviewPresentationCoordinatorTests.swift
    - Tests/KromoraKitTests/FilmstripNavigationTests.swift
    - Tests/KromoraKitTests/HistogramTests.swift
    - Tests/KromoraKitTests/DevelopInspectorTests.swift
    - Tests/KromoraKitTests/ComparisonModeTests.swift
    - Tests/KromoraKitTests/PreviewDiskCacheTests.swift
    - Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift
  docs:
    - docs/APP_ARCHITECTURE.md
    - docs/COMPARISON_MODE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-460
    - KRMA-466
    - KRMA-432
  commands:
    - swift build
    - swift test --filter 'PreviewAdmissionCoordinatorTests|PreviewPresentationCoordinatorTests|FilmstripNavigationTests|HistogramTests|ComparisonModeTests|PreviewDiskCacheTests'
    - scripts/ci-tests.sh fast
    - dg validate
    - git diff --check
---

Parent: KRMA-460

## Execution brief (reviewed 2026-09-23)

Start only after KRMA-466 is `done`. Edited-thumbnail debounce reads `isPreviewInteractionActive` and `previewDebounceTask`; moving both owners at once will tangle the fences.

KRMA-432 already moved generations, resolution planners, cache keys, and canonical cache writes into `PreviewPresentationCoordinator`. `PreviewCoordinator` is still the only type that submits `RenderRequest`s into `RenderEngine`. This ticket moves the **admission** that is still on `AppViewModel`. Do not give the new type a `PreviewSurface`, a second renderer, or the published `EditDocument`.

Create `Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift`. Leave `PreviewPresentationCoordinator` as the generation/cache owner and `PreviewCoordinator` as the render funnel. The new type calls those two; it does not absorb them.

Line numbers are from the 2026-09-23 review of the 5,561-line `AppViewModel.swift`. Search by symbol if they drift.

### Land three slices, in order, each with tests green

Do not move the whole preview MARK in one edit.

**Slice A — histogram admission.** Move only:

- fields `histogramTaskRevision`, `histogramTaskRequest`, `histogramTaskAssetID` (~589–594) and `histogramJobID` (~820)
- `updateHistogram(for:presentedImage:)` (~4997)
- `cancelHistogram(clear:pump:)` (~5078)
- `refreshHistogramGate()` (~5091)

Leave `toggleInspector()` and `keepInspectorTabValid()` on `AppViewModel`. Histogram work runs on scheduler lane `.editor`, priority `.histogram`, and tallies `engine.histogram(presentedImage:space:maxDimension:)` against the presented frame. It must not rebuild the source graph. The gate is: inspector presented, Info tab, matching source, and the source/display/asset fence inside the task. `publishPreview` (~4752) and `adoptStoredEdits` (~2205) call `updateHistogram`; those calls become forwards. `docs/COMPARISON_MODE.md` and KRMA-554: the histogram describes the displayed comparison request (`displayRequest`), not a separately derived image.

**Slice B — adjacent prefetch and idle cache-fill.** These live in the image-loading section, not the Preview MARK. Move:

- types `AdjacentPreviewCandidate`, `IdlePreviewCandidate`, `IdlePreviewWorkItem` (~785–800)
- `idlePreviewBuildJobID`, `idleBuildTask`, `idleBuildGeneration`, `idleBuildCursor`, `maxItemsPerIdleSession` (~805–809)
- `adjacentPreviewPrefetchJobID`, `prefetchDelayTask` (~818, ~825)
- `cancelIdlePreviewBuild(resetCursor:)` (~1968)
- `scheduleAdjacentPreviewPrefetch()` (~2224)
- `scheduleIdlePreviewBuild()` (~2339)
- `runIdlePreviewBuild(...)` (~2422)
- `adjacentPreviewPlan(for:nativeExtent:)` (~4053) if prefetch is the only caller

Hard invariant, already commented on `runIdlePreviewBuild`: idle fill never calls `previewSurface`, `PreviewCoordinator`, `previewState`, histogram, or selection APIs. It writes the disk cache only. `maxItemsPerIdleSession` stays 20. Idle job id `idle-preview-build` and prefetch job id `adjacent-preview-prefetch` stay distinct; neither cancellation may cancel the other. `load()` (~1987) still calls `cancelIdlePreviewBuild(resetCursor: true)` before source preparation. `NSApplication.shared.isActive` remains an idle admission guard.

**Slice C — interactive/settled submit, debounce, comparison retry.** Move:

- `previewBackingSize`, `intensityDebounceMs` (60) (~4046–4047)
- `pendingPreviewCacheLookup` (~780)
- `previewScheduledSourceRevision` (~813)
- `previewDebounceTask`, `previewDebounceGeneration` (~826–827)
- `displayRequest` (~4099)
- `schedulePreview`, `scheduleCropEntryPreview`, `scheduleCorrectivePreview` (~4134–4155)
- `makeSettledPreviewRequest`, `canonicalPreviewPlan`, `submitSettledPreview` (~4160–4297)
- `scheduleInteractivePreview` (~4305)
- `updatePreviewBackingSize` (~4343) — `PreviewView` calls this; keep an `AppViewModel` forwarder
- `scheduleSettledPreviewAfterDebounce` (~4359)
- comparison cluster in the undo section: `scheduleOriginalPreview` (~4773), `comparisonPreviewDidFail` (~4901), `cancelComparisonPreview` (~4932), plus `comparisonPreviewScheduledRevision`, `comparisonPreviewRetriedRevision`, `comparisonPreviewRetryTask`, and `comparisonPreviewJobID`

`displayRequest` is the single accessor for “pixels on screen”, including the crop-tool uncropped frame and the Space comparison baseline. Histogram and settled submit both read it. Move it with slice C, and point slice A’s histogram input at that same accessor through the destination so the two slices do not grow a second request builder.

### Stay on AppViewModel

- `load()`, `updateDocument()`, `applyHistoryDocument()`, `shutdown()`, and `publishPreview` (the method that calls `previewSurface.present`)
- `previewSurface` / `originalPreviewSurface`
- `showOriginal` and `toggleSideBySide` policy. They may call into the coordinator.
- `beginPreviewInteraction` / `endPreviewInteraction` as the public methods views call. They also open and close an undo group and, after KRMA-466, cancel or admit edited thumbnails. Move the display-revision, debounce, and `previewCoordinator.beginInteraction` / `endInteraction` half into the coordinator; the root method keeps undo and thumbnail sequencing and then calls the coordinator.
- `beginCanvasInteraction` / `endCanvasInteraction` (~4458–4467). Pinch-zoom sets `isPreviewInteractionActive` and calls `previewCoordinator.beginInteraction` **without** an undo group. Preserve that split. The comment above `beginCanvasInteraction` explains why.
- Canvas workflow forwarders (`scheduleCanvasWorkflowPreview` and siblings, ~5538). They stay one-line calls.

### Fences and shutdown

Preserve latest-wins on source revision, document identity (`displayRequest.document == request.document`), display revision, and asset id inside every cache-lookup and submit completion. A settled request with a non-nil `sourceROI` must not adopt the canonical cache raster (comment in `submitSettledPreview`). Corrective preview (`preemptsPredecessor: false`) queues behind the speculative frame instead of cancelling it.

`isPreviewInteractionActive` is read by edited thumbnails. After both extractions, one owner publishes that flag. Prefer the admission coordinator, with the thumbnail destination reading it the same way it does today.

`shutdown()` (~5395) currently bumps `previewDebounceGeneration`, cancels `comparisonPreviewRetryTask`, nils preview callbacks, then later cancels `idleBuildTask`, `prefetchDelayTask`, and `previewDebounceTask` before `previewPresentation.shutdown()` and `previewCoordinator.shutdown()`. The new `shutdown()` must run at those same points: invalidate generations first, cancel handles, then let the root await `previewCoordinator.shutdown()` and `workScheduler.cancelAllAndWait()`.

### Tests

Add `Tests/KromoraKitTests/PreviewAdmissionCoordinatorTests.swift` with fakes (no `AppViewModel`, no GPU) for:

- stale display revision / asset id drops a cache hit and a histogram result
- idle admission never calls the preview publication fake
- idle and adjacent-prefetch job ids cancel independently
- comparison retry runs once per comparison revision
- ROI requests do not adopt a canonical cache hit

Keep green, and do not rewrite them to fit a new API:

- `FilmstripNavigationTests.testAdjacentPrefetchUsesStoredEditsForNeverOpenedNeighbor`
- `FilmstripNavigationTests.testAdjacentPrefetchScaleKeyMatchesSubsequentSelectionPreview`
- `HistogramTests`
- `DevelopInspectorTests` histogram cases (`testNoHistogramIsTalliedWhileTheDevelopTabIsShowing`, `testSwitchingBackToInfoRecomputesTheHistogram`, `testRapidEditsCoalesceHistogramWorkAfterTheSettledPreview`, `testLateHistogramResultCannotReplaceANewerEdit`, `testHistogramFollowsTheDisplayedComparisonRequest`)
- `ComparisonModeTests`
- `PreviewDiskCacheTests.testSettledHitSkipsTheRendererAndStillAdmitsHistogram`
- `PreviewPresentationCoordinatorTests`
- `ThumbnailSwitchLifecycleTests` histogram/selection cases

Update the “Preview-presentation ownership” section of `docs/APP_ARCHITECTURE.md` so admission, cache, and render funnel are three named owners.

### Checks

Per slice, then once at the end:

- `swift build`
- `swift test --filter 'PreviewAdmissionCoordinatorTests|PreviewPresentationCoordinatorTests|FilmstripNavigationTests|HistogramTests|ComparisonModeTests|PreviewDiskCacheTests'`
- `scripts/ci-tests.sh fast`
- `dg validate`
- `git diff --check`

Swift 6: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.

## Objective

Move the remaining preview admission/scheduling and histogram admission state out of `AppViewModel` into `PreviewPresentationCoordinator` or a narrow sibling, without making that collaborator own `PreviewSurface` or the published document.

## Ownership contract

- State owned: interactive/settled submit admission, debounce, adjacent prefetch, idle cache-fill admission, comparison retry, and histogram admission state left after KRMA-432.
- Admitted commands: submit interactive/settled preview work, request adjacent prefetch or idle fill, retry comparison, and request histogram work.
- Published values: preview/histogram outcomes and narrow presentation status values; `AppViewModel` remains the published document owner and `PreviewCoordinator` remains the only render-admission owner.
- Revision checks: preserve latest-wins source/document/display fences, comparison generations, and separate idle-vs-prefetch job IDs.
- Task handles: bounded debounce/retry/prefetch/cache-fill tasks with cancellation on supersession, source switch, document replacement, and shutdown.
- Shutdown behavior: cancel scheduler-owned work before preview/cache collaborators are released; retain existing last-valid-frame and failure behavior.
- Resource limits: reuse the existing planners, cache I/O, scheduler lanes, and bounded queues; no second renderer, GPU owner, or unbounded background work.

## Scope and acceptance

- [ ] `RenderRequest` / `RenderEngine` funnel semantics and preview quality/resource policies are preserved.
- [ ] Histogram parity and comparison retry behavior are preserved.
- [ ] Collaborator-level fake-based admission/fence tests exist, with AppViewModel integration coverage for navigation, comparison, and histogram behavior.
- [ ] `load()`, `updateDocument()`, `applyHistoryDocument()`, and `shutdown()` sequencing remain root-owned.
- [ ] Focused tests, `swift build`, the relevant fast CI lane, `dg validate`, and `git diff --check` pass.

### Comment — cursor @ 2026-09-24T01:13:35.459Z

Triage 2026-09-23: added a three-slice execution brief (histogram, idle/prefetch, then settled/interactive/comparison). Start only after KRMA-466.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-24T03:55:55.332Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] RenderRequest / RenderEngine funnel semantics and preview quality/resource policies are preserved. (pass) — PreviewCoordinator remains the sole render-admission owner; PreviewAdmissionCoordinator.submit/scheduleInteractivePreview forward into it unchanged. Focused suite and fast CI lane pass.
- [x] Histogram parity and comparison retry behavior are preserved. (pass) — Histogram admission moved to PreviewAdmissionCoordinator.updateHistogram/cancelHistogram/refreshHistogramGate and behaves correctly (HistogramTests, DevelopInspectorTests histogram cases pass). Comparison-retry behavior still works, but the cluster was never actually moved off AppViewModel (see finding below) despite being explicitly in scope.
- [ ] Collaborator-level fake-based admission/fence tests exist, with AppViewModel integration coverage for navigation, comparison, and histogram behavior. (fail) — PreviewAdmissionCoordinatorTests.swift has only 1 of the 5 required cases (idle/adjacent-prefetch job-id independence). Missing: stale display revision/asset id drops a cache hit and histogram result; idle admission never calls the preview publication fake; comparison retry runs once per comparison revision; ROI requests do not adopt a canonical cache hit. AppViewModel integration coverage (FilmstripNavigationTests, ComparisonModeTests, ThumbnailSwitchLifecycleTests, PreviewDiskCacheTests) remains green.
- [x] load(), updateDocument(), applyHistoryDocument(), and shutdown() sequencing remain root-owned. (pass) — Verified in AppViewModel.swift; shutdown() calls previewAdmissionCoordinator.shutdown() at the same point the pre-extraction code cancelled debounce/idle/prefetch work, before previewCoordinator.shutdown()/workScheduler.cancelAllAndWait().
- [x] Focused tests, swift build, the relevant fast CI lane, dg validate, and git diff --check pass. (pass) — All five checks pass cleanly (see checks_run). This confirms the landed slice is functionally correct, not that the ticket's scope is complete.
Checks run:
- swift build: pass
- swift test --filter 'PreviewAdmissionCoordinatorTests|PreviewPresentationCoordinatorTests|FilmstripNavigationTests|HistogramTests|ComparisonModeTests|PreviewDiskCacheTests': 46/46 pass
- scripts/ci-tests.sh fast: pass (exit 0)
- dg validate: OK (only pre-existing unrelated model-name warnings)
- git diff --check: pass
Findings:
- Slice C's comparison-retry cluster (comparisonPreviewScheduledRevision, comparisonPreviewRetriedRevision, comparisonPreviewRetryTask, comparisonPreviewJobID, scheduleOriginalPreview, comparisonPreviewDidFail, cancelComparisonPreview) was never moved into PreviewAdmissionCoordinator; it remains entirely on AppViewModel (lines ~332-336, ~812, ~3891-4051). This contradicts the ticket's explicit ownership contract ('State owned: ... comparison retry ...') and the Slice C execution brief.
- docs/APP_ARCHITECTURE.md was updated to state PreviewAdmissionCoordinator 'owns ... comparison-retry admission,' which is currently inaccurate given the above.
- PreviewAdmissionCoordinatorTests.swift implements only 1 of the 5 fake-based test cases the ticket required (job-id independence); the stale-revision/asset-id fence, idle-admission-never-publishes, comparison-retry-once-per-revision, and ROI-no-canonical-adoption cases are all missing.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUEZU4FBFZYXXGTZ
Summary: Stage 3 landed histogram, idle/prefetch, and interactive/settled admission correctly (build/tests/CI all green), but the comparison-retry cluster explicitly required by Slice C and the ownership contract was never moved off AppViewModel, and docs/APP_ARCHITECTURE.md now inaccurately claims it was. 4 of 5 required PreviewAdmissionCoordinatorTests fake-based cases are also missing. Filed KRMA-562 as the child ticket to finish the extraction and add the missing tests; returning KRMA-467 to review.
