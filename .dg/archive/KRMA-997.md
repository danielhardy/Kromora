---
id: KRMA-997
title: Validate recovery ownership before rolling back a package transaction
type: bug
status: done
priority: urgent
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: recoverExpiredWriter establishes an exclusive claim, reads the current lease, and checks owner plus expiry before any journal or staging mutation; rejected takeover leaves journal, staging, and lock bytes unchanged
      result: pass
      notes: Reviewed recovery under the package-directory flock and the preserved-lock takeover. The unexpired and concurrent acquisition/recovery tests verify journal, staging, and lock state.
    - criterion: "The unexpired lease probe is a test: an unexpired lease with a staged uncommitted transaction produces contention and leaves the journal present"
      result: pass
      notes: testRecoverExpiredWriterRejectsUnexpiredLeaseWithoutTouchingJournal passes and checks journal count and exact lock bytes.
    - criterion: A writer renewed or replaced after expiry observation survives the recovery contention check
      result: pass
      notes: Renewal tests cover renewal before takeover and a renewal paused after ownership validation while recovery races. They use real package files and separate callers or threads in one process; no second OS process was run.
    - criterion: A dead local writer recovers through recoverDeadWriter before expiry, while recoverExpiredWriter does not roll back a live local writer after expiry
      result: pass
      notes: testDeadLocalWriterRecoversBeforeLeaseExpiryAndRollsBackFirst passes; the live local owner regression preserves the journal and lock bytes.
    - criterion: A failure after the ownership check and before publish leaves recovery retryable and visible to the next opener
      result: pass
      notes: The injected recovery failure preserves lock, journal, and staging state, then retry recovers the interrupted transaction. Added coverage also proves stale abort cannot undo a successful recovery rollback.
    - criterion: swift build is warning-free
      result: pass
      notes: swift build exited 0 with no warnings.
    - criterion: scripts/ci-tests.sh fast exits 0
      result: pass
      notes: The exact final tree passed all 1,947 required fast-lane tests.
  checks_run:
    - swift test --filter PortablePackageTransactionTests — exit 0; 24 tests passed
    - swift test --filter PortablePackageImportTests — exit 0; 10 tests passed
    - swift build — exit 0; no warnings
    - scripts/ci-tests.sh fast — exit 0; 1,947 required tests passed
    - git diff --check and git diff --cached --check — exit 0
    - Reviewed recovery, acquisition, renewal, commit, abort, and import cleanup ownership paths
  findings: []
  fixes:
    - Fenced abort rollback and owner recovery retry with the package ownership fence, so a stale owner fails before replaying its cached journal after takeover.
    - Added testStaleAbortCannotUndoRecoveryRollback to verify the restored target and transaction cleanup survive a stale abort.
    - Changed import cleanup to stop on lease ownership errors and retry recovery only while the current caller still owns the package.
  verification_commits:
    - e2c201a09aa03464c7530be8d6d9d8cb3ca6b4a3
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T19:05:45.894Z
  session: 01MV8GWPSOB8V9J8NR
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - release-readiness
  - readiness-2026-10-14
  - must-fix
  - storage
created: 2026-10-14T16:08:53.671Z
updated: 2026-10-14T19:05:45.897Z
parent: KRMA-994
depends_on:
  - KRMA-1017
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Models/PortablePackageTransaction.swift
    - Sources/KromoraKit/Models/PortableLibrarySession.swift
    - Tests/KromoraKitTests/PortablePackageTransactionTests.swift
  docs:
    - CLAUDE.md
    - docs/STORAGE_POLICY.md
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-994
    - KRMA-998
  commands:
    - swift test --filter PortablePackageTransactionTests
    - scripts/ci-tests.sh fast
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T17:45:28.867Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 2784da66
  - e2c201a09aa03464c7530be8d6d9d8cb3ca6b4a3
---

## Objective

Expired-writer recovery must take exclusive ownership and re-check that exact lease before it rolls back a transaction. A rejected takeover leaves the current writer's journal and staging untouched.

## Context

Ordering bug confirmed on 2026-10-14 with an in-process probe. A two-process race was not reproduced. `PortablePackageLease.recoverExpiredWriter` (`Sources/KromoraKit/Models/PortablePackageTransaction.swift`, around line 292) calls `PortablePackageTransaction.recover` and only then `breakExpired`, which is where `expiresAt <= now` is checked (around line 278).

Probe: unexpired lease, staged uncommitted transaction, `recoverExpiredWriter` at that same time. The journal was removed, then the call threw contention.

The production opener observes expiry in a separate acquisition attempt (`PortableLibrarySession.swift`, around line 260) and later calls recovery. That observation is not exclusive ownership. Another process, or a renewal already in flight, can change the lease before recovery runs. The session's serial queue does not coordinate other processes.

`recoverDeadWriter` (around line 300) is the path for a conclusively dead local writer and may roll back before timestamp expiry. Do not fold that into timestamp expiry. A live local writer must not be rolled back merely because a timestamp expired.

Sibling: KRMA-998 makes `fullSyncDirectory` actually throw. Do not swallow those errors while you are in this file. Existing test `testRecoverExpiredWriterRollsBackThenAllowsANewLease` in `Tests/KromoraKitTests/PortablePackageTransactionTests.swift` must keep passing. Parent epic: KRMA-994. Review finding 3.

## Acceptance criteria

- [ ] `recoverExpiredWriter` establishes an exclusive claim, reads the current lease, and checks owner plus expiry before any journal/staging mutation. A failed check throws contention (or the existing contention error) and leaves the journal, staging, and lock bytes unchanged.
- [ ] The review probe is a test: unexpired lease, staged uncommitted transaction, `recoverExpiredWriter` at the same `now`, contention thrown, journal still present.
- [ ] Add a contention test where expiry was true at the first read and the owner renews or is replaced before rollback. The renewed/replaced writer's transaction survives. Use the real package directory and lease files. Two `PortableLibrarySession` / lease callers in one test are enough when they do not share an in-memory lock; add a second OS process only if same-process callers would hide the race. Say which level you tested in the review comment.
- [ ] A dead local writer still recovers through `recoverDeadWriter`, including when its timestamp has not expired. Do not let `recoverExpiredWriter` roll back a writer that is still alive on this Mac.
- [ ] Add or extend a crash-point test so a failure after the ownership check and before publish does not leave a half-applied recovery that the next opener cannot see. Keep the existing fault injector if it already covers a point; do not delete coverage.
- [ ] `swift build` is warning-free. `scripts/ci-tests.sh fast` exits 0.

## Constraints

- Re-read the cited lines before editing. Line numbers drift.
- Swift 6 language mode stays on. No `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, or `#available` branches. No new dependencies.
- Do not run `scripts/run-kromora-capture.sh`. Display-bound numbers already live in `docs/TESTING.md`.
- Preserve unrelated working-tree changes. Do not revert other tickets' edits.
- One issue at a time. Commit subject starts with this issue id. Hand off at `review`; do not mark `done`.


### Comment — claude @ 2026-10-14T17:45:28.347Z

recoverExpiredWriter now renames manifest.lock to a private claim file (atomic, one winner), re-reads it, and only if expiresAt <= now installs its own fresh recovery lease and rolls back; otherwise it restores the lock with RENAME_EXCL and throws contended before touching journal/staging. Former owner's renew/assertOwnership fail during rollback; rollback failure restores the original expired lock so the next opener still sees the journal. recoverDeadWriter untouched. Tests (PortablePackageTransactionTests, 5 new): unexpired probe (journal+lock bytes unchanged), owner renewed after expiry observed, former-owner fencing via afterClaim seam, 8 concurrent recoverers (same-process, real files; no second OS process — the rename claim is a filesystem primitive so same-process callers don't hide it), failure after ownership check then retry recovers. swift build 0 warnings; ci-tests.sh fast exit 0 (one earlier run hit an unrelated timing flake in EditPersistenceIntegrationTests.testLongGestureCheckpoints..., passes alone and on rerun). Commit a4ce34a0.

### Comment — codex @ 2026-10-14T19:05:30.673Z

Verification review exercised real package directories and lease files with separate lease callers and cross-thread races in one process. No second OS process was run. Tests cover renewal in flight, stale renewal after takeover, ordinary acquisition during recovery, commit/recovery ordering, and stale abort after rollback. The stale-abort data-loss path was fixed in e2c201a0.

## Agent log

- 2026-10-14T18:05:43.238Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [ ] recoverExpiredWriter establishes exclusive ownership and verifies the claimed owner and expiry before mutating journal or staging; rejected takeover leaves them and lock bytes unchanged (fail) — The local-live-writer case is now rejected, but the rename of manifest.lock creates an absent-path interval in which ordinary acquire can win O_EXCL. The ownership transition is also not fenced against a renewal already past assertOwnership.
- [x] The unexpired lease probe throws contention and preserves the staged transaction journal (pass) — testRecoverExpiredWriterRejectsUnexpiredLeaseWithoutTouchingJournal passed; it checks journal count and exact lock bytes.
- [ ] A writer renewed or replaced after expiry observation survives the recovery contention check (fail) — The real-package, same-process renewal test covers renewal completed before recoverExpiredWriter starts, and passes. It does not cover renewal publishing after recoverExpiredWriter claims the old file and installs its recovery lease. No second OS process was run.
- [x] Dead local writers recover through recoverDeadWriter before expiry, while recoverExpiredWriter does not roll back a live local writer after expiry (pass) — The dead-local recovery test passes. Added a real-file regression test proving an expired live local lease returns contention and preserves the journal and lock bytes.
- [x] A failure after the ownership check leaves recovery retryable and visible to the next opener (pass) — The injected afterClaim failure test preserves the journal, then a retry recovers it and restores the prior file.
- [x] swift build is warning-free (pass) — swift build exited 0 with no warnings.
- [x] scripts/ci-tests.sh fast exits 0 (pass) — Final run exited 0 after 1,930 required tests.
Checks run:
- swift test --filter PortablePackageTransactionTests — exit 0; 17 tests passed
- swift test --filter ExpiredWriterLease — exit 0; 4 tests passed
- swift test --filter AppLaunchTests/testLaunchOpensLibraryWhenTakeoverAccepted — exit 0; 1 test passed
- swift build — exit 0; no warnings
- scripts/ci-tests.sh fast — exit 0; 1,930 required tests passed
- git diff --cached --check — exit 0
- Reviewed recoverExpiredWriter, renew, writeDurably, acquire, and PortableLibrarySession.acquireWriterLease; race analysis was static and not reproduced
Findings:
- blocker: recoverExpiredWriter renames manifest.lock to a private claim path, leaving the normal lock path absent until it creates a fresh recovery lease. An ordinary acquire can win O_EXCL in that interval, then recovery sees contention and drops the claim; the new session can proceed while the old interrupted journal remains.
- blocker: renew validates the old owner in assertOwnership, then later publishes through writeDurably using replaceItemAt. If recovery installs its lease after that validation but before replacement, the in-flight renewal can overwrite the recovery lease with the former owner record. That owner can then pass assertOwnership and publish while recovery is rolling back.
Fixes:
- Added a guard that restores the claimed lock and returns contention when an expired lease belongs to a process still alive on this Mac.
- Added real-file coverage for the expired live-local-owner case and updated stale-writer fixtures to represent remote identities accurately.
Verification commits:
- 2784da66
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV8EHTA28IWM5Y3K
Summary: Partial verification: live local writers are now protected and the declared checks pass, but lease renewal and ordinary acquisition can still defeat the recovery ownership fence.

- 2026-10-14T19:05:45.894Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] recoverExpiredWriter establishes an exclusive claim, reads the current lease, and checks owner plus expiry before any journal or staging mutation; rejected takeover leaves journal, staging, and lock bytes unchanged (pass) — Reviewed recovery under the package-directory flock and the preserved-lock takeover. The unexpired and concurrent acquisition/recovery tests verify journal, staging, and lock state.
- [x] The unexpired lease probe is a test: an unexpired lease with a staged uncommitted transaction produces contention and leaves the journal present (pass) — testRecoverExpiredWriterRejectsUnexpiredLeaseWithoutTouchingJournal passes and checks journal count and exact lock bytes.
- [x] A writer renewed or replaced after expiry observation survives the recovery contention check (pass) — Renewal tests cover renewal before takeover and a renewal paused after ownership validation while recovery races. They use real package files and separate callers or threads in one process; no second OS process was run.
- [x] A dead local writer recovers through recoverDeadWriter before expiry, while recoverExpiredWriter does not roll back a live local writer after expiry (pass) — testDeadLocalWriterRecoversBeforeLeaseExpiryAndRollsBackFirst passes; the live local owner regression preserves the journal and lock bytes.
- [x] A failure after the ownership check and before publish leaves recovery retryable and visible to the next opener (pass) — The injected recovery failure preserves lock, journal, and staging state, then retry recovers the interrupted transaction. Added coverage also proves stale abort cannot undo a successful recovery rollback.
- [x] swift build is warning-free (pass) — swift build exited 0 with no warnings.
- [x] scripts/ci-tests.sh fast exits 0 (pass) — The exact final tree passed all 1,947 required fast-lane tests.
Checks run:
- swift test --filter PortablePackageTransactionTests — exit 0; 24 tests passed
- swift test --filter PortablePackageImportTests — exit 0; 10 tests passed
- swift build — exit 0; no warnings
- scripts/ci-tests.sh fast — exit 0; 1,947 required tests passed
- git diff --check and git diff --cached --check — exit 0
- Reviewed recovery, acquisition, renewal, commit, abort, and import cleanup ownership paths
Findings:
- None
Fixes:
- Fenced abort rollback and owner recovery retry with the package ownership fence, so a stale owner fails before replaying its cached journal after takeover.
- Added testStaleAbortCannotUndoRecoveryRollback to verify the restored target and transaction cleanup survive a stale abort.
- Changed import cleanup to stop on lease ownership errors and retry recovery only while the current caller still owns the package.
Verification commits:
- e2c201a09aa03464c7530be8d6d9d8cb3ca6b4a3
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV8GWPSOB8V9J8NR
Summary: Verification passed after fencing stale abort cleanup; all required checks succeeded.
