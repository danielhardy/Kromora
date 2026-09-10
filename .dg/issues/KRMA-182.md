---
id: KRMA-182
title: Core analysis value types (ToneStatistics, ColorStatistics, quality/timings)
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Core analysis value types exist as Sendable Codable Equatable facts
      result: pass
      notes: Implemented ToneStatistics, LuminanceDistribution, ColorStatistics, ChannelClipping, AnalysisQuality, AnalysisTimings, and AnalysisVersion.
    - criterion: Round-trip and neutral/default behavior are covered
      result: pass
      notes: Focused Codable/default/version tests pass.
    - criterion: No edit recommendations or Vision/Core Image coupling
      result: pass
      notes: Types contain facts only; source file imports Foundation and simd.
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
  completed_at: 2026-09-04T14:53:33.298Z
  session: 01MTN2Q9BLNLXVVFKE
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:48.514Z
updated: 2026-09-10T12:53:45.261Z
order: hpmr2l8f
board: product
branch: main
commits:
  - d85e6cce5ba9129573193b543ef9b74607b7ec10
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/` (suggested new group)
**Depends on:** none (foundation ticket)
**Epic:** KRMA-181 — see `docs/PHASE3_SPEC.md` §3

## 1. Problem

Before any statistics or mask code exists, Lumo needs the small, shared value types that both the
tone analyzer (KRMA-192) and the mask/region system (KRMA-184+) will build on. This ticket is
scoped **narrowly** to those primitives — it does not include `AnalyzedRegion` or any mask-related
type (those now live in KRMA-184, the `RegionMask` foundation ticket, per the revised
mask-first sequencing) and it does not include the full `PhotoAnalysis` struct (that's assembled
in KRMA-194, once masks and regional statistics exist to fill it).

## 2. Requirement (acceptance criteria)

1. `struct ToneStatistics: Sendable, Codable, Equatable` — `minimum`, `maximum`, `mean`, `p01`,
   `p05`, `p10`, `p25`, `p50`, `p75`, `p90`, `p95`, `p99`, `shadowClippingFraction`,
   `highlightClippingFraction`. Support both `linear` and `perceptual` luminance variants (either
   as two instances behind a small wrapper, or a reused `LuminanceDistribution` type — pick one,
   document why).
2. `struct ColorStatistics: Sendable, Codable, Equatable` — `meanRGB`/`medianRGB`
   (`SIMD3<Float>`), `saturationMedian`, `saturationP95`, `channelClipping`,
   `estimatedNeutrality`, `colorfulness`.
3. `struct AnalysisQuality: Sendable, Codable, Equatable` — one `Bool` per optional analysis tier
   (`globalToneAvailable`, `attentionAvailable`, `foregroundAvailable`, `faceAnalysisAvailable`,
   `peopleAnalysisAvailable`) plus `overallConfidence: Float`.
4. `struct AnalysisTimings: Sendable, Codable, Equatable` — one `Duration` per stage
   (`imagePreparation`, `globalTone`, `faceDetection`, `saliency`, `foregroundMasking`,
   `personSegmentation`, `regionalAnalysis`, `total`).
5. `struct AnalysisVersion: Sendable, Codable, Equatable, Hashable` (or `UInt16`) with bump-on-
   change discipline, mirroring `AutoAdjustmentSettings.currentVersion`'s clamp pattern in
   `Sources/LumoKit/Models/AutoAdjustment.swift:11-31`.
6. None of these types names an edit parameter (no `recommendedExposure` etc.) — facts only.
7. Swift 6 clean, zero escape hatches. No `Vision`/`CoreImage` import anywhere in this module.

## 3. Implementation notes

- Match the house style of `Sources/LumoKit/Models/EditDocument.swift` /
  `AdjustmentNode.swift` (small `Sendable, Codable, Equatable` value types, `static let
  neutral`/`.default` conveniences).
- Do **not** add `AnalyzedRegion`, `RegionKind`, or anything mask-related here — KRMA-184 owns
  that, and it's the type most at risk of drifting into two competing shapes if two tickets both
  try to define it. If you're tempted to add a mask reference field to any type in this ticket,
  stop and check whether KRMA-184 should own it instead.

## 4. Where to look

- `Sources/LumoKit/Models/AutoAdjustment.swift` — existing Tier-0 statistics + version-clamp
  precedent.
- `Sources/LumoKit/Models/EditDocument.swift`, `AdjustmentNode.swift` — house style.
- `docs/PHASE3_SPEC.md` §3.

## 5. Testing

- `Tests/LumoKitTests/AnalysisValueTypesTests.swift` (new): `Codable` round-trip for every type
  above, both fully-populated and default/neutral states. Version-clamp behavior if used.
- `swift test` stays green; no `@unchecked Sendable` anywhere.

## Agent log

- 2026-09-04T14:53:33.299Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Core analysis value types exist as Sendable Codable Equatable facts (pass) — Implemented ToneStatistics, LuminanceDistribution, ColorStatistics, ChannelClipping, AnalysisQuality, AnalysisTimings, and AnalysisVersion.
- [x] Round-trip and neutral/default behavior are covered (pass) — Focused Codable/default/version tests pass.
- [x] No edit recommendations or Vision/Core Image coupling (pass) — Types contain facts only; source file imports Foundation and simd.
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
Pickup session: 01MTN2Q9BLNLXVVFKE
Summary: Added Codable Sendable analysis facts: ToneStatistics with linear/perceptual distributions, ColorStatistics, AnalysisQuality, AnalysisTimings, and versioned AnalysisVersion.
