---
id: KRMA-184
title: RegionMask core abstraction (mask type, semantic kinds, quality levels)
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: RegionMask and NormalizedMask are stable Sendable Codable Equatable values
      result: pass
      notes: RegionMask stores a RegionMaskReference rather than pixel data; NormalizedMask validates and clamps portable payloads.
    - criterion: Semantic kinds and quality ordering are explicit and Codable
      result: pass
      notes: Subject/background/person/face/foreground-instance plus unknown forward-compatible kind are covered; analysis < preview < render.
    - criterion: Provider boundary is framework-independent
      result: pass
      notes: SemanticMaskProviding is async and no Vision/Core Image import is present in RegionMask.swift.
  checks_run:
    - swift test --filter AnalysisValueTypesTests|AnalysisImageTests|RegionMaskTests (8 passed, 0 failed)
    - swift build (passed)
    - git diff --check (clean)
  findings: []
  fixes: []
  verification_commits:
    - d85e6cce5ba9129573193b543ef9b74607b7ec10
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-04T14:53:48.252Z
  session: 01MTN2QRLZE28F4ODN
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:49.295Z
updated: 2026-09-10T12:53:45.410Z
depends_on:
  - KRMA-183
order: lb8co6tg
board: product
branch: main
commits:
  - d85e6cce5ba9129573193b543ef9b74607b7ec10
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/RegionMask.swift`
**Depends on:** KRMA-183
**Epic:** KRMA-181 — see `docs/PHASE3_SPEC.md` §3 (revised: mask foundation precedes analysis)

## 1. Problem — read this before starting

This ticket is the single most important structural decision in the whole subsystem: **masks are
a first-class, shared abstraction that both Auto and a future user-facing Masking feature consume
identically — not a private concept `PhotoAnalysis` invents for itself.**

If `PhotoAnalysis` grows its own ad-hoc mask representation now, and a real masking UI is built
later against a different one, the result is duplicated Vision calls, duplicated caches, subtly
different masks for the same photo, and coordinate-system bugs between the two. This ticket exists
to make that impossible by construction: everything downstream — Auto's regional statistics
(KRMA-193), region assembly (KRMA-194), and the eventual Masking UI (KRMA-201) — consumes the
*same* `RegionMask` type through the *same* `SemanticMaskProviding` protocol.

## 2. Requirement (acceptance criteria)

1. `struct NormalizedMask: Sendable, Codable, Equatable` — mask pixel data (or a reference to it,
   see below) in Lumo's normalized coordinate space (KRMA-183), at a specific pixel resolution.
2. `struct RegionMask: Sendable, Codable, Equatable, Identifiable` — the Lumo-owned mask
   representation. At minimum: `id`, `kind: SemanticMaskKind`, `bounds: NormalizedRect`,
   `quality: MaskQuality`, `reference: RegionMaskReference` (pointer into mask storage — actual
   pixels are cached by KRMA-185's `MaskStore`, never embedded inline), `confidence: Float`,
   `coverage: Float`. This supersedes/absorbs what an earlier draft of this plan called
   `AnalyzedRegion`'s mask field — `RegionMask` is now the canonical unit; `AnalyzedRegion`
   (KRMA-194) becomes a thin wrapper that pairs a `RegionMask` with computed statistics, not a
   competing mask definition.
3. `struct RegionMaskReference: Sendable, Codable, Equatable, Hashable` — `cacheKey:
   MaskCacheKey`, `size: PixelDimensions`, `quality: MaskQuality`.
4. `enum SemanticMaskKind: Sendable, Codable, Equatable, Hashable`:
   ```swift
   enum SemanticMaskKind {
       case subject
       case background
       case person
       case face
       case foregroundInstance(Int)
   }
   ```
   Leave room to grow (sky, hair, skin, …) without breaking `Codable` round-trips of already-
   cached masks — document the forward-compat story (e.g. an `.unknown(String)` fallback case, or
   a documented policy that new cases invalidate the mask cache via a version field).
5. `enum MaskQuality: Sendable, Codable, Equatable, Comparable { case analysis, preview, render }`
   — see `docs/PHASE3_SPEC.md` for the rationale: Auto only ever needs `.analysis` (the ~768px
   canonical image); a user painting/refining a mask for a local adjustment eventually needs
   `.render` (full-res/tile-based, built in KRMA-202). `.preview` sits between (e.g. for the
   Masking UI's live editing view before a final high-quality commit).
6. `protocol SemanticMaskProviding: Sendable`:
   ```swift
   protocol SemanticMaskProviding: Sendable {
       func mask(
           for kind: SemanticMaskKind,
           image: AnalysisImage,
           quality: MaskQuality
       ) async throws -> RegionMask
   }
   ```
   This is the seam every mask provider (KRMA-188/189/190/191) implements and the seam both Auto
   (via KRMA-193/194) and the Masking UI (KRMA-201) call through. Nothing outside the Vision
   adapter (KRMA-187) may know *how* a mask was produced — Vision today, Core ML or something else
   later, without either consumer caring.
7. `MaskCacheKey`, `PixelDimensions` — small `Sendable, Codable, Hashable` value types (pattern
   after `PhotoAssetID` in `Sources/LumoKit/Models/PhotoAsset.swift`).
8. No pixel storage/persistence logic in this ticket — that's KRMA-185. This ticket defines the
   *shape*, not the store.
9. Swift 6 clean, zero escape hatches. No `Vision`/`CoreImage` import.

## 3. Implementation notes

- This ticket is types + protocol only, same discipline as KRMA-182. Resist the urge to also
  implement `MaskStore` or a Vision provider here — keeping this ticket's surface small is what
  makes it safe for KRMA-185/186/187+ to build on in parallel once it lands.
- Think of the eventual call sites this type needs to support cleanly (from the architecture
  proposal):
  ```swift
  let subjectMask = maskService.mask(for: .subject, image: image, quality: .analysis)
  let stats = toneAnalyzer.statistics(image: image, through: subjectMask)   // KRMA-193
  ```
  and, unchanged, later from the Masking UI:
  ```swift
  let mask = maskService.mask(for: .subject, image: image, quality: .preview)
  ```
  If a field or method shape makes the second call site awkward compared to the first, fix it now
  — retrofitting this type after providers/consumers exist is much more expensive.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §3 — types this ticket supersedes/refines from the original domain model
  draft.
- `Sources/LumoKit/Models/PhotoAsset.swift` — `PhotoAssetID` pattern for `MaskCacheKey`.
- KRMA-183 — `NormalizedRect`/`NormalizedPoint`, which `NormalizedMask`/`RegionMask` build on.

## 5. Testing

- `Tests/LumoKitTests/RegionMaskTests.swift` (new): `Codable` round-trip for every type;
  `MaskQuality` ordering (`.analysis < .preview < .render`, or whatever ordering makes the
  refinement pipeline's "upgrade quality if needed" logic in KRMA-202 sensible); `SemanticMaskKind`
  equality/hashability including the associated-value `.foregroundInstance(Int)` case.
- A fake `SemanticMaskProviding` conformer used purely to prove the protocol shape compiles and
  is callable asynchronously — no real provider yet.

## Agent log

- 2026-09-04T14:53:48.253Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] RegionMask and NormalizedMask are stable Sendable Codable Equatable values (pass) — RegionMask stores a RegionMaskReference rather than pixel data; NormalizedMask validates and clamps portable payloads.
- [x] Semantic kinds and quality ordering are explicit and Codable (pass) — Subject/background/person/face/foreground-instance plus unknown forward-compatible kind are covered; analysis < preview < render.
- [x] Provider boundary is framework-independent (pass) — SemanticMaskProviding is async and no Vision/Core Image import is present in RegionMask.swift.
Checks run:
- swift test --filter AnalysisValueTypesTests|AnalysisImageTests|RegionMaskTests (8 passed, 0 failed)
- swift build (passed)
- git diff --check (clean)
Findings:
- None
Fixes:
- None
Verification commits:
- d85e6cce5ba9129573193b543ef9b74607b7ec10
Actor: codex
Resolved model: unknown
Pickup session: 01MTN2QRLZE28F4ODN
Summary: Added the shared RegionMask contract, normalized payload type, semantic mask kinds, explicit quality levels, cache key/reference values, and SemanticMaskProviding seam.
