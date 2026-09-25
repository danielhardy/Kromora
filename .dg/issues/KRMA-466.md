---
id: KRMA-466
title: "Stage 2: Extract edited-thumbnail workflow ownership from AppViewModel"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Current thumbnail demand behavior for collection, filmstrip, and grid is preserved.
      result: pass
      notes: All call sites (init onThumbnailDemand, collection selection, paste, LUT scan callbacks, source replacement, adoptStoredEdits, Look/LUT application, preview settle/interaction end, undo/history apply, shutdown) remain one-line forwards to EditedThumbnailCoordinator; ThumbnailSwitchLifecycleTests (16/16) and ThumbnailTests (9/10, 1 pre-existing unrelated failure) confirm behavior.
    - criterion: Latest-wins behavior and crop-aware cache identity are preserved.
      result: pass
      notes: isCurrentEditedThumbnailRequest fences on generation, collection item presence, source cacheIdentity, and active source/document revision or per-asset document revision, matching the pre-extraction contract verbatim; setPresentedCrop still runs before render.
    - criterion: Collaborator tests with fakes cover debounce, cancellation, stale completions, and cache identity; integration coverage remains for navigation and edit adoption.
      result: pass
      notes: "EditedThumbnailCoordinatorTests (5/5): debounce coalescing, shutdown drops late result, source-identity change rejects late result, revision string composition, identity-document nil publish without rendering. Fakes only, no AppViewModel construction. ThumbnailSwitchLifecycleTests retained for integration coverage."
    - criterion: No second document store, generic event bus, root back-reference, or Swift 6 escape hatch is introduced.
      result: pass
      notes: Coordinator holds only a weak EditedThumbnailDestination reference plus value/Sendable collaborators (ImageWorkScheduler, EditedThumbnailRendering, EditDocumentStore). No @unchecked Sendable/nonisolated(unsafe)/@preconcurrency; PackageSettingsTests-style constraints unaffected. AppViewModel remains sole document/collection owner.
    - criterion: Focused tests, swift build, the relevant fast CI lane, dg validate, and git diff --check pass.
      result: pass
      notes: "swift build: pass. Focused filter: 30/31 pass; ThumbnailTests.testImportingFromDataAlsoProducesThumbnails fails identically on parent commit faab249 (verified in an isolated worktree) — pre-existing, unrelated to this change. scripts/ci-tests.sh fast: exit 0, no failures. dg validate: OK (only pre-existing unrelated model-name warnings). git diff --check: pass (no changes needed)."
  checks_run:
    - "swift build: pass"
    - "swift test --filter 'EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests|ThumbnailTests': 30/31 pass; sole failure (testImportingFromDataAlsoProducesThumbnails) reproduced on parent commit faab249 in an isolated worktree, confirming it predates this change"
    - "scripts/ci-tests.sh fast: pass (exit 0)"
    - "dg validate: OK"
    - "git diff --check: pass"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-24T03:34:23.105Z
  session: 01MUEZ2SZDTNVSMJI1
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - architecture
  - maintainability
  - appviewmodel
created: 2026-09-19T16:27:23.427Z
updated: 2026-09-24T03:34:23.107Z
depends_on:
  - KRMA-465
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift
    - Sources/KromoraKit/Models/PhotoAnalysis/AutoWorkflowCoordinator.swift
    - Sources/KromoraKit/Models/Thumbnails.swift
    - Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift
    - Tests/KromoraKitTests/ThumbnailTests.swift
    - Tests/KromoraKitTests/MaskingWorkflowCoordinatorTests.swift
    - Tests/KromoraKitTests/AutoWorkflowCoordinatorTests.swift
  docs:
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-460
    - KRMA-528
    - KRMA-529
  commands:
    - swift build
    - swift test --filter 'EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests|ThumbnailTests'
    - scripts/ci-tests.sh fast
    - dg validate
    - git diff --check
---

Parent: KRMA-460

## Execution brief (reviewed 2026-09-23)

KRMA-465 is already satisfied by KRMA-528. Do not re-extract Auto. Implement only edited-thumbnail ownership.

`AppViewModel.swift` is 5,561 lines. Line numbers below are from this review; if they drift, search for the symbol names.

### Pattern to copy

Follow `MaskingWorkflowCoordinator` / `MaskingWorkflowDestination` (KRMA-529): a `@MainActor` collaborator, a narrow destination protocol back into `AppViewModel`, and fake-only tests that do not construct `AppViewModel`. `AutoWorkflowCoordinator` is the other precedent for invocation fences and cancellation. Name the new type `EditedThumbnailCoordinator`.

The destination may expose the values the moved methods already read: collection item lookup, `editorDocument` session/revision, active asset id, source/document revision, `isShuttingDown`, preview-interaction and preview-debounce flags, `resolvedLUT`, `editStore.load`, and `collection` thumbnail publication (`invalidateEditedThumbnail`, `applyEditedThumbnail`, `setPresentedCrop`). It must not be a stored `AppViewModel` reference, a second `EditDocument` store, or an event bus.

### State and methods to move

Owned state, currently under MARK “Owned state”:

- `editedThumbnailGenerations`
- `editedThumbnailDebounceTasks`
- `pendingEditedThumbnailAssetID`
- `editedThumbnailJobPrefix` (`"edited-thumbnail-"`)

Methods. The MARK “Edit-aware thumbnails” block is about lines 3251–3503. One helper lives outside that MARK, in image loading:

- `requestEditedThumbnail(for:priority:force:)` (~3257)
- `isCurrentEditedThumbnailRequest(...)` (~3414)
- `editedThumbnailRevision(document:lut:)` (~3454)
- `scheduleEditedThumbnailAfterSettle(for:priority:)` (~3461)
- `cancelEditedThumbnailDebounce(for:)` (~3486)
- `refreshMaterializedEditedThumbnails()` (~3495)
- `invalidateEditedThumbnailWork(for:)` (~1955)

Move these verbatim, including the comments. Behavior changes are out of scope.

### Behavior the move must preserve

- Scheduler lane is `.thumbnail`. Job id is `editedThumbnailJobPrefix + assetID.raw`. A demand for a job already queued updates priority unless `force` is true, in which case the job is cancelled and replaced.
- While `isPreviewInteractionActive` or `previewDebounceTask != nil`, an active-asset demand is stored in `pendingEditedThumbnailAssetID` and is not enqueued. Non-active demand returns without queueing during that interval.
- Debounce sleep is 500 milliseconds, then one `force: true` request. Superseding the task cancels the previous sleep.
- `isCurrentEditedThumbnailRequest` is the late-result fence: generation, item still present, source `cacheIdentity`, and either the active source/document revision (active asset) or `editorDocument.revision(for:)` (any other asset).
- An identity in-memory document publishes a nil thumbnail plus a revision string. It does not render.
- Before render, `collection.setPresentedCrop(document.crop, for:)` runs. `RenderRequest` uses `quality: .thumbnail`, `output: .raster`, and `Thumbnails.defaultMaxPixelSize` on both edges. `engine.prepareSource` is the extent fallback. `engine.makeThumbnailCGImage` is the only render call. Do not submit a full-resolution preview.
- Revision string is `document.editHash + ":" + (lut?.cacheFingerprint ?? "unresolved")`.

### Call sites that stay on AppViewModel and become one-line forwards

- `collection.onThumbnailDemand` in `init` (~1037)
- `refreshMaterializedEditedThumbnails()` from the LUT scan callbacks in `wireCoordinators` (~1277 and ~1287)
- `invalidateEditedThumbnailWork` from source replacement (~2017)
- `scheduleEditedThumbnailAfterSettle` from `adoptStoredEdits` (~2208), Look selection, LUT application, the end of `scheduleSettledPreviewAfterDebounce` (~4376), `endPreviewInteraction` (~4404), and undo/history apply (~4589)
- `requestEditedThumbnail` from collection selection (~3233) and paste (~3592)
- `beginPreviewInteraction` (~4385) still cancels the active thumbnail debounce and job before starting a preview gesture
- `shutdown()` (~5446–5460) currently snapshots `editedThumbnailDebounceTasks`, cancels them, and clears `pendingEditedThumbnailAssetID`. After the move, `EditedThumbnailCoordinator.shutdown()` owns that, and `AppViewModel.shutdown()` calls it beside the other collaborator shutdowns. Keep the existing order: cancel generations before awaiting render work, and await the scheduler barrier before `persistence.discard()`.

`beginPreviewInteraction` also opens an undo group. Leave that sequencing on the root. KRMA-467 owns preview debounce itself; until that lands, the thumbnail coordinator reads the preview-busy flags through the destination.

### Tests and docs

Add `Tests/KromoraKitTests/EditedThumbnailCoordinatorTests.swift`. Fakes only. Cover:

- debounce coalesces a burst to one trailing request
- cancellation / shutdown drops the late result
- a stale generation or source identity does not publish
- the revision string includes edit hash and LUT fingerprint
- an identity document publishes nil without calling the renderer

Keep these existing suites green:

- `ThumbnailSwitchLifecycleTests` (edited-thumbnail, crop-aware, debounce, interaction-skip, and delayed-completion cases)
- `ThumbnailTests`

Add an “Edited-thumbnail ownership” section to `docs/APP_ARCHITECTURE.md` in the same shape as “Masking-workflow ownership”, and add a row to the boundaries table.

### Checks

- `swift build`
- `swift test --filter 'EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests|ThumbnailTests'`
- `scripts/ci-tests.sh fast`
- `dg validate`
- `git diff --check`

If a focused test fails, run it on the parent commit before deciding it is caused by this change. Do not fix unrelated suites in this ticket.

### Out of scope

Preview admission, idle cache-fill, histogram, and comparison retry (KRMA-467). Auto (KRMA-528). Masking (KRMA-529). Canvas (KRMA-552). Package import (KRMA-551). Thumbnail pixel size, crop math, and Library mosaic layout (KRMA-461, already done).

Swift 6: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`. Task closures are `@Sendable`. `CIImage` stays inside the render engine.

## Objective

Create an `EditedThumbnailCoordinator` that owns edited-thumbnail scheduling state, while `AppViewModel` keeps demand hooks and the published collection projection.

## Ownership contract

- State owned: per-asset generations, debounce tasks, job IDs, and cache-identity hashing needed to identify the latest edited thumbnail request.
- Admitted commands: request, debounce, cancel, and resolve an edited thumbnail for a specific asset/document snapshot; demand hooks remain in the root.
- Published values: thumbnail results and narrow status values crossing as `Sendable` values; no collaborator-owned published active document or collection store.
- Revision checks: asset/source identity, document revision, cache identity, and generation/job ID must fence late completions.
- Task handles: bounded per-asset debounce/work handles using existing `ImageWorkScheduler` lanes and cancellation IDs; superseded work is cancelled/dropped.
- Shutdown behavior: cancel all pending thumbnail work and release scheduler/cache references during shutdown and source teardown.
- Resource limits: reuse existing scheduler lanes and cache limits; no unbounded per-asset task retention or full-resolution render fan-out.

## Scope and acceptance

- [ ] Current thumbnail demand behavior for collection, filmstrip, and grid is preserved.
- [ ] Latest-wins behavior and crop-aware cache identity are preserved.
- [ ] Collaborator tests with fakes cover debounce, cancellation, stale completions, and cache identity; integration coverage remains for navigation and edit adoption.
- [ ] No second document store, generic event bus, root back-reference, or Swift 6 escape hatch is introduced.
- [ ] Focused tests, `swift build`, the relevant fast CI lane, `dg validate`, and `git diff --check` pass.

### Comment — cursor @ 2026-09-24T01:13:35.243Z

Triage 2026-09-23: added an execution brief with the current symbols, fences, call sites, tests, and the MaskingWorkflowCoordinator pattern. KRMA-465 no longer blocks this once it is done.

### Comment — codex @ 2026-09-24T03:28:36.071Z

Implemented in 60172fd (Extract edited thumbnail coordinator). Edited-thumbnail scheduling state and methods now live in EditedThumbnailCoordinator behind a narrow destination/rendering seam; AppViewModel keeps thin forwards and sole document/collection ownership. Added fake-only coordinator coverage and architecture ownership documentation. Verification: swift build passed; EditedThumbnailCoordinatorTests (5/5) and ThumbnailSwitchLifecycleTests (16/16) passed; fast CI passed; dg validate and git diff --check passed. The focused aggregate command exits 1 only because ThumbnailTests.testImportingFromDataAlsoProducesThumbnails fails identically on parent 15528d1 (nil import URL).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-24T03:34:23.105Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Current thumbnail demand behavior for collection, filmstrip, and grid is preserved. (pass) — All call sites (init onThumbnailDemand, collection selection, paste, LUT scan callbacks, source replacement, adoptStoredEdits, Look/LUT application, preview settle/interaction end, undo/history apply, shutdown) remain one-line forwards to EditedThumbnailCoordinator; ThumbnailSwitchLifecycleTests (16/16) and ThumbnailTests (9/10, 1 pre-existing unrelated failure) confirm behavior.
- [x] Latest-wins behavior and crop-aware cache identity are preserved. (pass) — isCurrentEditedThumbnailRequest fences on generation, collection item presence, source cacheIdentity, and active source/document revision or per-asset document revision, matching the pre-extraction contract verbatim; setPresentedCrop still runs before render.
- [x] Collaborator tests with fakes cover debounce, cancellation, stale completions, and cache identity; integration coverage remains for navigation and edit adoption. (pass) — EditedThumbnailCoordinatorTests (5/5): debounce coalescing, shutdown drops late result, source-identity change rejects late result, revision string composition, identity-document nil publish without rendering. Fakes only, no AppViewModel construction. ThumbnailSwitchLifecycleTests retained for integration coverage.
- [x] No second document store, generic event bus, root back-reference, or Swift 6 escape hatch is introduced. (pass) — Coordinator holds only a weak EditedThumbnailDestination reference plus value/Sendable collaborators (ImageWorkScheduler, EditedThumbnailRendering, EditDocumentStore). No @unchecked Sendable/nonisolated(unsafe)/@preconcurrency; PackageSettingsTests-style constraints unaffected. AppViewModel remains sole document/collection owner.
- [x] Focused tests, swift build, the relevant fast CI lane, dg validate, and git diff --check pass. (pass) — swift build: pass. Focused filter: 30/31 pass; ThumbnailTests.testImportingFromDataAlsoProducesThumbnails fails identically on parent commit faab249 (verified in an isolated worktree) — pre-existing, unrelated to this change. scripts/ci-tests.sh fast: exit 0, no failures. dg validate: OK (only pre-existing unrelated model-name warnings). git diff --check: pass (no changes needed).
Checks run:
- swift build: pass
- swift test --filter 'EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests|ThumbnailTests': 30/31 pass; sole failure (testImportingFromDataAlsoProducesThumbnails) reproduced on parent commit faab249 in an isolated worktree, confirming it predates this change
- scripts/ci-tests.sh fast: pass (exit 0)
- dg validate: OK
- git diff --check: pass
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUEZ2SZDTNVSMJI1
