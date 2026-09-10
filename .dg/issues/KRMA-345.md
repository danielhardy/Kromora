---
id: KRMA-345
title: Implement pure coordinated AutoEnhancementPolicy proposals
type: feature
status: done
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
updated: 2026-09-10T19:03:59.869Z
depends_on:
  - KRMA-343
  - KRMA-344
order: zzz
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


### Comment — pi @ 2026-09-10T19:03:23.311Z

Implementation complete on main at 9103358 (1 production file + 1 test file, +1243 lines). Pure coordinated AutoEnhancementPolicy proposals:

What was built
- AutoEnhancementPolicy.swift (new): AutoEnhancementPolicy.propose(facts:current:sourceKind:) — pure deterministic, no actor/renderer/Vision/UI. AutoEnhancementFacts (measurement tone + pixel-correlated color + scene + signal confidence + headroom + detail availability + as-shot WB), AutoSourceKind (raw/standard), AutoControlChange (previous/proposed/confidence/reason/evidence per moved control), AutoEvidenceUsed, AutoEnhancementProposal (full proposed document + change map + requested/avoided masks + notes, Codable/Sendable/Equatable, isNoOp when empty).
- Coordination: exposure places first (median + tonal-key brakes + backlight lift + clipping guard, ±1.25 EV); tails shrink by max(0.6, 1-|E|*0.25) so they correct only the residual, with extra highlight protection on positive exposure. User edits refine at half strength; controls past half range are untouched; tone section skipped entirely below 0.2 global-tone confidence.
- White balance through the existing mapping (RAW neutralTemperature/Tint photographic direction, standard temperatureTint node inverted about D65 — warm cast lowers RAW temp, raises standard temp, tint same sign). Requires credible non-mixed neutral candidate or mean/median estimator agreement; vetoes on mixed/mono/mixed-light/weak color confidence; sunset warmth preserved when neutral evidence is weak; RAW without a base temperature is left untouched.
- Color restrained (clip-driven saturation cut or muted-scene vibrance lift, skipped when mixed/mono/night/sunset/weak evidence); detail is fog-gated dehaze only (≤25, RAW detail knobs and texture/clarity never touched); master curve never synthesized in v1 (identity stays identity, custom preserved byte-for-byte).
- Mask advisory only, no layers: requested [.subject] when backlit + prominent, avoided [.face, .person] always.

Verification: 20/20 AutoEnhancementPolicyTests green (range/invariant assertions, never exact float equality); all Auto suites green; swift build clean; ci-tests fast (exit 0) and serial (328 tests, 0 failures) lanes green. No image leaves the device; no concurrency escape hatch.
