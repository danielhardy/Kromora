---
id: KRMA-392
title: "Phase 3: add paged library queries, index projection, and unified scheduling"
type: feature
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - library
  - architecture
  - performance
  - index
created: 2026-09-12T19:19:22.252Z
updated: 2026-09-13T04:43:55.013Z
depends_on:
  - KRMA-391
  - KRMA-389
  - KRMA-406
  - KRMA-407
  - KRMA-408
  - KRMA-409
  - KRMA-410
order: zzzx
board: product
---

## Objective

Make a large package usable without materialising the entire library, while keeping the package as
truth and ensuring package I/O yields to interactive editing.

## Dependencies

- KRMA-391 — package records and membership summaries must be stable before an index projection is
  introduced.
- KRMA-389 — scale generator and baseline are required for the 100,000-asset exit gate.

## Scope

Add `LibraryQueryController` with value-summary pages of roughly 500 assets, UUID-keyed selection,
index-side filtering/sorting, progressive first-page publication, bounded thumbnail materialisation,
automatic index rebuild, and `EditDocumentStore`/`EditPersistenceCoordinator` demotion from canonical
truth to projection. Extend `ImageWorkScheduler` with package I/O lanes; do not add a second
scheduler. Preserve coalesced edit persistence and existing render/thumbnail priority behavior.

## Acceptance criteria

- [ ] Warm launch reads the first page from the index without walking asset directories, parsing XMP,
  or reading originals; missing/corrupt index rebuilds from membership shards and publishes the first
  page before the full rebuild completes.
- [ ] A 100,000-asset library materialises neither 100,000 observable objects nor 100,000 decoded
  thumbnails; filtering/sorting stays in the index and selection is UUID-based.
- [ ] Visible/active editor work is not queued behind import, index rebuild, validation, or
  maintenance; background work yields under editor contention and package commits remain single-writer.
- [ ] The package remains the sole canonical copy of edits/metadata; deleting the local index loses
  no user data.
- [ ] Scale, concurrency, memory, scheduler fairness, edit persistence, relocation, render, and
  deletion regression tests pass without changing KRMA-371 behavior.
- [ ] `swift build`, applicable fast/serial lanes, `dg validate`, and `git diff --check` pass.

## Verification lane

Large-library performance/concurrency lane at 1k/10k/100k assets, plus the existing render/UI
regression lanes. Capture p95 and p99.9 results against KRMA-389's baseline.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
