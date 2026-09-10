---
id: KRMA-345
title: Implement pure coordinated AutoEnhancementPolicy proposals
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
  - policy
created: 2026-09-10T14:40:05.095Z
updated: 2026-09-10T14:53:40.307Z
depends_on:
  - KRMA-343
  - KRMA-344
order: zh
board: product
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Replace independent slider formulas with a pure, coordinated `AutoEnhancementPolicy` that proposes an editable document change from frozen analysis facts and the current document.

## Scope

- Define value-only proposal types for changed controls, confidence, reasons, evidence used, algorithm version, and requested/avoided masks.
- Coordinate exposure first, then tone placement, then local/regional corrections. Prevent overlapping controls from fighting each other.
- Support tone controls (exposure, highlights, shadows, whites, blacks, contrast, and a monotonic master curve only when neutral or Auto-owned), white balance through the existing RAW/standard mapping, color controls, and supported detail controls.
- Preserve existing curves, mixer choices, grading, Looks/LUTs, composition/crop, and manual masks. Leave a value unchanged when evidence cannot justify improvement.
- Preserve warm illumination and mixed-light scenes when neutral evidence is weak.
- Use current inspector mapping and control ranges; do not duplicate or invert temperature/tint semantics.

## Acceptance criteria

- [ ] The policy is a pure deterministic function with no actor, renderer, Vision, or UI dependency.
- [ ] The proposal records exactly which controls changed and why, with per-control confidence and bounded values.
- [ ] Exposure establishes placement before highlights/shadows/whites/blacks/contrast are derived; tone controls do not double-correct the same defect.
- [ ] White balance changes only with credible neutral evidence or agreement between independent estimators, and standard-image versus RAW direction is tested.
- [ ] Vibrance/saturation and any channel mixer/detail changes are restrained and skipped when evidence is unreliable.
- [ ] User-owned curves, mixer, grading, Looks/LUTs, crop/composition, and masks are byte-for-byte or semantically preserved unless explicitly represented as Auto-owned state.
- [ ] High-key, low-key, sunset, monochrome, fog, snow, night, and backlit fixtures produce intent-preserving proposals.
- [ ] Proposal and rationale tests use ranges/invariants rather than exact floating-point equality.

## Non-goals

- Do not render or rank candidates here.
- Do not create local mask layers here.
- Do not add creative grading, grain, or crop changes.

## Likely files

- `Sources/KromoraKit/Models/AutoAdjustment.swift`
- `Sources/KromoraKit/Models/LightAdjustments.swift`
- `Sources/KromoraKit/Models/ColorAdjustments.swift`
- `Sources/KromoraKit/Models/RAWDevelopSettings.swift`
- `Sources/KromoraKit/Models/AdjustmentNode.swift`
- `Sources/KromoraKit/Models/EditDocument.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/AutoLightEngine.swift`
- `Tests/KromoraKitTests/Auto*Tests.swift`

## Verification

Add pure unit tests for neutral, clipped, cast, high-key, low-key, sunset, backlit, unsupported-detail, weak-neutral, and already-edited documents. Run focused Auto tests and `swift build`.
