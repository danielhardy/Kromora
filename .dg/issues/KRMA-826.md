---
id: KRMA-826
title: Filmstrip thumbnails stuck on spinners after Photos import
type: bug
status: done
priority: high
agent: claude
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Previously visible/requested demand survives loadPortableWindow/appendPortableWindow in demand-driven mode.
      result: pass
      notes: Reload restores surviving explicit and visible IDs; append retains existing Items and demand. Released, removed, and speculative-only IDs are excluded.
    - criterion: Optionally reuse existing Item thumbnails for IDs surviving reload.
      result: not_applicable
      notes: Reload deliberately creates new Items and restores demand; optional raster reuse is unnecessary to resolve the defect.
    - criterion: Deterministic injected-provider regression reloads existing IDs plus new assets and reaches ready without another appearance/request.
      result: pass
      notes: Three LibraryGridTests cover visible-window reload, cached/prepared filmstrip requests, and append/released/removed/speculative demand. Reload cases include three new assets.
    - criterion: Manually import 3+ Photos items into an existing ~15-item library in Edit; visible thumbnails settle without scrolling/relaunch.
      result: pass
      notes: "Human acceptance gate: manual-check blocker evt_muy8z4vk_v5r1y6 was resolved by web at 2026-10-07T17:59:11.765Z, immediately before verification resume. This pickup relies on that human resolution; no independent UI rerun or detailed manual result was recorded in the compiled context."
    - criterion: Run scripts/ci-tests.sh fast and serial; do not run display-bound capture harness.
      result: pass
      notes: "Current HEAD 5a019f47: fast 1,540 tests, serial 491 tests, zero failures, both exit 0. Display-bound capture harness was not run."
  checks_run:
    - Independent correctness, maintainability, security, and performance review of 70497cf8 and 8ca79cfa and current reload/append, demand, cancellation, packed-read, and filmstrip paths.
    - "scripts/ci-tests.sh fast: exit 0; 1,540 tests. Log /tmp/krma-826-verification-fast.log."
    - "scripts/ci-tests.sh serial: exit 0; 491 tests, zero failures. Log /tmp/krma-826-verification-serial.log."
    - "git diff --check: exit 0."
    - Inspected final output and exit status of all command sessions; diagnostic sample exited 0; no background tasks remain.
  findings:
    - No unresolved correctness, maintainability, security, or performance findings. Earlier cached-cell and prepared-overlap demand-loss findings were fixed in 8ca79cfa.
  fixes:
    - Existing verification commit 8ca79cfa records explicit demand before cached/pending-read early returns, restores actual demanded IDs including prepared overlaps, and fences deferred packed-read requests against generation changes and released demand. No additional edits in this pickup.
  verification_commits:
    - 8ca79cfa3d2dbb1493d0e6bfa5c110926115d078
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-07T18:07:00.167Z
  session: 01MUYEWC1AKKBX2K4M
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - filmstrip
  - thumbnails
  - photos-import
created: 2026-10-07T14:03:28.551Z
updated: 2026-10-07T18:07:00.170Z
blockers:
  - id: evt_muy8z4vk_v5r1y6
    type: human
    reason: Required manual Photos-import acceptance check remains unverified; UI automation cannot attach to the isolated test editor (cgWindowNotFound), although automated lanes and packaged app verification pass after verification commit 8ca79cfa.
    action: Build/run current main (including 8ca79cfa), enter Edit in a library with ~15+ existing photos, import 3+ new photos from Photos, and confirm visible filmstrip thumbnails all settle without scrolling or relaunching. Record the result, then run dg issue resume KRMA-826 verification for report/completion.
    created_at: 2026-10-07T15:13:26.384Z
    resolved_at: 2026-10-07T17:59:11.765Z
    resolved_by: web
order: a0
board: product
blocked_reason: Required manual Photos-import acceptance check remains unverified; UI automation cannot attach to the isolated test editor (cgWindowNotFound), although automated lanes and packaged app verification pass after verification commit 8ca79cfa.
blocked_action: Build/run current main (including 8ca79cfa), enter Edit in a library with ~15+ existing photos, import 3+ new photos from Photos, and confirm visible filmstrip thumbnails all settle without scrolling or relaunching. Record the result, then run dg issue resume KRMA-826 verification for report/completion.
blocked_from_status: verification
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/Models/ImageCollection.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Views/FilmstripView.swift
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-07T14:51:56.153Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 8ca79cfa3d2dbb1493d0e6bfa5c110926115d078
---

## Objective
After a Photos import, every filmstrip cell must resolve to a thumbnail. No cell may stay on its loading spinner until the user scrolls or relaunches.

## Observed
Right after importing 3 photos from Photos (status bar: "Photos import complete — 3 imported, 0 duplicates, 0 skipped, 0 failed"), the Edit-view filmstrip showed 19 items. About 10 of them were permanent placeholder spinners, including cells in the middle of the visible strip. Others loaded normally (the cells that were already cached or scrolled into view).

## Investigation (code reading only; not reproduced in a debugger)
Likely cause: a demand-driven thumbnail reset that visible filmstrip cells never re-request.

1. `PhotosImportBatchCoordinator` finishes the batch via `refreshPhotosImportCollection()` -> `reloadPortableCollection()` -> `ImageCollection.loadPortableWindow(...)` (`Sources/KromoraKit/Models/ImageCollection.swift`, ~line 503).
2. `loadPortableWindow` replaces `items` with brand-new `Item`s (thumbnails nil, state `.notRequested`) and calls `cancelThumbnailWork()`. That clears `thumbnailDemandIDs`, `thumbnailDemandPriorities`, `preparedThumbnailIDs`, `visibleEditedThumbnailIDs`, and pending frame reads. It leaves `isThumbnailDemandDriven == true`.
3. It then calls `enqueueThumbnails()`, which in demand-driven mode only calls `fillThumbnailQueue()`. `fillThumbnailQueue()` admits only ids that are in `thumbnailDemandIDs` or `preparedThumbnailIDs`, and both were just emptied, so nothing is queued apart from whatever `openPortableAsset` prepares around the selected index (+/-2).
4. The filmstrip (`Sources/KromoraKit/Views/FilmstripView.swift`, ~lines 70-81) requests thumbnails only from each cell `.onAppear`. The cells keep the same `.id(item.id)` across the reload, so SwiftUI does not re-fire `onAppear`, and nobody calls `requestThumbnail(for:)` again. Cells outside the +/-2 window stay on `ProgressView` indefinitely.

## Acceptance criteria
- After `loadPortableWindow`/`appendPortableWindow` while demand-driven, thumbnails that were previously visible/requested are re-requested (e.g. re-publish visible demand after a reload, or preserve demand across `cancelThumbnailWork` for ids that still exist).
- Optionally reuse existing `Item` thumbnails for ids that survive the reload instead of discarding them.
- Add a deterministic test using the injected original-thumbnail provider (see KRMA-751): load a window, request thumbnails for visible ids, call `loadPortableWindow` with the same ids plus new ones, and assert all demanded ids reach `.ready` without a new `onAppear`/request.
- Verify manually: import 3+ photos from Photos into a library that already has ~15 items while in Edit view; no spinners remain.
- Run `scripts/ci-tests.sh fast` and `serial`. Do not run the display-bound capture harness.

## Notes
`LightInspectorView.swift` has uncommitted local edits; do not revert. If the root cause turns out to differ from the above, record what was actually found on the ticket.


### Comment — claude @ 2026-10-07T14:51:59.430Z

Commit 70497cf8. Root cause matched the ticket: loadPortableWindow's cancelThumbnailWork emptied demand and cells with unchanged ids never re-fired onAppear. loadPortableWindow now re-requests prior visible/explicit demand for surviving ids, skipping adjacent-prepared ids; re-requesting those broke RelaunchParityTests. New test testPortableWindowReloadReRequestsPreviouslyVisibleThumbnails fails without the fix. ci-tests fast and serial pass. Manual Photos-import check not done (non-interactive). appendPortableWindow unchanged: its new cells get onAppear.


### Comment — codex @ 2026-10-07T14:58:27.373Z

Independent verification found two uncovered demand-loss cases in 70497cf8: a filmstrip cell can explicitly request an ID also in preparedThumbnailIDs, and an already-painted cached cell returns before requestOriginalThumbnail records its demand. The new per-cell regression failed on the handoff tree (exit 1) and passes after localized fixes that record demand at requestThumbnail entry and snapshot actual demand IDs rather than excluding all prepared IDs. Deferred packed-read requests now also check generation and released demand. Tests use the injected thumbnail provider, include three new assets, and cover append retention plus released/removed/speculative demand. Fast lane passed (1,539 tests); serial and manual checks in progress.


### Comment — codex @ 2026-10-07T15:13:26.168Z

Verification fixes committed as 8ca79cfa (8ca79cfa changes only ImageCollection.swift and LibraryGridTests.swift). Checks: scripts/ci-tests.sh fast exited 0 with 1,539 tests; scripts/ci-tests.sh serial exited 0 with 490 tests and zero failures; scripts/app-store-build.sh exited 0 and passed bundle/resource/signature/icon verification; git diff --check passed. The targeted grid/filmstrip reload tests passed after the fix; the filmstrip regression failed before it with the expected reload spinner timeout. No remaining code-review findings or child implementation blockers. Manual acceptance is unverified: the current production app can be inspected, but the isolated 15-photo host repeatedly returns cgWindowNotFound from UI automation despite reporting a visible window. All spawned command sessions completed and were inspected; every temporary UI host was stopped and confirmed absent. Request human manual import of 3+ Photos items in Edit with ~15+ existing items, then confirm all visible filmstrip cells settle without scrolling/relaunch. Resume verification afterward; a passing canonical structured report and completion are still pending this required result.

## Agent log

- 2026-10-07T18:07:00.167Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Previously visible/requested demand survives loadPortableWindow/appendPortableWindow in demand-driven mode. (pass) — Reload restores surviving explicit and visible IDs; append retains existing Items and demand. Released, removed, and speculative-only IDs are excluded.
- [ ] Optionally reuse existing Item thumbnails for IDs surviving reload. (not_applicable) — Reload deliberately creates new Items and restores demand; optional raster reuse is unnecessary to resolve the defect.
- [x] Deterministic injected-provider regression reloads existing IDs plus new assets and reaches ready without another appearance/request. (pass) — Three LibraryGridTests cover visible-window reload, cached/prepared filmstrip requests, and append/released/removed/speculative demand. Reload cases include three new assets.
- [x] Manually import 3+ Photos items into an existing ~15-item library in Edit; visible thumbnails settle without scrolling/relaunch. (pass) — Human acceptance gate: manual-check blocker evt_muy8z4vk_v5r1y6 was resolved by web at 2026-10-07T17:59:11.765Z, immediately before verification resume. This pickup relies on that human resolution; no independent UI rerun or detailed manual result was recorded in the compiled context.
- [x] Run scripts/ci-tests.sh fast and serial; do not run display-bound capture harness. (pass) — Current HEAD 5a019f47: fast 1,540 tests, serial 491 tests, zero failures, both exit 0. Display-bound capture harness was not run.
Checks run:
- Independent correctness, maintainability, security, and performance review of 70497cf8 and 8ca79cfa and current reload/append, demand, cancellation, packed-read, and filmstrip paths.
- scripts/ci-tests.sh fast: exit 0; 1,540 tests. Log /tmp/krma-826-verification-fast.log.
- scripts/ci-tests.sh serial: exit 0; 491 tests, zero failures. Log /tmp/krma-826-verification-serial.log.
- git diff --check: exit 0.
- Inspected final output and exit status of all command sessions; diagnostic sample exited 0; no background tasks remain.
Findings:
- No unresolved correctness, maintainability, security, or performance findings. Earlier cached-cell and prepared-overlap demand-loss findings were fixed in 8ca79cfa.
Fixes:
- Existing verification commit 8ca79cfa records explicit demand before cached/pending-read early returns, restores actual demanded IDs including prepared overlaps, and fences deferred packed-read requests against generation changes and released demand. No additional edits in this pickup.
Verification commits:
- 8ca79cfa3d2dbb1493d0e6bfa5c110926115d078
Actor: codex
Resolved model: unknown
Pickup session: 01MUYEWC1AKKBX2K4M
Summary: Verification passed after human manual-gate resolution. Current fast/serial lanes passed (1,540/491 tests); no remaining findings or child blockers; prior verification fixes recorded in 8ca79cfa.
