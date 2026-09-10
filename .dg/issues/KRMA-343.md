---
id: KRMA-343
title: Measure the current rendered edit with linear, regional, and native-resolution statistics
type: feature
status: done
priority: high
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings:
    - "MEDIUM/correctness: CurrentEditMeasurementCache.filename (CurrentEditMeasurement.swift) used Swift Hasher (process-randomized seed) instead of a stable digest, unlike the SHA256-based PhotoAnalysisCache.filename precedent in the same directory. Every process launch produced a different on-disk filename for the same cache key, so the disk cache never hit across app restarts and old entries accumulated unboundedly. Fixed: replaced with SHA256(key.cacheKey), matching PhotoAnalysisCache.filename exactly (added CryptoKit import)."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-10T18:05:15.795Z
  session: 01MTVU579T7MAC8NH1
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - analysis
  - rendering
created: 2026-09-10T14:40:03.609Z
updated: 2026-09-10T18:05:15.798Z
depends_on:
  - KRMA-342
  - KRMA-181
order: a0
board: product
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Add a document-aware measurement pipeline for Auto. Existing analysis mostly measures source data or an empty `EditDocument`; Auto must measure the current rendered edit and then evaluate proposals against the same measurable facts.

## Scope

- Build an internal analysis view at approximately 768 pixels on the long edge, with configuration and explicit source/document/render revisions.
- Measure actual rendered pixels for linearized-RGB luminance, display/perceptual luminance, percentile/tail distributions, channel clipping, saturation, hue distribution, neutral candidates, local contrast, and regional tone/color.
- Preserve highlight headroom separately from the display histogram so highlight recovery is not inferred from clipped display pixels alone.
- Measure noise and edge detail from a bounded set of native-resolution patches. A reduced preview must not decide sharpening or noise reduction.
- Reuse the existing `PhotoAnalysis`, `AnalysisImage`, `MaskedToneAnalyzer`, `MaskStore`, and cache infrastructure. Missing semantic masks must leave global measurements usable.
- Provide a controlled analysis-document transformation that excludes LUTs, grading, grain, and decorative vignette for correction proposals, while retaining the complete edit for final candidate evaluation.

## Acceptance criteria

- [ ] A current-edit measurement request includes the effective document/source revision and cannot silently measure an empty or stale document.
- [ ] Linear luminance is computed from linearized RGB; display histogram and highlight headroom are separate values.
- [ ] Saturation/hue are derived from the same rendered pixel samples, not approximated from independent channel histograms.
- [ ] Neutral candidates expose confidence and location/region evidence; no neutral correction is recommended when evidence is weak or mixed.
- [ ] Global and regional measurements include confidence/quality independently; a failed mask does not discard global tone/color facts.
- [ ] Native-resolution noise/detail sampling is bounded, deterministic for a fixture, and reports unavailable rather than guessing when unsupported.
- [ ] Orientation, crop, color space, and RAW/standard image paths are covered by focused tests.
- [ ] Cache keys/fingerprints distinguish source, effective document, analysis configuration, and render revision.

## Non-goals

- Do not choose slider values here.
- Do not add new semantic mask providers; consume the completed KRMA-181 infrastructure.
- Do not persist image pixels in the edit document.

## Likely files

- `Sources/KromoraKit/Models/PhotoAnalysis/AnalysisImage.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/GlobalToneAnalyzer.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/MaskedToneAnalyzer.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysis.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift`
- `Sources/KromoraKit/Models/RenderEngine.swift`
- `Sources/KromoraKit/Models/EditDocument.swift`
- `Tests/KromoraKitTests/PhotoAnalysis*Tests.swift`

## Verification

Add generated fixtures for neutral, clipped, high-key, low-key, color-cast, and edited inputs. Run focused measurement tests and the fast test lane.


### Comment — pi @ 2026-09-10T16:59:16.944Z

Implementation complete on main at 71d167a (5 files, +1902/-6). CurrentEditMeasurer renders the effective document at the 768px analysis scale through the new CurrentEditSampling seam (production RenderEngine returns real RGBA8; FakeRenderEngine gained sampling stubs) and derives every fact from those same samples: linear-vs-display luminance via the shared histogram mapping, pixel-correlated saturation/12-bin hue/neutral candidates with mixed-frame decline, block local contrast, and HighlightHeadroom kept separate from display clipping (RAW decoder-gated, headroomEV never estimated from display bins). Regional facts reuse MaskedToneAnalyzer/MaskStore under the same effective document with per-mask failure counting; native noise/detail uses a bounded deterministic patch plan (max 8, center-probe first) and reports unavailable. GlobalToneAnalyzer/MaskedToneAnalyzer gained document-aware overloads; existing source-measurement behavior unchanged. Analysis-view transform reused from AutoCandidateEvaluation; native ROI crops in production return nil (documented) until a bounded ROI render exists. Verification: 22/22 CurrentEditMeasurementTests pass (revision guards, linear/display separation, same-sample color, neutral recommend/decline, mask-failure independence, effective-document regional, planner bounds/determinism, orientation/crop/space/RAW paths, cache key distinctions + round-trip); neighboring suites (GlobalTone, MaskedTone, Assembly, Coordinator, CandidateEvaluation, LightEngine, Cache, Image, ValueTypes) pass; scripts/ci-tests.sh fast (729) and serial lanes exit 0; swift build clean; dg validate OK; git diff --check clean. Known limitation: production nativeDetailPatches reports unavailable (no ROI-crop render yet); sharpening/NR must not consume preview-scale detail. No policy/selection changes per non-goals.

## Agent log

- 2026-09-10T18:05:15.795Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- MEDIUM/correctness: CurrentEditMeasurementCache.filename (CurrentEditMeasurement.swift) used Swift Hasher (process-randomized seed) instead of a stable digest, unlike the SHA256-based PhotoAnalysisCache.filename precedent in the same directory. Every process launch produced a different on-disk filename for the same cache key, so the disk cache never hit across app restarts and old entries accumulated unboundedly. Fixed: replaced with SHA256(key.cacheKey), matching PhotoAnalysisCache.filename exactly (added CryptoKit import).
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTVU579T7MAC8NH1
Summary: Independent verification passed after one localized fix: CurrentEditMeasurementCache used Swift's process-randomized Hasher for its on-disk cache filename instead of the SHA256 digest used by the adjacent PhotoAnalysisCache, which would have silently defeated the disk cache across app restarts. Fixed to match precedent; build and full fast test lane (729 tests) plus the 22 CurrentEditMeasurementTests pass.
