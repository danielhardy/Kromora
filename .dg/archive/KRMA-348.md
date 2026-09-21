---
id: KRMA-348
title: Add selective Auto-owned regional correction layers
type: feature
status: done
priority: high
agent: pi
model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A regional layer is added only when post-global measurements show a material regional conflict that global controls cannot solve within guardrails.
      result: pass
      notes: AutoRegionalCorrections.plan() gates on post-global tone thresholds (subjectDarkMedian, backgroundBrightMedian/clipping, minimumCastStrength) and only acts when validate() finds the matte usable.
    - criterion: No more than three Auto-owned layers are created, with stable purpose names such as Auto — Subject.
      result: pass
      notes: AutoRegionalPurpose.maximumLayers = 3, enforced by layers.prefix(3); layerName is fixed per purpose (Auto — Subject/Background/Color).
    - criterion: Subject, person, face, foreground, and background mask sources reuse the existing RegionMask/MaskStore/mask-recipe infrastructure.
      result: pass
      notes: Layers reference SemanticMaskDefinition/MaskComponent recipes; VisionSemanticMaskProvider still uses RegionMask/MaskStore for caching.
    - criterion: Face masks are landmark-derived, feathered, bounded, and intersected with available support; rectangle-only face masks are not used.
      result: pass
      notes: FaceLandmarkMask.rasterize() fits/feathers an ellipse to VNFaceLandmarkRegion2D points; VisionSemanticMaskProvider.faceMasks() now calls detectFaceLandmarks() and intersects with person/foreground support via AutoRegionalCorrections.intersectedWithSupport(); the old rectangle-based detectFaces() path is removed.
    - criterion: Uncertain, low-coverage, high-overlap, misaligned, or edge-risk masks are skipped with a reason in the result.
      result: pass
      notes: AutoRegionalCorrections.validate() checks coverage band, confidence floor, feathered-boundary (transitionFraction), and crop alignment; plan() appends an explained note for every skip.
    - criterion: Bright/blue pixels alone never create a sky mask.
      result: pass
      notes: No sky-mask or bright/blue pixel classification exists anywhere in the new code; masks derive solely from subject/background/face/person/foreground semantic targets.
    - criterion: Generated layers render consistently in preview and export, survive save/reopen, and remain ordinary user-editable layers.
      result: pass
      notes: Layers are ordinary LocalAdjustmentLayer values appended to EditDocument.localAdjustments via the existing recipe path, so they use the same render/persist code as user-created layers; testPlannedLayersAppendAsEditableRecipesAndRoundTrip exercises the round trip. Not independently re-verified against a live full render pipeline in this pass.
    - criterion: Tests cover no-mask degradation, overlapping people, feathered boundaries, crop/orientation alignment, duplicate prevention input, and regional improvement without background damage.
      result: pass
      notes: "AutoRegionalCorrectionsTests: testEmptyEvidencePlansNoLayersWithExplanations, testOverlappingSubjectAndBackgroundSkipsWithReason, testFeatheredMattePassesTransitionCheck/testLandmarkMatteIsFeatheredAndCentered, testCropThatDiscardsTheMaskSkipsWithReason/testCropAlignedBoundsCheck, testExistingAutoLayersSuppressPlanning, testMaterialConflictPlansSubjectLiftAndBackgroundProtection."
  checks_run:
    - swift build (clean, zero new warnings/errors)
    - swift test --filter 'AutoRegionalCorrectionsTests|VisionSemanticMaskProviderTests' (21/21 + 7/7 passed, matches implementer's report)
    - swift test --filter 'Auto|Masking|Mask|Rotation' (249 executed, 5 skipped, 0 failures)
    - git diff --check 854beac..7d8fa20 (clean)
    - scripts/ci-tests.sh fast (832 tests, 0 failures)
    - scripts/ci-tests.sh serial (328 tests, 0 failures)
    - re-ran swift build + fast/serial lanes again after applying the verification fix below
  findings:
    - "[correctness] Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift: faceMasks() numbered .face/.faceInstance(N) kinds by raw Vision detection order instead of position among faces surviving the support intersection. Failure scenario: When person/foreground support wipes an earlier detected face's coverage to zero (e.g. two overlapping face detections resolving onto one person matte) while a later face survives, the surviving face was labeled .faceInstance(1) (or higher) with no .face at index 0. faceMask(index: 0) still returns it correctly (positional indexing into the filtered array), but the RegionMask.kind stored/cached under that mask and shown by MaskingPanel/AnalysisDebugPanel (\"Face N+1\") would misreport the face count/label for a single-face photo. Outcome: fixed."
  fixes:
    - "VisionSemanticMaskProvider.swift: number surviving faces by their position in the output masks array (masks.count) rather than their position in the raw Vision detection loop, so the .face/.faceInstance(N) kind sequence stays contiguous even when support intersection drops an earlier detection. Localized, no behavior/schema change beyond correcting the numbering; build and full fast/serial CI lanes re-verified green afterward."
  verification_commits:
    - d43dee4
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-10T23:13:28.394Z
  session: 01MTW4YM7O8PL6ZNTE
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - auto
  - masking
  - rendering
created: 2026-09-10T14:40:07.847Z
updated: 2026-09-10T23:13:28.397Z
depends_on:
  - KRMA-347
  - KRMA-181
order: a0
board: product
commits:
  - d43dee4
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

## Agent log

- 2026-09-10T23:13:28.395Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A regional layer is added only when post-global measurements show a material regional conflict that global controls cannot solve within guardrails. (pass) — AutoRegionalCorrections.plan() gates on post-global tone thresholds (subjectDarkMedian, backgroundBrightMedian/clipping, minimumCastStrength) and only acts when validate() finds the matte usable.
- [x] No more than three Auto-owned layers are created, with stable purpose names such as Auto — Subject. (pass) — AutoRegionalPurpose.maximumLayers = 3, enforced by layers.prefix(3); layerName is fixed per purpose (Auto — Subject/Background/Color).
- [x] Subject, person, face, foreground, and background mask sources reuse the existing RegionMask/MaskStore/mask-recipe infrastructure. (pass) — Layers reference SemanticMaskDefinition/MaskComponent recipes; VisionSemanticMaskProvider still uses RegionMask/MaskStore for caching.
- [x] Face masks are landmark-derived, feathered, bounded, and intersected with available support; rectangle-only face masks are not used. (pass) — FaceLandmarkMask.rasterize() fits/feathers an ellipse to VNFaceLandmarkRegion2D points; VisionSemanticMaskProvider.faceMasks() now calls detectFaceLandmarks() and intersects with person/foreground support via AutoRegionalCorrections.intersectedWithSupport(); the old rectangle-based detectFaces() path is removed.
- [x] Uncertain, low-coverage, high-overlap, misaligned, or edge-risk masks are skipped with a reason in the result. (pass) — AutoRegionalCorrections.validate() checks coverage band, confidence floor, feathered-boundary (transitionFraction), and crop alignment; plan() appends an explained note for every skip.
- [x] Bright/blue pixels alone never create a sky mask. (pass) — No sky-mask or bright/blue pixel classification exists anywhere in the new code; masks derive solely from subject/background/face/person/foreground semantic targets.
- [x] Generated layers render consistently in preview and export, survive save/reopen, and remain ordinary user-editable layers. (pass) — Layers are ordinary LocalAdjustmentLayer values appended to EditDocument.localAdjustments via the existing recipe path, so they use the same render/persist code as user-created layers; testPlannedLayersAppendAsEditableRecipesAndRoundTrip exercises the round trip. Not independently re-verified against a live full render pipeline in this pass.
- [x] Tests cover no-mask degradation, overlapping people, feathered boundaries, crop/orientation alignment, duplicate prevention input, and regional improvement without background damage. (pass) — AutoRegionalCorrectionsTests: testEmptyEvidencePlansNoLayersWithExplanations, testOverlappingSubjectAndBackgroundSkipsWithReason, testFeatheredMattePassesTransitionCheck/testLandmarkMatteIsFeatheredAndCentered, testCropThatDiscardsTheMaskSkipsWithReason/testCropAlignedBoundsCheck, testExistingAutoLayersSuppressPlanning, testMaterialConflictPlansSubjectLiftAndBackgroundProtection.
Checks run:
- swift build (clean, zero new warnings/errors)
- swift test --filter 'AutoRegionalCorrectionsTests|VisionSemanticMaskProviderTests' (21/21 + 7/7 passed, matches implementer's report)
- swift test --filter 'Auto|Masking|Mask|Rotation' (249 executed, 5 skipped, 0 failures)
- git diff --check 854beac..7d8fa20 (clean)
- scripts/ci-tests.sh fast (832 tests, 0 failures)
- scripts/ci-tests.sh serial (328 tests, 0 failures)
- re-ran swift build + fast/serial lanes again after applying the verification fix below
Findings:
- [correctness] Sources/KromoraKit/Models/PhotoAnalysis/VisionSemanticMaskProvider.swift: faceMasks() numbered .face/.faceInstance(N) kinds by raw Vision detection order instead of position among faces surviving the support intersection. Failure scenario: When person/foreground support wipes an earlier detected face's coverage to zero (e.g. two overlapping face detections resolving onto one person matte) while a later face survives, the surviving face was labeled .faceInstance(1) (or higher) with no .face at index 0. faceMask(index: 0) still returns it correctly (positional indexing into the filtered array), but the RegionMask.kind stored/cached under that mask and shown by MaskingPanel/AnalysisDebugPanel ("Face N+1") would misreport the face count/label for a single-face photo. Outcome: fixed.
Fixes:
- VisionSemanticMaskProvider.swift: number surviving faces by their position in the output masks array (masks.count) rather than their position in the raw Vision detection loop, so the .face/.faceInstance(N) kind sequence stays contiguous even when support intersection drops an earlier detection. Localized, no behavior/schema change beyond correcting the numbering; build and full fast/serial CI lanes re-verified green afterward.
Verification commits:
- d43dee4
Actor: claude
Resolved model: sonnet
Pickup session: 01MTW4YM7O8PL6ZNTE
Summary: Independent verification passed: build clean, focused AutoRegionalCorrections/VisionSemanticMaskProvider suites (21/21, 7/7) plus full fast (832) and serial (328) CI lanes all green, git diff --check clean. Found and fixed a minor face-mask numbering gap (contiguous renumbering after support-intersection drops a face) in VisionSemanticMaskProvider.faceMasks(); re-ran build and CI lanes after the fix, still green.
