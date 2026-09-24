---
id: KRMA-467
title: "Stage 3: Move remaining preview and histogram scheduling ownership"
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - architecture
  - maintainability
  - appviewmodel
created: 2026-09-19T16:27:24.296Z
updated: 2026-09-24T01:18:17.490Z
depends_on:
  - KRMA-466
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
