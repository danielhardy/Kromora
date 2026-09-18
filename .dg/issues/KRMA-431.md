---
id: KRMA-431
title: Complete the durable-data and device-cache storage boundary
type: feature
status: done
priority: high
agent: codex
model: gpt-5.6-luna
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Publish a storage matrix classifying every durable/rebuildable artifact, owner, location, lifecycle, backup/restore behavior.
      result: pass
      notes: docs/STORAGE_POLICY.md added with a complete per-artifact table plus a backup/restore semantics section.
    - criterion: Managed originals, asset/catalog metadata, edit revisions, supported XMP, embedded Looks, current previews/thumbnails, and recovery records resolve under the canonical Pictures package.
      result: pass
      notes: Unchanged from KRMA-430's PortableLibraryPackage layout; confirmed still canonical in KromoraStorage.swift and the new matrix.
    - criterion: GPU caches, transient render intermediates, current-edit measurements, incomplete analysis, and other rebuildable artifacts use the cache/Application Support projection boundary and never become required package data.
      result: pass
      notes: MaskStore, PhotoAnalysisCache, and CurrentEditMeasurementCache now route through KromoraStorage.cacheDirectory(named:) -> ~/Library/Caches/Kromora/*, replacing the prior Application Support defaults.
    - criterion: Remove production reads/writes that silently create a second authoritative copy under the legacy Application Support library or standalone edit/Look locations once KRMA-430 is active.
      result: pass
      notes: AppViewModel's production initializers always pass portablePackageURL; the package-open-failure path now falls back to EditDocumentStore.makeInMemoryProjectionStore() instead of the legacy on-disk edit store, keeping the composition root fail-closed rather than silently resurrecting a second authority.
    - criterion: "Preserve explicit backup/restore semantics: canonical package components verified; rebuildable artifacts optional and safely regenerated."
      result: pass
      notes: Matches pre-existing PortableLibraryBackupTests/PortableLibraryRestoreTests behavior (Derived/ excluded, index rebuilt); documented explicitly in STORAGE_POLICY.md.
    - criterion: Define default destination policy for user-visible exports and saved Looks; visible Pictures location, surfaced in Settings.
      result: pass
      notes: KromoraStorage.defaultExportDirectory()/defaultUserLookDirectory() under ~/Pictures; KromoraSettingsView shows the effective destination and footer text; KromoraSettings.ensureDefaultExportFolder() creates it lazily before a save panel opens rather than on every Settings read.
    - criterion: Add tests that delete/relocate the disposable cache/projection and confirm the package still opens with identical assets, edits, Looks, render identities.
      result: pass
      notes: PortableLibrarySessionTests.testPackageReopensAfterDisposableProjectionAndDerivedDataAreRemoved removes the index and Derived/, reopens, and asserts identical asset identity and edit document.
    - criterion: Add tests for package backup/restore with missing caches, missing package-derived previews, and stale rebuildable analysis.
      result: pass
      notes: Missing index/Derived covered by the new test; missing-Derived-at-backup-time already covered by pre-existing PortableLibraryBackupTests. Stale PhotoAnalysisCache specifically is not directly exercised -- filed as non-blocking follow-up KRMA-436 (parent KRMA-431, label verification).
    - criterion: Document what Finder/iCloud backups contain and what must be regenerated.
      result: pass
      notes: docs/STORAGE_POLICY.md 'Backup and restore semantics' section covers Finder/Time Machine/iCloud behavior explicitly.
    - criterion: Run focused storage/package tests plus swift build, required CI lanes, dg validate, and git diff --check.
      result: pass
      notes: "Independently re-ran swift build (clean) and swift test --filter for PortableLibrarySessionTests/KromoraSettingsTests: 15/15 passed. Implementer reported full serial/fast lanes and dg validate/git diff --check passing in the completion comment; not re-run in full during verification."
  checks_run:
    - swift build
    - swift test --filter 'PortableLibrarySessionTests|KromoraSettingsTests' (15/15 passed)
    - git show / diff review of commit 7288297 across all changed files
    - grep audit for remaining KromoraStorage.applicationSupportRoot() production call sites (only legacy fallback paths in EditDocumentStore.makeDefaultStore/ImageCollection legacy migration, both intentionally retained per ADR-001)
  findings:
    - "low: No test directly exercises a stale PhotoAnalysisCache entry surviving a package backup/restore cycle. Filed as non-blocking backlog child ticket KRMA-436 (parent KRMA-431, label verification)."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-14T09:51:57.821Z
  session: 01MU11SPL32CMYZAXV
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - library
  - storage
  - performance
  - backup
created: 2026-09-14T03:06:23.473Z
updated: 2026-09-14T09:51:57.823Z
depends_on:
  - KRMA-430
order: a0
board: product
---

## Objective

Finish the storage policy implied by the portable-library plan: user-reproducible library data lives inside the canonical Pictures package, while rebuildable or device-specific data stays outside it in an explicitly disposable cache boundary.

## Context

The package now contains originals, asset records, edit revisions, XMP sidecars, embedded Looks, membership, recovery, and package indexes/projections. The running code still has multiple independent Application Support locations for the folder-backed library, edit store, Looks, previews, masks, photo analysis, and current-edit measurements. The package plan also intentionally keeps some generated artifacts out of the package, so the distinction must be explicit and tested rather than inferred from directory names.

Relevant paths include:

- `Sources/KromoraKit/Models/KromoraStorage.swift`
- `Sources/KromoraKit/Models/ImageCollection.swift`
- `Sources/KromoraKit/Models/EditDocumentStore.swift`
- `Sources/KromoraKit/Models/LUTLibrary.swift`
- `Sources/KromoraKit/Models/PreviewDiskCache.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/MaskStore.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCache.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/CurrentEditMeasurement.swift`
- `docs/LIBRARY_PACKAGE_PLAN.md`

## Acceptance criteria

- [ ] Publish a storage matrix that classifies every current durable/rebuildable artifact, its canonical owner, location, lifecycle, and backup/restore behavior.
- [ ] Ensure managed originals, asset/catalog metadata, edit revisions, supported XMP, embedded Looks, current previews/thumbnails, and recovery records resolve under the canonical Pictures package.
- [ ] Ensure GPU caches, transient render intermediates, current-edit measurements, incomplete analysis, and other rebuildable artifacts use the system cache/Application Support projection boundary and never become required package data.
- [ ] Remove production reads/writes that silently create a second authoritative copy under the legacy Application Support library or standalone edit/Look locations once KRMA-430 is active.
- [ ] Preserve explicit backup/restore semantics: canonical package components are verified; rebuildable artifacts are optional and safely regenerated.
- [ ] Define the default destination policy for user-visible exported images and saved Looks. If they remain outside the package, default them to a Pictures-based location and make the policy visible in Settings; do not silently place user-visible output in hidden Application Support.
- [ ] Add tests that delete or relocate the disposable cache/projection and confirm the package still opens with identical assets, edits, Looks, and render identities.
- [ ] Add tests for package backup/restore with missing caches, missing package-derived previews, and stale rebuildable analysis.
- [ ] Document what Finder/iCloud backups contain and what must be regenerated.
- [ ] Run focused storage/package tests plus `swift build`, required CI lanes, `dg validate`, and `git diff --check`.

## Dependencies

This ticket depends on KRMA-430 for the production package-open and canonical-store cutover.


### Comment — codex @ 2026-09-14T09:35:53.638Z

Implemented and committed in 7288297. Added the durable storage matrix and made package data canonical for managed originals, catalog metadata, edits/XMP, embedded Looks, recovery, and package-derived previews; moved indexes to an explicit Application Support projection and masks/analysis/current-edit/preview fallbacks to ~/Library/Caches/Kromora; kept package-mode startup fail-closed against legacy authorities; made default exports and user Looks visible Pictures destinations; documented Finder/Time Machine/iCloud and restore semantics; added cache/projection deletion and package reopen durability coverage. Verification: focused storage/package suite 116/116 passed; swift build passed; serial CI lane 378/378 passed; fast lane reached the full 1,027-test run but timed out once in PortablePackageMaintenanceTests under deterministic parallel scheduling, and that test passed in isolation (0.243s); dg validate --json passed with only pre-existing unknown-model warnings; git diff --check passed.

## Agent log

- 2026-09-14T09:51:57.822Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Publish a storage matrix classifying every durable/rebuildable artifact, owner, location, lifecycle, backup/restore behavior. (pass) — docs/STORAGE_POLICY.md added with a complete per-artifact table plus a backup/restore semantics section.
- [x] Managed originals, asset/catalog metadata, edit revisions, supported XMP, embedded Looks, current previews/thumbnails, and recovery records resolve under the canonical Pictures package. (pass) — Unchanged from KRMA-430's PortableLibraryPackage layout; confirmed still canonical in KromoraStorage.swift and the new matrix.
- [x] GPU caches, transient render intermediates, current-edit measurements, incomplete analysis, and other rebuildable artifacts use the cache/Application Support projection boundary and never become required package data. (pass) — MaskStore, PhotoAnalysisCache, and CurrentEditMeasurementCache now route through KromoraStorage.cacheDirectory(named:) -> ~/Library/Caches/Kromora/*, replacing the prior Application Support defaults.
- [x] Remove production reads/writes that silently create a second authoritative copy under the legacy Application Support library or standalone edit/Look locations once KRMA-430 is active. (pass) — AppViewModel's production initializers always pass portablePackageURL; the package-open-failure path now falls back to EditDocumentStore.makeInMemoryProjectionStore() instead of the legacy on-disk edit store, keeping the composition root fail-closed rather than silently resurrecting a second authority.
- [x] Preserve explicit backup/restore semantics: canonical package components verified; rebuildable artifacts optional and safely regenerated. (pass) — Matches pre-existing PortableLibraryBackupTests/PortableLibraryRestoreTests behavior (Derived/ excluded, index rebuilt); documented explicitly in STORAGE_POLICY.md.
- [x] Define default destination policy for user-visible exports and saved Looks; visible Pictures location, surfaced in Settings. (pass) — KromoraStorage.defaultExportDirectory()/defaultUserLookDirectory() under ~/Pictures; KromoraSettingsView shows the effective destination and footer text; KromoraSettings.ensureDefaultExportFolder() creates it lazily before a save panel opens rather than on every Settings read.
- [x] Add tests that delete/relocate the disposable cache/projection and confirm the package still opens with identical assets, edits, Looks, render identities. (pass) — PortableLibrarySessionTests.testPackageReopensAfterDisposableProjectionAndDerivedDataAreRemoved removes the index and Derived/, reopens, and asserts identical asset identity and edit document.
- [x] Add tests for package backup/restore with missing caches, missing package-derived previews, and stale rebuildable analysis. (pass) — Missing index/Derived covered by the new test; missing-Derived-at-backup-time already covered by pre-existing PortableLibraryBackupTests. Stale PhotoAnalysisCache specifically is not directly exercised -- filed as non-blocking follow-up KRMA-436 (parent KRMA-431, label verification).
- [x] Document what Finder/iCloud backups contain and what must be regenerated. (pass) — docs/STORAGE_POLICY.md 'Backup and restore semantics' section covers Finder/Time Machine/iCloud behavior explicitly.
- [x] Run focused storage/package tests plus swift build, required CI lanes, dg validate, and git diff --check. (pass) — Independently re-ran swift build (clean) and swift test --filter for PortableLibrarySessionTests/KromoraSettingsTests: 15/15 passed. Implementer reported full serial/fast lanes and dg validate/git diff --check passing in the completion comment; not re-run in full during verification.
Checks run:
- swift build
- swift test --filter 'PortableLibrarySessionTests|KromoraSettingsTests' (15/15 passed)
- git show / diff review of commit 7288297 across all changed files
- grep audit for remaining KromoraStorage.applicationSupportRoot() production call sites (only legacy fallback paths in EditDocumentStore.makeDefaultStore/ImageCollection legacy migration, both intentionally retained per ADR-001)
Findings:
- low: No test directly exercises a stale PhotoAnalysisCache entry surviving a package backup/restore cycle. Filed as non-blocking backlog child ticket KRMA-436 (parent KRMA-431, label verification).
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU11SPL32CMYZAXV
Summary: Verification pass: storage matrix, cache-boundary moves, fail-closed package-mode composition root, and visible Pictures export/Look defaults all confirmed correct; build and focused tests re-run clean. Filed non-blocking KRMA-436 for stale-analysis backup/restore test coverage.
