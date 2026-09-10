---
id: KRMA-344
title: Add scene classification evidence and per-signal confidence for Auto
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
  - vision
created: 2026-09-10T14:40:04.363Z
updated: 2026-09-10T14:53:39.619Z
depends_on:
  - KRMA-343
  - KRMA-181
order: z
board: product
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Strengthen Auto's interpretation of the measured photograph without turning scene labels into fixed presets. Combine existing semantic signals with Vision scene classification and expose independent confidence for every usable signal.

## Scope

- Add an internal scene-evidence value that can represent night, sunset/warm illumination, snow/high-key, fog/low-contrast, backlighting, monochrome/low-color, mixed light, and ordinary daylight as evidence with confidence rather than a hard preset.
- Use Vision scene classification where available, behind the existing Apple-only adapter and deployment guards. Keep the minimum supported macOS behavior graceful when an API is unavailable.
- Combine face, person, foreground, background, saliency, regional deltas, tone/color, and scene evidence without allowing one failed provider to erase other signals.
- Define confidence aggregation and evidence provenance so policy can scale or skip a correction when evidence is weak or contradictory.
- Keep scene facts in analysis values; recommendations belong in `AutoEnhancementPolicy`.

## Acceptance criteria

- [ ] Scene classification is optional and unavailable APIs/failures are represented as missing evidence, not fatal analysis errors.
- [ ] Night, sunset/warm light, snow/high-key, fog, backlight, monochrome, and mixed-light fixtures produce evidence with confidence and no fixed scene preset.
- [ ] Confidence is reported separately for global tone, color/neutral, scene, subject/regions, detail, and each semantic provider used by Auto.
- [ ] Conflicting or missing signals reduce confidence and correction strength predictably; they do not invent a white balance or mask.
- [ ] Existing `PhotoAnalysis`/cache versioning remains backward-compatible with neutral defaults for older cached values.
- [ ] Focused tests assert evidence ranges and degradation behavior on synthetic fixtures and on `#available`-guarded unsupported paths.

## Non-goals

- Do not change renderer controls or apply edits.
- Do not optimize Apple image-aesthetics scores.
- Do not add a required Core ML model or cloud fallback.

## Likely files

- `Sources/KromoraKit/Models/PhotoAnalysis/SceneCharacteristicsAnalyzer.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysis.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/AnalysisValueTypes.swift`
- `Tests/KromoraKitTests/PhotoAnalysis*Tests.swift`

## Verification

Run focused scene/quality/cache tests on the deployment target and current macOS SDK. Confirm no image leaves the device and no concurrency escape hatch is introduced.
