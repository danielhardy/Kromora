---
id: KRMA-641
title: Flaky LibraryGridTests.testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding under full fast lane
type: bug
status: ready
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-26T21:20:58.902Z
updated: 2026-09-27T02:28:37.243Z
parent: KRMA-637
blockers: []
order: zv
board: product
---

## Objective

Flaky LibraryGridTests.testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding under full fast lane

## Context

Found while independently verifying KRMA-637 (AutoEnhancementCoordinatorTests fix). Running
`scripts/ci-tests.sh fast` on a clean HEAD (90811f0, no product-source changes) failed once with:

```
LibraryGridTests.swift:260: error: ... a virtualized grid must not decode every discovered cell before it appears
LibraryGridTests.swift:274: error: ... requesting one materialized cell must not admit the rest of the folder
```

both in `testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding`. This is unrelated to KRMA-637's
scope (Auto Light/Color low-key intent). Re-running the same `fast` lane immediately after passed with
exit 0, and running `swift test --filter LibraryGridTests` in isolation passed all 13 tests. This points
to a timing-sensitive interaction under `--parallel` full-suite execution (demand/materialization ordering
racing against other concurrently-running tests), not a deterministic regression.

## Acceptance criteria

- [ ] Root-cause the flake in `testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding` (or the demand-driven
      grid materialization path it exercises) and make the test deterministic under `scripts/ci-tests.sh fast`
      when run repeatedly (e.g. 10+ consecutive full `fast` lane runs with no failures).

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
