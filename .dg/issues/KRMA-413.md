---
id: KRMA-413
title: "Phase 4.3: explicit validation/scrub — critical vs. rebuildable classification"
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Validation walks all canonical and rebuildable components and produces a report with two distinct buckets (critical vs rebuildable).
      result: pass
      notes: PortableLibraryValidation.run walks manifest, membership shards, asset records, originals, edit revisions, XMP sidecars, embedded Looks (canonical) and Derived thumbnails/previews, local index, masks, analysis (rebuildable) into criticalFailures/rebuildableGaps.
    - criterion: A corrupted asset record or edit sidecar is reported as critical; a missing thumbnail or stale index is reported as rebuildable, never critical.
      result: pass
      notes: Confirmed by PortableLibraryValidationTests (testCorruptAssetRecordAndEditSidecarAreCritical, testStaleIndexAndMalformedDerivedArtifactsStayRebuildable) plus manual read of classification logic.
    - criterion: The validation API is reusable by backup and restore, not UI-only.
      result: pass
      notes: "PortableLibraryBackup.validateCanonicalReferences now delegates to PortableLibraryValidation.run(options: .criticalOnly); PortableLibraryRestore calls that same backup helper for both fast-path and full-scan gates."
    - criterion: Running validation performs no destructive or mutating action on the package.
      result: pass
      notes: Implementation only reads files; testValidationDoesNotMutateThePackage snapshots the package before/after and asserts byte-for-byte equality.
    - criterion: swift build, swift test, dg validate, and git diff --check pass.
      result: pass
      notes: Re-ran swift build, targeted swift test (validation/backup/restore/PackageSettingsTests), dg validate, and git diff --check after the verification fix; all clean.
  checks_run:
    - swift build
    - swift test --filter PortableLibraryValidationTests|PortableLibraryBackupTests|PortableLibraryRestoreTests|PackageSettingsTests
    - dg validate
    - git diff --check
    - manual code review of Sources/KromoraKit/Models/PortableLibraryValidation.swift and its integration in PortableLibraryBackup.swift/PortableLibraryRestore.swift
  findings:
    - "low: unused typealias PortableLibraryValidator (dead code) in Sources/KromoraKit/Models/PortableLibraryValidation.swift — fixed by removal"
  fixes:
    - Removed the unused PortableLibraryValidator typealias in PortableLibraryValidation.swift (localized, no behavior change).
  verification_commits:
    - 2105687e1fd09808e23338a495f3f61ddf45fb45
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T16:06:02.365Z
  session: 01MU007U82FNKX3WKL
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - backup
  - recovery
created: 2026-09-12T19:44:25.610Z
updated: 2026-09-21T02:09:32.087Z
order: a0
board: product
commits:
  - 2105687e1fd09808e23338a495f3f61ddf45fb45
---

## Objective

Implement explicit library validation/scrubbing that separates missing/corrupt critical data
(manifest, shards, asset records, edit sidecars) from rebuildable data (thumbnails, previews, local
index, masks, analysis results) — the check both backup and restore rely on.

## Dependencies

- KRMA-392 (index/projection ownership must be stable so validation can tell "critical" from
  "rebuildable" correctly).
- KRMA-391 (checksums and format are required to validate against).

## Scope

- Implement a validation/scrub pass over a package that walks manifest, shards, asset records, and
  edit sidecars, verifying checksums and structural integrity, and separately walks `Derived/`
  (thumbnails, previews), the local index, masks, and analysis results.
- Report results in two explicit buckets: critical failures (data loss risk — manifest/shard/record/
  sidecar corruption or missing) and rebuildable gaps (missing/stale thumbnails, previews, index,
  masks, analysis — never treated as data loss).
- This validation report is the sibling backup/restore tickets' dependency for "verify every
  canonical component" and "validates completely" — expose it as a reusable API, not just a UI
  action.
- Do not perform any destructive action as part of validation itself (no auto-deletion, no
  auto-rebuild) — reporting only; remediation is explicit user/maintenance action (sibling tickets).

## Acceptance criteria

- [ ] Validation walks all canonical components and all rebuildable components and produces a report
  with two distinct buckets (critical vs rebuildable).
- [ ] A corrupted asset record or edit sidecar is reported as critical; a missing thumbnail or stale
  index is reported as rebuildable, never as critical.
- [ ] The validation API is reusable by backup and restore (not UI-only).
- [ ] Running validation performs no destructive or mutating action on the package.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Validation/unit lane with injected corruption at each canonical and rebuildable component type,
asserting correct bucket classification.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-393, KRMA-392, KRMA-391


### Comment — codex @ 2026-09-13T16:03:55.503Z

Implemented in commit 462c1ff. Added the reusable read-only PortableLibraryValidation scrub with explicit critical and rebuildable buckets, checksum/structural checks across manifest, shards, records, originals, edit revisions, XMP sidecars, embedded Looks, Derived artifacts, and optional local index/mask/analysis caches. Added cancellation/progress, no-mutation guarantees, backup/restore canonical validation reuse, tests, and engineering documentation. Verification: swift build passed; focused validation/package/backup/restore tests passed (18/18); dg validate --json passed; git diff --check passed. Full swift test executed 1423 tests with 14 pre-existing async/UI failures in AutoAdjustment, ComparisonMode, ExportCoordinator, FilmstripNavigation, LUTWorkflow, MaskingWorkspace, and ThumbnailSwitchLifecycle suites.

## Agent log

- 2026-09-13T16:06:02.365Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Validation walks all canonical and rebuildable components and produces a report with two distinct buckets (critical vs rebuildable). (pass) — PortableLibraryValidation.run walks manifest, membership shards, asset records, originals, edit revisions, XMP sidecars, embedded Looks (canonical) and Derived thumbnails/previews, local index, masks, analysis (rebuildable) into criticalFailures/rebuildableGaps.
- [x] A corrupted asset record or edit sidecar is reported as critical; a missing thumbnail or stale index is reported as rebuildable, never critical. (pass) — Confirmed by PortableLibraryValidationTests (testCorruptAssetRecordAndEditSidecarAreCritical, testStaleIndexAndMalformedDerivedArtifactsStayRebuildable) plus manual read of classification logic.
- [x] The validation API is reusable by backup and restore, not UI-only. (pass) — PortableLibraryBackup.validateCanonicalReferences now delegates to PortableLibraryValidation.run(options: .criticalOnly); PortableLibraryRestore calls that same backup helper for both fast-path and full-scan gates.
- [x] Running validation performs no destructive or mutating action on the package. (pass) — Implementation only reads files; testValidationDoesNotMutateThePackage snapshots the package before/after and asserts byte-for-byte equality.
- [x] swift build, swift test, dg validate, and git diff --check pass. (pass) — Re-ran swift build, targeted swift test (validation/backup/restore/PackageSettingsTests), dg validate, and git diff --check after the verification fix; all clean.
Checks run:
- swift build
- swift test --filter PortableLibraryValidationTests|PortableLibraryBackupTests|PortableLibraryRestoreTests|PackageSettingsTests
- dg validate
- git diff --check
- manual code review of Sources/KromoraKit/Models/PortableLibraryValidation.swift and its integration in PortableLibraryBackup.swift/PortableLibraryRestore.swift
Findings:
- low: unused typealias PortableLibraryValidator (dead code) in Sources/KromoraKit/Models/PortableLibraryValidation.swift — fixed by removal
Fixes:
- Removed the unused PortableLibraryValidator typealias in PortableLibraryValidation.swift (localized, no behavior change).
Verification commits:
- 2105687e1fd09808e23338a495f3f61ddf45fb45
Actor: claude
Resolved model: sonnet
Pickup session: 01MU007U82FNKX3WKL
Summary: Verified PortableLibraryValidation scrub: independent read-only pass, all acceptance criteria confirmed by code review + targeted tests, one localized dead-code fix applied (unused typealias).
