---
id: KRMA-192
title: Global tone + color statistics analyzer (Tier 0)
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Global analyzer uses the canonical AnalysisImage and existing histogram machinery
      result: pass
      notes: GlobalToneAnalyzer requests a neutral RenderEngining histogram at the AnalysisImage dimensions, retaining rasterization inside RenderEngine and avoiding a second per-pixel image path.
    - criterion: ToneStatistics cover perceptual and linear variants with explicit luminance semantics
      result: pass
      notes: The implementation documents the sRGB renderer space and Rec.709 Y formula inherited from HistogramData; perceptual bins remain encoded and linear bins apply the sRGB transfer decode.
    - criterion: ColorStatistics are computed from the same pass
      result: pass
      notes: Mean/median RGB, clipping, neutrality, colorfulness, and marginal saturation estimates derive from the same validated 256-bin histogram.
    - criterion: Tier-0 availability and failure behavior are explicit
      result: pass
      notes: Successful analysis returns AnalysisQuality.globalToneAvailable=true; unavailable and malformed histograms throw typed GlobalToneAnalysisError values.
    - criterion: Swift 6 and no Vision dependency
      result: pass
      notes: The analyzer is Sendable, renderer-injectable for deterministic tests, imports no Vision, and introduces no concurrency escape hatch.
  checks_run:
    - swift test --filter GlobalToneAnalyzerTests --filter VisionSemanticMaskProviderTests --filter RegionMaskTests (12 passed, 0 failed)
    - swift build (passed as part of focused test build)
    - git diff --check (clean)
  findings:
    - Color saturation is intentionally a conservative marginal estimate because HistogramData does not retain per-pixel channel correlation; a future masked/color pass can refine it without changing the Tier-0 seam.
  fixes: []
  verification_commits:
    - 31748f5
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-04T15:16:44.534Z
  session: 01MTN3K9I38U3X3C1E
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:52.506Z
updated: 2026-09-10T12:53:46.008Z
depends_on:
  - KRMA-182
  - KRMA-183
order: wz4w97mp
board: product
branch: main
commits:
  - 31748f5
---

**Type:** Feature
**Component:** new `Sources/LumoKit/Models/PhotoAnalysis/GlobalToneAnalyzer.swift`
**Depends on:** KRMA-182, KRMA-183
**Epic:** KRMA-181 — see `docs/ENGINEERING_GUIDE.md (Tier 0)

## 1. Problem

Tier 0 (global tone + color statistics) is the only tier that's ever required — Auto must degrade
to it alone if every Vision/mask request fails or is unavailable. It should exist and be solid
before mask-dependent analysis (KRMA-193+) is built, and it works from the canonical
`AnalysisImage` (KRMA-183) with no mask/Vision dependency at all.

## 2. Requirement (acceptance criteria)

1. Computes `ToneStatistics` (both `linear`/`perceptual`, KRMA-182) from an `AnalysisImage` using
   a high-resolution luminance histogram (256 or 512 bins).
2. Luminance definition explicit and documented: `Y = 0.2126R + 0.7152G + 0.0722B`, computed once
   per variant — document the color space each is sampled in, reconciling with whatever
   `Histogram.swift` already assumes for the existing `AutoImageStatistics`.
3. `ColorStatistics` (KRMA-182) computed from the same canonical image, same pass where practical.
4. **No per-pixel Swift loops over large buffers** — reuse `Sources/LumoKit/Models/Histogram.swift`'s
   GPU-backed histogram machinery (`RenderEngine.histogram`) if it can be pointed at the analysis
   image, rather than reimplementing.
5. No `Vision` import — this is the one tier that never depends on masks or Vision.
6. Populates `AnalysisQuality.globalToneAvailable = true` on success; this is the one tier allowed
   to be a hard requirement (a thrown error) rather than soft-degrading.
7. Swift 6 clean, zero escape hatches.

## 3. Implementation notes

- Reuse `RenderEngine.histogram(...)` rather than a second histogram code path.

## 4. Where to look

- `Sources/LumoKit/Models/Histogram.swift`, `RenderEngine.swift` (`func histogram`).
- `Sources/LumoKit/Models/AutoAdjustment.swift:63-100` — existing percentile/weighted-mean math to
  reuse or adapt.

## 5. Testing

- `Tests/LumoKitTests/GlobalToneAnalyzerTests.swift` (new): synthetic images with hand-computable
  expected percentiles; clipping-fraction correctness for deliberately over/underexposed fixtures.
- Rough timing check against the < 20 ms Tier-0 budget (`docs/ENGINEERING_GUIDE.md) — full benchmark
  infra is KRMA-206.

## Agent log

- 2026-09-04T15:16:44.535Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Global analyzer uses the canonical AnalysisImage and existing histogram machinery (pass) — GlobalToneAnalyzer requests a neutral RenderEngining histogram at the AnalysisImage dimensions, retaining rasterization inside RenderEngine and avoiding a second per-pixel image path.
- [x] ToneStatistics cover perceptual and linear variants with explicit luminance semantics (pass) — The implementation documents the sRGB renderer space and Rec.709 Y formula inherited from HistogramData; perceptual bins remain encoded and linear bins apply the sRGB transfer decode.
- [x] ColorStatistics are computed from the same pass (pass) — Mean/median RGB, clipping, neutrality, colorfulness, and marginal saturation estimates derive from the same validated 256-bin histogram.
- [x] Tier-0 availability and failure behavior are explicit (pass) — Successful analysis returns AnalysisQuality.globalToneAvailable=true; unavailable and malformed histograms throw typed GlobalToneAnalysisError values.
- [x] Swift 6 and no Vision dependency (pass) — The analyzer is Sendable, renderer-injectable for deterministic tests, imports no Vision, and introduces no concurrency escape hatch.
Checks run:
- swift test --filter GlobalToneAnalyzerTests --filter VisionSemanticMaskProviderTests --filter RegionMaskTests (12 passed, 0 failed)
- swift build (passed as part of focused test build)
- git diff --check (clean)
Findings:
- Color saturation is intentionally a conservative marginal estimate because HistogramData does not retain per-pixel channel correlation; a future masked/color pass can refine it without changing the Tier-0 seam.
Fixes:
- None
Verification commits:
- 31748f5
Actor: codex
Resolved model: unknown
Pickup session: 01MTN3K9I38U3X3C1E
Summary: Added renderer-backed Tier-0 global tone/color analysis with dual luminance statistics, typed validation, and quality reporting.
