---
id: KRMA-349
title: Add Auto result provenance, ownership, fingerprints, and schema migration
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: AutoEnhancementResult is value-only, codable, sendable, and contains proposed document, version, changed controls, confidence, reasons, candidate provenance, and validation measurements.
      result: pass
    - criterion: Ownership is explicit for generated layers and distinguishes Auto-owned from user-owned state.
      result: pass
    - criterion: Existing Auto layers are updated/reused by stable purpose/provenance identity; repeated successful runs do not append duplicates.
      result: pass
      notes: Reconciliation keyed on AutoLayerProvenance.stableIdentity in EditDocument.applyingAutoResult and AutoRegionalCorrections; covered by testProtectedUserLayerIsNotDuplicatedByLaterAutoResult and testAutoResultReusesExistingAutoLayerButProtectsUserLayer.
    - criterion: Editing any Auto-generated layer or control converts the affected ownership to user-owned without losing the user's edit.
      result: pass
      notes: markUserOwned() now preserves autoProvenance intentionally so the layer stays protected from later replacement/duplication; verified isAutoOwned still gates on ownership==.auto so protection logic is unaffected.
    - criterion: A successful rendering fingerprint makes repeating Auto on an unchanged input a no-op; changing source, manual edits, relevant settings, algorithm version, or render identity invalidates it.
      result: pass
      notes: Fingerprint documentHash is recomputed from the post-reconciliation document (applied.renderingHash) so it matches the actually-persisted document, not the transient candidate; renderingHash explicitly excludes lastAutoRunFingerprint avoiding circularity. Covered by testFingerprintMatchesDocumentAfterExistingAutoLayerIsReused and testFingerprintChangesForSourceDocumentAlgorithmAndRenderer.
    - criterion: Older persisted documents decode with neutral defaults and remain renderable; new schema fields have migration tests.
      result: pass
      notes: testLegacyDocumentsUseNeutralAutoMetadata.
    - criterion: Cache invalidation is scoped to affected analysis/render identities and does not delete unrelated user edits.
      result: pass
      notes: Render/analysis caches are content-addressed by document/source hash already (RenderCacheHash.digest over renderingHash), so changes to Auto-owned layers naturally scope invalidation without needing separate cache-clearing code; no unrelated user layers are touched by reconciliation.
    - criterion: Codable round-trip, migration, ownership transition, duplicate prevention, and fingerprint tests are present.
      result: pass
      notes: testResultAndOwnershipMetadataRoundTrip, testAutoAndUserOwnedLayersSurviveRecordSaveAndReopen, testLegacyDocumentsUseNeutralAutoMetadata, testManualEditReleasesAutoLayerAndClearsFingerprint, testProtectedUserLayerIsNotDuplicatedByLaterAutoResult, testFingerprintMatchesDocumentAfterExistingAutoLayerIsReused, testFingerprintChangesForSourceDocumentAlgorithmAndRenderer all present and passing.
  checks_run:
    - swift build
    - swift test --filter AutoEnhancementResultTests (8/8 passed)
    - scripts/ci-tests.sh fast (837/837 passed)
    - scripts/ci-tests.sh serial (328/328 passed)
    - git status --porcelain (only pre-existing unrelated .dg bookkeeping changes, no source diffs introduced)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-10T23:41:38.109Z
  session: 01MTW64UPPMZT3UM8Q
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - persistence
created: 2026-09-10T14:40:08.569Z
updated: 2026-09-10T23:41:38.111Z
depends_on:
  - KRMA-347
  - KRMA-348
order: a0
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


### Comment — codex @ 2026-09-10T23:38:33.283Z

Implemented and committed as 0348cf3 (KRMA-349: stabilize Auto provenance and fingerprints). Auto result application now reconciles generated layers by stable provenance, preserves protected provenance after manual ownership transfer, prevents duplicates beside user-owned layers, and recomputes fingerprints after stable-ID reuse. Added Codable save/reopen, ownership transition, duplicate prevention, and fingerprint regression tests. Verification: swift test — 1,210 tests passed, 47 expected skips; swift build passed; git diff --check passed. Pre-existing unrelated .dg working-tree changes were preserved.

## Agent log

- 2026-09-10T23:41:38.109Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] AutoEnhancementResult is value-only, codable, sendable, and contains proposed document, version, changed controls, confidence, reasons, candidate provenance, and validation measurements. (pass)
- [x] Ownership is explicit for generated layers and distinguishes Auto-owned from user-owned state. (pass)
- [x] Existing Auto layers are updated/reused by stable purpose/provenance identity; repeated successful runs do not append duplicates. (pass) — Reconciliation keyed on AutoLayerProvenance.stableIdentity in EditDocument.applyingAutoResult and AutoRegionalCorrections; covered by testProtectedUserLayerIsNotDuplicatedByLaterAutoResult and testAutoResultReusesExistingAutoLayerButProtectsUserLayer.
- [x] Editing any Auto-generated layer or control converts the affected ownership to user-owned without losing the user's edit. (pass) — markUserOwned() now preserves autoProvenance intentionally so the layer stays protected from later replacement/duplication; verified isAutoOwned still gates on ownership==.auto so protection logic is unaffected.
- [x] A successful rendering fingerprint makes repeating Auto on an unchanged input a no-op; changing source, manual edits, relevant settings, algorithm version, or render identity invalidates it. (pass) — Fingerprint documentHash is recomputed from the post-reconciliation document (applied.renderingHash) so it matches the actually-persisted document, not the transient candidate; renderingHash explicitly excludes lastAutoRunFingerprint avoiding circularity. Covered by testFingerprintMatchesDocumentAfterExistingAutoLayerIsReused and testFingerprintChangesForSourceDocumentAlgorithmAndRenderer.
- [x] Older persisted documents decode with neutral defaults and remain renderable; new schema fields have migration tests. (pass) — testLegacyDocumentsUseNeutralAutoMetadata.
- [x] Cache invalidation is scoped to affected analysis/render identities and does not delete unrelated user edits. (pass) — Render/analysis caches are content-addressed by document/source hash already (RenderCacheHash.digest over renderingHash), so changes to Auto-owned layers naturally scope invalidation without needing separate cache-clearing code; no unrelated user layers are touched by reconciliation.
- [x] Codable round-trip, migration, ownership transition, duplicate prevention, and fingerprint tests are present. (pass) — testResultAndOwnershipMetadataRoundTrip, testAutoAndUserOwnedLayersSurviveRecordSaveAndReopen, testLegacyDocumentsUseNeutralAutoMetadata, testManualEditReleasesAutoLayerAndClearsFingerprint, testProtectedUserLayerIsNotDuplicatedByLaterAutoResult, testFingerprintMatchesDocumentAfterExistingAutoLayerIsReused, testFingerprintChangesForSourceDocumentAlgorithmAndRenderer all present and passing.
Checks run:
- swift build
- swift test --filter AutoEnhancementResultTests (8/8 passed)
- scripts/ci-tests.sh fast (837/837 passed)
- scripts/ci-tests.sh serial (328/328 passed)
- git status --porcelain (only pre-existing unrelated .dg bookkeeping changes, no source diffs introduced)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTW64UPPMZT3UM8Q
Summary: Independent verification pass: provenance-stable reconciliation, ownership-transition protection, and post-reconciliation fingerprint recompute all check out; full fast+serial suites pass; no code changes needed.
