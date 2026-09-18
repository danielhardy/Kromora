---
id: KRMA-435
title: Photos batch import rebuilds the whole portable library index per item
type: task
status: done
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - library
  - performance
created: 2026-09-14T09:20:26.016Z
updated: 2026-09-14T13:37:20.543Z
depends_on:
  - KRMA-430
order: a0
board: product
commits:
  - 672b0ac
---

Parent: KRMA-430 (verification finding, non-blocking)

## Context

KRMA-430 activated `PortableLibrarySession` as the production library boundary. Photos-picker
multi-select import goes through `PhotosImportCoordinator.append(_:ordinal:)` (`Sources/KromoraKit/ViewModels/PhotosImportCoordinator.swift:232`),
which calls `AppViewModel.insertPhotosImport(_:ordinal:)` once **per imported photo**
(`Sources/KromoraKit/ViewModels/AppViewModel.swift:2455`).

When a portable library is active, each call does:
- `PortableLibrarySession.importData` (`Sources/KromoraKit/Models/PortableLibrarySession.swift:114`),
  which ends with `refreshIndex()` — rebuilds `LibraryIndexProjection` from **every** membership
  shard in the package (`LibraryIndexProjection.init(package:)`,
  `Sources/KromoraKit/Models/LibraryQueryController.swift:98`) and rewrites the whole index file to disk.
- `AppViewModel.reloadPortableCollection()` (`Sources/KromoraKit/ViewModels/AppViewModel.swift:1573`),
  which calls `materializedAssets()` — pages through the **entire** query result and issues a
  `package.readAssetRecord`/`embeddedSourceURL` disk read for every asset currently in the library,
  not just the newly imported one.

For a batch of N Photos-picker imports into a pre-existing library of size M, this is O(N × M)
membership-shard reads/rewrites and asset-record reads, all on the main actor between each item's
progress update. It is functionally correct (fast/serial CI suites pass, small-library manual
testing is fine) but will visibly slow down — and increasingly so as the library grows — exactly
the multi-photo Photos import path the ticket called out as a first-class import route.

## Acceptance criteria

- [ ] Batch imports driven by `PhotosImportCoordinator`/`insertPhotosImport` do not rebuild the
      full package index projection or re-materialize the full asset list once per item; the
      per-item cost should not scale with existing library size M.
- [ ] Selection-on-first-import and progress-reporting behavior for Photos import is preserved.
- [ ] Add a regression test (can reuse `SyntheticLibraryGeneratorTests`/library-scale fixtures)
      that imports a batch of N items into a library with existing assets and asserts the
      index/materialize work is bounded (e.g. a call-count or timing assertion), not O(N × M).

## Out of scope

- Changing the single-image/folder/removable-media import paths, which import one batch at a time
  already and are not affected by this finding.

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-14T13:37:20.541Z: Coalesced portable Photos batch imports: reuse duplicate-detection catalog across per-item commits, defer projection/collection refresh until batch completion, preserve first-item selection, and add regression coverage. Verification: swift test --filter PhotosImportTests (22 passed); swift test --filter PortablePackageImportTests (3 passed); swift build -c release passed. Full suite reached 1,469 tests with one unrelated pre-existing PortableLibraryRestoreTests lease-expiry failure.
