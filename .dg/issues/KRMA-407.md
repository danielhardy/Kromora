---
id: KRMA-407
title: "Phase 3.2: automatic index rebuild from membership shards with progressive paging"
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
created: 2026-09-12T19:44:20.441Z
updated: 2026-09-13T04:43:57.478Z
depends_on:
  - KRMA-406
order: zzzzh
board: product
---

## Objective

Implement automatic index rebuild from the package's membership shards, with progressive first-page
publication, so a missing or corrupt local index never blocks the library from opening and warm
launch never has to walk asset directories or parse XMP.

## Dependencies

- The `LibraryQueryController`/index-projection ticket (this rebuilds the structure it reads).

## Scope

- Implement rebuild-from-shards: given only the package's membership shards (denormalised summaries
  from KRMA-391), reconstruct the local index projection without opening every asset record or
  reading originals.
- On missing or corrupt index detection, trigger rebuild automatically and publish the first
  ~500-asset page as soon as it is available, continuing the rebuild in the background rather than
  blocking the UI until the full rebuild completes.
- Warm launch (index present and valid) must read the first page directly from the index with no
  directory walk, no XMP parse, and no original-file read — verify this with instrumentation, not
  just inspection.
- The index remains explicitly non-canonical: deleting it must never lose data, since it is fully
  reconstructable from the package (this is the invariant the sibling scale-regression ticket
  verifies end to end).

## Acceptance criteria

- [ ] Warm launch reads the first page from the index with zero directory walks, XMP parses, or
  original-file reads (verified by test instrumentation).
- [ ] A missing or corrupted index is detected, triggers an automatic rebuild from membership shards,
  and the first page is published before the full rebuild completes.
- [ ] Deleting the local index and reopening the package reconstructs an equivalent index with no
  data loss (content, not just count, is verified).
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Large-library performance/concurrency lane at 1k/10k for rebuild-timing shape; correctness (no data
loss on rebuild) verified at all three KRMA-389 scale sizes where feasible in CI time budget (100k in
the optional/benchmark lane).

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-392, KRMA-391
