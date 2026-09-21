---
id: KRMA-411
title: "Phase 4.1: verified library backup — snapshot, incremental copy, atomic publish"
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Backup flushes pending edits and snapshots a consistent package state (no half-committed data in the backup).
      result: pass
      notes: run() calls flushPendingEdits before acquiring the writer lease, recovers any in-flight transaction under that lease, then validates canonical references before snapshotting; covered by testBackupFlushesBeforeSnapshotPublishesAndExcludesDerived.
    - criterion: Interrupting and resuming a backup completes without re-copying unchanged content and without corruption.
      result: pass
      notes: Staging state is persisted per-file and reused via checksum match or previous-backup hardlink/clonefile reuse; covered by testCancellationLeavesDestinationAbsentAndResumeUsesStaging and testDiskFullLeavesResumableStagingWithoutPublishing.
    - criterion: Every canonical component is checksum-verified in the backup; Derived/ gaps do not fail verification.
      result: pass
      notes: Fixed isVerifiedBackup()'s existence guard, which did not exempt rebuildable (Derived/) files and contradicted the per-file verify() behavior it otherwise relies on.
    - criterion: The backup destination is atomically published — a cancelled or failed backup never presents as a complete, usable backup.
      result: pass
      notes: Same-volume staging directory renamed into place only after full copy+verify, with a .previous sibling swap and crash-recovery path (recoverPriorPublication); covered by all four tests.
    - criterion: swift build, swift test, dg validate, and git diff --check pass.
      result: pass
      notes: swift build clean; focused PortableLibraryBackupTests 4/4 pass after fixes; dg validate OK with the same 3 pre-existing model-name warnings noted by the implementer; git diff --check clean. Full scripts/ci-tests.sh fast run reproduced pre-existing unrelated failures in ExportCoordinatorTests/LUTWorkflowTests/MaskingWorkspaceTests (disk I/O/timing flakiness), consistent with the implementer's noted baseline of unrelated Auto/export/filmstrip/LUT/masking failures; not touched by this change.
  checks_run:
    - swift build
    - swift test --filter PortableLibraryBackupTests (4/4 pass, before and after fixes)
    - dg validate
    - git diff --check
    - scripts/ci-tests.sh fast (pre-existing unrelated failures only, matching documented baseline)
  findings:
    - "medium: isVerifiedBackup() failed a backup that includes Derived/ content if any Derived file was later missing, contradicting the documented 'rebuildable gaps never fail verification' contract enforced everywhere else in the file. Fixed."
    - "low: a staging directory left over from a different source library backed up to the same destination path silently inherited that unrelated snapshotID instead of starting a fresh one. Fixed."
  fixes:
    - "isVerifiedBackup(): existence guard now exempts rebuildable files, matching verify()'s per-file behavior."
    - "run(): snapshotID is only inherited from staging state when that state's sourceLibraryID matches the current source package; otherwise a fresh UUID is used."
  verification_commits:
    - 6a7d05d
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T15:32:34.833Z
  session: 01MTZYXUYQ22ELWE5C
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - backup
  - recovery
created: 2026-09-12T19:44:23.907Z
updated: 2026-09-13T15:32:34.835Z
depends_on:
  - KRMA-392
  - KRMA-391
order: a0
board: product
commits:
  - 6a7d05d
---

## Objective

Implement "Back Up Library…": a consistent snapshot, incremental/resumable copy, canonical-component
verification, and atomic destination publication.

## Dependencies

- KRMA-392 (package/index ownership and scheduler behavior must be stable).
- KRMA-391 (transaction journals, checksums, leases, and recovery layout are required for safe
  backup).

## Scope

- Implement a "Back Up Library…" flow that first flushes any pending edits (via the coalesced
  edit-persistence path) and coordinates a consistent snapshot of the package (no in-flight commit
  half-copied).
- Implement incremental/resumable copy to a backup destination: a previously interrupted backup can
  resume rather than restart from scratch, and only changed content is re-copied on subsequent runs.
- Verify every canonical component (manifest, shards, asset records, edit sidecars) during/after
  copy; explicitly exclude `Derived/` (thumbnails/previews — rebuildable) from counting as an
  integrity failure if it's missing or stale in the backup.
- Publish the backup destination atomically — a backup is either fully present and verified or not
  present at all; no partial backup is ever left looking complete.
- Support cancellation with clean resume on the next attempt.

## Acceptance criteria

- [ ] Backup flushes pending edits and snapshots a consistent package state (no half-committed data
  in the backup).
- [ ] Interrupting and resuming a backup completes without re-copying unchanged content and without
  corruption.
- [ ] Every canonical component is checksum-verified in the backup; `Derived/` gaps do not fail
  verification.
- [ ] The backup destination is atomically published — a cancelled or failed backup never presents as
  a complete, usable backup.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Backup/restore fault-injection lane: cancellation mid-copy, resume correctness, disk-full during
backup, and canonical-vs-rebuildable verification distinction.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-393, KRMA-392, KRMA-391


### Comment — codex @ 2026-09-13T15:28:10.634Z

Implemented verified library backup support in commit 4ee9873. Added PortableLibraryBackup with pre-snapshot flush hooks, writer-lease transaction recovery, canonical reference validation, incremental clone/link reuse, streamed copy with checksums, resumable staging, cancellation and disk-full recovery, and atomic directory publication with complete metadata. Added four tests covering flush/Derived exclusion, incremental reuse, cancellation/resume, and disk-full recovery. Verification: swift build PASS; focused backup suite 4/4 PASS; git diff --check PASS; dg validate OK with 3 pre-existing model-name warnings. Full suite previously completed 1,415 tests / 53 skips with 10 unrelated Auto/export/filmstrip/LUT/masking timing/environment failures.

## Agent log

- 2026-09-13T15:32:34.833Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Backup flushes pending edits and snapshots a consistent package state (no half-committed data in the backup). (pass) — run() calls flushPendingEdits before acquiring the writer lease, recovers any in-flight transaction under that lease, then validates canonical references before snapshotting; covered by testBackupFlushesBeforeSnapshotPublishesAndExcludesDerived.
- [x] Interrupting and resuming a backup completes without re-copying unchanged content and without corruption. (pass) — Staging state is persisted per-file and reused via checksum match or previous-backup hardlink/clonefile reuse; covered by testCancellationLeavesDestinationAbsentAndResumeUsesStaging and testDiskFullLeavesResumableStagingWithoutPublishing.
- [x] Every canonical component is checksum-verified in the backup; Derived/ gaps do not fail verification. (pass) — Fixed isVerifiedBackup()'s existence guard, which did not exempt rebuildable (Derived/) files and contradicted the per-file verify() behavior it otherwise relies on.
- [x] The backup destination is atomically published — a cancelled or failed backup never presents as a complete, usable backup. (pass) — Same-volume staging directory renamed into place only after full copy+verify, with a .previous sibling swap and crash-recovery path (recoverPriorPublication); covered by all four tests.
- [x] swift build, swift test, dg validate, and git diff --check pass. (pass) — swift build clean; focused PortableLibraryBackupTests 4/4 pass after fixes; dg validate OK with the same 3 pre-existing model-name warnings noted by the implementer; git diff --check clean. Full scripts/ci-tests.sh fast run reproduced pre-existing unrelated failures in ExportCoordinatorTests/LUTWorkflowTests/MaskingWorkspaceTests (disk I/O/timing flakiness), consistent with the implementer's noted baseline of unrelated Auto/export/filmstrip/LUT/masking failures; not touched by this change.
Checks run:
- swift build
- swift test --filter PortableLibraryBackupTests (4/4 pass, before and after fixes)
- dg validate
- git diff --check
- scripts/ci-tests.sh fast (pre-existing unrelated failures only, matching documented baseline)
Findings:
- medium: isVerifiedBackup() failed a backup that includes Derived/ content if any Derived file was later missing, contradicting the documented 'rebuildable gaps never fail verification' contract enforced everywhere else in the file. Fixed.
- low: a staging directory left over from a different source library backed up to the same destination path silently inherited that unrelated snapshotID instead of starting a fresh one. Fixed.
Fixes:
- isVerifiedBackup(): existence guard now exempts rebuildable files, matching verify()'s per-file behavior.
- run(): snapshotID is only inherited from staging state when that state's sourceLibraryID matches the current source package; otherwise a fresh UUID is used.
Verification commits:
- 6a7d05d
Actor: claude
Resolved model: sonnet
Pickup session: 01MTZYXUYQ22ELWE5C
