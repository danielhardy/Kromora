---
id: KRMA-412
title: "Phase 4.2: library restore with full pre-replace validation"
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Restore never replaces the active package until the candidate validates completely.
      result: pass
      notes: Staged copy is fully re-validated (checksums, canonical references, index rebuild, every edit revision) before the rename-publish boundary.
    - criterion: A failed validation leaves the active package untouched and reports the specific failure.
      result: pass
      notes: Verified via testFailedValidationLeavesActivePackageUntouchedAndReportsFailure; typed PortableLibraryRestoreError surfaces the specific cause.
    - criterion: A clean-profile restore reproduces every edit exactly, verified by an automated test.
      result: pass
      notes: testRestoreRebuildsCleanIndexAndPreservesEveryEditRepresentation rebuilds the index from shards into an empty profile and compares native+XMP sidecars byte-for-byte.
    - criterion: Cancellation during restore leaves the active package in its prior, untouched state.
      result: pass
      notes: Verified via testCancellationDuringRestoreDoesNotReplaceActivePackage; final cancellation check precedes the publish rename.
    - criterion: swift build, swift test, dg validate, and git diff --check pass.
      result: pass
      notes: Re-ran after the fix below; focused PortableLibrary*/PortablePackage* lane 28/28, PackageSettingsTests 3/3, dg validate --json ok (pre-existing unrelated model-name warnings only), git diff --check clean.
  checks_run:
    - swift build
    - swift test --filter PortableLibrary|PortablePackage (28/28 pass)
    - swift test --filter PackageSettingsTests (3/3 pass)
    - dg validate --json
    - git diff --check
    - manual repro test proving the lease-leak bug before the fix, then confirming it passes after the fix
  findings:
    - "HIGH correctness: Successful restore orphaned the candidate lease lock, permanently bricking the newly active package for writes. Sources/KromoraKit/Models/PortableLibraryRestore.swift: the candidate lease was acquired at the staging path, publish() renamed staging onto active, then the lease was released via candidateLease.release() which still pointed at the staging path. Since that path no longer existed post-rename, release() silently no-op'd instead of removing the lock, so the lock file that moved to the new active path (owned by the candidate's ownerID) was never removed. Any subsequent PortablePackageLease.acquire on the restored active package (import, edit, backup, another restore) failed with 'already being written' for the full 180s lease duration and required manual lease-breaking after. Not caught by existing tests because none attempted a write against the active package after a successful restore. Reproduced with a temporary test performing a successful restore then immediately acquiring a lease on the active package; it failed with PortablePackageLeaseError.contended before the fix."
  fixes:
    - "Sources/KromoraKit/Models/PortablePackageTransaction.swift: added PortablePackageLease.release(movedTo:), which releases the lease against a lock file relocated by an atomic directory rename rather than the lease's original packageRoot."
    - "Sources/KromoraKit/Models/PortableLibraryRestore.swift: after a successful publish(), release the candidate lease via release(movedTo: active) instead of the stale staging path; on a failed publish, still release at the original staging path since nothing moved."
    - "Tests/KromoraKitTests/PortableLibraryRestoreTests.swift: extended testRestoreRebuildsCleanIndexAndPreservesEveryEditRepresentation to assert the restored active package can be re-leased for a write immediately after restore, guarding against regression of the orphaned-lease bug."
  verification_commits:
    - f803e8b
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T15:49:00.890Z
  session: 01MTZZI8R6VENNHG7Z
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - backup
  - recovery
created: 2026-09-12T19:44:24.777Z
updated: 2026-09-13T15:49:00.892Z
depends_on:
  - KRMA-411
order: a0
board: product
commits:
  - f803e8b
---

## Objective

Implement restore: a backup (or any package copy) is only promoted to the active library after it
validates completely, and a clean profile restoring it reproduces every edit exactly.

## Dependencies

- The backup ticket (restore consumes what it produces; the validation logic sibling ticket defines
  the checks restore relies on — coordinate ordering with whichever lands first, but restore must not
  ship without validation available).

## Scope

- Implement a restore flow that takes a backup (or package copy) location and validates it completely
  before making it the active library — the currently-active package must never be replaced with an
  unvalidated or partially-valid candidate.
- On validation failure, restore must fail cleanly, leaving the currently-active package untouched
  and reporting what failed.
- On success, verify from a clean profile (no prior local index/cache) that the restored package
  reproduces every edit exactly, using the index-rebuild-from-shards mechanism from KRMA-392.
- Support cancellation during restore with no partial replacement of the active package.

## Acceptance criteria

- [ ] Restore never replaces the active package until the candidate validates completely.
- [ ] A failed validation leaves the active package untouched and reports the specific failure.
- [ ] A clean-profile restore reproduces every edit exactly (content-level comparison against the
  pre-backup state), verified by an automated test.
- [ ] Cancellation during restore leaves the active package in its prior, untouched state.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Backup/restore fault-injection lane: clean-profile restore correctness, validation-failure handling,
and cancellation-safety of the active package.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-393, KRMA-392


### Comment — codex @ 2026-09-13T15:44:04.484Z

Implemented validated library restore in f315196. Restore verifies backup metadata/checksums and canonical references, stages beside the active package, rebuilds a clean index from membership shards, validates every native/XMP edit revision, and atomically publishes only after all gates pass. Cancellation and validation failure leave the active package untouched. Checks: swift build PASS; focused backup/restore/package/index lane 25/25 PASS; restore lane 3/3 PASS; dg validate --json PASS with pre-existing model-name warnings; git diff --check PASS. Full swift test --no-parallel completed 1,419 tests / 53 skips with 14 failures in known asynchronous Auto/export/filmstrip/thumbnail lanes unrelated to this change.

## Agent log

- 2026-09-13T15:49:00.890Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Restore never replaces the active package until the candidate validates completely. (pass) — Staged copy is fully re-validated (checksums, canonical references, index rebuild, every edit revision) before the rename-publish boundary.
- [x] A failed validation leaves the active package untouched and reports the specific failure. (pass) — Verified via testFailedValidationLeavesActivePackageUntouchedAndReportsFailure; typed PortableLibraryRestoreError surfaces the specific cause.
- [x] A clean-profile restore reproduces every edit exactly, verified by an automated test. (pass) — testRestoreRebuildsCleanIndexAndPreservesEveryEditRepresentation rebuilds the index from shards into an empty profile and compares native+XMP sidecars byte-for-byte.
- [x] Cancellation during restore leaves the active package in its prior, untouched state. (pass) — Verified via testCancellationDuringRestoreDoesNotReplaceActivePackage; final cancellation check precedes the publish rename.
- [x] swift build, swift test, dg validate, and git diff --check pass. (pass) — Re-ran after the fix below; focused PortableLibrary*/PortablePackage* lane 28/28, PackageSettingsTests 3/3, dg validate --json ok (pre-existing unrelated model-name warnings only), git diff --check clean.
Checks run:
- swift build
- swift test --filter PortableLibrary|PortablePackage (28/28 pass)
- swift test --filter PackageSettingsTests (3/3 pass)
- dg validate --json
- git diff --check
- manual repro test proving the lease-leak bug before the fix, then confirming it passes after the fix
Findings:
- HIGH correctness: Successful restore orphaned the candidate lease lock, permanently bricking the newly active package for writes. Sources/KromoraKit/Models/PortableLibraryRestore.swift: the candidate lease was acquired at the staging path, publish() renamed staging onto active, then the lease was released via candidateLease.release() which still pointed at the staging path. Since that path no longer existed post-rename, release() silently no-op'd instead of removing the lock, so the lock file that moved to the new active path (owned by the candidate's ownerID) was never removed. Any subsequent PortablePackageLease.acquire on the restored active package (import, edit, backup, another restore) failed with 'already being written' for the full 180s lease duration and required manual lease-breaking after. Not caught by existing tests because none attempted a write against the active package after a successful restore. Reproduced with a temporary test performing a successful restore then immediately acquiring a lease on the active package; it failed with PortablePackageLeaseError.contended before the fix.
Fixes:
- Sources/KromoraKit/Models/PortablePackageTransaction.swift: added PortablePackageLease.release(movedTo:), which releases the lease against a lock file relocated by an atomic directory rename rather than the lease's original packageRoot.
- Sources/KromoraKit/Models/PortableLibraryRestore.swift: after a successful publish(), release the candidate lease via release(movedTo: active) instead of the stale staging path; on a failed publish, still release at the original staging path since nothing moved.
- Tests/KromoraKitTests/PortableLibraryRestoreTests.swift: extended testRestoreRebuildsCleanIndexAndPreservesEveryEditRepresentation to assert the restored active package can be re-leased for a write immediately after restore, guarding against regression of the orphaned-lease bug.
Verification commits:
- f803e8b
Actor: claude
Resolved model: sonnet
Pickup session: 01MTZZI8R6VENNHG7Z
Summary: Verified validated library restore: acceptance criteria hold, publication is atomic and gated on full pre-replace validation, cancellation and validation-failure paths leave the active package untouched. Found and fixed a blocking bug: successful restore orphaned the candidate lease lock, permanently bricking the newly active package for further writes; fixed via PortablePackageLease.release(movedTo:) and covered with a regression assertion.
