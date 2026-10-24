---
id: KRMA-931
title: Write culling ratings/flags off the main actor, coalesced into one transaction per shard
type: task
status: done
priority: urgent
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Batch session API groups updates by membership shard and commits at most one transaction per changed shard while preserving single-asset behavior.
      result: pass
      notes: Verified 50 assets across multiple shards, reopened package values, clamping, unchanged no-op behavior, missing-asset error, and revision-preserving clamped no-op.
    - criterion: Coordinator builds updates using dictionary lookup and queues package writes off the main actor; culling presentation remains immediate.
      result: pass
      notes: Reviewed coordinator path and serial package-I/O drain; no per-id first(where:) or synchronous main-actor write remains.
    - criterion: Write failures are surfaced once for a batch without crashing.
      result: pass
      notes: CullingStateBatchWriteTests.testFailureIsReportedOncePerBatch passed.
    - criterion: Rapid successive culling updates preserve the later value.
      result: pass
      notes: CullingStateBatchWriteTests.testRapidSuccessiveEnqueuesEndAtLastValue passed.
    - criterion: Pending culling writes are flushed for session shutdown and before quit through AppViewModel.flushPendingWrites().
      result: pass
      notes: Session shutdown test and new gated AppViewModel flush integration test passed.
    - criterion: swift build is warning-free and Swift 6 safety constraints remain intact.
      result: pass
      notes: swift build exited 0; no concurrency escape hatches were introduced.
    - criterion: Fast CI lane passes, applying the specified isolated rerun exception if the separately tracked StoredEditAdoption test is the sole failure.
      result: pass
      notes: The final fast run reported only StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto; its specified isolated rerun passed. Recorded in the KRMA-931 review comment.
  checks_run:
    - swift build — exit 0
    - scripts/ci-tests.sh fast — final run exit 1 only for StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto; specified isolated rerun passed
    - swift test --filter StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto — exit 0
    - git diff --check — exit 0
  findings:
    - Scheduler rejection or cancellation before operation start could invoke a synchronous package-write fallback from the main-actor terminal callback.
    - An out-of-range rating request that clamped to the already-stored value could still advance assetRevision.
  fixes:
    - Retry scheduler terminal cases on a detached task while keeping the session drain pending; retain the scheduler-free inline fallback.
    - Clamp ratings before the unchanged-state comparison.
    - Added tests for rejected scheduler jobs, clamped no-op ratings, and AppViewModel quit-flush ordering.
  verification_commits:
    - 6d4c1bab
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T15:33:50.391Z
  session: 01MV6U050XWI8PE5G4
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - performance
  - package
  - culling
created: 2026-10-13T14:47:41.781Z
updated: 2026-10-13T15:33:50.394Z
parent: KRMA-922
blockers: []
order: n
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T15:24:06.005Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 6d4c1bab
---

## Objective

Rating/flagging a large selection must not stall the UI. Persist culling changes off the main actor,
as one package transaction per affected membership shard instead of one per photo, with the UI
updating optimistically.

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding M5. `PortableLibrarySession` (`Sources/KromoraKit/Models/
PortableLibrarySession.swift`) is `@MainActor`. Durable package transactions (journal writes,
`F_FULLFSYNC` per file, directory fsyncs, checksums, renames; see `PortablePackageTransaction.swift`)
run inline on the main actor from several user actions, stalling the UI.

The off-main mechanism already exists: `ImageWorkScheduler.enqueuePackageIO(id:lane:priority:
onTerminal:operation:)` (`Sources/KromoraKit/Models/ImageWorkScheduler.swift` ~L259). Its `operation`
runs off the main actor in a package-I/O lane. `PortableLibrarySession` already uses it for index
load/write and backfills (see its `scheduler`, `indexWriteJobID`, … properties and the
`enqueuePackageIO` call sites near L321, L414, L511, L575). Copy that pattern. A session created
without a scheduler (some tests) falls back to inline work; keep that fallback working.

Package values (`package`, `lease`, `clock`) are captured as `let`s before hopping off the main actor
(see `updateLibraryState` L1549 for how they are read). Mutations must still go through
`lease.withWriterMutationLock` so writer exclusivity is unchanged.

Specific to culling:

- `Sources/KromoraKit/ViewModels/LibraryBrowsingCoordinator.swift` ~L570
  `persistPortableLibraryStateIfNeeded()` loops `collection.lastCullingAssetIDs`, and for EACH id does
  `collection.items.first(where:)` (O(n) per asset, O(n·m) overall) and then a synchronous
  `library.updateLibraryState(for:rating:flag:)` on the main actor.
- `PortableLibrarySession.updateLibraryState` (L1549) opens a transaction, reads the whole membership
  shard (`PortableLibraryPackage.shard(for: assetID)` picks the shard), mutates one entry, stages the
  shard JSON, commits. Many ids in the same shard therefore re-read and re-write the same file N times.
- Failures are surfaced once via `destination?.presentLibraryError(...)`.

## Acceptance criteria

- [ ] New session API, e.g. `updateLibraryState(_ updates: [(PortablePhotoAssetID, rating: Int, flag:
      PhotoFlag)]) throws`, groups updates by shard and performs ONE transaction per shard (read shard
      once, apply all, stage, commit). Single-photo behavior (clamping rating to 0...5, no-op when
      unchanged, `assetRevision` bump, `PortablePackageTrashError.assetNotFound`) is preserved. The
      old single-asset method may delegate to the new one.
- [ ] `persistPortableLibraryStateIfNeeded` builds the update list with a dictionary lookup of
      `collection.items` by id (no `first(where:)` inside the loop), then enqueues the batch via
      `enqueuePackageIO` (a dedicated lane/job id; reuse an existing lane unless one clearly fits
      better). The main actor never performs the write.
- [ ] The UI state (rating/flag shown on the cell and in filters) updates immediately; it does not wait
      for the write. If the write later fails, the existing `presentLibraryError` message is shown once
      for the batch and no crash occurs.
- [ ] Rapid successive culling actions are ordered: a later batch for the same asset is never
      overwritten by an earlier one (enqueue per-session serial order, or coalesce pending updates
      last-write-wins before the write begins). Add a test that applies rating 1 then 5 to the same
      asset in quick succession and asserts the package ends at 5.
- [ ] Tests (fast lane, `Tests/KromoraKitTests`, find the existing PortableLibrarySession culling tests
      with `grep -rn updateLibraryState Tests`): (a) a batch of 50 assets across multiple shards
      commits exactly one transaction per shard (count via the journal/transaction seam if one exists,
      otherwise assert on observable shard file revisions); (b) all values read back after reopening
      the package; (c) shutdown with pending writes flushes or cleanly cancels without corrupting.
- [ ] `ExportCoordinator`/shutdown ordering unchanged: pending culling writes are flushed by
      `flushPendingWrites()` before quit (read how `KromoraAppDelegate.applicationShouldTerminate`
      uses it) so a rating made just before ⌘Q is not lost. Add a test.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).

## Implementation notes

Do not change how the in-memory `collection` models culling. Do not touch virtual copy, delete, or
open-repair paths (separate tickets). If you find the write must be awaited somewhere (e.g. before
export), expose an `await` flush point rather than blocking.


### Comment — claude @ 2026-10-13T15:24:05.506Z

Implemented in bb54cd10. PortableLibrarySession.updateLibraryState(_ updates:) groups by shard, one transaction per shard (single-asset method delegates). enqueueLibraryStateUpdates coalesces last-write-wins with a serial drain on the package-I/O lane (inline fallback without scheduler, and on evicted/rejected/cancelled so no rating is dropped). Coordinator builds updates via dictionary lookup and never writes on main. flushPendingLibraryState() is awaited by AppViewModel.flushPendingWrites and session shutdown; shutdown also rewrites the index projection since scheduler-wide cancellation could drop the queued index write. Tests: CullingStateBatchWriteTests (shard transaction count, reopen, ordering 1 then 5, shutdown flush, failure once). swift build warning-free; scripts/ci-tests.sh fast exit 0.


### Comment — codex @ 2026-10-13T15:33:19.667Z

Counterpoint verification: the final scripts/ci-tests.sh fast run had one failure, StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto. Per the issue instructions, I reran it alone with swift test --filter StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto; it passed, so I left that separately tracked test unchanged. swift build passed. Local verification fixes cover clamped no-op ratings and keep scheduler rejection retries off the main actor; added coverage for the AppViewModel quit flush.

## Agent log

- 2026-10-13T15:33:50.391Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Batch session API groups updates by membership shard and commits at most one transaction per changed shard while preserving single-asset behavior. (pass) — Verified 50 assets across multiple shards, reopened package values, clamping, unchanged no-op behavior, missing-asset error, and revision-preserving clamped no-op.
- [x] Coordinator builds updates using dictionary lookup and queues package writes off the main actor; culling presentation remains immediate. (pass) — Reviewed coordinator path and serial package-I/O drain; no per-id first(where:) or synchronous main-actor write remains.
- [x] Write failures are surfaced once for a batch without crashing. (pass) — CullingStateBatchWriteTests.testFailureIsReportedOncePerBatch passed.
- [x] Rapid successive culling updates preserve the later value. (pass) — CullingStateBatchWriteTests.testRapidSuccessiveEnqueuesEndAtLastValue passed.
- [x] Pending culling writes are flushed for session shutdown and before quit through AppViewModel.flushPendingWrites(). (pass) — Session shutdown test and new gated AppViewModel flush integration test passed.
- [x] swift build is warning-free and Swift 6 safety constraints remain intact. (pass) — swift build exited 0; no concurrency escape hatches were introduced.
- [x] Fast CI lane passes, applying the specified isolated rerun exception if the separately tracked StoredEditAdoption test is the sole failure. (pass) — The final fast run reported only StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto; its specified isolated rerun passed. Recorded in the KRMA-931 review comment.
Checks run:
- swift build — exit 0
- scripts/ci-tests.sh fast — final run exit 1 only for StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto; specified isolated rerun passed
- swift test --filter StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto — exit 0
- git diff --check — exit 0
Findings:
- Scheduler rejection or cancellation before operation start could invoke a synchronous package-write fallback from the main-actor terminal callback.
- An out-of-range rating request that clamped to the already-stored value could still advance assetRevision.
Fixes:
- Retry scheduler terminal cases on a detached task while keeping the session drain pending; retain the scheduler-free inline fallback.
- Clamp ratings before the unchanged-state comparison.
- Added tests for rejected scheduler jobs, clamped no-op ratings, and AppViewModel quit-flush ordering.
Verification commits:
- 6d4c1bab
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV6U050XWI8PE5G4
Summary: Verified batched off-main culling persistence; fixed two localized edge cases.
