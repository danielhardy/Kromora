---
id: KRMA-761
title: "Record why a persisted frame was rejected: classification outcome and reason ledger"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Unit test per FrameRejectionReason; classify unchanged
      result: pass
      notes: Reason matrix present; placeholder only refines mismatch reason (f7fa11b).
    - criterion: Fake-store test proves each lookup site records exactly one ledger entry with right surface/outcome
      result: pass
      notes: "Delivered by child KRMA-771 (d0c26e4): preview, original thumb, edited thumb, and collection launch-frame tests assert count, surface, missingFile and corrupt outcomes."
    - criterion: Cheap, non-blocking recording; zero new diagnostics
      result: pass
      notes: swift build clean.
    - criterion: No behaviour change; fast and serial lanes pass
      result: pass
      notes: fast exit 0 (1477 tests); serial 459 tests, 0 failures.
    - criterion: docs/TESTING.md documents ledger and summary line
      result: pass
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-02T14:53:38.023Z
  session: 01MUR2VE69SYP32LAI
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - observability
  - cache
created: 2026-10-02T13:44:20.181Z
updated: 2026-10-02T14:53:38.027Z
depends_on:
  - KRMA-771
blockers: []
order: a0
board: product
commits:
  - f7fa11b
---

## Objective

Make every persisted-frame lookup report **what it decided and why**, so a cold relaunch that should have been warm is visible in one log line or one test assertion instead of needing a debugger. Today a rejected frame is indistinguishable from a missing one, which is how the relaunch cache miss in KRMA-763 went unnoticed.

## Background

The last-known-frame architecture (`.context/last-known-frame-plan.md`) persists a 2048 px preview per photo (`LatestPreviewFrameStore`, `Derived/Previews/*.kframe`) and a 480 px original and edited thumbnail per photo (`ThumbnailFrameStore`, packed in `Derived/Thumbnails`). Every read is judged by `FrameClassifier.classify` (`Sources/KromoraKit/Models/PresentationFrame.swift`), which returns `.exact`, `.staleCompatible`, `.provisionalOnly`, or `.unusable`. `.unusable` collapses at least four different causes into one value: asset ID mismatch, source fingerprint mismatch, invalid dimensions, and a color space that cannot be presented losslessly. Callers (`PreviewPresentationCoordinator.beginStoredFrameLookup`, `OriginalThumbnailLoader.load`, `EditedThumbnailCoordinator.request`, `ImageCollection.applyStoredFrames`) then treat a miss and a rejection identically and say nothing.

`Sources/KromoraKit/Models/Observability.swift` already holds the project's signposts and counters; reuse its conventions.

## Work

1. Add `FrameRejectionReason` (e.g. `assetMismatch`, `sourceFingerprintMismatch`, `placeholderSourceIdentity`, `dimensionsInvalid`, `colorSpaceUnpresentable`) and a pure `FrameClassifier.classifyWithReason` (or an equivalent) that returns the classification plus the first failing reason. `classify` must keep its current signature and behaviour and be implemented in terms of the new function so there is still exactly one freshness implementation.
2. Add a small `FrameLookupLedger` (an actor or a `@MainActor` final class, whichever matches how `Observability` is already used) that records, per lookup: surface (`editPreview`, `gridOriginal`, `gridEdited`, `filmstrip`, `launchHint`), outcome (`missingFile`, `corrupt`, `rejected(reason)`, `staleCompatible`, `provisionalOnly`, `exact`), and a monotonic timestamp. No file paths, no photo contents, asset IDs only as the existing observability code already logs them.
3. Call it from the four lookup sites listed above. Wiring only; do not change any decision.
4. Expose the ledger to tests through an injectable seam on `AppViewModel` and `ImageCollection` (default: a shared instance), and print a one-line summary per surface (counts by outcome, top rejection reason) through the existing logging at the end of a library load and when Edit settles. DEBUG/diagnostic builds only if that is how `Observability` already gates output.
5. Update `docs/TESTING.md` with one short paragraph: what the ledger records and how to read the summary line.

## Acceptance criteria

- [ ] A unit test per `FrameRejectionReason` constructs the minimal frame/inputs that triggers it and asserts both the classification (`.unusable`) and the reason; and asserts `classify` returns exactly what it returned before for every row of the existing `PresentationFrameTests` matrix (those tests stay green unmodified).
- [ ] A test with a fake frame store proves each of the four lookup sites records exactly one ledger entry per lookup with the right surface and outcome, including a corrupt envelope (outcome `corrupt`, no throw to the caller) and a missing file.
- [ ] Recording is cheap and non-blocking: no main-actor I/O is added, and `swift build` produces zero new diagnostics.
- [ ] No behaviour change: the `fast` and `serial` CI lanes pass with no test edited other than additions.
- [ ] `docs/TESTING.md` documents the ledger and the summary line.

## Rules for an unattended run (read first)

- **Do not run the display-bound captures** (`scripts/run-kromora-capture.sh`, the last-known-frame benchmark). Everything here is verified by deterministic tests (`scripts/ci-tests.sh fast|serial`) that need no window and no unlocked display (see CLAUDE.md, "Display-bound benchmarks").
- **Do not open child tickets.** If a criterion cannot be met, record exactly what you measured and tried in a comment on this ticket, commit what is safe, and hand off to review.
- Keep the change to what this ticket lists. Swift 6 mode with zero escape hatches (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`). macOS 26 / Apple Silicon only; no `#available` branches and no third-party dependencies.
- Cache files are disposable presentation caches, never package truth. A cache failure must degrade to a miss, never to an error, a wrong-photo frame, or a blocked open.
- Commit with a subject that starts `KRMA-<this id>:`. Do not push. Do not stash, reset, or revert anyone else's uncommitted changes in the tree.


### Comment — codex @ 2026-10-02T14:14:10.368Z

Implemented reason-bearing frame classification, lookup outcome recording for edit preview, original/edited thumbnails, collection hydration, and launch hints, plus per-surface summary signposts and TESTING.md guidance. Added classifier reason coverage, monotonic ledger summary coverage, and a temp-store test distinguishing a missing preview from a corrupt envelope. Verification: swift build (exit 0), scripts/ci-tests.sh fast (exit 0), scripts/ci-tests.sh serial (457 tests, 0 failures). Coverage gap: the acceptance criterion requesting one fake-frame-store integration test asserting exactly one ledger record at each of the four lookup sites is not included; the new tests cover classifier reasons and store/ledger behavior, while the lookup paths are wired but not individually asserted end to end. Commit fb04ad5.

## Agent log

- 2026-10-02T14:21:07.237Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Unit test per FrameRejectionReason; classify unchanged (pass) — Reason matrix test present. Fixed a behaviour change: placeholder check ran first and could reject frames classify previously accepted; it now only refines the mismatch reason.
- [ ] Fake-store test proves each of the four lookup sites records exactly one ledger entry with right surface/outcome (fail) — Not implemented; only classifier, store corrupt/missing, and ledger summary tests exist.
- [x] Cheap, non-blocking recording; zero new diagnostics (pass) — swift build clean.
- [x] No behaviour change; fast and serial lanes pass (pass) — fast exit 0; serial 457 tests 0 failures after fix.
- [x] docs/TESTING.md documents ledger and summary line (pass)
Checks run:
- swift build
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- swift test --filter PresentationFrame
Findings:
- high: missing per-lookup-site ledger integration tests (preview, original thumb, edited thumb, ImageCollection hydration) incl. corrupt and missing-file outcomes
- fixed: classifyWithReason checked placeholder identity first, changing classify results for placeholder-fingerprint frames
Fixes:
- f7fa11b: placeholder reason only refines fingerprint mismatch
Verification commits:
- f7fa11b
Actor: claude
Resolved model: sonnet
Pickup session: 01MUR1NZJEJZCQA4L6
Summary: Acceptance criterion for per-lookup-site ledger tests (one entry per lookup, corrupt and missing outcomes) is unmet.

- 2026-10-02T14:53:38.023Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Unit test per FrameRejectionReason; classify unchanged (pass) — Reason matrix present; placeholder only refines mismatch reason (f7fa11b).
- [x] Fake-store test proves each lookup site records exactly one ledger entry with right surface/outcome (pass) — Delivered by child KRMA-771 (d0c26e4): preview, original thumb, edited thumb, and collection launch-frame tests assert count, surface, missingFile and corrupt outcomes.
- [x] Cheap, non-blocking recording; zero new diagnostics (pass) — swift build clean.
- [x] No behaviour change; fast and serial lanes pass (pass) — fast exit 0 (1477 tests); serial 459 tests, 0 failures.
- [x] docs/TESTING.md documents ledger and summary line (pass)
Checks run:
- swift build
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUR2VE69SYP32LAI
Summary: Verified: ledger, reasons, docs, and per-site lookup tests (via KRMA-771) all in place; build clean, fast and serial lanes pass.
