---
id: KRMA-406
title: "Phase 3.1: LibraryQueryController and index projection (paged, UUID-selected)"
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
created: 2026-09-12T19:44:19.493Z
updated: 2026-09-13T04:43:56.629Z
depends_on:
  - KRMA-391
  - KRMA-389
order: zzzz
board: product
---

## Objective

Implement `LibraryQueryController` and the index projection it reads from: value-summary pages of
roughly 500 assets, UUID-keyed selection, and index-side filtering/sorting — the core mechanism that
lets a large package be browsed without materialising the whole library.

## Dependencies

- KRMA-391 (Phase 2 package records and membership summaries must be stable).
- KRMA-389 (scale generator needed to exercise this at 1k/10k/100k during development).

## Scope

- Design the index projection: a local, rebuildable structure (derived from the package's membership
  shards) that can answer "give me page N of the library, filtered/sorted thus" without opening every
  asset record or reading originals.
- Implement `LibraryQueryController` with paging (~500-asset value-summary pages), returning enough
  per-asset summary data for list/grid UI without decoding thumbnails.
- Selection must be UUID-based (from KRMA-390's identity), not index-position-based, so it stays
  correct across paging, filtering, and background index rebuilds.
- Filtering and sorting must execute against the index projection, not by materialising and
  filtering the full in-memory asset list.
- This ticket does not yet handle index rebuild-from-shards mechanics (sibling ticket) or scheduler
  integration (sibling ticket) — build against a projection that is assumed valid/present here.

## Acceptance criteria

- [ ] `LibraryQueryController` returns ~500-asset value-summary pages without decoding thumbnails or
  reading full asset records for entries outside the requested page.
- [ ] Selection survives paging, filtering, and re-sorting without drift (UUID-keyed, verified by
  test).
- [ ] Filtering and sorting operations run against the index projection and are verified (by test
  instrumentation) not to touch original files or full asset records for a 10,000-asset synthetic
  library.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Large-library performance/unit lane using KRMA-389's generator at 1k and 10k for development speed;
100k is covered by the sibling scale-regression ticket.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-392, KRMA-391, KRMA-389
