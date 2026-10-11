---
id: KRMA-863
title: "Library grid on launch: unedited photos spin and reflow from 4:3 placeholders"
type: bug
status: done
priority: high
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: On relaunch of an existing library the grid lays out at final shapes immediately, with no 4:3 to mosaic reflow for unedited photos.
      result: pass
      notes: Reviewed the index-load hydration path and passed testColdRelaunchPublishesLegacyUneditedFirstPageWithFinalRatio; the first page is published with source-header-derived ratios, and the repair pass persists legacy summaries.
    - criterion: A relaunch log shows where the remaining spinner time goes, and a follow-up fix (or a documented reason) is recorded.
      result: pass
      notes: Issue context documents the Display P3 rejection root cause, tier diagnostics, and post-fix warm relaunch capture. The remaining prefetch queue delay is recorded as non-blocking; no display-bound recapture was run.
    - criterion: Library, thumbnail and relaunch-parity tests pass.
      result: pass
      notes: "Declared test command passed: 101 tests, 0 failures."
  checks_run:
    - swift test --filter LibraryGridTests|ThumbnailTests|ObservabilityTests|RelaunchParityTests|PackageEditProjectionTests|PortableLibraryPackageTests|PortableLibrarySessionTests — passed; exit 0; 101 tests, 0 failures
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T03:03:59.204Z
  session: 01MV38LZTHX65GXJR6
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T15:52:51.054Z
updated: 2026-10-11T03:03:59.208Z
blockers: []
order: zz
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths:
      - path: .dg/issues/KRMA-863.md
        access: write
        confidence: 1
      - path: Sources/KromoraKit/Models/ImageCollection.swift
        access: write
        confidence: 1
      - path: Sources/KromoraKit/Models/Observability.swift
        access: write
        confidence: 1
      - path: Sources/KromoraKit/Models/OriginalThumbnailLoader.swift
        access: write
        confidence: 1
      - path: Sources/KromoraKit/Models/ThumbnailFrameEncoding.swift
        access: write
        confidence: 1
      - path: Tests/KromoraKitTests/LibraryGridTests.swift
        access: write
        confidence: 1
      - path: Tests/KromoraKitTests/ObservabilityTests.swift
        access: write
        confidence: 1
      - path: Tests/KromoraKitTests/ThumbnailTests.swift
        access: write
        confidence: 1
    base: dd2a443660e69232d3df16c847ebad69d2d03345
    head: d7f619a3ac3a442df55dcbe63865e589a11cc112
    captured_at: 2026-10-11T03:00:48.916Z
commits:
  - c5edcd151352d995bcc64f692941d02303217938
  - b65954f385684707f03f4643ffc1e87a09dc8d9d
  - d7f619a3ac3a442df55dcbe63865e589a11cc112
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


### Comment — claude @ 2026-10-10T15:52:58.058Z

Implemented in c5edcd15: stored-original aspect adoption, diagnostics, and test. Library, thumbnail, relaunch-parity and observability tests pass. The spinner cause is not yet known; relaunch the dev build with the thumbnail-frames log stream described in the ticket and attach the output.


### Comment — claude @ 2026-10-10T18:20:40.927Z

First relaunch capture (thumbnail-frames log): (1) ThumbnailFrameRead lines are cheap (readMs 0-4, applyMs 0-7) and all report original=true, but were visible=false prefetch reads that sat queued ~3000 ms (queueMs 2967-2991); only one visible=true read appears (queueMs 0, applyMs 204). (2) ThumbnailOriginalLoad (provider level) shows dozens of 190-2450 ms loads, completing in a serial staircase (329, 742, 1126, 1509 ms, about 0.4 s apart) with queueMs 1-6 s, i.e. cells waited and then loaded slowly one after another. Cached originals exist for all photos, so these look like source decodes or store-actor waits, but the log could not say which. Follow-up b65954f385684707f03f4643ffc1e87a09dc8d9d adds tier=memory|pack|decode, packOutcome and lookupMs/decodeMs per load. Next capture should answer whether visible cells are decoding source despite valid packed frames.


### Comment — claude @ 2026-10-10T18:28:06.690Z

ROOT CAUSE FOUND from the second capture: every ThumbnailOriginalLoad decode reports packOutcome=rejected.colorSpaceUnpresentable. All 140 stored originals in the reporter's library are tagged displayP3 (the 33 edited frames are sRGB); WorkingSpace.current is sRGB and RasterColorSpace.displayP3.isLosslesslyPresentable(in: .sRGB) is false, so FrameClassifier refused every stored original and each launch re-decoded every unedited photo from source (190-550 ms each, serialised, behind a multi-second queue), then rewrote another P3 frame that would be rejected again. That is why edited photos (sRGB frames) appear instantly and unedited ones spin. Fix in d7f619a3ac3a442df55dcbe63865e589a11cc112: ThumbnailFrameEncoder.normalizedRaster converts to the working space; OriginalThumbnailLoader shows the same normalized pixels. Regression test fails without the fix with the same reason and passes with it; 178 related tests pass. Existing P3 frames self-heal: rejected once, re-decoded, rewritten as sRGB, instant from the second launch. Still open: the 2-3 s queueMs on prefetch frame reads and the 200 ms applyMs on visible reads (suspected aspect-adoption projection invalidation); recheck after one warm relaunch.


### Comment — claude @ 2026-10-10T18:32:24.971Z

Verification capture after d7f619a3 (relaunch with frames already rewritten): zero ThumbnailOriginalLoad lines, so no source decodes at all; every cell is served from packed frames. Visible-photo ThumbnailFrameRead now queueMs 0-8, readMs 0-1, applyMs 0-3 (was applyMs about 200). Remaining: the first batch of 12 prefetch reads (visible=false, issued about 5 s before the visible reads at 12:32:01) waits queueMs 2340-3334 and shows applyMs 98-196, rising per batch. Candidate causes: scheduler lane starvation by launch work, and one projection invalidation per adopted aspect on the main actor. Not blocking; reporter says launch is much better.


### Comment — claude @ 2026-10-11T01:13:15.271Z

Handoff to verification (implementer: claude; reporter has reviewed). Commits c5edcd15, b65954f3, d7f619a3. Root cause of unedited photos spinning on launch: ImageIO returns library thumbnails in Display P3, the working space is sRGB, and a P3 raster is never lossless there, so FrameClassifier rejected all 140 stored originals (colorSpaceUnpresentable) and every launch re-decoded every unedited photo from source. Fix: ThumbnailFrameEncoder.normalizedRaster converts to the working space and OriginalThumbnailLoader shows the same pixels. Also: an unresolved cell takes its aspect ratio from the stored original frame (Item.adoptStoredOriginalAspect), removing the 4:3 placeholder reflow, and ThumbnailFrameRead/ThumbnailOriginalLoad diagnostics (category thumbnail-frames) with tier=memory|pack|decode and packOutcome. Verified on the reporter's library: after one rewrite launch no ThumbnailOriginalLoad decodes, visible reads queueMs 0-8, applyMs 0-3. Tests: LibraryGridTests aspect adoption, ThumbnailTests P3 regression (fails without the fix with the same reason), 178 related tests green. Check: existing P3 frames self-heal on first launch; sRGB conversion may clip very saturated colors slightly; prefetch reads still queued 2-4 s at launch (noted, not blocking).


### Comment — claude @ 2026-10-11T01:13:24.308Z

Commits for KRMA-863 (oldest first; review with git show <sha>):
- c5edcd151352d995bcc64f692941d02303217938 KRMA-863: lay out unresolved library cells from the stored original frame and log thumbnail load timing
- b65954f385684707f03f4643ffc1e87a09dc8d9d KRMA-863: log which tier served each original thumbnail and why a decode happened
- d7f619a3ac3a442df55dcbe63865e589a11cc112 KRMA-863: store original thumbnails in the working space so the classifier accepts them

## Counterpoint verification blocker — 2026-10-10

The first-paint aspect acceptance criterion is not demonstrated and remains unmet. `admitFrameReads`
is started from visible-grid demand, and `adoptStoredOriginalAspect` runs only later in the async
`applyStoredFrames` callback. An unedited item with no dimensions or published ratio can therefore
still enter the grid projection at the 4:3 fallback before its packed frame is read. The new unit
test invokes the adoption method directly; existing relaunch-parity coverage exercises edited
frames, so neither covers an unedited cold relaunch's initial projection. This is broader than a
localized verifier fix because the ratio must be available before projection (for example through
persisted browsing metadata or an equivalent pre-layout hydration path).

Required change: make the exact source/presented aspect available before the first library grid
projection for an existing unedited asset, without waiting for the asynchronous thumbnail read.
Keep the stored-original-aspect guardrails for assets whose metadata is missing. Add an integration
test that reopens a package containing an unedited photo with unknown dimensions and an exact stored
original frame, then asserts its first grid projection uses the stored final ratio and does not
transition through 4:3 when thumbnail or deferred metadata work completes.

Verification: run `swift test --filter 'LibraryGridTests|ThumbnailTests|ObservabilityTests|RelaunchParityTests'`
and the new cold-relaunch integration test. Confirm the existing reporter-library relaunch still
serves cached originals without `ThumbnailOriginalLoad tier=decode` and preserves the corrected
initial mosaic layout.

### Comment — claude @ 2026-10-11T02:04:44.462Z

Addressed the verification blocker in 188f7312. Root gap: package summaries never stored pixel dimensions, so every unedited photo (even newly imported) had no ratio before the async read. Fix: import now records upright dimensions and presentedAspectRatio from the staged original's header; the existing presentedAspectRatio repair (background maintenance, already gated on missing summaries) now reads the original header for legacy summaries with no source shape and publishes dimensions + ratio. The first relaunch after upgrade still relies on stored-original adoption for the one-time repair window; every later launch builds items with the final ratio in the first projection. Tests: import records the oriented (EXIF 6) shape; repair resolves a legacy unedited summary and an item built from it has hasResolvedLibraryAspect and the final ratio with no thumbnail/metadata work; PortableLibraryPackageTests updated (import now records the pre-edit ratio). Package/Portable/Library/Import/Thumbnail/Observability/RelaunchParity filters pass. Not re-captured on the reporter library (display-bound/manual). Unrelated pre-existing failure seen: LightInspectorTests.testToneCurveResetUsesAccessibleTrailingDisclosureAction (uncommitted Light inspector work in the tree).

## Counterpoint verification blocker — 2026-10-11 (second pass)

The first-paint acceptance criterion still fails for an existing legacy package on its first relaunch after this update. `startIndexLoading` publishes the reconciled index and `startupFirstPage` before calling `startPresentedAspectRatioRepair`; that repair runs asynchronously as background maintenance. Import now records dimensions for newly imported photos, and repair eventually records them for legacy photos, but neither makes the old package's missing ratio available before its first page is projected. The new repair test checks an item constructed after calling the repair API; it does not reopen a session and observe the initial page. The implementation note above confirms the first post-upgrade relaunch relies on later stored-frame adoption, which itself runs only after visible demand schedules an asynchronous frame read.

Required change: ensure a legacy unedited asset's exact source/presented aspect is available to the first grid projection on the first relaunch after upgrade, without waiting for the background summary repair or visible thumbnail read. Preserve asynchronous/background behavior where possible after the first-page geometry is correct. Add a cold-relaunch integration test that opens a legacy package whose unedited asset has no summary dimensions/aspect but has an exact stored original frame, then asserts the first published grid page uses its final ratio and no subsequent thumbnail/deferred-metadata completion transitions it through the 4:3 fallback.

Verification: run `swift test --filter 'LibraryGridTests|ThumbnailTests|ObservabilityTests|RelaunchParityTests|PackageEditProjectionTests|PortableLibraryPackageTests|PortableLibrarySessionTests'` and the cold-relaunch integration test. Confirm the reporter-library cached-frame behavior remains intact; its display-bound relaunch capture is manual and should only be repeated if available during implementation follow-up.

### Comment — claude @ 2026-10-11T03:00:45.302Z

Addressed second verification blocker in 29c609df. The index-load operation now resolves presented ratios for the first page's entries that lack one (original header + current edit revision, read-only) and publishes the projection and startup first page with them, so a legacy package's first relaunch lays out at final shapes. Hydrated ids are tracked so the background repair still writes the durable summaries (dimensions + ratio). Added testColdRelaunchPublishesLegacyUneditedFirstPageWithFinalRatio (reopens a legacy package with async index loading, asserts the first completed publish carries the final ratio, then that repair persists dimensions). Ran LibraryGridTests|ThumbnailTests|ObservabilityTests|RelaunchParityTests|PackageEditProjectionTests|PortableLibraryPackageTests|PortableLibrarySessionTests: 101 tests, 0 failures. Reporter-library display capture not repeated.

## Agent log

- 2026-10-11T01:44:17.656Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] On relaunch of an existing library the grid lays out at final shapes immediately, with no 4:3 to mosaic reflow for unedited photos. (fail) — Aspect adoption runs only after visible demand schedules an asynchronous packed-frame read; an unresolved item can enter the first projection using the 4:3 fallback. Current unit coverage invokes adoption directly and relaunch parity covers edited frames, not an unedited cold relaunch.
- [x] A relaunch log shows where the remaining spinner time goes, and a follow-up fix (or a documented reason) is recorded. (pass) — Issue context records the Display P3 rejection root cause, tier diagnostics, and post-fix relaunch capture; prefetch queue delay remains documented as non-blocking.
- [x] Library, thumbnail and relaunch-parity tests pass. (pass) — Targeted command passed: 54 tests, 0 failures.
Checks run:
- swift test --filter LibraryGridTests|ThumbnailTests|ObservabilityTests|RelaunchParityTests — passed; exit 0; 54 tests, 0 failures
Findings:
- Blocking: initial unedited grid projection can still use the 4:3 fallback before the async packed-frame read supplies aspect geometry; acceptance requires final shape immediately.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV35RPDDBKSSL09H
Summary: Blocking: initial unedited grid projection may still use the 4:3 fallback before the async packed-frame read supplies aspect geometry. Persist or hydrate the ratio before first projection and add an unedited cold-relaunch integration test.

- 2026-10-11T02:57:50.046Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] On relaunch of an existing library the grid lays out at final shapes immediately, with no 4:3 to mosaic reflow for unedited photos. (fail) — New imports persist source dimensions, but on the first relaunch of a legacy package startIndexLoading publishes the first page before startPresentedAspectRatioRepair runs. Repair is background work, while stored-frame adoption waits for visible demand and an asynchronous frame read, so an unresolved unedited asset may still enter the initial projection at the 4:3 fallback.
- [x] A relaunch log shows where the remaining spinner time goes, and a follow-up fix (or a documented reason) is recorded. (pass) — The issue records the Display P3 frame rejection root cause, diagnostics, cached-frame post-fix capture, and the remaining prefetch delay as non-blocking.
- [x] Library, thumbnail and relaunch-parity tests pass. (pass) — The expanded related suite passed: 100 tests, 0 failures. The required cold-relaunch integration test is still missing.
Checks run:
- swift test --filter LibraryGridTests|ThumbnailTests|ObservabilityTests|RelaunchParityTests|PackageEditProjectionTests|PortableLibraryPackageTests|PortableLibrarySessionTests — passed; exit 0; 100 tests, 0 failures
Findings:
- Blocking: legacy unedited assets do not have guaranteed final geometry in the first published grid page on their first relaunch after upgrade. The session publishes the page before background summary repair; current tests validate repair output after the repair call rather than a cold session reopen.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV38EWXBLASJXLOJ
Summary: Blocker: first relaunch of a legacy package can still publish unedited cells with 4:3 fallback geometry before background aspect repair or asynchronous stored-frame adoption. Add pre-first-page hydration and a cold-relaunch integration test.

- 2026-10-11T03:03:59.204Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] On relaunch of an existing library the grid lays out at final shapes immediately, with no 4:3 to mosaic reflow for unedited photos. (pass) — Reviewed the index-load hydration path and passed testColdRelaunchPublishesLegacyUneditedFirstPageWithFinalRatio; the first page is published with source-header-derived ratios, and the repair pass persists legacy summaries.
- [x] A relaunch log shows where the remaining spinner time goes, and a follow-up fix (or a documented reason) is recorded. (pass) — Issue context documents the Display P3 rejection root cause, tier diagnostics, and post-fix warm relaunch capture. The remaining prefetch queue delay is recorded as non-blocking; no display-bound recapture was run.
- [x] Library, thumbnail and relaunch-parity tests pass. (pass) — Declared test command passed: 101 tests, 0 failures.
Checks run:
- swift test --filter LibraryGridTests|ThumbnailTests|ObservabilityTests|RelaunchParityTests|PackageEditProjectionTests|PortableLibraryPackageTests|PortableLibrarySessionTests — passed; exit 0; 101 tests, 0 failures
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV38LZTHX65GXJR6
Summary: Verification passed: cold legacy first-page geometry is hydrated before publication; 101 targeted tests passed.
