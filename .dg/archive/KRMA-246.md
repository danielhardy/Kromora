---
id: KRMA-246
title: EditRecord model + SwiftData-backed EditDocumentStore
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: EditRecord and SwiftData-backed EditDocumentStore replace the JSON catalog while preserving the caller-facing API
      result: pass
    - criterion: Relink-on-move, minimal Status, counters, and persistence test seams work against SwiftData
      result: pass
    - criterion: makeContainer uses local no-CloudKit storage and degrades to in-memory storage with writeFailure status
      result: pass
    - criterion: Swift 6 concurrency checks and opt-out scan pass
      result: pass
  checks_run:
    - swift test --filter EditDocumentStoreTests|EditPersistenceIntegrationTests|PackageSettingsTests|SwiftDataConcurrencyProbeTests -- 21 passed
    - swift test -- 913 executed, 41 skipped, 0 failures
    - swift build -c release -- passed
    - git diff --check -- passed
    - dg validate -- passed with existing unknown pickup-model warning
  findings:
    - The requested direct EditDocument property triggers a SwiftData runtime Composite Coder fatal error for this nested Codable document, and .transformable is rejected by the SDK macro; the durable document is therefore represented by the working Data attribute plus a document value facade.
    - CoreData teardown I/O messages appear when tests delete temporary directories while actor stores finish, but all tests pass.
  fixes: []
  verification_commits:
    - c2b7851
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-06T23:30:41.046Z
  session: 01MTQFX8CFTLU7YFPP
labels:
  - persistence
created: 2026-09-06T04:06:24.937Z
updated: 2026-09-10T12:53:50.349Z
depends_on:
  - KRMA-244
  - KRMA-245
order: kqhutdg0
board: product
commits:
  - c2b7851
---

## Objective

The core rewrite: replace the JSON-envelope `EditDocumentStore` with a SwiftData-backed one.

## Context

See the epic body for shared constraints (Swift 6 strict concurrency zero-opt-out, no migration
path, no CloudKit, `EditPersistenceCoordinator` untouched). Depends on Child 1's spike proving the
`@Model`/`@ModelActor` pattern is viable.

## Work

New `Sources/LumoKit/Models/EditRecord.swift`:

```swift
@Model
final class EditRecord {
    @Attribute(.unique) var assetID: String   // PhotoAssetID.description
    var document: EditDocument                // Codable struct, stored as an attribute
    var sourcePath: String?
    var sourceFileName: String?
    var sourceBookmark: Data?
}
```

`EditDocument` (`EditDocument.swift:13`) is unchanged — still `Codable, Sendable, Equatable` — no
decomposition into a relationship graph needed.

Rewrite `EditDocumentStore` (`EditDocumentStore.swift`) as a `@ModelActor`, keeping the same
public method surface (`load(for: EditSourceReference)`, `load(for: PhotoAssetID)`,
`document(for:)`, `save(_:for: EditSourceReference)`, `save(_:for: PhotoAssetID, url:)`) so callers
change minimally. Internals move from an in-memory dictionary + JSON file to
`FetchDescriptor<EditRecord>` queries.

**Drop** (no longer meaningful without a schema-versioned JSON envelope): `Envelope`/`Record`/
`SourceLocator`/`VersionlessEnvelope`, `currentVersion`, `StoreError.newerSchema`,
`.unsupportedVersion`, `.bak` backup/recovery (`.recoveredFromBackup`, `.corrupt`), `bytesWritten`.

**Keep, reimplemented against SwiftData:**
- Relink-on-move (security-scoped bookmark matching) — a real feature independent of storage
  format; port `makeLocator`/`matches`/`locator(for:existing:)` to query by `sourcePath`/
  `sourceBookmark`.
- Minimal `Status` (`ready`, `relinked`, `writeFailure(String)`).
- Save-attempt/write counters, kept small and actor-isolated, for `EditPersistenceIntegrationTests`'
  coalescing assertions.
- Test seams (`artificialWriteDelay`, `failuresBeforeSuccess`, `writeStartSignal`), now guarding
  the SwiftData save call.

Add `EditDocumentStore.makeContainer(url:) throws -> ModelContainer` writing to
`~/Library/Application Support/Lumo/EditStore.store`. On container-creation failure, fall back to
an in-memory `ModelContainer` and surface `.writeFailure` — preserves the existing "never crash,
degrade to neutral edits" resilience property.

## Acceptance criteria

- [ ] `EditRecord.swift` added as specified; `EditDocument` unchanged.
- [ ] `EditDocumentStore` rewritten as a `@ModelActor` with the same public method surface as
      today, backed by `FetchDescriptor<EditRecord>` instead of an in-memory dictionary + JSON file.
- [ ] Listed obsolete types/cases removed; no dead code left behind referencing them.
- [ ] Relink-on-move, `Status`, save/write counters, and test seams ported and working against
      SwiftData.
- [ ] `makeContainer(url:)` added with in-memory fallback + `.writeFailure` surfacing on failure.
- [ ] Zero Swift 6 concurrency diagnostics, zero opt-outs (`PackageSettingsTests` still passes).

## Depends on

Child 1 (spike).

## Agent log

- 2026-09-06T23:30:41.048Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] EditRecord and SwiftData-backed EditDocumentStore replace the JSON catalog while preserving the caller-facing API (pass)
- [x] Relink-on-move, minimal Status, counters, and persistence test seams work against SwiftData (pass)
- [x] makeContainer uses local no-CloudKit storage and degrades to in-memory storage with writeFailure status (pass)
- [x] Swift 6 concurrency checks and opt-out scan pass (pass)
Checks run:
- swift test --filter EditDocumentStoreTests|EditPersistenceIntegrationTests|PackageSettingsTests|SwiftDataConcurrencyProbeTests -- 21 passed
- swift test -- 913 executed, 41 skipped, 0 failures
- swift build -c release -- passed
- git diff --check -- passed
- dg validate -- passed with existing unknown pickup-model warning
Findings:
- The requested direct EditDocument property triggers a SwiftData runtime Composite Coder fatal error for this nested Codable document, and .transformable is rejected by the SDK macro; the durable document is therefore represented by the working Data attribute plus a document value facade.
- CoreData teardown I/O messages appear when tests delete temporary directories while actor stores finish, but all tests pass.
Fixes:
- None
Verification commits:
- c2b7851
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTQFX8CFTLU7YFPP
Summary: SwiftData EditRecord and @ModelActor-backed EditDocumentStore are implemented in c2b7851. Verification passed: full swift test (913 executed, 41 skipped, 0 failures), focused persistence/concurrency lane (21 passed), swift build -c release, git diff --check, and dg validate. The store uses local SwiftData with row-level FetchDescriptor queries, bookmark relinking, actor-isolated counters/test seams, and in-memory fallback with actionable writeFailure status.
