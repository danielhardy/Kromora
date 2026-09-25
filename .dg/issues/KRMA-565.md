---
id: KRMA-565
title: Extract preview publication from AppViewModel
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: publishPreview, presentSettledRaster, and didPresentVisibleFrame move to PreviewPublicationCoordinator, which holds no AppViewModel/PreviewSurface reference.
      result: pass
      notes: PreviewPublicationCoordinator.swift owns publish/presentSettledRaster/didPresentVisibleFrame; it only holds a weak PreviewPublicationDestination and no surface or CIContext. AppViewModel conforms via a value/hook-only extension.
    - criterion: lastPresentedVisibleRequest, lastPresentedVisibleImage, lastPublishedVisibleRequest move to the coordinator; resetForSource() replaces the nil sites in load() and clearActiveSourceAfterLibraryDeletion; install()'s no-frame-published check uses a coordinator accessor with the condition unchanged.
      result: pass
      notes: Fields are private(set) on the coordinator. load() and the deletion-clear path call resetForSource(). install() now reads !previewPublicationCoordinator.hasPublishedFrame, logically identical to the prior lastPublishedVisibleRequest == nil check.
    - criterion: pendingDevelopChange moves to the coordinator as noteDevelopChange(); the three document-commit assignment sites forward to it.
      result: pass
      notes: All three prior assignment sites (undo/update paths) now call previewPublicationCoordinator.noteDevelopChange(...); OR-into-existing semantics preserved.
    - criterion: didPresentVisibleFrame preserves its 7-step order (fence check; ready/status/Auto; store frame; comparison schedule-or-cancel then clear flag; histogram if resolved; scheduleIdlePreviewBuild; canonical cache write only for .preview + nil sourceROI).
      result: pass
      notes: "Order matches exactly in the new implementation, including scheduleOriginalPreview(allowBeforePresentationConfirmation: false) matching the prior call's default parameter value."
    - criterion: "publishPreview keeps the latest-wins guard and settled/interactive branching, including the no-image settled failure path and the side-by-side scheduleOriginalPreview(allowBeforePresentationConfirmation: true) call."
      result: pass
      notes: Guard and branching reproduced in PreviewPublicationCoordinator.publish(_:); confirmed line-by-line against the pre-extraction AppViewModel.publishPreview.
    - criterion: load, updateDocument, applyHistoryDocument, shutdown, PreviewSurface storage, showOriginal/toggleSideBySide, and the previewCoordinator.onPublication = nil shutdown ordering stay on AppViewModel.
      result: pass
      notes: Confirmed unchanged in AppViewModel.swift; only the onPublication closure body now forwards into the coordinator.
    - criterion: PreviewPublicationCoordinatorTests covers stale fence, interactive-no-histogram/idle, settled-complete admits histogram/idle/cache, settled-ROI skips cache, one-shot develop-change comparison schedule, and resetForSource.
      result: pass
      notes: All 6 required cases present in Tests/KromoraKitTests/PreviewPublicationCoordinatorTests.swift and pass.
    - criterion: docs/APP_ARCHITECTURE.md names publication, admission, and render submission as three separate owners.
      result: pass
      notes: Ownership table and prose both updated to list PreviewPublicationCoordinator alongside PreviewAdmissionCoordinator and PreviewCoordinator.
    - criterion: "Swift 6 mode: no @unchecked Sendable / nonisolated(unsafe) / @preconcurrency; CIImage crosses the boundary only as a value the destination presents; no CIContext stored."
      result: pass
      notes: PreviewPublicationCoordinator stores only RenderRequest/CIImage values (no CIContext) and is @MainActor; no escape hatches introduced.
    - criterion: Focused tests, swift build, the fast CI lane, dg validate, and git diff --check pass.
      result: pass
      notes: See checks_run. The 2 focused-filter failures are testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument and testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto in PreviewCutoverTests, both failing on a missing temp-package asset.json (EditDocumentStore.swift:289). Reproduced independently on the pre-extraction parent commit (2789196) in an isolated worktree with the identical failure, confirming this is a pre-existing package-fixture issue unrelated to this ticket's change. scripts/ci-tests.sh fast (which does not use this narrower filter) passed all 1211/1211.
  checks_run:
    - "swift build: pass"
    - "swift test --filter 'PreviewPublicationCoordinatorTests|PreviewAdmissionCoordinatorTests|PreviewCutoverTests|PreviewDiskCacheTests|ComparisonModeTests|FilmstripNavigationTests': 58 executed, 1 skipped (no local RAW fixture), 2 pre-existing unrelated failures (PreviewCutoverTests package asset.json, reproduced on parent commit 2789196 in an isolated worktree)"
    - "scripts/ci-tests.sh fast: pass (exit 0, 1211/1211)"
    - "dg validate: OK (only pre-existing unrelated model-name/context-completeness warnings)"
    - "git diff --check: pass (exit 0)"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T05:47:29.554Z
  session: 01MUGJAETBADIQYC8A
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - architecture
  - maintainability
  - appviewmodel
created: 2026-09-24T15:18:53.177Z
updated: 2026-09-25T05:47:29.556Z
depends_on:
  - KRMA-467
blockers: []
order: a0
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


### Comment — codex @ 2026-09-25T05:42:05.892Z

Implemented and committed as a84a901 (Extract preview publication coordinator). PreviewPublicationCoordinator now owns publication fences, presented-frame state, drawable confirmation, comparison-change tracking, histogram/idle admission hooks, and canonical cache writes; AppViewModel retains the surfaces and published UI state. Added six coordinator tests and updated preview ownership docs. Verification: swift build passed; PreviewPublicationCoordinatorTests passed (6/6); scripts/ci-tests.sh fast completed all 1,211 required-fast tests with no failure diagnostics; dg validate and git diff --check passed. The exact focused filter ran 58 tests with 1 skip and 3 failures: testEachKnobVisiblyChangesThePreview and the Space comparison now pass in isolated reruns, while testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument still fails because its temporary package asset.json is missing; the parallel filter also reports the same missing asset.json in testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto. Handing off for review with this package fixture issue noted.

## Agent log

- 2026-09-25T05:47:29.554Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] publishPreview, presentSettledRaster, and didPresentVisibleFrame move to PreviewPublicationCoordinator, which holds no AppViewModel/PreviewSurface reference. (pass) — PreviewPublicationCoordinator.swift owns publish/presentSettledRaster/didPresentVisibleFrame; it only holds a weak PreviewPublicationDestination and no surface or CIContext. AppViewModel conforms via a value/hook-only extension.
- [x] lastPresentedVisibleRequest, lastPresentedVisibleImage, lastPublishedVisibleRequest move to the coordinator; resetForSource() replaces the nil sites in load() and clearActiveSourceAfterLibraryDeletion; install()'s no-frame-published check uses a coordinator accessor with the condition unchanged. (pass) — Fields are private(set) on the coordinator. load() and the deletion-clear path call resetForSource(). install() now reads !previewPublicationCoordinator.hasPublishedFrame, logically identical to the prior lastPublishedVisibleRequest == nil check.
- [x] pendingDevelopChange moves to the coordinator as noteDevelopChange(); the three document-commit assignment sites forward to it. (pass) — All three prior assignment sites (undo/update paths) now call previewPublicationCoordinator.noteDevelopChange(...); OR-into-existing semantics preserved.
- [x] didPresentVisibleFrame preserves its 7-step order (fence check; ready/status/Auto; store frame; comparison schedule-or-cancel then clear flag; histogram if resolved; scheduleIdlePreviewBuild; canonical cache write only for .preview + nil sourceROI). (pass) — Order matches exactly in the new implementation, including scheduleOriginalPreview(allowBeforePresentationConfirmation: false) matching the prior call's default parameter value.
- [x] publishPreview keeps the latest-wins guard and settled/interactive branching, including the no-image settled failure path and the side-by-side scheduleOriginalPreview(allowBeforePresentationConfirmation: true) call. (pass) — Guard and branching reproduced in PreviewPublicationCoordinator.publish(_:); confirmed line-by-line against the pre-extraction AppViewModel.publishPreview.
- [x] load, updateDocument, applyHistoryDocument, shutdown, PreviewSurface storage, showOriginal/toggleSideBySide, and the previewCoordinator.onPublication = nil shutdown ordering stay on AppViewModel. (pass) — Confirmed unchanged in AppViewModel.swift; only the onPublication closure body now forwards into the coordinator.
- [x] PreviewPublicationCoordinatorTests covers stale fence, interactive-no-histogram/idle, settled-complete admits histogram/idle/cache, settled-ROI skips cache, one-shot develop-change comparison schedule, and resetForSource. (pass) — All 6 required cases present in Tests/KromoraKitTests/PreviewPublicationCoordinatorTests.swift and pass.
- [x] docs/APP_ARCHITECTURE.md names publication, admission, and render submission as three separate owners. (pass) — Ownership table and prose both updated to list PreviewPublicationCoordinator alongside PreviewAdmissionCoordinator and PreviewCoordinator.
- [x] Swift 6 mode: no @unchecked Sendable / nonisolated(unsafe) / @preconcurrency; CIImage crosses the boundary only as a value the destination presents; no CIContext stored. (pass) — PreviewPublicationCoordinator stores only RenderRequest/CIImage values (no CIContext) and is @MainActor; no escape hatches introduced.
- [x] Focused tests, swift build, the fast CI lane, dg validate, and git diff --check pass. (pass) — See checks_run. The 2 focused-filter failures are testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument and testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto in PreviewCutoverTests, both failing on a missing temp-package asset.json (EditDocumentStore.swift:289). Reproduced independently on the pre-extraction parent commit (2789196) in an isolated worktree with the identical failure, confirming this is a pre-existing package-fixture issue unrelated to this ticket's change. scripts/ci-tests.sh fast (which does not use this narrower filter) passed all 1211/1211.
Checks run:
- swift build: pass
- swift test --filter 'PreviewPublicationCoordinatorTests|PreviewAdmissionCoordinatorTests|PreviewCutoverTests|PreviewDiskCacheTests|ComparisonModeTests|FilmstripNavigationTests': 58 executed, 1 skipped (no local RAW fixture), 2 pre-existing unrelated failures (PreviewCutoverTests package asset.json, reproduced on parent commit 2789196 in an isolated worktree)
- scripts/ci-tests.sh fast: pass (exit 0, 1211/1211)
- dg validate: OK (only pre-existing unrelated model-name/context-completeness warnings)
- git diff --check: pass (exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGJAETBADIQYC8A
Summary: Verified PreviewPublicationCoordinator extraction: publication funnel, presented-frame fields, and pendingDevelopChange fully moved off AppViewModel per spec; all 6 required coordinator tests present; docs updated; build/tests/CI/validate/diff-check all pass (2 pre-existing unrelated PreviewCutoverTests failures reproduced on the parent commit).
