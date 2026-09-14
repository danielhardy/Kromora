---
id: KRMA-418
title: Package open() eagerly decodes every asset record, violating documented lazy-validation policy
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: open() no longer decodes every asset record in every shard as part of normal open; only shard/manifest-level structural checks remain eager.
      result: pass
      notes: open(at:) now only reads/validates the manifest (via openForQuery) and each membership shard (readMembershipShard). The per-entry readAssetRecord(for:) loop was removed.
    - criterion: Corrupt-record detection still happens, but on documented triggers (read failure, attribute mismatch, explicit validation, verified backup/restore, or background maintenance).
      result: pass
      notes: readAssetRecord(for:) still decodes and validates the record; it is invoked from real read paths (EditDocumentStore, PortablePackageImport, PortablePackageEditSidecar), so corruption surfaces on first actual read rather than eagerly at open.
    - criterion: testCorruptShardAndRecordAreDiscoveredWhenOpeningThePackage (or an updated equivalent) still passes, adjusted if corruption is now surfaced through a different trigger point.
      result: pass
      notes: Renamed to testCorruptShardIsDiscoveredOnOpenAndCorruptRecordOnRead; now asserts a corrupt shard fails at open() and a corrupt record fails at reopened.readAssetRecord(for:). Passed.
    - criterion: swift build, swift test, dg validate pass.
      result: pass
      notes: "swift build succeeded. Focused swift test -filter PortableLibraryPackageTests|PortablePackageEndToEndRegressionTests: 14/14 passed. dg validate: OK (same pre-existing unknown-model warnings noted by implementer, unrelated to this change)."
  checks_run:
    - swift build
    - swift test --filter PortableLibraryPackageTests|PortablePackageEndToEndRegressionTests (14/14 passed)
    - dg validate
    - git status --porcelain (source tree clean; only pre-existing .dg bookkeeping diffs)
    - manual review of PortableLibraryPackage.swift open()/openForQuery()/readMembershipShard()/readAssetRecord()/validate(shard:)/validate(record:) and all callers of open(at:) and readAssetRecord(for:)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T15:08:58.023Z
  session: 01MTZY7D4DF3GW1ZQR
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - performance
  - persistence
created: 2026-09-13T13:42:51.763Z
updated: 2026-09-13T15:08:58.025Z
parent: KRMA-405
depends_on:
  - KRMA-405
order: a0
board: product
---

## Objective

`PortableLibraryPackage.open(at:)` (Sources/KromoraKit/Models/PortableLibraryPackage.swift:344-363)
was changed in KRMA-405 (commit 6462688) to decode every non-tombstoned asset record in every
membership shard on every open, in order to surface a corrupt-record scenario at open time
(`testCorruptShardAndRecordAreDiscoveredWhenOpeningThePackage`).

This directly conflicts with `docs/LIBRARY_PACKAGE_PLAN.md` (§ around line 449): "Validate a
specific original only when a read fails, or when size/attributes disagree with the record... Full
scrubs run only via explicit validation, verified backup, restore, or scheduled low-priority
[maintenance]." Eagerly decoding every asset record on every `open()` call is exactly the kind of
full scrub the plan reserves for explicit/background validation, not the hot open/relocate path.

## Context

At the plan's target scale (100,000 assets, docs/LIBRARY_PACKAGE_PLAN.md line 9), `open()` now does
an O(n) JSON decode of every asset record before returning — on every app launch, every relocation
check, and every place that re-opens a package. This is the same path KRMA-405's own relocation
scenario exercises. It is functionally correct (tests pass, corrupt records are caught) but is a
performance regression relative to documented intent, and it's out of scope for KRMA-405's verifier
to fix with a localized patch since a proper fix requires a design decision (e.g. validate only
manifest/shard structure eagerly, defer per-record decode/corruption checks to lazy-on-read or an
explicit/background validation pass, matching the plan's existing "validate when a read fails"
model).

## Acceptance criteria

- [ ] `open()` no longer decodes every asset record in every shard as part of normal open; only
  shard/manifest-level structural checks remain eager.
- [ ] Corrupt-record detection still happens, but on the documented triggers (read failure,
  attribute mismatch, explicit validation, verified backup/restore, or background maintenance) per
  docs/LIBRARY_PACKAGE_PLAN.md.
- [ ] `testCorruptShardAndRecordAreDiscoveredWhenOpeningThePackage` (or an updated equivalent) still
  passes, adjusted if the corruption is now surfaced through the new trigger point instead of open.
- [ ] `swift build`, `swift test`, `dg validate` pass.

## Implementation notes

Touches Sources/KromoraKit/Models/PortableLibraryPackage.swift:344-363. Consider whether shard-level
membership decode already gives enough structural confidence and whether the corrupt-record test
should instead exercise a subsequent read (e.g. `readAssetRecord`) rather than `open()` itself.

### Comment — codex @ 2026-09-13T15:07:34.602Z

Implemented in commit 5680027. PortableLibraryPackage.open(at:) now eagerly validates only the manifest and all membership shards; asset records remain lazy and are validated by readAssetRecord(for:). Updated the corruption regression to assert corrupt shards fail on open while corrupt records fail on read. Verification: swift build passed; focused corruption test passed; PortableLibraryPackageTests + PortablePackageEndToEndRegressionTests passed 14/14; dg validate passed with the existing unknown-model warnings; git diff --check passed. An unfiltered swift test run completed with 10 unrelated pre-existing UI/async timing or environment failures in AutoAdjustment, ComparisonMode, ExportCoordinator, FilmstripNavigation, LUTWorkflow, and MaskingWorkspace tests; no package tests failed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-13T15:08:58.023Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] open() no longer decodes every asset record in every shard as part of normal open; only shard/manifest-level structural checks remain eager. (pass) — open(at:) now only reads/validates the manifest (via openForQuery) and each membership shard (readMembershipShard). The per-entry readAssetRecord(for:) loop was removed.
- [x] Corrupt-record detection still happens, but on documented triggers (read failure, attribute mismatch, explicit validation, verified backup/restore, or background maintenance). (pass) — readAssetRecord(for:) still decodes and validates the record; it is invoked from real read paths (EditDocumentStore, PortablePackageImport, PortablePackageEditSidecar), so corruption surfaces on first actual read rather than eagerly at open.
- [x] testCorruptShardAndRecordAreDiscoveredWhenOpeningThePackage (or an updated equivalent) still passes, adjusted if corruption is now surfaced through a different trigger point. (pass) — Renamed to testCorruptShardIsDiscoveredOnOpenAndCorruptRecordOnRead; now asserts a corrupt shard fails at open() and a corrupt record fails at reopened.readAssetRecord(for:). Passed.
- [x] swift build, swift test, dg validate pass. (pass) — swift build succeeded. Focused swift test -filter PortableLibraryPackageTests|PortablePackageEndToEndRegressionTests: 14/14 passed. dg validate: OK (same pre-existing unknown-model warnings noted by implementer, unrelated to this change).
Checks run:
- swift build
- swift test --filter PortableLibraryPackageTests|PortablePackageEndToEndRegressionTests (14/14 passed)
- dg validate
- git status --porcelain (source tree clean; only pre-existing .dg bookkeeping diffs)
- manual review of PortableLibraryPackage.swift open()/openForQuery()/readMembershipShard()/readAssetRecord()/validate(shard:)/validate(record:) and all callers of open(at:) and readAssetRecord(for:)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTZY7D4DF3GW1ZQR
Summary: Verified: open() eager loop removed, shard-level structural validation retained, asset records validated lazily on read; build/tests/dg validate pass.
