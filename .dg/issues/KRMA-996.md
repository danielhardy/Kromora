---
id: KRMA-996
title: Keep failed rating and flag writes dirty until they commit
type: bug
status: done
priority: urgent
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: After a failed culling write, the failed asset/value pairs stay pending and flush retries them.
      result: pass
      notes: Malformed-shard rating-4 probe passed; repairing the shard and flushing again persisted rating 4.
    - criterion: A newer rating or flag for the same asset replaces the failed value.
      result: pass
      notes: Newer-intent regression passed; retry persisted rating 2 and reject flag, not the failed rating 4 and pick.
    - criterion: "Partial success is per shard: committed shards leave the pending set and failed shards remain retryable."
      result: pass
      notes: Two-shard partial-failure test passed; the failed shard committed on retry.
    - criterion: Visible rating and flag stay at the intended values while pending or failed, and failures are reported.
      result: pass
      notes: LibraryBrowsingCoordinator keeps the optimistic collection value and presents its failure callback; the per-batch reporting test passed.
    - criterion: A failed culling flush participates in the termination save result, while an empty successful queue is not a failure.
      result: pass
      notes: AppViewModel folds the culling flush result into PersistenceFlushResult; failed and empty-queue paths passed. Quit Without Saving now discards failed culling state before shutdown.
    - criterion: Tests cover malformed-shard retry, newer intent, two-shard partial failure, and the existing error-reported-once behavior.
      result: pass
      notes: All 15 CullingStateBatchWriteTests passed, including error reporting once per batch.
    - criterion: swift build is warning-free and scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: Build emitted no warnings; fast lane passed 1,921 tests.
  checks_run:
    - "swift test --filter CullingStateBatchWriteTests: passed, 15 tests, exit 0"
    - "swift test --filter PortableLibrarySession: passed, 23 tests, exit 0"
    - "swift build: passed, exit 0, no warnings"
    - "scripts/ci-tests.sh fast: passed, 1,921 tests, exit 0"
    - "git diff --check: passed"
  findings:
    - Quit Without Saving discarded edit snapshots but retained failed culling changes; shutdown could retry and commit them after the user chose to discard.
  fixes:
    - AppViewModel.discardPendingWrites now waits for any active culling drain and clears pending and failed culling changes. Added a shutdown regression test.
  verification_commits:
    - 841f6860
    - d181114d
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T17:19:01.781Z
  session: 01MV8D5P21S6ETFD8X
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - release-readiness
  - readiness-2026-10-14
  - must-fix
  - library
created: 2026-10-14T16:08:52.894Z
updated: 2026-10-14T17:19:01.784Z
parent: KRMA-994
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Models/PortableLibrarySession.swift
    - Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-994
    - KRMA-1005
  commands:
    - swift test --filter PortableLibrarySession
    - scripts/ci-tests.sh fast
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T17:08:05.031Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - d181114d
  - 841f6860
---

## Objective

A rating or flag that fails to commit stays dirty, can be retried, and can make quit offer Retry Saving. A later successful flush writes the latest intended value. A failed shard does not discard a shard that already committed.

## Context

Confirmed on 2026-10-14. `PortableLibrarySession.startLibraryStateDrain` (`Sources/KromoraKit/Models/PortableLibrarySession.swift`, around line 1874) copies `pendingLibraryStateUpdates` and then `removeAll()` before the write. On failure, `completeLibraryStateBatch` (around line 1944) reports the error and does not put the batch back. `flushPendingLibraryState()` returns `Void`. `AppViewModel.flushPendingWrites` (around line 4224) awaits that flush and returns only the edit-document `PersistenceFlushResult`, so a culling failure cannot participate in Retry Saving / Quit Without Saving.

`LibraryBrowsingCoordinator` (around line 551) has already updated the visible rating or flag. Its failure callback only presents an error.

Probe: make a membership shard unreadable, queue rating 4, wait for the reported failure, repair the shard, flush again. The durable rating stayed 0.

Edit persistence already keeps a failed snapshot and fences generations. Match that contract. Do not invent a second writer.

Related, but do not implement here: KRMA-1005 and KRMA-1006 move other filesystem work off the main actor. If your fix returns from a UI call before the write finishes, the dirty state from this ticket is what makes that safe. Parent epic: KRMA-994. Review finding 2.

## Acceptance criteria

- [ ] After a failed culling write, the failed asset/value pairs are still pending. A later `flushPendingLibraryState` retries them without the user setting the rating again.
- [ ] A newer rating or flag for the same asset replaces the failed value. The retry must not resurrect the older failed value.
- [ ] Partial success is per shard: assets whose shard committed stay committed and leave the pending set; assets whose shard failed stay pending. Read `writeLibraryState` and test at least two shards, one failing.
- [ ] The visible rating/flag stays on the user's intended value while the write is pending or failed, and the failure is still reported. Do not snap the UI back to the old durable value and also drop the pending write.
- [ ] Flush returns a result that quit already understands, or `flushPendingWrites` folds the culling outcome into the result it already returns. A failed culling flush is a failed save: termination can offer retry versus quit without saving. A successful flush of an empty queue is not a failure.
- [ ] Tests: the probe (malformed shard, rating 4, repair, second flush, durable rating 4); a newer intent replacing a failed one; a two-shard partial failure. Extend the existing "error reported once" test rather than deleting it.
- [ ] `swift build` is warning-free. `scripts/ci-tests.sh fast` exits 0.

## Constraints

- Re-read the cited lines before editing. Line numbers drift.
- Swift 6 language mode stays on. No `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, or `#available` branches. No new dependencies.
- Do not run `scripts/run-kromora-capture.sh`. Display-bound numbers already live in `docs/TESTING.md`.
- Preserve unrelated working-tree changes. Do not revert other tickets' edits.
- One issue at a time. Commit subject starts with this issue id. Hand off at `review`; do not mark `done`.


### Comment — claude @ 2026-10-14T17:08:04.501Z

Implemented in d181114d. Failed culling shards stay dirty (failedLibraryStateUpdates), retry on next enqueue/flush, newer intents replace failed values, partial success is per shard, flushPendingLibraryState returns PersistenceFlushResult and flushPendingWrites folds it in so quit offers Retry Saving. Added 3 tests + extended the reported-once test. swift build warning-free; scripts/ci-tests.sh fast exit 0. Not changed: UI keeps intended value (coordinator untouched); assets removed from the library are dropped rather than retried.

## Agent log

- 2026-10-14T17:19:01.781Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] After a failed culling write, the failed asset/value pairs stay pending and flush retries them. (pass) — Malformed-shard rating-4 probe passed; repairing the shard and flushing again persisted rating 4.
- [x] A newer rating or flag for the same asset replaces the failed value. (pass) — Newer-intent regression passed; retry persisted rating 2 and reject flag, not the failed rating 4 and pick.
- [x] Partial success is per shard: committed shards leave the pending set and failed shards remain retryable. (pass) — Two-shard partial-failure test passed; the failed shard committed on retry.
- [x] Visible rating and flag stay at the intended values while pending or failed, and failures are reported. (pass) — LibraryBrowsingCoordinator keeps the optimistic collection value and presents its failure callback; the per-batch reporting test passed.
- [x] A failed culling flush participates in the termination save result, while an empty successful queue is not a failure. (pass) — AppViewModel folds the culling flush result into PersistenceFlushResult; failed and empty-queue paths passed. Quit Without Saving now discards failed culling state before shutdown.
- [x] Tests cover malformed-shard retry, newer intent, two-shard partial failure, and the existing error-reported-once behavior. (pass) — All 15 CullingStateBatchWriteTests passed, including error reporting once per batch.
- [x] swift build is warning-free and scripts/ci-tests.sh fast exits 0. (pass) — Build emitted no warnings; fast lane passed 1,921 tests.
Checks run:
- swift test --filter CullingStateBatchWriteTests: passed, 15 tests, exit 0
- swift test --filter PortableLibrarySession: passed, 23 tests, exit 0
- swift build: passed, exit 0, no warnings
- scripts/ci-tests.sh fast: passed, 1,921 tests, exit 0
- git diff --check: passed
Findings:
- Quit Without Saving discarded edit snapshots but retained failed culling changes; shutdown could retry and commit them after the user chose to discard.
Fixes:
- AppViewModel.discardPendingWrites now waits for any active culling drain and clears pending and failed culling changes. Added a shutdown regression test.
Verification commits:
- 841f6860
- d181114d
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV8D5P21S6ETFD8X
Summary: Verified culling retry, partial-shard persistence, and quit handling; fixed discard semantics.
