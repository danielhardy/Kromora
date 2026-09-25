---
id: KRMA-565
title: Extract preview publication from AppViewModel
type: task
status: backlog
priority: medium
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - architecture
  - maintainability
  - appviewmodel
created: 2026-09-24T15:18:53.177Z
updated: 2026-09-24T15:19:43.804Z
depends_on:
  - KRMA-467
blockers: []
order: u
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewPresentationCoordinator.swift
    - Tests/KromoraKitTests/PreviewAdmissionCoordinatorTests.swift
    - Tests/KromoraKitTests/PreviewCutoverTests.swift
    - Tests/KromoraKitTests/PreviewDiskCacheTests.swift
    - Tests/KromoraKitTests/ComparisonModeTests.swift
    - Tests/KromoraKitTests/FilmstripNavigationTests.swift
  docs:
    - docs/APP_ARCHITECTURE.md
    - docs/COMPARISON_MODE.md
  issues:
    - KRMA-460
    - KRMA-467
    - KRMA-564
  commands:
    - swift build
    - swift test --filter 'PreviewPublicationCoordinatorTests|PreviewAdmissionCoordinatorTests|PreviewCutoverTests|PreviewDiskCacheTests|ComparisonModeTests|FilmstripNavigationTests'
    - scripts/ci-tests.sh fast
    - dg validate
    - git diff --check
---

Parent: KRMA-460. Start only after KRMA-467 is `done`. KRMA-564 may land first; this ticket does not depend on it. Read `PreviewAdmissionCoordinator` as it exists after KRMA-467 rather than re-deriving admission.

## Objective

Move the settled/interactive preview publication funnel out of `AppViewModel` into a `PreviewPublicationCoordinator`. `PreviewAdmissionCoordinator` keeps scheduling. `PreviewCoordinator` keeps render submission. `PreviewSurface` stays owned by the root and is reached only through a destination method.

`AppViewModel.swift` is 4,560 lines. The publication cluster is about lines 3711–3872 (`publishPreview`, `presentSettledRaster`, `didPresentVisibleFrame`). Search by symbol if the numbers drift.

## Pattern

Follow `PreviewAdmissionDestination`: a `@MainActor` protocol of values and hooks, a coordinator that holds no `AppViewModel` and no `PreviewSurface`. `init` already assigns `previewCoordinator.onPublication` (about line 1163). Keep that assignment on the root and forward the publication into the coordinator.

The coordinator creates no scheduler jobs and no tasks. Histogram, idle cache-fill, and comparison retry stay on `PreviewAdmissionCoordinator`. This ticket calls those existing methods; it does not move them again.

## Move these methods

- `publishPreview(_:)` (~3711)
- `presentSettledRaster(...)` (~3791)
- `didPresentVisibleFrame(...)` (~3829)

Fields whose writes live in that cluster. Search every use before moving, including `load` and `clearActiveSourceAfterLibraryDeletion`, which currently nil them:

- `lastPresentedVisibleRequest`
- `lastPresentedVisibleImage`
- `lastPublishedVisibleRequest`

Expose `resetForSource()` and call it from the existing nil sites (`load` around line 2005, and any deletion/source-clear path that nils the same fields). `install` reads `lastPublishedVisibleRequest == nil` as "no frame has been published yet" (about line 2076). Replace that read with a coordinator accessor. Do not change the condition.

`pendingDevelopChange` is set from the document-commit path (search the three assignments around lines 3334, 3633, and 3702) and consumed inside `didPresentVisibleFrame`. Move the flag onto the coordinator. Replace those assignments with `noteDevelopChange()` so undo/update still arms one comparison refresh for the next presented frame.

`previewState`, `statusMessage`, and Auto readiness stay published by `AppViewModel`. The destination sets them. `previewSurface.present` and `originalPreviewSurface` stay behind destination methods such as `presentAdjustedFrame` and the existing original-preview hooks. The coordinator must not hold a surface.

`didPresentVisibleFrame` keeps this order:

1. Drop the frame unless asset, source revision, display revision, source, and `displayRequest.document` still match.
2. Set preview ready, replace the "Loading …" status for a RAW source, and publish Auto `.ready` when Auto is idle.
3. Store the presented request and image.
4. If side-by-side is visible or `pendingDevelopChange` was set, call `scheduleOriginalPreview`. Otherwise cancel the comparison preview. Clear the develop-change flag.
5. If stored edits for this source revision are resolved, call `updateHistogram`.
6. Call `scheduleIdlePreviewBuild`.
7. Write the canonical cache only for a `.preview` frame whose `sourceROI` is nil.

`publishPreview` keeps the latest-wins guard on asset, source revision, display revision, and `publication.request.source == imageSource`. Settled frames go through `presentSettledRaster`. Interactive GPU and raster frames call the surface directly and do not start histogram or idle work. A settled publication with no image sets preview failed, Auto unavailable, and the existing "Could not render" status. A settled publication that does present, while side-by-side is visible, calls `scheduleOriginalPreview(allowBeforePresentationConfirmation: true)`.

## Stay on AppViewModel

- `load`, `updateDocument`, `applyHistoryDocument`, `shutdown`
- `PreviewSurface` / `originalPreviewSurface` storage
- `showOriginal` and `toggleSideBySide`
- `previewCoordinator.onPublication = nil` inside `shutdown`, still before collaborator teardown
- Admission methods that are already one-line forwards to `PreviewAdmissionCoordinator` (`schedulePreview`, `scheduleIdlePreviewBuild`, `updateHistogram`, `scheduleOriginalPreview`)

## Tests and docs

Add `Tests/KromoraKitTests/PreviewPublicationCoordinatorTests.swift` with fakes. Cover:

- a stale asset or display revision does not present
- an interactive frame presents and does not call histogram or idle admission
- a settled complete frame presents, admits histogram when stored edits are resolved, admits idle build, and writes the canonical cache
- a settled ROI frame does not write the canonical cache
- `noteDevelopChange` causes one comparison schedule on the next presented frame and then clears
- `resetForSource` makes the "no frame published yet" accessor true

Keep green:

- `PreviewAdmissionCoordinatorTests`
- `PreviewPresentationCoordinatorTests`
- `PreviewCutoverTests`
- `PreviewDiskCacheTests`
- `FilmstripNavigationTests`
- `ComparisonModeTests`
- `ThumbnailSwitchLifecycleTests`

Update the preview section of `docs/APP_ARCHITECTURE.md` so publication, admission, and render submission are three named owners. `PreviewSurface` remains root-owned.

## Checks

- `swift build`
- `swift test --filter 'PreviewPublicationCoordinatorTests|PreviewAdmissionCoordinatorTests|PreviewCutoverTests|PreviewDiskCacheTests|ComparisonModeTests|FilmstripNavigationTests'`
- `scripts/ci-tests.sh fast`
- `dg validate`
- `git diff --check`

Swift 6: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`. `CIImage` crosses this boundary only as a value the destination presents. Do not store a `CIContext`.

## Out of scope

Library browsing (KRMA-564). Changing render quality, cache keys, or comparison policy. Moving `PreviewAdmissionCoordinator` into this type.
