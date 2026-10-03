---
id: KRMA-767
title: Backfill presentedAspectRatio at package open so old packages never reflow cells
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Legacy fixture repaired in background; summaries and item ratios match sidecar, no main-actor record reads
      result: pass
      notes: Covered by PackageEditProjectionTests/PortableLibrarySessionTests/LibraryBrowsingCoordinatorTests added in c690f62; lanes green.
    - criterion: "Second launch: zero repair work (gate) and cellGeometryReflow == 0"
      result: pass
      notes: Gate computed from in-memory index; reflow counted only after first grid presentation.
    - criterion: Cancel midway leaves valid package; resume completes
      result: pass
      notes: Per-shard transactions; tests cover cancellation/resume.
    - criterion: User edit during repair wins
      result: pass
      notes: Writer mutation lock plus fresh membership re-read and only-if-nil merge.
    - criterion: Repair delta publishes only ratio, no thumbnail reads/renders
      result: pass
      notes: presentedAspectRatioUpdates delta path patches geometry only; counting-provider test present.
    - criterion: fast and serial lanes pass; STORAGE_POLICY.md updated
      result: pass
      notes: fast 1510 tests, serial 469 tests, 0 failures; docs updated.
  checks_run:
    - scripts/ci-tests.sh fast (1510 tests, pass)
    - scripts/ci-tests.sh serial (469 tests, 0 failures)
  findings:
    - "Non-blocking: the writer mutation lock is held across a whole shard's sidecar reads, so an edit commit on the main actor could briefly block behind a background repair shard; shards are small and repair is one-time per package, so no ticket opened."
  fixes: []
  verification_commits:
    - c690f62
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-03T07:13:03.045Z
  session: 01MUS1U0EJ76BK7IEN
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - library
  - package
created: 2026-10-02T13:44:23.636Z
updated: 2026-10-03T07:13:03.047Z
blockers: []
order: a0
board: product
commits:
  - c690f62
---

## Objective

Make sure every library cell knows its **final aspect ratio before any pixel arrives**, for packages created before `presentedAspectRatio` existed, so cells never change size after first layout.

## Background

`PortablePackageAssetSummary.presentedAspectRatio` (`Sources/KromoraKit/Models/PortableLibraryPackage.swift`) is the ratio a cell reserves: source aspect with the current edit's crop and rotation applied. It is written in the same transaction as each edit commit. For a package written before the field existed it is nil and decodes as "same as source". The explicit repair, `PortablePackageEditSidecar.repairPresentedAspectRatios(lease:now:isCancelled:)`, **is never called from production code** (only its definition and tests reference it). Consequence: for any cropped or rotated photo in an older package, the cell starts at the source ratio and reflows when edit state arrives, through `ImageCollection.Item.adoptStoredGeometry` (which bumps `cropGeneration` and invalidates the whole collection projection) or `setPresentedCrop`. That is a visible jump on every launch until the photo is next edited. The owner's package has 256 photos.

## Work

1. After the library index is published and the package lease is available, run `repairPresentedAspectRatios` once per package **in the background**: off the main actor, lowest scheduler priority, cooperative cancellation through its `isCancelled` parameter, yielding to any user-visible work. Gate it so it runs at most once per package revision (a cheap check: skip when no live summary lacks the field, computed from the already-loaded index, not by reading records).
2. Publish an index delta for the repaired assets so cells adopt the ratio through the normal projection path. The delta must change **only the ratio**; it must not re-trigger thumbnail reads or renders for those cells.
3. Make the repair batched so one slow shard does not hold the lease for long (it already commits per shard; keep that) and make sure it does not conflict with a user edit commit (reuse the lease/transaction rules the existing repair already follows; add a test that an edit commit during the repair wins and is not overwritten).
4. Count `cellGeometryReflow` in `Observability` wherever an item's `libraryAspectRatio` changes after its first layout (`adoptStoredGeometry`, `setPresentedCrop`). KRMA-770 asserts it is zero for steady-state scenarios.

## Acceptance criteria

- [ ] Fixture package with several cropped/rotated edited photos whose summaries lack `presentedAspectRatio`: after the background repair, every summary and every `ImageCollection.Item.libraryAspectRatio` equals the ratio computed from the edit sidecar, with no asset record reads on the main actor.
- [ ] Second launch of the same fixture: zero repair work (the gate), and `cellGeometryReflow == 0` while the grid loads and edited thumbnails hydrate.
- [ ] Cancelling the repair midway leaves a valid package; resuming completes it; the test proves the package validates after each cancellation point (existing fault-injection helpers).
- [ ] A user edit committed while the repair is running wins; the final summary matches the user's edit.
- [ ] Repair publishes only ratio changes: a test with a counting thumbnail provider proves no thumbnail read/render is triggered by the delta.
- [ ] `fast` and `serial` lanes pass; `docs/STORAGE_POLICY.md` notes the repair runs automatically and is idempotent.

## Rules for an unattended run (read first)

- **Do not run the display-bound captures** (`scripts/run-kromora-capture.sh`, the last-known-frame benchmark). Everything here is verified by deterministic tests (`scripts/ci-tests.sh fast|serial`) that need no window and no unlocked display (see CLAUDE.md, "Display-bound benchmarks").
- **Do not open child tickets.** If a criterion cannot be met, record exactly what you measured and tried in a comment on this ticket, commit what is safe, and hand off to review.
- Keep the change to what this ticket lists. Swift 6 mode with zero escape hatches (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`). macOS 26 / Apple Silicon only; no `#available` branches and no third-party dependencies.
- Cache files are disposable presentation caches, never package truth. A cache failure must degrade to a miss, never to an error, a wrong-photo frame, or a blocked open.
- Commit with a subject that starts `KRMA-<this id>:`. Do not push. Do not stash, reset, or revert anyone else's uncommitted changes in the tree.


### Comment — codex @ 2026-10-03T07:06:41.579Z

Implemented automatic shard-batched presentedAspectRatio repair after index publication, ratio-only grid deltas, cellGeometryReflow observability, and storage policy documentation. Added legacy package, cancellation/resume, edit-race, and thumbnail-isolation coverage. Verification: ci-tests fast (1,510 tests) and serial (469 tests) passed. Commit: c690f62.

## Agent log

- 2026-10-03T07:13:03.045Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Legacy fixture repaired in background; summaries and item ratios match sidecar, no main-actor record reads (pass) — Covered by PackageEditProjectionTests/PortableLibrarySessionTests/LibraryBrowsingCoordinatorTests added in c690f62; lanes green.
- [x] Second launch: zero repair work (gate) and cellGeometryReflow == 0 (pass) — Gate computed from in-memory index; reflow counted only after first grid presentation.
- [x] Cancel midway leaves valid package; resume completes (pass) — Per-shard transactions; tests cover cancellation/resume.
- [x] User edit during repair wins (pass) — Writer mutation lock plus fresh membership re-read and only-if-nil merge.
- [x] Repair delta publishes only ratio, no thumbnail reads/renders (pass) — presentedAspectRatioUpdates delta path patches geometry only; counting-provider test present.
- [x] fast and serial lanes pass; STORAGE_POLICY.md updated (pass) — fast 1510 tests, serial 469 tests, 0 failures; docs updated.
Checks run:
- scripts/ci-tests.sh fast (1510 tests, pass)
- scripts/ci-tests.sh serial (469 tests, 0 failures)
Findings:
- Non-blocking: the writer mutation lock is held across a whole shard's sidecar reads, so an edit commit on the main actor could briefly block behind a background repair shard; shards are small and repair is one-time per package, so no ticket opened.
Fixes:
- None
Verification commits:
- c690f62
Actor: claude
Resolved model: sonnet
Pickup session: 01MUS1U0EJ76BK7IEN
Summary: Verified: fast and serial lanes pass; criteria met.
