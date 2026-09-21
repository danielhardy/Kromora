---
id: KRMA-393
title: "Phase 4: add verified backup, restore, validation, and maintenance"
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Backup flushes edits, coordinates a consistent snapshot, verifies canonical components, excludes Derived from integrity failure, and resumes after cancellation
      result: pass
      notes: PortableLibraryBackup flushes through the caller hook, recovers in-flight transactions under the writer lease, streams checksummed canonical files, keeps resumable staging, atomically publishes only after verification, and excludes Derived by default; backup cancellation and disk-full tests pass.
    - criterion: Restore validates completely before replacing the active package and clean-profile restore reproduces every edit
      result: pass
      notes: PortableLibraryRestore stages beside the active package, validates backup metadata/checksums/canonical references and edit sidecars, rebuilds the index, compares clean-profile output, and publishes atomically; cancellation and failed-validation tests leave the active package untouched.
    - criterion: Validation separates missing/corrupt critical data from rebuildable artifacts
      result: pass
      notes: PortableLibraryValidation reports criticalFailures separately from rebuildableGaps for thumbnails, previews, local index, masks, and analysis; read-only and classification tests pass.
    - criterion: Remove-from-library quarantines/tombstones, confirmed reclaim is the only permanent deletion, and referenced originals are protected
      result: pass
      notes: PortablePackageTrash uses journaled quarantine/restore and confirmation-gated reclaim; referenced assets are tombstoned without moving or deleting their originals. Existing folder-backed deletion regressions pass unchanged.
    - criterion: Backup/restore, checksum, cancellation, disk-full, quarantine, compaction, clean-profile, deletion, recovery tests pass with dg validate and git diff --check
      result: pass
      notes: swift build passed; swift test --no-parallel passed 1434 tests with 53 skipped and 0 failures; dg validate --json passed with only pre-existing unknown-model warnings; git diff --check passed.
  checks_run:
    - swift build
    - swift test --filter PortableLibraryBackupTests|PortableLibraryRestoreTests|PortableLibraryValidationTests|PortablePackageTrashTests|PortablePackageMaintenanceTests
    - swift test --no-parallel
    - dg validate --json
    - git diff --check
  findings:
    - dg validate reports three pre-existing unknown-model warnings for gpt-5.6-luna/gpt-5.6-terra metadata; no validation errors.
  fixes: []
  verification_commits:
    - 5128a3f
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-13T18:35:24.002Z
  session: 01MU05HEMOJ5VALZPE
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - library
  - architecture
  - backup
  - recovery
created: 2026-09-12T19:19:25.898Z
updated: 2026-09-21T02:09:32.023Z
depends_on:
  - KRMA-413
  - KRMA-414
  - KRMA-415
order: zzzzzx
board: product
commits:
  - 5128a3f
---

## Objective

Complete the package lifecycle with verified backup/restore, explicit validation, recoverable trash,
and low-priority maintenance without turning rebuildable artifacts into integrity failures.

## Dependencies

- KRMA-392 — package/index ownership and scheduler behavior must be stable before maintenance work
  is added.
- KRMA-391 — transaction journals, checksums, leases, and recovery layout are required for safe
  backup and restore.

## Scope

Implement “Back Up Library…” with a consistent snapshot, incremental/resumable copy, canonical
component verification, and atomic destination publication; restore only after complete validation;
explicit validation/scrubbing; tombstone/quarantine trash and confirmed reclaim-space; immutable
revision and packed-thumbnail compaction. Keep `Derived/` optional/rebuildable and never make
automatic recovery destructive.

## Acceptance criteria

- [ ] Backup flushes edits, coordinates a consistent snapshot, verifies every canonical component,
  excludes `Derived/` from integrity failure, and resumes/restarts cleanly after cancellation.
- [ ] Restore never replaces the active package until the replacement validates completely and a
  clean profile reproduces every edit.
- [ ] Validation reports missing/corrupt critical data separately from rebuildable thumbnails,
  previews, local index, masks, and analysis results.
- [ ] Remove-from-library quarantines/tombstones; only explicit confirmed reclaim-space permanently
  deletes originals; referenced originals are never touched.
- [ ] Backup/restore, checksum, cancellation, disk-full, quarantine, compaction, clean-profile,
  deletion, and recovery tests pass with `dg validate` and `git diff --check`.

## Verification lane

Backup/restore and destructive-boundary fault-injection lane, including clean-profile restore and
large-package progress/cancellation checks.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-13T18:35:24.002Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Backup flushes edits, coordinates a consistent snapshot, verifies canonical components, excludes Derived from integrity failure, and resumes after cancellation (pass) — PortableLibraryBackup flushes through the caller hook, recovers in-flight transactions under the writer lease, streams checksummed canonical files, keeps resumable staging, atomically publishes only after verification, and excludes Derived by default; backup cancellation and disk-full tests pass.
- [x] Restore validates completely before replacing the active package and clean-profile restore reproduces every edit (pass) — PortableLibraryRestore stages beside the active package, validates backup metadata/checksums/canonical references and edit sidecars, rebuilds the index, compares clean-profile output, and publishes atomically; cancellation and failed-validation tests leave the active package untouched.
- [x] Validation separates missing/corrupt critical data from rebuildable artifacts (pass) — PortableLibraryValidation reports criticalFailures separately from rebuildableGaps for thumbnails, previews, local index, masks, and analysis; read-only and classification tests pass.
- [x] Remove-from-library quarantines/tombstones, confirmed reclaim is the only permanent deletion, and referenced originals are protected (pass) — PortablePackageTrash uses journaled quarantine/restore and confirmation-gated reclaim; referenced assets are tombstoned without moving or deleting their originals. Existing folder-backed deletion regressions pass unchanged.
- [x] Backup/restore, checksum, cancellation, disk-full, quarantine, compaction, clean-profile, deletion, recovery tests pass with dg validate and git diff --check (pass) — swift build passed; swift test --no-parallel passed 1434 tests with 53 skipped and 0 failures; dg validate --json passed with only pre-existing unknown-model warnings; git diff --check passed.
Checks run:
- swift build
- swift test --filter PortableLibraryBackupTests|PortableLibraryRestoreTests|PortableLibraryValidationTests|PortablePackageTrashTests|PortablePackageMaintenanceTests
- swift test --no-parallel
- dg validate --json
- git diff --check
Findings:
- dg validate reports three pre-existing unknown-model warnings for gpt-5.6-luna/gpt-5.6-terra metadata; no validation errors.
Fixes:
- None
Verification commits:
- 5128a3f
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MU05HEMOJ5VALZPE
Summary: Phase 4 package lifecycle verified: backup/restore, validation, quarantine/reclaim, and low-priority compaction are implemented and pass the full regression lane.
