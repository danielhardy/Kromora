---
id: KRMA-411
title: "Phase 4.1: verified library backup — snapshot, incremental copy, atomic publish"
type: feature
status: ready
priority: medium
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
updated: 2026-09-13T04:44:00.667Z
depends_on:
  - KRMA-392
  - KRMA-391
order: zzzzy
board: product
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
