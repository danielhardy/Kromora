---
id: KRMA-934
title: Move legacy open-time source-fingerprint repair out of the photo-open main-actor path
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: materializedAsset returns resolved asset without waiting for scheduled durable repair
      result: pass
      notes: The regression test gates the repair and confirms materializedAsset returns before release.
    - criterion: In-memory index reflects the repaired fingerprint; failures are logged and do not fail open
      result: pass
      notes: Scheduled path updates the index after package commit. Verification fix also makes scheduler-less fallback log and absorb transaction/index errors.
    - criterion: Repair is idempotent, cancellable at shutdown, and coalesced per asset
      result: pass
      notes: Per-asset pending job IDs coalesce repeated opens and shutdown cancels/waits for pending repair jobs.
    - criterion: Regression tests cover return-before-commit, durable repair, and shutdown with repair pending
      result: pass
    - criterion: swift build is warning-free and Swift 6 mode has no prohibited escape hatches
      result: pass
      notes: swift build completed with no diagnostics.
    - criterion: scripts/ci-tests.sh fast exits 0
      result: pass
      notes: Fast CI completed all 1815 required fast tests; testSlowMaterializationCannotReopenSupersededPhoto passed.
  checks_run:
    - swift build (exit 0; warning-free)
    - scripts/ci-tests.sh fast (exit 0; 1815 required fast tests passed)
  findings:
    - The scheduler-less fallback propagated fingerprint repair errors, which could fail photo open; fixed during verification.
  fixes:
    - Scheduler-less repair now logs source fingerprint repair failures with os.Logger and allows photo open to return.
  verification_commits:
    - 491c841be90299d2c0b92b0823ab671ee28c6f5c
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T19:18:41.434Z
  session: 01MV729E4V54J3CZLD
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - must-fix
  - performance
  - package
created: 2026-10-13T14:47:44.558Z
updated: 2026-10-13T19:18:41.438Z
parent: KRMA-922
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T19:15:15.453Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 491c841be90299d2c0b92b0823ab671ee28c6f5c
---

## Objective

Opening a legacy photo must not perform a durable package write transaction on the main actor.

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

Specific to open-time repair:

- `PortableLibrarySession.materializedAsset(for:)` (`async throws`, ~L1344) resolves the asset; at
  ~L1385 if `summary.sourceFingerprint != resolved.source.portableIdentity.sourceFingerprint` it calls
  `package.replaceSourceFingerprint(for:with:lease:now:)` (a write transaction) and then
  `applyIndexDelta(...)`, inline on the main actor, during photo open.
- This only triggers for legacy/placeholder records; the goal is that open returns the resolved asset
  without waiting for the durable write.

## Acceptance criteria

- [ ] `materializedAsset` returns the resolved `PhotoAsset` immediately and schedules the
      `replaceSourceFingerprint` + `applyIndexDelta` repair via `enqueuePackageIO` (background priority;
      reuse `sourceFingerprintBackfillJobID` if its semantics fit, otherwise add a job id).
- [ ] The in-memory index entry reflects the repaired fingerprint once the repair completes; a repair
      that fails is logged (os_log, not `print`) and does not fail the open.
- [ ] The repair is idempotent and cancellable at shutdown; repeated opens of the same asset do not
      enqueue duplicate jobs (coalesce by asset id).
- [ ] Tests: using the existing `materializationGate`/legacy-placeholder helpers in
      `StoredEditAdoptionTests.swift`, a legacy open (a) returns before the repair commits (gate the
      repair), (b) the package eventually holds the repaired fingerprint, (c) shutdown with the repair
      pending does not hang.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).

## Implementation notes

Keep the existing `assert(...)` that follows (the index entry fingerprint check) valid or adapt it to
the deferred repair. Do not touch culling, virtual copy or delete paths.


### Comment — claude @ 2026-10-13T19:15:14.952Z

Implemented in 562a1905: PortableLibrarySession.repairSourceFingerprintOnOpen schedules replaceSourceFingerprint + applyIndexDelta on the package-I/O lane (background, per-asset job id, coalesced, cancelled in shutdown, os Logger on failure); scheduler-less sessions repair inline. The trailing assert was removed since the index entry now updates when the repair commits. Tests added in StoredEditAdoptionTests (open returns while repair gated, disk holds repaired fingerprint, shutdown with pending repair). swift build warning-free; scripts/ci-tests.sh fast exit 0 (testSlowMaterializationCannotReopenSupersededPhoto passed).

## Agent log

- 2026-10-13T19:18:41.434Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] materializedAsset returns resolved asset without waiting for scheduled durable repair (pass) — The regression test gates the repair and confirms materializedAsset returns before release.
- [x] In-memory index reflects the repaired fingerprint; failures are logged and do not fail open (pass) — Scheduled path updates the index after package commit. Verification fix also makes scheduler-less fallback log and absorb transaction/index errors.
- [x] Repair is idempotent, cancellable at shutdown, and coalesced per asset (pass) — Per-asset pending job IDs coalesce repeated opens and shutdown cancels/waits for pending repair jobs.
- [x] Regression tests cover return-before-commit, durable repair, and shutdown with repair pending (pass)
- [x] swift build is warning-free and Swift 6 mode has no prohibited escape hatches (pass) — swift build completed with no diagnostics.
- [x] scripts/ci-tests.sh fast exits 0 (pass) — Fast CI completed all 1815 required fast tests; testSlowMaterializationCannotReopenSupersededPhoto passed.
Checks run:
- swift build (exit 0; warning-free)
- scripts/ci-tests.sh fast (exit 0; 1815 required fast tests passed)
Findings:
- The scheduler-less fallback propagated fingerprint repair errors, which could fail photo open; fixed during verification.
Fixes:
- Scheduler-less repair now logs source fingerprint repair failures with os.Logger and allows photo open to return.
Verification commits:
- 491c841be90299d2c0b92b0823ab671ee28c6f5c
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV729E4V54J3CZLD
Summary: Verified the off-main source-fingerprint repair. Fixed scheduler-less repair failures so they are logged without failing photo open; build and fast CI passed.
