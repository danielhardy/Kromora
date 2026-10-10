---
id: KRMA-863
title: "Library grid on launch: unedited photos spin and reflow from 4:3 placeholders"
type: bug
status: backlog
priority: high
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T15:52:51.054Z
updated: 2026-10-10T15:52:51.423Z
blockers: []
order: zzzz
board: product
---

## Objective

On launch, some Library grid photos appear instantly at the right shape while others show a spinner in a 4:3 placeholder cell, then the whole grid reflows into the justified mosaic after a while. None of the photos are new. The reporter's hunch is that the instant ones are edited and the slow ones are not.

## Findings (read-only investigation, 2026-10-10)

- Not a missing cache: `Derived/Thumbnails` of the reporter's library holds an `-o1200` original thumbnail for all 140 photos, every one valid (pixel epoch 35 = current, `originalThumbnail480`, 1200x800, edit hash `original`, written 09:21 that morning) plus 31 `-e1200` edited ones, and legacy size-less `o`/`e` keys (48/21) still in the index. 34 of 140 photos have edits; the 23 launch-hint photos are mostly unedited (6 edited, 17 unedited), so launch hints do not explain instant vs slow.
- `Assets/*/asset.json` stores no pixel dimensions, so an unedited photo has no resolved aspect (`ImageCollection.Item.hasResolvedLibraryAspect` is false) and uses the 4:3 placeholder until deferred metadata arrives (`applyMetadata` then `invalidateCollectionProjection`). Edited photos already have a presented aspect ratio, which matches the "scaled correctly" ones.
- Each stored thumbnail carries `PresentedGeometry.orientedAspectRatio`. `applyStoredFrames` adopted geometry only from the edited frame, and `adoptStoredGeometry` also requires known dimensions, so a persisted original's ratio was ignored.
- The ledger summaries (`FrameLookupSummary`) log immediately at collection reload, before any read completes, so they always read `count=0` and cannot explain the spinners.
- Why unedited cells spin even though their frames are cached is not yet known.

## Work done in this ticket

1. `ImageCollection.Item.adoptStoredOriginalAspect(_:)` plus a call from the original-frame branch of `applyStoredFrames` (exact frames only): an unresolved cell takes the stored oriented ratio, so it lays out correctly at first paint and no longer reflows on metadata arrival. It never overrides dimensions, a published ratio, live document geometry, or a non-finite ratio.
2. Timing diagnostics, mirrored to the regular log (category `thumbnail-frames`, subsystem `com.kromora.app`) and as signposts: `ThumbnailFrameRead` (visible, queueMs, readMs, applyMs, whether an original and an edited frame were found) and `ThumbnailOriginalLoad` (queueMs, loadMs, loaded).
3. Test: `LibraryGridTests.testStoredOriginalGeometryResolvesAnUnresolvedCellWithoutOverridingKnownShapes`; ObservabilityTests vocabulary updated.

## Remaining work and how to use the diagnostics

Relaunch the dev build with `log stream --predicate 'subsystem == "com.kromora.app" AND category == "thumbnail-frames"'`. Large `queueMs` on `ThumbnailFrameRead` means read queueing (scheduler/lane limits); large `readMs` means pack I/O or raster decode; `ThumbnailOriginalLoad` lines with big `loadMs` mean cells are falling back to decoding the source instead of using the cached original. Fix the cause the log shows. Also consider persisting pixel dimensions with the asset record or index so the placeholder never appears, and logging the lookup summaries after reads complete.

## Acceptance criteria

- On relaunch of an existing library the grid lays out at final shapes immediately, with no 4:3 to mosaic reflow for unedited photos.
- A relaunch log shows where the remaining spinner time goes, and a follow-up fix (or a documented reason) is recorded.
- Library, thumbnail and relaunch-parity tests pass.
