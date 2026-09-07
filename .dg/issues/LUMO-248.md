---
id: LUMO-248
title: Rewrite persistence tests for SwiftData
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: EditDocumentStoreTests cover round-trip persistence, relink-on-move, failure injection, and concurrent-access serialization against an in-memory ModelContainer; obsolete schema/migration/backup cases are absent
      result: pass
    - criterion: EditPersistenceIntegrationTests retain coalescing, debounce, cancellation, retry, and relaunch assertions against the SwiftData actor counters
      result: pass
    - criterion: All listed incidental test files compile against the in-memory-container initializer
      result: pass
    - criterion: Deterministic Swift test lane passes with no new Swift 6 concurrency diagnostics
      result: pass
  checks_run:
    - swift test --filter EditDocumentStoreTests|EditPersistenceIntegrationTests|LUTWorkflowTests|CropWorkflowTests|ImportedPhotoDurabilityTests — 32 passed
    - swift test — 914 executed, 41 skipped, 0 failures
    - git diff --check — passed
    - dg validate — passed with pre-existing unknown pickup-model warning
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-06T23:49:18.157Z
  session: 01MTQGI8CT7T49NO4A
labels:
  - persistence
  - testing
created: 2026-09-06T04:06:26.874Z
updated: 2026-09-07T04:02:50.262Z
depends_on:
  - LUMO-244
  - LUMO-246
  - LUMO-247
order: ngzpmqyv
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

## Agent log

- 2026-09-06T23:49:18.159Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] EditDocumentStoreTests cover round-trip persistence, relink-on-move, failure injection, and concurrent-access serialization against an in-memory ModelContainer; obsolete schema/migration/backup cases are absent (pass)
- [x] EditPersistenceIntegrationTests retain coalescing, debounce, cancellation, retry, and relaunch assertions against the SwiftData actor counters (pass)
- [x] All listed incidental test files compile against the in-memory-container initializer (pass)
- [x] Deterministic Swift test lane passes with no new Swift 6 concurrency diagnostics (pass)
Checks run:
- swift test --filter EditDocumentStoreTests|EditPersistenceIntegrationTests|LUTWorkflowTests|CropWorkflowTests|ImportedPhotoDurabilityTests — 32 passed
- swift test — 914 executed, 41 skipped, 0 failures
- git diff --check — passed
- dg validate — passed with pre-existing unknown pickup-model warning
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTQGI8CT7T49NO4A
Summary: Rewrote persistence coverage around in-memory SwiftData containers, added concurrent model-context serialization coverage, preserved shared-container relaunch assertions, and converted all listed incidental test stores.
