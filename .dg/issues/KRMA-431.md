---
id: KRMA-431
title: Complete the durable-data and device-cache storage boundary
type: feature
status: claimed
priority: high
agent: codex
model: gpt-5.6-luna
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
updated: 2026-09-14T09:21:58.423Z
depends_on:
  - KRMA-430
order: t
board: product
claim:
  actor: codex
  session: 01MU11AJYU2O6S4DQ2
  claimed_at: 2026-09-14T09:21:58.422Z
  expires_at: 2026-09-14T10:21:58.422Z
  model: gpt-5.6-luna
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
