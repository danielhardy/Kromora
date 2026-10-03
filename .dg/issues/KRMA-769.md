---
id: KRMA-769
title: Pre-warm previews and thumbnails for photos never opened, while the app is idle in Library or Edit
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Counting fake engine: builds missing frames in distance order, second pass builds nothing"
      result: pass
      notes: IdleFrameWarmerCoordinatorTests pass
    - criterion: User-visible request cancels/pauses warmer; late result not published
      result: pass
      notes: generation fence checked after every await in warm()
    - criterion: Low Power, thermal, inactive suspend via seam
      result: pass
      notes: IdleFrameWarmerConditions.permitsWork checked in canContinue
    - criterion: No frame for unresolved Look without saved reference or non-canonical request
      result: pass
      notes: mayRenderEditedPixels/permitsExactReuse guards
    - criterion: Relaunch parity with zero preview and edited-thumbnail renders
      result: pass
      notes: RelaunchParityTests pass (10)
    - criterion: Never evicts pinned frames; stops at cap low-water mark
      result: pass
      notes: pinned assets set; capacityReached outcome
    - criterion: Idle-build tests migrated; docs updated; fast/serial lanes pass
      result: pass
      notes: Docs updated in APP_ARCHITECTURE and TESTING; implementer reported fast 1506 and serial 469 passing; I re-ran the focused warmer, relaunch, admission, and package-settings tests (33) and they passed. I did not re-run the full lanes.
  checks_run:
    - swift build
    - swift test --filter IdleFrameWarmer|RelaunchParity|PreviewAdmissionCoordinator|PackageSettings (33 tests passed)
    - code review of IdleFrameWarmerCoordinator.swift
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-03T06:26:04.661Z
  session: 01MUS0CO3N7ZZS2Y8S
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - cache
created: 2026-10-02T13:44:24.788Z
updated: 2026-10-03T06:26:04.663Z
depends_on:
  - KRMA-765
  - KRMA-766
blockers: []
order: a0
board: product
---

## Objective

After the app has been idle for a moment, quietly build the persisted frames for photos the user has **never opened**, so the first Edit open of any photo and the first scroll to any part of the library are warm, not just the ones visited in a previous session. The owner's library has 256 photos but only 22 persisted previews.

## Background

Depends on KRMA-763, KRMA-764, KRMA-765, KRMA-766: building frames under placeholder identities would be wasted, and the exact-hit path must exist for the work to pay off.

Existing machinery: `PreviewAdmissionCoordinator.scheduleIdlePreviewBuild` / `runIdlePreviewBuild` renders previews for photos around the selection **only when the Edit collection is active** (`collection.isActive`), waits 1.5 s, and stops for any user activity; `storedFrameIsExact(for:)` already lets it skip photos whose persisted frame is exact. `EditedThumbnailCoordinator` renders edited thumbnails on demand for visible cells only. `ImageWorkScheduler` has `background` priority and a `packageIO` lane; `ThumbnailFrameStore` writes are batched. Nothing builds frames while the user sits in the Library, and nothing builds the 480 px original/edited thumbnails beyond the visible window plus one prefetch page.

## Work

1. Generalize the idle build into one resumable **frame warmer** that works from both Library and Edit: ordered by distance from the current selection/viewport, then by recency (`LaunchHints`), covering (a) 480 px original thumbnails, (b) 480 px edited thumbnails for edited photos, (c) 2048 px canonical previews. A photo needing nothing is skipped without touching the source (decide from stored metadata plus the KRMA-763 identity only).
2. Constraints, each enforced in code and by a test: runs only at `.background` priority and yields instantly to any user-visible request, ROI render, export or editor work (the scheduler's existing contention rules); never starts until launch hydration and the first index page have published; suspended while `ProcessInfo.processInfo.isLowPowerModeEnabled`, thermal state is `.serious` or worse, or the app is inactive; one photo in flight at a time; cooperative cancellation between photos and inside the render boundary where it exists today.
3. Persist progress implicitly: the frame stores are the progress record, so a relaunch resumes by skipping what is already exact. No new state file.
4. Never write a frame for a non-canonical request (ROI, comparison, interactive quality) or while the Look for the photo is unresolved without a saved Look reference.
5. Cap disk usage by the existing 1 GB preview cap and thumbnail pack compaction; the warmer must stop when the cap's low-water mark is reached rather than evicting frames the user just looked at (pinned/visible frames are never evicted by warming).
6. Expose a small progress value (done, remaining) for diagnostics only; no new UI.

## Acceptance criteria

- [ ] Deterministic test with a counting fake engine: in Library with no interaction, after the idle delay the warmer builds all missing frames in distance order, one at a time, and a second pass over the same package builds **nothing** (all exact).
- [ ] A user-visible request (select a photo, scroll, start an export) cancels or pauses the warmer within one photo's work and its late result never publishes into a surface; the warmer resumes after the next idle delay.
- [ ] Low Power Mode, serious thermal state, and an inactive app each suspend it (inject the state through a test seam).
- [ ] No frame is written for a photo with an unresolved Look and no saved Look reference, nor for any non-canonical request.
- [ ] After the warmer has run over a fixture library, a relaunch (KRMA-762 harness extended) opens every photo with zero preview renders and the grid hydrates with zero edited-thumbnail renders, including photos the test never opened.
- [ ] The warmer never evicts a pinned/visible frame and stops at the cap low-water mark (test with a tiny `previewFrameStoreCapBytes`).
- [ ] The existing idle-build tests are migrated, not deleted; `fast` and `serial` lanes pass. Document the policy in `docs/APP_ARCHITECTURE.md` and `docs/TESTING.md`.

## Rules for an unattended run (read first)

- **Do not run the display-bound captures** (`scripts/run-kromora-capture.sh`, the last-known-frame benchmark). Everything here is verified by deterministic tests (`scripts/ci-tests.sh fast|serial`) that need no window and no unlocked display (see CLAUDE.md, "Display-bound benchmarks").
- **Do not open child tickets.** If a criterion cannot be met, record exactly what you measured and tried in a comment on this ticket, commit what is safe, and hand off to review.
- Keep the change to what this ticket lists. Swift 6 mode with zero escape hatches (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`). macOS 26 / Apple Silicon only; no `#available` branches and no third-party dependencies.
- Cache files are disposable presentation caches, never package truth. A cache failure must degrade to a miss, never to an error, a wrong-photo frame, or a blocked open.
- Commit with a subject that starts `KRMA-<this id>:`. Do not push. Do not stash, reset, or revert anyone else's uncommitted changes in the tree.


### Comment — codex @ 2026-10-03T06:25:13.718Z

Implemented idle warming for original and edited thumbnails plus canonical previews, with metadata-first skips, system and interaction gates, serialized background scheduling, cancellation fences, and preview-cap protection. Added three-photo relaunch parity coverage and updated architecture/testing docs. Verified fast (1,506 tests), serial (469 tests), and focused warmer/relaunch tests. Commit: 3452bfb.

## Agent log

- 2026-10-03T06:26:04.661Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Counting fake engine: builds missing frames in distance order, second pass builds nothing (pass) — IdleFrameWarmerCoordinatorTests pass
- [x] User-visible request cancels/pauses warmer; late result not published (pass) — generation fence checked after every await in warm()
- [x] Low Power, thermal, inactive suspend via seam (pass) — IdleFrameWarmerConditions.permitsWork checked in canContinue
- [x] No frame for unresolved Look without saved reference or non-canonical request (pass) — mayRenderEditedPixels/permitsExactReuse guards
- [x] Relaunch parity with zero preview and edited-thumbnail renders (pass) — RelaunchParityTests pass (10)
- [x] Never evicts pinned frames; stops at cap low-water mark (pass) — pinned assets set; capacityReached outcome
- [x] Idle-build tests migrated; docs updated; fast/serial lanes pass (pass) — Docs updated in APP_ARCHITECTURE and TESTING; implementer reported fast 1506 and serial 469 passing; I re-ran the focused warmer, relaunch, admission, and package-settings tests (33) and they passed. I did not re-run the full lanes.
Checks run:
- swift build
- swift test --filter IdleFrameWarmer|RelaunchParity|PreviewAdmissionCoordinator|PackageSettings (33 tests passed)
- code review of IdleFrameWarmerCoordinator.swift
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUS0CO3N7ZZS2Y8S
Summary: Verified idle frame warmer: gates, serialization, cap protection, tests pass.
