---
id: KRMA-765
title: "Relaunch Library: stored original and edited thumbnails hydrate exact with no render and no swap"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "RelaunchParityTests session 2: zero renders/prepareSource/original decodes"
      result: pass
      notes: Covered by updated RelaunchParityTests; fast lane green
    - criterion: Single raster assignment through relaunch, stable aspect ratio
      result: pass
      notes: onThumbnailAssignment seam and confirmStoredEditedThumbnail; tests pass
    - criterion: Stale case one render, one replacement
      result: pass
    - criterion: Missing frame case original in final geometry then edited once
      result: pass
    - criterion: Look unchanged rescan causes zero renders
      result: pass
      notes: Existing applyLookLibraryDelta tests green
    - criterion: LaunchHints and viewport parity
      result: pass
      notes: Parameterized parity test added
    - criterion: Frame-read lane obeys maxConcurrentReads
      result: pass
      notes: LaunchHintsTests green
    - criterion: fast and serial lanes pass
      result: pass
      notes: fast 1488 tests, serial 466 tests, 0 failures
  checks_run:
    - scripts/ci-tests.sh fast (1488 tests)
    - scripts/ci-tests.sh serial (466 tests, 0 failures)
    - manual diff review of ce6ab4d
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-03T02:36:52.520Z
  session: 01MURRYZFLF41832LS
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - cache
  - library
created: 2026-10-02T13:44:22.489Z
updated: 2026-10-03T02:36:52.522Z
parent: KRMA-764
depends_on:
  - KRMA-763
blockers: []
order: a0
board: product
---

## Objective

On relaunch, every visible Library cell and filmstrip cell paints its **last presented appearance** (edited pixels, final aspect ratio) straight from the persisted frame, performs **zero** render or source-decode work for photos whose inputs have not changed, and never swaps original-to-edited or changes size after first paint.

## Background

Depends on KRMA-763 (real identity at launch) and KRMA-764 (no placeholder frames). Current flow: `ImageCollection.admitFrameReads` / `applyStoredFrames` read frames for the visible window plus one prefetch page, `LibraryBrowsingCoordinator` hydrates hinted frames from `LaunchHints` before the real viewport is known, `OriginalThumbnailLoader` goes memory -> packed frame -> decode, and `EditedThumbnailCoordinator.request` reopens the edit, resolves the Look, reads the packed edited frame and classifies it with `FrameClassifier`.

Gaps to close (verify each in code before changing it):

1. `applyStoredFrames` presents a stored **edited** frame after classifying it only against `FrameCurrentInputs(source:)`, i.e. as provisional. That is right for first paint, but the later `EditedThumbnailCoordinator` pass must then see the frame as already **exact** (using the saved revision's content-addressed Look, `loaded.lookSignature`, and the edit hash) and publish without rendering. Confirm that after KRMA-763 that second pass issues no `prepareSource` / `makeThumbnailCGImage` call for an unchanged photo; fix the ordering if it does.
2. `applyStoredFrames` adopts stored geometry (`adoptStoredGeometry`, bumping `cropGeneration` and invalidating the collection projection) when the package summary has no `presentedAspectRatio`. That is a visible reflow after first layout. After KRMA-767 lands this path should be unreachable for current packages; here, make sure a summary **with** a published ratio never reflows and that the fallback reflow is counted by a counter so KRMA-770 can assert zero.
3. The original thumbnail must be shown inside the final geometry (`.fit` within the reserved ratio) until edited pixels arrive, and edited pixels must replace it only once (`.fill`); a stored edited frame that is exact must be the **first** raster the cell ever shows, not the second.
4. `LaunchHints` hydration (`LibraryBrowsingCoordinator.prepareLaunchHints`, `applyLaunchFrames`) must produce the same result as the viewport path for the same photo: same classification, same single paint.

## Work

Fix whichever of the four gaps the code actually has; for each, add the test below first, watch it fail, then fix. Keep `ImageCollection`'s published-state churn minimal (it is `@Observable`; avoid invalidating the whole collection projection for a single cell).

## Acceptance criteria

- [ ] In `RelaunchParityTests` (KRMA-762) session 2, for every unchanged photo in the visible window: zero edited-thumbnail render requests, zero source `prepareSource` calls from the thumbnail path, and zero original-thumbnail decodes (the original comes from the packed frame; assert `OriginalThumbnailLoader` never reaches its decode tier). The matching `XCTExpectFailure` wrappers are removed.
- [ ] A cell test records every raster assignment for an edited photo through relaunch: exactly one assignment (the stored edited frame), no original-then-edited sequence, and the cell's `libraryAspectRatio` is identical at first layout and at the end.
- [ ] Stale case: when the edit changed between sessions, the stored frame is shown immediately (inert), exactly one render runs, and exactly one replacement occurs (crossfade only if `FrameRefinementPolicy` says so); no intermediate original frame is shown.
- [ ] Missing frame case: the original is shown in the final geometry, then edited pixels arrive once; the cell size never changes.
- [ ] Look unchanged-rescan case: after relaunch, `LUTLibrary.onScanned` with identical Looks causes zero thumbnail renders (existing `applyLookLibraryDelta` tests stay green).
- [ ] LaunchHints path and viewport path produce identical results for the same photos (one parameterized test).
- [ ] The frame-read lane still obeys `ThumbnailFrameReadPolicy.maxConcurrentReads` and does not delay index publication (existing `LaunchHintsTests` stay green).
- [ ] `fast` and `serial` lanes pass.

## Rules for an unattended run (read first)

- **Do not run the display-bound captures** (`scripts/run-kromora-capture.sh`, the last-known-frame benchmark). Everything here is verified by deterministic tests (`scripts/ci-tests.sh fast|serial`) that need no window and no unlocked display (see CLAUDE.md, "Display-bound benchmarks").
- **Do not open child tickets.** If a criterion cannot be met, record exactly what you measured and tried in a comment on this ticket, commit what is safe, and hand off to review.
- Keep the change to what this ticket lists. Swift 6 mode with zero escape hatches (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`). macOS 26 / Apple Silicon only; no `#available` branches and no third-party dependencies.
- Cache files are disposable presentation caches, never package truth. A cache failure must degrade to a miss, never to an error, a wrong-photo frame, or a blocked open.
- Commit with a subject that starts `KRMA-<this id>:`. Do not push. Do not stash, reset, or revert anyone else's uncommitted changes in the tree.


### Comment — codex @ 2026-10-03T02:30:29.627Z

Implemented persisted-frame-first relaunch hydration for the visible grid and filmstrip. Exact edited frames now confirm without a duplicate raster assignment; stale frames remain first paint through one replacement; missing edits use the packed original in reserved geometry. Added relaunch decode/render/reflow/raster assertions and LaunchHints/viewport parity coverage. Verification passed: scripts/ci-tests.sh fast (1,488 tests) and scripts/ci-tests.sh serial (466 tests). Commit: ce6ab4d.

## Agent log

- 2026-10-03T02:36:52.520Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] RelaunchParityTests session 2: zero renders/prepareSource/original decodes (pass) — Covered by updated RelaunchParityTests; fast lane green
- [x] Single raster assignment through relaunch, stable aspect ratio (pass) — onThumbnailAssignment seam and confirmStoredEditedThumbnail; tests pass
- [x] Stale case one render, one replacement (pass)
- [x] Missing frame case original in final geometry then edited once (pass)
- [x] Look unchanged rescan causes zero renders (pass) — Existing applyLookLibraryDelta tests green
- [x] LaunchHints and viewport parity (pass) — Parameterized parity test added
- [x] Frame-read lane obeys maxConcurrentReads (pass) — LaunchHintsTests green
- [x] fast and serial lanes pass (pass) — fast 1488 tests, serial 466 tests, 0 failures
Checks run:
- scripts/ci-tests.sh fast (1488 tests)
- scripts/ci-tests.sh serial (466 tests, 0 failures)
- manual diff review of ce6ab4d
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MURRYZFLF41832LS
Summary: Verification passed: persisted-frame-first relaunch hydration reviewed; fast and serial lanes green.
