---
id: KRMA-409
title: "Phase 3.4: demote EditDocumentStore/EditPersistenceCoordinator to projection"
type: feature
status: ready
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - performance
  - index
  - persistence
created: 2026-09-12T19:44:22.243Z
updated: 2026-09-13T04:43:59.040Z
depends_on:
  - KRMA-406
  - KRMA-408
order: zzzzv
board: product
---

## Objective

Demote `EditDocumentStore`/`EditPersistenceCoordinator` from canonical source of truth to a
projection over the package, so the package (from KRMA-391) becomes the sole canonical copy of edits
and metadata.

## Dependencies

- The `LibraryQueryController`/index-projection ticket and the scheduler-lanes ticket (this changes
  what backs the store those depend on and how its I/O is scheduled).

## Scope

- Change `EditDocumentStore`/`EditPersistenceCoordinator` so package edit sidecars (KRMA-391) are the
  canonical write target; any local cache these types keep becomes a rebuildable projection, not the
  source of truth.
- Ensure deleting the local index/cache these coordinators maintain loses no user edit data — a
  rebuild from the package must reproduce every edit exactly.
- Preserve existing coalesced-write behavior (batching/debouncing edit saves) — this is a change of
  backing store and truth ownership, not of the save-coalescing policy itself.
- Preserve current render/thumbnail priority behavior for edit-triggered re-renders.

## Acceptance criteria

- [ ] The package is the sole canonical copy of edits/metadata; `EditDocumentStore`/
  `EditPersistenceCoordinator` state is demonstrably rebuildable from it.
- [ ] Deleting the local `EditDocumentStore`/coordinator cache and reconstructing it from the package
  reproduces every edit exactly (content-level comparison, not just count).
- [ ] Existing coalesced edit-persistence timing/behavior is unchanged (regression test).
- [ ] Current render/thumbnail priority behavior for edit-triggered work is unchanged.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Persistence/regression lane: clean-profile rebuild-from-package test, plus existing edit-persistence
and render-priority regression suites.

## Context

- context.files: Sources/KromoraKit (EditDocumentStore, EditPersistenceCoordinator)
- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-392, KRMA-391
