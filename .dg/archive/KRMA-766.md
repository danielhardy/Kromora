---
id: KRMA-766
title: "Relaunch Edit: an exact stored preview opens with zero render requests and one published frame"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "Relaunch test JPEG and RAW-like: zero render requests, one confirmed frame, trace storedFrame->confirmed; XCTExpectFailure removed"
      result: pass
      notes: RelaunchParityTests extended; fast lane green.
    - criterion: Histogram and supporting work admitted exactly once for exact open
      result: pass
      notes: Covered by new PreviewAdmissionCoordinator/Relaunch tests.
    - criterion: "Stale open: inert stored frame, one render, one replacement"
      result: pass
      notes: WarmReopenPresentationTests pixel-epoch case passes.
    - criterion: Replaced source bytes classify unusable and never present
      result: pass
      notes: testReplacedSourceNeverShowsTheStoredFrame passes.
    - criterion: Cold open unchanged
      result: pass
      notes: Thumbnail/embedded deferred at most 50ms budget; settled render now waits for stored edits to resolve, which is always set by adoptStoredEdits.
    - criterion: Rapid A->B->A late completions dropped
      result: pass
      notes: Deferred state reset and generation-checked in beginLoad.
    - criterion: "Look unresolved at open: still exact"
      result: pass
      notes: storedEditLook adopted from the stored revision reference.
    - criterion: fast, serial, identity lanes pass
      result: pass
      notes: fast 1489, serial 468, identity 4; 0 failures.
  checks_run:
    - scripts/ci-tests.sh fast (1489 tests, 0 failures)
    - scripts/ci-tests.sh serial (468 tests, 0 failures)
    - scripts/ci-tests.sh identity (4 tests, 0 failures)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-03T03:47:30.152Z
  session: 01MURUDZBAY5HAIP6N
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - cache
  - edit
created: 2026-10-02T13:44:23.058Z
updated: 2026-10-03T03:47:30.154Z
parent: KRMA-764
blockers: []
order: a0
board: product
---

## Objective

On relaunch, the first Edit open of a photo whose inputs have not changed shows **one** frame, the stored 2048 px preview, with **zero preview render requests**; histogram and supporting work are admitted exactly once. No embedded camera JPEG, no original thumbnail, no unedited-then-edited sequence.

## Background

KRMA-763 identity propagation, KRMA-764 store guards, and the KRMA-777 sweep are implemented. This is a follow-up to those changes; KRMA-764 now waits on this issue and KRMA-765 for its remaining acceptance criteria. The Edit open path is `AppViewModel.beginLoad` (`Sources/KromoraKit/ViewModels/AppViewModel.swift`, ~2058-2160): it starts a presentation session, presents any already-materialized same-asset thumbnail as a provisional candidate, and calls `PreviewPresentationCoordinator.beginStoredFrameLookup` in parallel with source preparation. `classifyStoredFrame` then decides exact / stale / provisional once the stored edit and Look are adopted (`storedEditsResolvedSourceRevision`, `storedEditLook`). An exact hit routes through the normal confirmed-frame tail (`PreviewAdmissionCoordinator.submitSettledPreview`) without a render.

Observed: after relaunch the owner sees the first open "render through its stages". Likely contributors to verify, in order: (1) identity mismatch (fixed by KRMA-763); (2) provisional present of the **original thumbnail** (`item.originalThumbnailForPresentation`) before the stored frame arrives, producing a low-res-then-high-res double paint even when the stored frame is exact; (3) the embedded camera JPEG still being published for RAW when the stored lookup is slower than extraction (`presentEmbeddedFirstFrame` / `SourceSessionCoordinator`); (4) the exact classification being delayed behind source preparation (`editsResolved`), so the stored frame is shown provisionally and then the settled path re-renders when the Look signature or edit hash is not yet known.

## Work

1. Add the failing tests first (see criteria), then fix what they expose. Prefer reordering and gating over new machinery: the stored frame lookup is already parallel to source preparation.
2. If the stored frame can be read before the original/edited thumbnail would be presented, and the item's `thumbnail` is only a lower-resolution stand-in for the same pixels, skip presenting the thumbnail when a stored frame lookup is in flight and is expected to hit (use the ledger/last-known state; do not wait for it longer than the existing budget in `docs/TESTING.md`). Never leave the canvas blank and never show another asset's pixels.
3. Suppress the embedded-JPEG publication whenever a same-asset candidate (stored frame or thumbnail) has been shown (existing rule); verify it also holds when the stored frame arrives **after** extraction started, and fence a late embedded frame that would replace a better one.
4. Make exact classification not depend on source preparation when everything needed is already known: the stored edit revision's content hash and its content-addressed Look reference (`storedLook`) are available from the edit store before the source is prepared; confirm `editsResolved` becomes true as soon as `adoptStoredEdits` has them (see KRMA-755), and that the Look browser scan state is irrelevant to exactness.

## Acceptance criteria

- [ ] Relaunch test (in `RelaunchParityTests`, KRMA-762), JPEG and RAW-like fixtures: opening each unchanged photo records **zero** preview render requests, exactly one confirmed frame, and a presentation-session trace of at most `storedFrame -> confirmed(storedFrame)` (no `originalThumbnail`, no `embedded` step when a stored frame exists). The matching `XCTExpectFailure` wrappers are removed.
- [ ] Histogram and edited-thumbnail/comparison supporting work are admitted exactly once for an exact open (extend the existing counters used by the PreviewPresentationCoordinator suite).
- [ ] Stale open (edit changed, or `pixelEpoch` bumped): stored frame shown at once, inert (no tools, histogram, scopes, comparison, cache write, or `lastPublishedVisibleRequest` driven by it), one render, one replacement; no embedded or original frame in between.
- [ ] Replaced source bytes: the persisted old-source frame classifies `.unusable`, is never presented or used to skip work, and reopening the photo publishes one confirmed frame after exactly one render using the replacement fingerprint.
- [ ] Cold open (no stored frame): behaviour is unchanged (thumbnail or embedded first frame, then settled), and the settled render writes the canonical frame once.
- [ ] Rapid A -> B -> A: late stored-frame, embedded and render completions from an older session are dropped (extend the existing generation-fence tests); the surface never shows A after B is selected.
- [ ] Look unresolved at open time (scan not finished) with a saved Look reference: still exact, no render, no wait for the scan.
- [ ] `fast` and `serial` lanes pass; no change to the render quality of settled frames (existing identity-gate lane `scripts/ci-tests.sh identity` passes).

## Rules for an unattended run (read first)

- **Do not run the display-bound captures** (`scripts/run-kromora-capture.sh`, the last-known-frame benchmark). Everything here is verified by deterministic tests (`scripts/ci-tests.sh fast|serial`) that need no window and no unlocked display (see CLAUDE.md, "Display-bound benchmarks").
- **Do not open child tickets.** If a criterion cannot be met, record exactly what you measured and tried in a comment on this ticket, commit what is safe, and hand off to review.
- Keep the change to what this ticket lists. Swift 6 mode with zero escape hatches (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`). macOS 26 / Apple Silicon only; no `#available` branches and no third-party dependencies.
- Cache files are disposable presentation caches, never package truth. A cache failure must degrade to a miss, never to an error, a wrong-photo frame, or a blocked open.
- Commit with a subject that starts `KRMA-<this id>:`. Do not push. Do not stash, reset, or revert anyone else's uncommitted changes in the tree.


### Comment — codex @ 2026-10-03T03:38:13.602Z

Implemented relaunch exact-preview reuse, deferred thumbnail/embedded candidates within the first-paint budget, source replacement handling, and immediate saved edit/Look identity adoption. Added JPEG/RAW-like, stale, replaced-source, unresolved Look, and supporting-work regressions. Commit c1328d9. Checks passed: fast (1489), serial (468), identity (4), focused relaunch/admission/publication/cutover suites, and dg validate.

## Agent log

- 2026-10-03T03:47:30.152Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Relaunch test JPEG and RAW-like: zero render requests, one confirmed frame, trace storedFrame->confirmed; XCTExpectFailure removed (pass) — RelaunchParityTests extended; fast lane green.
- [x] Histogram and supporting work admitted exactly once for exact open (pass) — Covered by new PreviewAdmissionCoordinator/Relaunch tests.
- [x] Stale open: inert stored frame, one render, one replacement (pass) — WarmReopenPresentationTests pixel-epoch case passes.
- [x] Replaced source bytes classify unusable and never present (pass) — testReplacedSourceNeverShowsTheStoredFrame passes.
- [x] Cold open unchanged (pass) — Thumbnail/embedded deferred at most 50ms budget; settled render now waits for stored edits to resolve, which is always set by adoptStoredEdits.
- [x] Rapid A->B->A late completions dropped (pass) — Deferred state reset and generation-checked in beginLoad.
- [x] Look unresolved at open: still exact (pass) — storedEditLook adopted from the stored revision reference.
- [x] fast, serial, identity lanes pass (pass) — fast 1489, serial 468, identity 4; 0 failures.
Checks run:
- scripts/ci-tests.sh fast (1489 tests, 0 failures)
- scripts/ci-tests.sh serial (468 tests, 0 failures)
- scripts/ci-tests.sh identity (4 tests, 0 failures)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MURUDZBAY5HAIP6N
Summary: Verification passed: fast/serial/identity lanes green; no findings.
