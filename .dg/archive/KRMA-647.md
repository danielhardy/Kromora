---
id: KRMA-647
title: Edit history compaction reads every revision file to check for named snapshots
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Compaction determines named-snapshot status from pointer/record metadata already resident in asset.json, without decoding the revision file, so a maintenance pass with nothing to compact does no extra disk I/O per revision.
      result: pass
      notes: PortablePackageEditPointer.isNamedSnapshot is set on write (PortablePackageEditSidecar.swift:307-314). compactRevisions computes protected/newest retention and short-circuits via `guard !stale.isEmpty` before ever touching named-snapshot state (PortablePackageMaintenance.swift:600-626); only when an asset actually needs compaction does it consult pointer.isNamedSnapshot, and it only falls back to readEditRevision for pointers with a nil (legacy) value.
    - criterion: New pointer field decodes existing packages without it, defaulting consistently with today's behavior (no named snapshots), verified by a round-trip test.
      result: pass
      notes: Custom Codable init/encode decodeIfPresent/encodeIfPresent isNamedSnapshot (PortableLibraryPackage.swift:228-250). testLegacyEditPointerDecodesAndRoundTripsAsNotNamedSnapshot confirms a pre-field JSON payload decodes to nil and round-trips as nil, and compactRevisions treats nil as 'unknown, fall back to reading the revision' rather than 'not a snapshot', preserving legacy behavior.
    - criterion: New PortablePackageMaintenanceTests case seeds a named snapshot among more revisions than maximumEditRevisions and asserts it survives compaction while other stale revisions are pruned.
      result: pass
      notes: "testRevisionCompactionRetainsNamedSnapshotsAndPrunesOtherStaleRevisions: 5 revisions with maximumEditRevisions=2, revision 2 named; asserts revisions [2,4,5] survive, 1 and 3 are pruned and unreadable, and the named snapshot's content is still fetchable post-compaction."
  checks_run:
    - swift build (debug) - success
    - swift test --filter 'PortablePackageMaintenanceTests|PortableLibraryPackageTests' - 17/17 passed
    - scripts/ci-tests.sh fast - 1279/1279 tests, exit 0, no failures
  findings:
    - "low: A separate, pre-existing code path (branch-on-history-navigation in appendEditRevision, PortablePackageEditSidecar.swift:299-303) still calls readEditRevision per forward pointer to check snapshotName when starting a new edit branch. Out of scope for this ticket (not part of ordinary maintenance/compactRevisions), but could reuse the new isNamedSnapshot pointer field in a future ticket."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T17:53:27.609Z
  session: 01MUK43NK9YGGTMSTQ
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-27T05:51:35.817Z
updated: 2026-09-28T14:41:33.381Z
parent: KRMA-604
blockers: []
order: jbk5a8kr
board: product
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

### Comment — codex @ 2026-09-27T17:48:03.622Z

Implemented pointer-level named snapshot metadata and retained legacy sidecar fallback only when compaction is needed. Added legacy pointer round-trip and named snapshot compaction coverage. Focused verification passed: 8 tests, 0 failures. Commit: 25a6fb9.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T17:53:27.609Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Compaction determines named-snapshot status from pointer/record metadata already resident in asset.json, without decoding the revision file, so a maintenance pass with nothing to compact does no extra disk I/O per revision. (pass) — PortablePackageEditPointer.isNamedSnapshot is set on write (PortablePackageEditSidecar.swift:307-314). compactRevisions computes protected/newest retention and short-circuits via `guard !stale.isEmpty` before ever touching named-snapshot state (PortablePackageMaintenance.swift:600-626); only when an asset actually needs compaction does it consult pointer.isNamedSnapshot, and it only falls back to readEditRevision for pointers with a nil (legacy) value.
- [x] New pointer field decodes existing packages without it, defaulting consistently with today's behavior (no named snapshots), verified by a round-trip test. (pass) — Custom Codable init/encode decodeIfPresent/encodeIfPresent isNamedSnapshot (PortableLibraryPackage.swift:228-250). testLegacyEditPointerDecodesAndRoundTripsAsNotNamedSnapshot confirms a pre-field JSON payload decodes to nil and round-trips as nil, and compactRevisions treats nil as 'unknown, fall back to reading the revision' rather than 'not a snapshot', preserving legacy behavior.
- [x] New PortablePackageMaintenanceTests case seeds a named snapshot among more revisions than maximumEditRevisions and asserts it survives compaction while other stale revisions are pruned. (pass) — testRevisionCompactionRetainsNamedSnapshotsAndPrunesOtherStaleRevisions: 5 revisions with maximumEditRevisions=2, revision 2 named; asserts revisions [2,4,5] survive, 1 and 3 are pruned and unreadable, and the named snapshot's content is still fetchable post-compaction.
Checks run:
- swift build (debug) - success
- swift test --filter 'PortablePackageMaintenanceTests|PortableLibraryPackageTests' - 17/17 passed
- scripts/ci-tests.sh fast - 1279/1279 tests, exit 0, no failures
Findings:
- low: A separate, pre-existing code path (branch-on-history-navigation in appendEditRevision, PortablePackageEditSidecar.swift:299-303) still calls readEditRevision per forward pointer to check snapshotName when starting a new edit branch. Out of scope for this ticket (not part of ordinary maintenance/compactRevisions), but could reuse the new isNamedSnapshot pointer field in a future ticket.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUK43NK9YGGTMSTQ
Summary: Verified: compaction reads pointer-level isNamedSnapshot instead of decoding revisions; legacy nil field falls back only when compaction is actually needed; build + focused tests + full fast CI lane all pass.
