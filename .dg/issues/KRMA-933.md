---
id: KRMA-933
title: Remove photos from the library off the main actor
type: task
status: done
priority: high
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Package removal is scheduled off the main actor and each item is published to the grid as its cleanup completes.
      result: pass
      notes: Per-item package-I/O jobs preserve sequential processing and incremental grid updates.
    - criterion: Removal preserves alreadyRemoved, assetNotFound compatibility, failure summary, and shutdown consistency semantics.
      result: pass
      notes: Existing partial failure, retry, and shutdown tests pass.
    - criterion: A gated removal does not block a main-actor hop.
      result: pass
      notes: testMainActorStaysResponsiveWhileSessionRemovalIsGated passes.
    - criterion: A deletion in progress prevents a second deletion from colliding with the active scheduler job.
      result: pass
      notes: Added a single-flight guard and testSecondDeletionBatchIsRejectedWhileAnotherItemIsInFlight.
    - criterion: Deletion tests cover partial failure and shutdown mid-batch.
      result: pass
      notes: All 13 LibraryDeletionCoordinatorTests pass.
    - criterion: Swift build is warning-free and Swift 6 concurrency constraints remain satisfied.
      result: pass
      notes: swift build completed without diagnostics; package settings checks passed in the fast lane.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: All 1,811 required fast-lane tests passed.
  checks_run:
    - swift build (exit 0; no diagnostics)
    - swift test --filter LibraryDeletionCoordinatorTests (13 tests, 0 failures)
    - scripts/ci-tests.sh fast (1,811 tests, exit 0)
    - git diff --check (exit 0)
  findings:
    - Concurrent disjoint deletion batches could replace the shared removal scheduler job ID; an earlier package transaction could commit while its continuation reported cancellation, leaving the grid stale.
  fixes:
    - Made LibraryDeletionCoordinator deletion single-flight and added regression coverage for a second batch targeting a different item.
  verification_commits:
    - 2ad0f4a17ddd006e3e62b3190f2a04b4247b4908
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T19:01:45.104Z
  session: 01MV71HJ047IOCIOPH
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - performance
  - package
created: 2026-10-13T14:47:43.607Z
updated: 2026-10-13T19:01:45.107Z
parent: KRMA-922
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T18:53:31.317Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 2ad0f4a17ddd006e3e62b3190f2a04b4247b4908
---

## Objective

Deleting/removing photos must not block the UI per removed item.

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

Specific to deletion:

- `Sources/KromoraKit/ViewModels/LibraryDeletionCoordinator.swift` ~L174 calls
  `portableLibrary.removeFromLibrary(item.asset.source.portableIdentity.assetID)` synchronously in a
  per-candidate loop (after clearing cached analysis). It already treats
  `PortablePackageTrashError.alreadyRemoved` as idempotent success and collects `failures` for one
  summary error.
- `PortableLibrarySession.removeFromLibrary` (~L1516) runs `lease.withWriterMutationLock { … }` with a
  quarantine/tombstone transaction.
- There is a collaborator test file from KRMA-437 for this coordinator; extend it.

## Acceptance criteria

- [ ] The removal loop moves into one `enqueuePackageIO` job (or one job per N items) that processes
      candidates sequentially off the main actor and reports per-item outcome back to the main actor
      (removed / alreadyRemoved / failed) so the grid updates as items finish, not only at the end.
- [ ] All existing semantics are preserved: `alreadyRemoved` is success; `allowsUnregisteredSourceDeletion`
      with `assetNotFound` still falls through to edit-record cleanup; `failures` are summarized in one
      error; cancel/shutdown stops between items without leaving a half-removed item.
- [ ] The main actor is never blocked for more than the per-item UI update: add a test that gates the
      session removal and asserts a `@MainActor` hop completes while it is gated.
- [ ] A progress/disabled state prevents starting a second deletion on overlapping items.
- [ ] Existing deletion tests pass (`grep -rln LibraryDeletionCoordinator Tests`); add tests for
      partial failure (one item throws) and for shutdown mid-batch.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).

## Implementation notes

Do not change the trash/quarantine format or `PortablePackageTrashError`. Do not touch culling,
virtual copy or open-repair paths.


### Comment — claude @ 2026-10-13T18:53:35.731Z

Commit a1304d90. Package removal now runs per item on the package-I/O lane via PortableLibrarySession.removeFromLibraryOffMain, with the quarantine/tombstone transaction under lease.withWriterMutationLock. The inline fallback for a session without a scheduler is kept. LibraryDeletionCoordinator awaits it per item and removes each item from the grid as it lands. alreadyRemoved, assetNotFound and failure-summary semantics are unchanged. Overlapping deletion of the same items is rejected inside the coordinator (isDeleting/inFlightIDs, with an error message); I did not add a separate UI disabled state, because the confirm flow already clears the confirmation. New tests: gated main-actor hop, overlap rejection, shutdown mid-batch. Partial failure was already covered by testPartialFailureCleansUpDeletedItemsAndReportsError. swift build is clean. ci-tests fast failed once on the unrelated DeriveCoordinatorTests.testStaleSuccessAfterDismissDoesNotPublish (flaky, order-sensitive), then passed on re-run with that test also passing alone. The shutdown test asserts consistency (reported deletions match what left the grid) rather than an exact count.

## Agent log

- 2026-10-13T19:01:45.104Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Package removal is scheduled off the main actor and each item is published to the grid as its cleanup completes. (pass) — Per-item package-I/O jobs preserve sequential processing and incremental grid updates.
- [x] Removal preserves alreadyRemoved, assetNotFound compatibility, failure summary, and shutdown consistency semantics. (pass) — Existing partial failure, retry, and shutdown tests pass.
- [x] A gated removal does not block a main-actor hop. (pass) — testMainActorStaysResponsiveWhileSessionRemovalIsGated passes.
- [x] A deletion in progress prevents a second deletion from colliding with the active scheduler job. (pass) — Added a single-flight guard and testSecondDeletionBatchIsRejectedWhileAnotherItemIsInFlight.
- [x] Deletion tests cover partial failure and shutdown mid-batch. (pass) — All 13 LibraryDeletionCoordinatorTests pass.
- [x] Swift build is warning-free and Swift 6 concurrency constraints remain satisfied. (pass) — swift build completed without diagnostics; package settings checks passed in the fast lane.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — All 1,811 required fast-lane tests passed.
Checks run:
- swift build (exit 0; no diagnostics)
- swift test --filter LibraryDeletionCoordinatorTests (13 tests, 0 failures)
- scripts/ci-tests.sh fast (1,811 tests, exit 0)
- git diff --check (exit 0)
Findings:
- Concurrent disjoint deletion batches could replace the shared removal scheduler job ID; an earlier package transaction could commit while its continuation reported cancellation, leaving the grid stale.
Fixes:
- Made LibraryDeletionCoordinator deletion single-flight and added regression coverage for a second batch targeting a different item.
Verification commits:
- 2ad0f4a17ddd006e3e62b3190f2a04b4247b4908
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV71HJ047IOCIOPH
Summary: Verification passed; fixed concurrent deletion batches cancelling a shared package-I/O job.
