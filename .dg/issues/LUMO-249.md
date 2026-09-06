---
id: LUMO-249
title: Remove obsolete whole-catalog-rewrite benchmark
type: task
status: backlog
priority: medium
labels:
  - persistence
created: 2026-09-06T04:06:27.772Z
updated: 2026-09-06T04:06:38.846Z
depends_on:
  - LUMO-244
  - LUMO-246
order: zzzzzq
board: product
---

## Objective

Remove the obsolete whole-catalog-rewrite benchmark now that persistence is row-level.

## Context

`Tests/LumoKitTests/EditPersistenceBenchmarkTests.swift` and
`docs/EDIT_PERSISTENCE_BENCHMARK_2026-09-01.md` exist to measure the cost of rewriting the whole
JSON catalog per edit. Once Child 2 lands row-level SwiftData persistence, that premise is moot.

## Work

- Delete `Tests/LumoKitTests/EditPersistenceBenchmarkTests.swift`.
- Delete `docs/EDIT_PERSISTENCE_BENCHMARK_2026-09-01.md`.
- Add a one-line note to `docs/CODE_REVIEW.md` closing out that finding as resolved by this epic.

## Acceptance criteria

- [ ] Both files removed.
- [ ] `docs/CODE_REVIEW.md` records the finding as resolved, with a pointer to this epic.
- [ ] `swift test` still passes with the benchmark test removed.

## Depends on

Child 2.
