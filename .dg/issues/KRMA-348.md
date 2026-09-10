---
id: KRMA-348
title: Add selective Auto-owned regional correction layers
type: feature
status: review
priority: high
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - masking
  - rendering
created: 2026-09-10T14:40:07.847Z
updated: 2026-09-10T20:10:26.521Z
depends_on:
  - KRMA-347
  - KRMA-181
order: w
board: product
claim:
  actor: pi
  session: 01MTVYH3P5N53XFML4
  claimed_at: 2026-09-10T20:05:27.125Z
  expires_at: 2026-09-10T21:05:27.125Z
---

## Parent epic

KRMA-341 — Content-aware Auto engine and renderer-backed candidate evaluation.


## Objective

Create local corrections only when regional evidence shows that a global proposal cannot improve an important region without damaging another. Use existing editable mask recipes and rendering, with no inferred sky mask or duplicate mask implementation.

## Scope

- Re-measure subject/background/face/foreground regions after the selected global proposal.
- Support at most three Auto-owned layers: subject lift, bright-background protection, and localized color correction.
- Prefer person/foreground segmentation for visible edits; use saliency only for subject choice, never as an automatic adjustment mask by itself.
- Replace rectangle-based face treatment with feathered landmark-derived regions intersected with person/foreground support where available.
- Refine boundaries and validate coverage, overlap, edge contrast, confidence, and orientation/crop alignment before adding a layer.
- Expose ordinary editable controls and normal preview/export rendering for generated layers.

## Acceptance criteria

- [ ] A regional layer is added only when post-global measurements show a material regional conflict that global controls cannot solve within guardrails.
- [ ] No more than three Auto-owned layers are created, with stable purpose names such as `Auto — Subject`.
- [ ] Subject, person, face, foreground, and background mask sources reuse the existing `RegionMask`/`MaskStore`/mask-recipe infrastructure.
- [ ] Face masks are landmark-derived, feathered, bounded, and intersected with available support; rectangle-only face masks are not used.
- [ ] Uncertain, low-coverage, high-overlap, misaligned, or edge-risk masks are skipped with a reason in the result.
- [ ] Bright/blue pixels alone never create a sky mask.
- [ ] Generated layers render consistently in preview and export, survive save/reopen, and remain ordinary user-editable layers.
- [ ] Tests cover no-mask degradation, overlapping people, feathered boundaries, crop/orientation alignment, duplicate prevention input, and regional improvement without background damage.

## Non-goals

- Do not build a new masking UI.
- Do not replace or mutate manual masks.
- Do not infer arbitrary semantic classes beyond available Vision signals.

## Likely files

- `Sources/KromoraKit/Models/LocalMaskModels.swift`
- `Sources/KromoraKit/Models/LocalMaskRenderer.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/RegionMask.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/MaskOperations.swift`
- `Sources/KromoraKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift`
- `Sources/KromoraKit/Models/EditDocument.swift`
- `Sources/KromoraKit/ViewModels/AppViewModel+Masking.swift`
- `Tests/KromoraKitTests/Masking*Tests.swift`

## Verification

Run focused mask/render tests, generated backlit/person/face fixtures, preview/export parity tests, `swift build`, and `git diff --check`.


### Comment — pi @ 2026-09-10T20:09:59.623Z

Completion summary (pi): selective Auto-owned regional correction layers are implemented on branch krma-348-regional-corrections at 7d8fa20 (base cf46f2a plus a ±800K comment correction). Pure AutoRegionalCorrections planner emits at most three ordinary editable semantic recipes (Auto — Subject / Background / Color) only on material post-global regional conflict, with explained skips for missing evidence, unverifiable separation, overlap, hard edges, coverage/confidence, crop misalignment, and existing Auto layers; FaceLandmarkMask replaces rectangle face treatment with feathered landmark-derived ellipses intersected with person/foreground support, and VisionSemanticMaskProvider.faceMasks now skips landmark-less faces instead of boxing them. Verification: 21/21 AutoRegionalCorrectionsTests, 81/81 across the four Auto suites, 45/45 masking/rotation neighbors, VisionSemanticMaskProviderTests 7/7, swift build clean, git diff --check clean, scripts/ci-tests.sh fast and serial lanes exit 0. Moving to review for verification.
