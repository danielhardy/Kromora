---
id: LUMO-248
title: Rewrite persistence tests for SwiftData
type: task
status: backlog
priority: medium
labels:
  - persistence
  - testing
created: 2026-09-06T04:06:26.874Z
updated: 2026-09-06T04:06:38.415Z
depends_on:
  - LUMO-244
  - LUMO-246
  - LUMO-247
order: zzzzzh
board: product
---

## Objective

Rewrite persistence tests for the SwiftData-backed store.

## Context

See the epic body for shared constraints. Child 2 changes what's testable (no more schema envelope
or backup/recovery); Child 3 updates the callers these tests construct.

## Work

- `Tests/LumoKitTests/EditDocumentStoreTests.swift` — drop schema-migration/legacy-format/backup-
  recovery cases (no longer applicable); keep and re-target round-trip save/load, relink-on-move,
  injected write failures, and concurrent-access serialization, using
  `ModelConfiguration(isStoredInMemoryOnly: true)`.
- `Tests/LumoKitTests/EditPersistenceIntegrationTests.swift` — keep coalescing/debounce/cancellation
  assertions; update counter names to match Child 2's actor.
- Other incidental constructors of `EditDocumentStore(fileURL:)` (`CropTests`, `LUTWorkflowTests`,
  `ComparisonModeTests`, `ExportCoordinatorTests`, `EditClipboardTests`, `LibraryCullingTests`,
  `CoordinatorBoundaryTests`, `ImportedPhotoDurabilityTests`, `PreviewCutoverTests`,
  `LookLUTExportTests`) — mechanical find/replace to the new in-memory-container initializer.

## Acceptance criteria

- [ ] `EditDocumentStoreTests` covers round-trip persistence, relink-on-move, failure injection, and
      concurrent-access serialization against an in-memory `ModelContainer`; schema/migration/backup
      cases removed.
- [ ] `EditPersistenceIntegrationTests` coalescing/debounce/cancellation assertions pass against the
      renamed counters.
- [ ] Every other test file listed above compiles against the new in-memory-container initializer.
- [ ] `swift test` deterministic lane passes, zero Swift 6 concurrency diagnostics.

## Depends on

Child 2, Child 3.
