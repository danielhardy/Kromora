---
id: KRMA-647
title: Edit history compaction reads every revision file to check for named snapshots
type: task
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-27T05:51:35.817Z
updated: 2026-09-27T05:51:35.817Z
blockers: []
order: zzzv
board: product
parent: KRMA-604
---

## Objective

Avoid decoding every historical edit revision on disk during package maintenance just to learn
whether it carries a named snapshot.

## Context

Verification finding from KRMA-604 (durable edit history, named snapshots, virtual copies).
`PortablePackageMaintenance.compactRevisions` (`Sources/KromoraKit/Models/PortablePackageMaintenance.swift:600-621`)
now computes `namedSnapshots` for every asset by calling `package.readEditRevision(for:revision:)`
for every retained-candidate pointer — a full file read, JSON decode of the entire `EditDocument`,
and Look-reference validation per revision — purely to read the `snapshotName` field so compaction
does not discard named snapshots. `PortablePackageEditPointer` (the lightweight per-asset pointer
struct persisted in `asset.json`) does not carry `snapshotName`, so there is no way to answer "is
this revision a named snapshot" from pointer metadata alone.

`compactRevisions` runs during ordinary background maintenance (`PortablePackageMaintenance.run`),
iterating every shard and every non-tombstoned asset in the whole library, `assetsScanned += 1`
per asset. Before this change the stale/retained computation was pure in-memory work over pointer
metadata (revision numbers only). Now every maintenance pass does this decode-and-validate work
for every pointer of every asset — including assets with zero named snapshots — and it happens
unconditionally, before the `guard !stale.isEmpty` short-circuit that would otherwise skip an
asset needing no compaction. At library scale (thousands of assets, each with tens of edit
revisions), this turns a cheap metadata scan into a full-library file-read/JSON-decode pass on
every maintenance cycle.

There is also no test coverage for the specific claim (documented in
`docs/LIBRARY_PACKAGE_FORMAT.md` and `docs/ENGINEERING_GUIDE.md`) that "named snapshots are
retained during ordinary revision compaction" — `PortablePackageMaintenanceTests` has no test that
exercises compaction with a mix of named-snapshot and ordinary revisions exceeding
`maximumEditRevisions`.

## Acceptance criteria

- [ ] Compaction can determine whether a revision is a named snapshot from pointer/record
      metadata already resident in `asset.json`, without decoding the revision file, so a
      maintenance pass that finds nothing to compact does no extra disk I/O per revision.
- [ ] If this requires a new field on `PortablePackageEditPointer` (e.g. carrying whether the
      revision is named), decoding existing packages without the field defaults consistently with
      today's behavior (no named snapshots) and is exercised by a round-trip test.
- [ ] Add a `PortablePackageMaintenanceTests` case that seeds an asset with a named snapshot among
      more revisions than `maximumEditRevisions` and asserts the named snapshot's pointer survives
      compaction while other stale, unprotected revisions are pruned.

## Implementation notes

Localized to `PortablePackageEditPointer`/`PortablePackageEditHistoryPointers` (schema change —
out of scope for a verification-stage fix) and `compactRevisions` in `PortablePackageMaintenance.swift`.
Keep the `readEditRevision` fallback for old packages whose pointers predate the new field, if any
are expected to exist on disk already.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
