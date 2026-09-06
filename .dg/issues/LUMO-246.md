---
id: LUMO-246
title: EditRecord model + SwiftData-backed EditDocumentStore
type: task
status: backlog
priority: medium
labels:
  - persistence
created: 2026-09-06T04:06:24.937Z
updated: 2026-09-06T04:06:37.150Z
depends_on:
  - LUMO-244
  - LUMO-245
order: zzzzy
board: product
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
