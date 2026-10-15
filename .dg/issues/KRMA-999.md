---
id: KRMA-999
title: Release decoded thumbnails that are outside the visible working set
type: bug
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: After an item leaves the working set, its original, edited, and displayed pixel references are nil while identity and metadata remain.
      result: pass
      notes: Eviction clears decoded raster slots and edit-frame tags while retaining the Item, asset identity, source, and metadata. Deterministic coverage checks both thumbnail slots and stable identity.
    - criterion: The working set is the visible ids plus the existing prefetch/navigation neighborhood, and paging beyond that cap does not retain decoded images from the prior window.
      result: pass
      notes: Visible frame-read ids and prepared navigation ids are tracked; ids leaving both sets are evicted. A generated-image viewport transition test verifies that the prior viewport is cleared and the current one remains populated.
    - criterion: Releasing an already-decoded thumbnail releases it, and in-flight thumbnail/frame work is canceled.
      result: pass
      notes: releaseThumbnail now cancels the original decode and pending packed-frame read; late frame applications are rejected when the item is outside the current working set.
    - criterion: Revisiting an evicted id asks the durable thumbnail frame store again.
      result: pass
      notes: The injectable frame store readCount increases after eviction and revisit, covering the durable-frame lookup path without requiring a render.
    - criterion: Generated-image tests reproduce release of both slots and verify that later browsing does not retain prior decoded images; no resident-memory figure is asserted.
      result: pass
      notes: LibraryGridTests cover original and edited slot release, page append, viewport transition, and frame-store reread with small generated images.
    - criterion: swift build is warning-free and scripts/ci-tests.sh fast exits 0; serial runs only if the real renderer is touched.
      result: pass
      notes: Build completed without diagnostics; the fast lane passed all 1,937 required tests. The real renderer was untouched, so serial was not required.
  checks_run:
    - swift build — passed with no warnings
    - swift test --filter ImageCollection — 1 passed, 0 failures
    - swift test focused LibraryGridTests for release, revisit, and viewport transition — 3 passed, 0 failures
    - scripts/ci-tests.sh fast — exit 0; 1,937 required tests
    - git diff --check — passed
  findings:
    - "Fixed during verification: a pending persisted-frame read could finish after release and repopulate a thumbnail outside the working set."
  fixes:
    - Track the active frame-read window, evict decoded images outside it and the prepared navigation neighborhood, cancel pending frame reads on eviction, and fence late frame application against current working-set membership.
  verification_commits:
    - 4bc75f9b
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T18:36:21.328Z
  session: 01MV8FWECPELEV84A6
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - release-readiness
  - readiness-2026-10-14
  - must-fix
  - memory
  - library
created: 2026-10-14T16:08:55.212Z
updated: 2026-10-14T18:36:21.332Z
parent: KRMA-994
blockers: []
order: n
board: product
context:
  files:
    - Sources/KromoraKit/Models/ImageCollection.swift
    - Sources/KromoraKit/Models/Thumbnails.swift
  docs:
    - CLAUDE.md
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-994
    - KRMA-1016
    - KRMA-959
  commands:
    - swift test --filter ImageCollection
    - scripts/ci-tests.sh fast
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T18:24:50.206Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 4bc75f9b
---

## Objective

Scrolling the library must not retain every visited photo's decoded thumbnails. Keep identity and metadata for the whole library. Keep pixels only for the visible cells and a small navigation neighborhood.

## Context

Ownership confirmed on 2026-10-14. Resident memory of a large library was not measured. `ImageCollection.Item` (`Sources/KromoraKit/Models/ImageCollection.swift`, around line 57) strongly retains original, edited, and displayed thumbnail images. Loading a later page appends items. `releaseThumbnail(for:)` (around line 851) drops demand and cancels some unfinished work, then returns immediately when a thumbnail already exists, so loaded images stay attached.

The thumbnail provider's 32 MB cache (`Sources/KromoraKit/Models/Thumbnails.swift`, around line 39) does not bound images retained by the collection. Lazy SwiftUI rows bound views, not those pixel buffers. The review's 7.2 GiB figure is a sizing example for 1,000 distinct 1200×800 RGBA8 pairs, not a measurement.

The 16 GB scroll soak belongs to KRMA-1016, not this ticket. Durable frames in the thumbnail frame store must survive eviction so a revisit can hydrate without a new render when a frame exists.

Parent epic: KRMA-994. Review finding 4. KRMA-959 is the unchecked lock in `Thumbnails.swift`; do not take that rewrite on here.

## Reproduction

Populate an item's original and edited image slots, begin demand-driven browsing, release that id, and inspect both slots. Then append another page. Today both images stay attached and the item count grows.

## Acceptance criteria

- [ ] After an item leaves the working set, its original, edited, and displayed pixel references are nil. Metadata, ids, and durable frame identity remain.
- [ ] The working set is the visible ids plus the existing prefetch neighborhood (`prepareAdjacentThumbnails` or its successor). Paging through more items than that cap does not leave decoded images on the discarded items.
- [ ] `releaseThumbnail` (or its replacement) actually releases a thumbnail that has already been decoded. Cancelling an in-flight job still happens.
- [ ] A revisit of an evicted id hydrates from a durable thumbnail frame when one exists, and does not require a full edited re-render for that case. Add a test if the frame store is already injectable; otherwise a focused test that the collection asks for the frame again is enough.
- [ ] A deterministic test with generated images reproduces the probe: both slots nil after release, and a later page does not keep the earlier page's decoded images. Do not allocate multi-gigabyte fixtures and do not assert a resident-memory number in CI.
- [ ] `swift build` is warning-free. `scripts/ci-tests.sh fast` exits 0. Run serial only if you touch the real renderer.

## Constraints

- Re-read the cited lines before editing. Line numbers drift.
- Swift 6 language mode stays on. No `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, or `#available` branches. No new dependencies.
- Do not run `scripts/run-kromora-capture.sh`. Display-bound numbers already live in `docs/TESTING.md`.
- Preserve unrelated working-tree changes. Do not revert other tickets' edits.
- One issue at a time. Commit subject starts with this issue id. Hand off at `review`; do not mark `done`.


### Comment — claude @ 2026-10-14T18:24:49.679Z

Implemented in 24e32d78. releaseThumbnail now cancels the job and, for ids outside the prepared neighborhood, calls Item.releaseDecodedThumbnails() (nils displayed/original/edited pixels, revision and stored-frame tag; resets thumbnailState) and clears completedFrameReadIDs so a revisit re-reads the durable packed frame (edited coordinator then sees a nil revision and reuses the exact stored frame, no render). Added two LibraryGridTests (both slots nil after release and a later page keeps none; revisit rehydrates). swift build clean; scripts/ci-tests.sh fast exits 0. Caveat: grid and filmstrip both call release, so a cell leaving one surface evicts pixels even if the other still shows it; they are not shown together today.

## Agent log

- 2026-10-14T18:36:21.328Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] After an item leaves the working set, its original, edited, and displayed pixel references are nil while identity and metadata remain. (pass) — Eviction clears decoded raster slots and edit-frame tags while retaining the Item, asset identity, source, and metadata. Deterministic coverage checks both thumbnail slots and stable identity.
- [x] The working set is the visible ids plus the existing prefetch/navigation neighborhood, and paging beyond that cap does not retain decoded images from the prior window. (pass) — Visible frame-read ids and prepared navigation ids are tracked; ids leaving both sets are evicted. A generated-image viewport transition test verifies that the prior viewport is cleared and the current one remains populated.
- [x] Releasing an already-decoded thumbnail releases it, and in-flight thumbnail/frame work is canceled. (pass) — releaseThumbnail now cancels the original decode and pending packed-frame read; late frame applications are rejected when the item is outside the current working set.
- [x] Revisiting an evicted id asks the durable thumbnail frame store again. (pass) — The injectable frame store readCount increases after eviction and revisit, covering the durable-frame lookup path without requiring a render.
- [x] Generated-image tests reproduce release of both slots and verify that later browsing does not retain prior decoded images; no resident-memory figure is asserted. (pass) — LibraryGridTests cover original and edited slot release, page append, viewport transition, and frame-store reread with small generated images.
- [x] swift build is warning-free and scripts/ci-tests.sh fast exits 0; serial runs only if the real renderer is touched. (pass) — Build completed without diagnostics; the fast lane passed all 1,937 required tests. The real renderer was untouched, so serial was not required.
Checks run:
- swift build — passed with no warnings
- swift test --filter ImageCollection — 1 passed, 0 failures
- swift test focused LibraryGridTests for release, revisit, and viewport transition — 3 passed, 0 failures
- scripts/ci-tests.sh fast — exit 0; 1,937 required tests
- git diff --check — passed
Findings:
- Fixed during verification: a pending persisted-frame read could finish after release and repopulate a thumbnail outside the working set.
Fixes:
- Track the active frame-read window, evict decoded images outside it and the prepared navigation neighborhood, cancel pending frame reads on eviction, and fence late frame application against current working-set membership.
Verification commits:
- 4bc75f9b
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV8FWECPELEV84A6
Summary: Counterpoint verification passed; fixed late frame-read retention and verified release, revisit, and window eviction.
