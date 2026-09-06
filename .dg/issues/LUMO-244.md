---
id: LUMO-244
title: SwiftData-backed edit persistence
type: task
status: backlog
priority: medium
labels:
  - epic
  - persistence
created: 2026-09-06T04:06:14.013Z
updated: 2026-09-06T04:19:41.609Z
order: zzzzv
board: product
---

## Context

`EditDocumentStore` currently persists every photo's edits into a single JSON file
(`~/Library/Application Support/Lumo/edit-records.json`), rewriting the *entire* file on every
single edit (`EditDocumentStore.swift:354` `persist()`). `docs/EDIT_PERSISTENCE_BENCHMARK_2026-09-01.md`
shows this doesn't scale: at 10,000 edited photos, one edit rewrites ~14MB and costs ~3.4s CPU /
~1.25s termination flush.

The product hasn't shipped, so there's no existing-data migration to preserve — existing local
edits can be lost. This epic replaces the JSON envelope with SwiftData (row-level, no third-party
dependency, ships with macOS 14+, already the deployment target).

## Shared constraints for every child ticket

- Swift 6 strict concurrency, zero opt-outs (no `@unchecked Sendable`, `nonisolated(unsafe)`,
  `@preconcurrency`) — `PackageSettingsTests` enforces this; it applies to `@Model`/`@ModelActor`
  code exactly as it does everywhere else in `LumoKit`.
- No migration path from `edit-records.json` — existing local edits may be lost. Don't write
  migration code; the old file/`.bak` are simply orphaned on disk.
- No CloudKit — local-storage swap only, out of scope for this epic.
- `EditPersistenceCoordinator.swift` (coalescing/debounce/retry policy) should need **no changes**
  — it only calls `store.save(_:for:) async throws`. If a child ticket finds itself touching that
  file's policy logic, that's a signal the storage-layer API surface drifted from the plan.

## Child tickets

1. Spike: validate SwiftData under Swift 6 strict concurrency — gate for the rest of the epic.
2. `EditRecord` model + SwiftData-backed `EditDocumentStore` — the core rewrite.
3. Update callers (`AppViewModel`, `ExportCoordinator`).
4. Rewrite persistence tests for SwiftData.
5. Remove the obsolete whole-catalog-rewrite benchmark.
6. Settings: reveal edit database in Finder.

Dependency graph: 2→1, 3→2, 4→2, 4→3, 5→2, 6→2. All six depend on this epic.

## Verification (epic-level definition of done)

- `swift build` and `swift test` (deterministic lane) pass with zero Swift 6 concurrency
  diagnostics and zero opt-outs (`PackageSettingsTests`).
- Rewritten `EditDocumentStoreTests`/`EditPersistenceIntegrationTests` pass, covering round-trip
  persistence, relink-on-move, coalescing, and failure injection.
- Manual check: `swift run`, make an edit, quit, relaunch, confirm the edit persisted via
  `EditStore.store` under Application Support (not `edit-records.json`).
- Epic done when all five children are `done` and the manual check above holds.
