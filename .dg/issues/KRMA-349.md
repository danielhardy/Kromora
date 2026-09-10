---
id: KRMA-349
title: Add Auto result provenance, ownership, fingerprints, and schema migration
type: feature
status: ready
priority: high
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - persistence
created: 2026-09-10T14:40:08.569Z
updated: 2026-09-10T14:53:43.086Z
depends_on:
  - KRMA-347
  - KRMA-348
order: zy
board: product
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Add the durable, value-only result and provenance model needed to review, persist, update, and safely migrate content-aware Auto edits.

## Scope

- Define internal `AutoEnhancementResult` containing the proposed `EditDocument`, algorithm/version identity, changed controls, confidence, reasons, validation measurements, candidate provenance, and generated-layer ownership metadata.
- Apply Auto ownership/provenance to generated layers without making image pixels part of the document schema.
- Update existing Auto-owned layers rather than appending duplicates; a manual edit to a generated layer converts it to user-owned and protects it from later automatic replacement.
- Store a successful rendering fingerprint for no-op detection when the same source/document/algorithm inputs recur.
- Version the edit schema and decode older documents with neutral defaults. Invalidate affected analysis/render caches when schema or algorithm identity changes.
- Keep result values `Sendable`, `Codable`, and independent of actors/render objects.

## Acceptance criteria

- [ ] `AutoEnhancementResult` is value-only, codable, sendable, and contains proposed document, version, changed controls, confidence, reasons, candidate provenance, and validation measurements.
- [ ] Ownership is explicit for generated layers and distinguishes Auto-owned from user-owned state.
- [ ] Existing Auto layers are updated/reused by stable purpose/provenance identity; repeated successful runs do not append duplicates.
- [ ] Editing any Auto-generated layer or control converts the affected ownership to user-owned without losing the user's edit.
- [ ] A successful rendering fingerprint makes repeating Auto on an unchanged input a no-op; changing source, manual edits, relevant settings, algorithm version, or render identity invalidates it.
- [ ] Older persisted documents decode with neutral defaults and remain renderable; new schema fields have migration tests.
- [ ] Cache invalidation is scoped to affected analysis/render identities and does not delete unrelated user edits.
- [ ] Codable round-trip, migration, ownership transition, duplicate prevention, and fingerprint tests are present.

## Non-goals

- Do not perform asynchronous analysis or rendering here.
- Do not change unrelated edit schema fields.
- Do not silently rewrite user-owned layers.

## Likely files

- `Sources/KromoraKit/Models/EditDocument.swift`
- `Sources/KromoraKit/Models/LocalMaskModels.swift`
- `Sources/KromoraKit/Models/EditRecord.swift`
- `Sources/KromoraKit/Models/EditDocumentStore.swift`
- `Sources/KromoraKit/Models/EditHistory.swift`
- `Sources/KromoraKit/Models/RenderCacheKey.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCache.swift`
- `Tests/KromoraKitTests/`

## Verification

Run persistence, undo/history, cache-key, and migration-focused tests plus `swift build`. Demonstrate save/reopen of a document containing Auto-owned and user-owned layers.
