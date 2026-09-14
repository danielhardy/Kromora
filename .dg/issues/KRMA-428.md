---
id: KRMA-428
title: "KRMA-415 verification: crash-safe quarantine sweep, scheduler-rejection retry, and maintenance scheduling wiring"
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: An interrupted maintenance run that leaves an orphaned Recovery/Quarantine/Maintenance/<uuid> directory is cleaned up by a subsequent run, verified by test.
      result: pass
      notes: sweepOrphanedMaintenanceQuarantine runs before compaction, stages each orphan for journaled removal via a real transaction; testMaintenanceSweepsOrphanedQuarantineDirectoryFromAnInterruptedPass and testAppActivationTriggersConfiguredPortableMaintenance both cover it.
    - criterion: A .rejected admission outcome is logged and retried like a failed pass, verified by test.
      result: pass
      notes: enqueueAttempt onTerminal handler now handles .rejected by logging to failureLog and calling scheduleRetry (bounded by retryLimit, 50ms backoff via a cancellable MainActor Task); testMaintenanceCoordinatorRetriesSchedulerRejectionAfterQueueDrains exercises the full reject-then-drain-then-succeed path.
    - criterion: PortablePackageMaintenance is actually invoked somewhere in the running app, with a cadence documented in a code comment or doc, and an end-to-end test covering that trigger.
      result: pass
      notes: AppViewModel wires schedulePortablePackageMaintenance() off didBecomeActiveNotification with a documented 2s idle delay (portableMaintenanceIdleDelay), gated on manifest.json existing and the job not already running; shutdown() cancels the pending trigger task and in-flight retries. testAppActivationTriggersConfiguredPortableMaintenance is a real end-to-end AppViewModel test, not just a coordinator-level test.
    - criterion: A test demonstrates package-I/O maintenance yields to concurrent editor-visible scheduler work.
      result: pass
      notes: testQueuedMaintenanceYieldsToEditorArrivingWhilePackageIOIsBusy in ImageWorkSchedulerTests shows a queued maintenance job runs only after a concurrently-arriving higher-priority editor job, and asserts yieldedPackageIOCount > 0.
    - criterion: swift build, swift test, dg validate, and git diff --check pass.
      result: pass
      notes: swift build clean; scripts/ci-tests.sh fast (1014 tests) and serial (375 tests) both pass with 0 failures; dg validate OK (pre-existing unrelated model-name warnings only); git diff --check clean.
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast (1014 tests, 0 failures)
    - scripts/ci-tests.sh serial (375 tests, 0 failures)
    - dg validate
    - git diff --check
    - manual review of PortablePackageMaintenance.swift, AppViewModel.swift wiring, and PortablePackageTransaction.stageRemoval/commit semantics
    - confirmed ImageWorkScheduler and PortablePackageMaintenance are both @MainActor so onTerminal(.rejected) is delivered synchronously within enqueue, matching test expectations
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T23:20:04.348Z
  session: 01MU0FM3O9LLYRFGNP
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - library
  - architecture
created: 2026-09-13T18:30:02.102Z
updated: 2026-09-13T23:20:04.350Z
parent: KRMA-415
depends_on:
  - KRMA-415
order: a0
board: product
---

## Objective

KRMA-415's revision/packed-thumbnail maintenance compaction (commit 7ad3f99, hardened further by
KRMA-415's counterpoint verification pass) is correct and crash-safe for the scenarios it's
exercised against, but three gaps remain around the edges of "runs as background scheduler work
that never turns a rebuildable artifact into an integrity failure":

1. **Orphaned quarantine directories across process restarts.** Revision compaction quarantines
   stale edit-revision sidecars under `Recovery/Quarantine/Maintenance/<uuid>` in one transaction,
   then permanently deletes that directory in a second, journaled `stageRemoval` transaction (fixed
   during counterpoint verification to replace a raw best-effort `FileManager.removeItem`). That
   makes the delete itself crash-safe, but nothing sweeps a `Recovery/Quarantine/Maintenance/*`
   directory left behind if the process stops between the two transactions (or before the second
   one's journal is even written) — the next maintenance pass only inspects live `asset.json`
   pointers, generates a fresh UUID for anything it finds newly stale, and never revisits an old
   orphaned UUID directory. Over many interrupted runs this leaks space, the exact thing
   compaction exists to reclaim.
2. **Scheduler-rejection is a silent no-op.** `PortablePackageMaintenance.enqueue`'s `onTerminal`
   handler only reacts to `.completed`/`.cancelled`; a `.rejected` outcome (package-I/O queue full)
   falls through without logging, without invoking `completion`, and without scheduling a retry.
   Queue-full is exactly the "under contention" scenario the acceptance criteria call out
   ("yields to editor-visible work under contention" + "a failed or interrupted maintenance pass is
   retried"), and it's currently the one outcome that isn't retried.
3. **Nothing calls `PortablePackageMaintenance` in the app.** The type and its scheduler wiring are
   fully implemented and unit-tested, but no coordinator/timer actually enqueues it — it's reachable
   only from tests. Someone needs to decide the cadence (app-active idle timer? on package open?) and
   wire it in, or this ticket's acceptance criteria are only proven in principle.

None of this is a data-loss risk today (everything here is rebuildable-tier per KRMA-415's scope,
and the feature is inert until wired up), so it does not block KRMA-415.

## Scope

- Add an orphan sweep for `Recovery/Quarantine/Maintenance/*` (e.g. at the start of
  `PortablePackageMaintenance.run`, alongside the existing `PortablePackageTransaction.recover`
  call): any directory there not part of the current pass gets staged for removal via
  `stageRemoval` and committed, so interrupted runs self-heal on the next pass.
- Handle `.rejected` in `PortablePackageMaintenance.enqueue`'s `onTerminal`: log it and schedule a
  retry (subject to the existing `retryLimit`), consistent with how `.completed`-with-failure is
  handled today.
- Decide and implement where/when `PortablePackageMaintenance.enqueue` is actually triggered in the
  running app (see `AppViewModel`/coordinators), and add a test that exercises it end-to-end (not
  just the coordinator in isolation).
- Add the "scheduler-fairness check under simultaneous editor activity" called for by KRMA-415's own
  verification lane description, which the merged tests don't yet cover.

## Acceptance criteria

- [ ] An interrupted maintenance run that leaves an orphaned `Recovery/Quarantine/Maintenance/<uuid>`
  directory is cleaned up by a subsequent run, verified by test.
- [ ] A `.rejected` admission outcome is logged and retried like a failed pass, verified by test.
- [ ] `PortablePackageMaintenance` is actually invoked somewhere in the running app, with a cadence
  documented in a code comment or doc, and an end-to-end test covering that trigger.
- [ ] A test demonstrates package-I/O maintenance yields to concurrent editor-visible scheduler work.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Implementation notes

Non-blocking; batch with other portable-package maintenance follow-up work rather than treating as
urgent — nothing here is reachable from the running app yet.

### Comment — codex @ 2026-09-13T23:14:55.041Z

Implemented in commit 4087a35. Added journaled orphan quarantine sweeping, scheduler-rejection logging with bounded delayed retries, app-activation maintenance wiring with a documented 2-second idle cadence, and scheduler fairness coverage. Verification: swift build, full swift test --no-parallel (1,439 executed, 53 skipped, 0 failures), dg validate, and git diff --check all pass.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

Found during KRMA-415 counterpoint verification. `swift build`/`swift test --no-parallel`/
`dg validate`/`git diff --check` all pass on KRMA-415 as verified (including a same-session fix
that replaced the best-effort quarantine delete with a journaled `stageRemoval` transaction), so
none of the above is a correctness regression in the merged code — these are coverage/robustness
gaps at the edges of the interruption and contention scenarios the ticket's own verification lane
called for.

- 2026-09-13T23:20:04.348Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] An interrupted maintenance run that leaves an orphaned Recovery/Quarantine/Maintenance/<uuid> directory is cleaned up by a subsequent run, verified by test. (pass) — sweepOrphanedMaintenanceQuarantine runs before compaction, stages each orphan for journaled removal via a real transaction; testMaintenanceSweepsOrphanedQuarantineDirectoryFromAnInterruptedPass and testAppActivationTriggersConfiguredPortableMaintenance both cover it.
- [x] A .rejected admission outcome is logged and retried like a failed pass, verified by test. (pass) — enqueueAttempt onTerminal handler now handles .rejected by logging to failureLog and calling scheduleRetry (bounded by retryLimit, 50ms backoff via a cancellable MainActor Task); testMaintenanceCoordinatorRetriesSchedulerRejectionAfterQueueDrains exercises the full reject-then-drain-then-succeed path.
- [x] PortablePackageMaintenance is actually invoked somewhere in the running app, with a cadence documented in a code comment or doc, and an end-to-end test covering that trigger. (pass) — AppViewModel wires schedulePortablePackageMaintenance() off didBecomeActiveNotification with a documented 2s idle delay (portableMaintenanceIdleDelay), gated on manifest.json existing and the job not already running; shutdown() cancels the pending trigger task and in-flight retries. testAppActivationTriggersConfiguredPortableMaintenance is a real end-to-end AppViewModel test, not just a coordinator-level test.
- [x] A test demonstrates package-I/O maintenance yields to concurrent editor-visible scheduler work. (pass) — testQueuedMaintenanceYieldsToEditorArrivingWhilePackageIOIsBusy in ImageWorkSchedulerTests shows a queued maintenance job runs only after a concurrently-arriving higher-priority editor job, and asserts yieldedPackageIOCount > 0.
- [x] swift build, swift test, dg validate, and git diff --check pass. (pass) — swift build clean; scripts/ci-tests.sh fast (1014 tests) and serial (375 tests) both pass with 0 failures; dg validate OK (pre-existing unrelated model-name warnings only); git diff --check clean.
Checks run:
- swift build
- scripts/ci-tests.sh fast (1014 tests, 0 failures)
- scripts/ci-tests.sh serial (375 tests, 0 failures)
- dg validate
- git diff --check
- manual review of PortablePackageMaintenance.swift, AppViewModel.swift wiring, and PortablePackageTransaction.stageRemoval/commit semantics
- confirmed ImageWorkScheduler and PortablePackageMaintenance are both @MainActor so onTerminal(.rejected) is delivered synchronously within enqueue, matching test expectations
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU0FM3O9LLYRFGNP
Summary: Verified KRMA-428: orphan quarantine sweep, scheduler-rejection retry, and app-activation maintenance wiring are correct, well-isolated, and fully tested; no fixes needed.
