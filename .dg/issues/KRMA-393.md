---
id: KRMA-393
title: "Phase 4: add verified backup, restore, validation, and maintenance"
type: feature
status: ready
priority: medium
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
updated: 2026-09-13T04:43:55.825Z
depends_on:
  - KRMA-392
  - KRMA-391
  - KRMA-411
  - KRMA-412
  - KRMA-413
  - KRMA-414
  - KRMA-415
order: zzzy
board: product
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
