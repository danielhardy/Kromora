---
id: KRMA-516
title: Renew the package writer lease for long-lived editing sessions
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Short injected-clock lease test keeps edits/imports writable beyond two lease durations
      result: pass
      notes: PortableLibrarySessionTests.testShortLeaseHeartbeatKeepsImportsWritablePastTwoDurations drives wake renewals on a short lease and imports successfully.
    - criterion: Shutdown cancels and awaits heartbeat before lease release
      result: pass
      notes: Per-job scheduler cancellation barrier plus PortableLibrarySession shutdown ordering; regression test confirms lock release and no post-shutdown renewal.
    - criterion: Contention/deleted/stolen/sleep-past-expiry loss is distinct and safe
      result: pass
      notes: Current-session ownership loss is surfaced as PortablePackageLeaseError.lostDuringSession; stale acquisition remains expired and explicit recovery only.
    - criterion: Long imports/backups renew before transactions and publication
      result: pass
      notes: Imports renew before each transaction; backups renew before snapshot work, at file boundaries, and before publication.
    - criterion: Fast and relevant package/session tests pass without real sleeps
      result: pass
      notes: scripts/ci-tests.sh fast passed 1126/1126; focused package/session/transaction/scheduler suite passed 63/63; injected clock tests suspend heartbeat without real waiting.
  checks_run:
    - swift build
    - git diff --check
    - swift test --filter 'PortableLibrary(Session|Backup|Restore|Package|Validation|EndToEndRegression)Tests|PortablePackage(Import|Transaction|Trash|Maintenance)Tests|ApplicationShellCoordinatorTests|ImageWorkSchedulerTests'
    - scripts/ci-tests.sh fast
    - dg validate
  findings:
    - Existing dg validate warnings report unknown historical gpt-5.6-luna model names; validation itself passes.
  fixes:
    - Added session-owned one-third-duration heartbeat on the shared package-I/O lane with injectable clock/sleep and wake renewal.
    - Added current-session loss fencing and actionable error text without changing stale previous-session recovery.
    - Added import/backup opportunistic renewal and application shutdown ordering.
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-21T21:29:23.403Z
  session: 01MUBQKTQGW3Y4NS74
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - correctness
  - package
created: 2026-09-21T20:32:58.406Z
updated: 2026-09-21T21:29:23.406Z
estimate: 3
order: n
board: product
---

## Objective

Keep the package writer lease valid for the lifetime of an editing session so edits, imports, culling state, and removals continue to persist after the current three-minute lease duration.

## Context and evidence

PortableLibrarySession acquires PortablePackageLease with a 180-second default duration, but only PortableLibraryRestore renews leases. Every normal write eventually calls PortablePackageTransaction.begin and lease.assertOwnership, so a session opened for more than about three minutes starts failing writes with an error that incorrectly suggests an unclean previous session. Probe tests confirmed both import and appendEditRevision fail after advancing an injected clock by 240 seconds; imports currently surface this as a per-item failure and can look successful to the user.

The main checkout may contain unrelated in-progress KRMA-511–515 edits. Start from a clean main or coordinate with those changes before touching shared views.

## Scope

- Add a session-owned heartbeat that renews at approximately one third of the lease duration.
- Run renewal on the existing package-I/O lane, make the duration/clock injectable, and cancel plus await the heartbeat during shutdown.
- Renew opportunistically before long transactions such as large imports and backups.
- Distinguish a lease lost during the current session from stale-previous-session takeover. Never break a lease owned by another writer.
- Define sleep/wake behavior: renew immediately after wake when ownership is still valid; otherwise stop writes, retain dirty snapshots, and expose an actionable error/banner.
- Cover release ordering so shutdown cannot start another write after the lease is released.

## Acceptance criteria

- [ ] A short-duration injected-clock test proves edits and imports commit after more than twice the lease duration.
- [ ] Shutdown cancels and awaits the heartbeat, and no renewal or write occurs after lease release.
- [ ] Contention, deleted-lock, stolen-lock, and sleep-past-expiry cases produce a distinct lostDuringSession-style error without silent data loss or unsafe lease breaking.
- [ ] Long imports/backups renew before entering the transaction.
- [ ] The fast test lane and relevant package transaction/session tests pass without real sleeps.

## Dependencies and coordination

This is the first item in the package correctness chain. CQ-02 depends on its outcome. Preserve the single-writer invariant and the existing O_EXCL lease acquisition behavior.

## Likely files and checks

PortablePackageTransaction.swift, PortableLibrarySession.swift, ApplicationShellCoordinator.swift, AppViewModel shutdown ordering, and package/session tests. Use the existing ImageWorkScheduler package-I/O lane and fault-injection/test-clock patterns.

## Agent log

- 2026-09-21T21:29:23.404Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Short injected-clock lease test keeps edits/imports writable beyond two lease durations (pass) — PortableLibrarySessionTests.testShortLeaseHeartbeatKeepsImportsWritablePastTwoDurations drives wake renewals on a short lease and imports successfully.
- [x] Shutdown cancels and awaits heartbeat before lease release (pass) — Per-job scheduler cancellation barrier plus PortableLibrarySession shutdown ordering; regression test confirms lock release and no post-shutdown renewal.
- [x] Contention/deleted/stolen/sleep-past-expiry loss is distinct and safe (pass) — Current-session ownership loss is surfaced as PortablePackageLeaseError.lostDuringSession; stale acquisition remains expired and explicit recovery only.
- [x] Long imports/backups renew before transactions and publication (pass) — Imports renew before each transaction; backups renew before snapshot work, at file boundaries, and before publication.
- [x] Fast and relevant package/session tests pass without real sleeps (pass) — scripts/ci-tests.sh fast passed 1126/1126; focused package/session/transaction/scheduler suite passed 63/63; injected clock tests suspend heartbeat without real waiting.
Checks run:
- swift build
- git diff --check
- swift test --filter 'PortableLibrary(Session|Backup|Restore|Package|Validation|EndToEndRegression)Tests|PortablePackage(Import|Transaction|Trash|Maintenance)Tests|ApplicationShellCoordinatorTests|ImageWorkSchedulerTests'
- scripts/ci-tests.sh fast
- dg validate
Findings:
- Existing dg validate warnings report unknown historical gpt-5.6-luna model names; validation itself passes.
Fixes:
- Added session-owned one-third-duration heartbeat on the shared package-I/O lane with injectable clock/sleep and wake renewal.
- Added current-session loss fencing and actionable error text without changing stale previous-session recovery.
- Added import/backup opportunistic renewal and application shutdown ordering.
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUBQKTQGW3Y4NS74
Summary: Implemented session-owned package lease heartbeat, loss fencing, long-operation renewals, wake handling, and shutdown ordering.
