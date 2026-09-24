---
id: KRMA-556
title: Recover a killed local package writer without waiting for the lease timeout
type: bug
status: verification
priority: urgent
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - stability
  - library
  - lease
created: 2026-09-23T15:17:37.655Z
updated: 2026-09-23T23:10:19.243Z
order: zv
board: product
---

## Objective

Recover a portable library promptly after the local `swift run` process is force-quit, while preserving the single-writer guarantee and never taking a lock from a live writer.

## User report

With `swift run`, Kromora opens and then the cursor remains a spinning rainbow ball. After force-quitting, the next launch reports that `/Users/dhardy/Pictures/Kromora Library.kromoralibrary` is already being written by “Daniel’s Mac mini” (PID 63740). The user can dismiss the alert, but Kromora cannot use the library.

The PID and device label are from the user’s error message; the process state and package contents have not been independently inspected.

## Code evidence

- `PortablePackageLease.defaultDuration` is 180 seconds. `acquire` returns `.contended` whenever an existing lock’s `expiresAt` is still in the future.
- `AppViewModel.openPortableLibrarySession` only invokes recovery after `.expired`. Although `PortablePackageLeaseInfo.writerProcessIsGone` checks the PID, that check is only reached for an expired lease. A process killed before its lease expires therefore blocks a local relaunch until expiry.
- Normal shutdown releases the lease, but force-quit/crash cannot run that cleanup. The lock file remains until recovery removes it.
- Recovery must run `PortablePackageTransaction.recover` before removing an expired lock.

## Scope

- Establish a reliable same-host owner identity and process-liveness check that distinguishes a dead writer from an active process and protects against PID reuse.
- Permit safe recovery of a provably dead local writer without waiting for the lease timestamp to expire.
- Preserve contention for a live local process and for a writer on another host when its liveness cannot be proven locally. Do not use the display device name or PID alone as a cross-host identity.
- Recover interrupted transactions before acquiring the replacement lease; surface a clear actionable error if ownership cannot be determined safely.
- Cover the `swift run` force-quit/relaunch path with deterministic lease/session tests. Do not change the package format without compatibility coverage.

## Acceptance criteria

- [ ] A lock owned by a terminated local process is recoverable immediately even when `expiresAt` is in the future.
- [ ] A lock owned by a live local process remains contended and is never removed.
- [ ] A remote-host lock is not treated as a dead local process; ambiguous ownership remains safe and actionable.
- [ ] Recovery rolls back any interrupted transaction before a new session can write.
- [ ] Tests cover local process exit before expiry, active process contention, stale recovery, and PID-reuse/identity behavior.
- [ ] A manual `swift run` force-quit/relaunch check opens the library without requiring a fixed timeout and reports recovery clearly.

## Likely files and checks

`PortablePackageTransaction.swift`, `PortableLibrarySession.swift`, `AppViewModel.swift`, `AppDelegate` shutdown/launch path, `PortablePackageTransactionTests.swift`, `PortableLibrarySessionTests.swift`, and `AppViewModelTests.swift`. Run focused lease/session tests, then the documented fast lane; manually exercise a forced process termination and immediate relaunch.

## Related observations

The reported unresponsive launch and the misleading zero-import result have separate tickets so their main-thread and presentation fixes can be reviewed independently. No production logs or crash report were supplied, so confirm the beachball’s main-thread stack before attributing it to a specific call.


### Comment — codex @ 2026-09-23T15:36:58.421Z

Implemented same-host writer identity using kern.uuid plus the exact process start token, allowing immediate recovery only when the identified local process is gone. Recovery rolls back interrupted transactions before replacing the lease, leaves live and ambiguous/remote owners contended, and surfaces recovery in the launch status. Added dead-before-expiry, live contention, remote identity, PID reuse, rollback ordering, and launch-path coverage. Focused tests passed (9 tests). Fast lane reached all 1,175 cases but failed on DevelopInspectorTests.testHistogramFollowsTheDisplayedComparisonRequest timing out; the same test failed when rerun alone. Manual swift run force-quit/relaunch was not run against the real user library.
