---
id: KRMA-343
title: Measure the current rendered edit with linear, regional, and native-resolution statistics
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
  - analysis
  - rendering
created: 2026-09-10T14:40:03.609Z
updated: 2026-09-10T14:53:38.923Z
depends_on:
  - KRMA-342
  - KRMA-181
order: y
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
