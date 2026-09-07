---
id: LUMO-264
title: Track the SwiftData concurrency probe test
type: task
status: backlog
priority: low
labels:
  - persistence
created: 2026-09-07T01:10:27.950Z
updated: 2026-09-07T01:11:09.533Z
depends_on:
  - LUMO-245
order: zzzzzzzh
board: product
---

## Objective

Put the LUMO-245 spike's concurrency gate under version control before it evaporates.

## Context

`Tests/LumoKitTests/SwiftDataConcurrencyProbeTests.swift` exists in the working tree but is
untracked (`??` in `git status`) — it was never committed with the epic. Its header says it
was deliberately kept as a compile-time gate for SwiftData's `@Model`/`@ModelActor` boundary
under Swift 6 strict concurrency, but an untracked file is one `git clean` away from deleting
that guarantee, and the "clean tree" verification checks do not cover it.

## Work

- `git add` the probe test as-is (it is self-contained and passes), or fold its assertions
  into `EditDocumentStoreTests` and delete the file. Either way the guarantee must live in a
  tracked file.
- If kept separate, rename out of the ticket-scoped `LUMO245` prefix so the next reader does
  not mistake it for scratch (e.g. `SwiftDataConcurrencyGateTests`).

## Acceptance criteria

- [ ] The concurrency-gate coverage lives in a tracked test file and passes in the
      deterministic lane.
- [ ] `git status --porcelain` shows no stray test files.
