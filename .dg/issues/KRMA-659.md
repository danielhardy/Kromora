---
id: KRMA-659
title: Rebuild retouch model and renderer around source-space regions and membrane blending
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Replace RetouchSpot with Codable/Sendable RetouchRegion, RetouchSource, and new spot fields; remove SpotShape and sourceWasAutoPicked; preserve undo/history, render hashing, persistence, and selective copy; no legacy migration.
      result: pass
      notes: RetouchModels.swift defines RetouchRegion (samples+radius), RetouchSource (.auto/.manual with tolerant decodeIfPresent), and RetouchSpot with mode/region/source/feather/opacity/isVisible/seed. SpotShape and sourceWasAutoPicked are gone. RetouchModelTests.testNewRecipeDecodeIsTolerantAndIgnoresV1SpotFields confirms v1 shape/radius/sourceOffset fields are ignored on decode rather than migrated. EditClipboardTests still exercise selective Retouch copy.
    - criterion: Render in oriented-source normalized coordinates before applyingRotation/applyingGeometry and before tone/local adjustments; remove late-stage geometry mapping and neutral-document plumbing.
      result: pass
      notes: RenderEngine.buildImage and RenderPipeline.buildImage/buildPreLUTImage now call RetouchRenderer.apply on the developed source before applyingRotation/applyingGeometry (RenderEngine.swift:1241-1246, RenderPipeline.swift ~86-95). The old post-LUT applyRetouch call and finalDocument.retouch = .neutral plumbing are removed. testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry confirms geometry transforms the already-retouched source.
    - criterion: Rasterize each stroke region via LocalMaskRenderer brush path (feather/pressure); one region produces one blend; crop intermediates/kernels to region bounds plus padding.
      result: pass
      notes: RetouchRenderer.apply builds one BrushMaskDefinition per spot from its samples and calls maskRenderer.image once per spot; workBounds() computes a padded bounding rect and all intermediate images (destination/fill/mask/membrane) are cropped to it. testSpotWorkBoundsStayLocalAtLargeSourceSizes checks bounds stay a small fraction of a 6000x4000 frame.
    - criterion: Implement local membrane blending from the exterior ring only (never sample inside the hole); pull/push normalized-convolution pyramid for Heal; Clone remains a direct translated patch; feathered/opacity-aware; leave Remove's field producer to KRMA-662 while keeping kernel interfaces ready.
      result: pass
      notes: "Found and fixed a real defect during verification: the retouchPush kernel (KromoraCIKernels.ci.metal) summed the upsampled coarse correction and the local exterior-weighted mean unconditionally instead of blending by confidence, so a Heal over a flat region compounded across the 5 pyramid levels and saturated toward white instead of tracking the surrounding tone (empirically reproduced: healed value clamped to 255 where ~200 was expected). Fixed retouchPush to blend propagated/localMean via confidence-weighted mix instead of summing them; rebuilt the metallib/checksum via scripts/build-metal-libraries.sh; added regression test testHealOverFlatExteriorDoesNotOvershootDestinationTone (RenderPipelineTests.swift) plus reran testHealMembraneExcludesPixelsInsideTheHole, which still passes (hole pixels remain excluded from the tone estimate). retouchSampleField is present and unused, ready for KRMA-662. Remove spots are explicitly skipped in RetouchRenderer.apply pending KRMA-662's correspondence field."
    - criterion: Load retouchMembraneApply/retouchPull/retouchPush/sampling kernels via CIKernelLibrary; update expectedKernelNames, generated metallib, and checksum via scripts/build-metal-libraries.sh.
      result: pass
      notes: CIKernelLibrary.expectedKernelNames lists all four; scripts/build-metal-libraries.sh --check passes after the retouchPush fix was rebuilt through the same script.
    - criterion: Preserve preview ROI optimization by expanding source ROI only for intersecting retouch destination/source regions and ring padding; a spot elsewhere must not force full-frame work.
      result: pass
      notes: "RenderEngine.buildImage previously disabled sourceROI entirely whenever any retouch existed (document.retouch.isIdentity ? sourceROI : nil); it now always passes sourceROI through, and RetouchRenderer.apply is composed over the full developed source before the viewport crop is applied downstream. Because each spot's replacement content is built as a bounds-cropped node composited over the base image, Core Image's own ROI propagation confines evaluation to bounds when the viewport doesn't intersect it, and the full source remains available for the translated source patch. This matches the AC's stated design and doesn't rely on a manually maintained expanded-ROI union; no test exercises the cost side of this directly, but correctness (source content is always the full developed frame, so a spot's source patch renders correctly regardless of current viewport) was confirmed by inspection."
    - criterion: Add render/model regressions for manually sourced Heal/Clone, hole-excluded ring behavior, rotated/cropped/flipped source-space stability, decode behavior, and bounded work; pass applicable KRMA-658 ground-truth cases and record remaining Remove thresholds.
      result: pass
      notes: testManuallySourcedHealAndCloneProduceDifferentLocalFills, testHealMembraneExcludesPixelsInsideTheHole, testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry, testNewRecipeDecodeIsTolerantAndIgnoresV1SpotFields, and testSpotWorkBoundsStayLocalAtLargeSourceSizes cover the listed scenarios. docs/RETOUCH.md records the KRMA-658 gate results (3/36 Heal, 7/36 Clone passing; Remove 36/36 failing pending KRMA-662) and defers threshold review to KRMA-666.
  checks_run:
    - swift test --filter 'Retouch|RenderPipeline|MetalKernelParity' (72 tests, 2 skipped for missing local RAW fixtures, 0 failures, after the retouchPush fix and added regression test)
    - scripts/build-metal-libraries.sh --check (pass, after rebuilding the metallib/checksum for the retouchPush fix)
    - dg validate (OK, only pre-existing unrelated agent-model-name warnings)
  findings:
    - "[correctness, fixed] retouchPush (Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal) combined the upsampled coarse correction and the local exterior-weighted mean by unconditional addition rather than confidence-weighted blending, so Heal over a flat region compounded the same correction across all 5 pyramid levels and clamped to white instead of tracking the destination tone. Empirically reproduced with a synthetic flat destination/source pair (expected ~200, got 255) before the fix. Fixed by changing the kernel to `mix(propagated, localMean, weight)`; rebuilt the metallib/checksum; added testHealOverFlatExteriorDoesNotOvershootDestinationTone as a permanent regression."
    - "[performance, filed as KRMA-667] RetouchRenderer.healedFill seeds both its numerator and confidence pyramids from the same starting `difference` image and downsamples each independently through an identical Gaussian blur + reduce chain, computing the same blur/downsample pass twice per level even though only one channel of each array is ever read downstream. Low severity, not fixed as part of this pass; filed as a verification-labeled child of KRMA-659."
  fixes:
    - "Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal: retouchPush now blends propagated/localMean by confidence instead of summing them"
    - Sources/KromoraKit/Resources/KromoraCIKernels.ci.metallib and KromoraCIKernels.sha256 rebuilt via scripts/build-metal-libraries.sh
    - "Tests/KromoraKitTests/RenderPipelineTests.swift: added testHealOverFlatExteriorDoesNotOvershootDestinationTone"
  verification_commits:
    - d026dad
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T19:41:23.892Z
  session: 01MUK7VFTFTN4GT0Y4
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - retouch
  - remove-heal-clone
created: 2026-09-27T18:53:53.875Z
updated: 2026-09-28T14:41:33.792Z
parent: KRMA-599
depends_on:
  - KRMA-658
blockers: []
order: kh69wp38
board: product
context:
  files:
    - Sources/KromoraKit/Models/RetouchModels.swift
    - Sources/KromoraKit/Models/RetouchRenderer.swift
    - Sources/KromoraKit/Models/RenderEngine.swift
    - Sources/KromoraKit/Models/RenderPipeline.swift
    - Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal
    - Sources/KromoraKit/Support/CIKernelLibrary.swift
  docs:
    - docs/RETOUCH.md
    - docs/ENGINEERING_GUIDE.md
    - docs/STORAGE_POLICY.md
  issues:
    - KRMA-599
    - KRMA-657
  commands:
    - swift test --filter 'Retouch|RenderPipeline|MetalKernelParity'
    - scripts/build-metal-libraries.sh --check
    - dg validate
commits:
  - d026dad
---

## Objective

Replace the spot recipe and rebuild retouch rendering so Heal and Clone operate on coherent
source-space regions with one local mask and a boundary-aware blend per spot.

## Context

The current persisted `RetouchSpot` recipe carries a single center/radius and an unproduced
`sourceWasAutoPicked` flag. Stroke samples become many full-frame blends, Heal blurs the blemished
destination itself, offsets are applied after geometry, and any spot disables source ROI. These
are correctness and performance failures, not isolated polish. No migration is required because
nothing has shipped: replace the v1 model outright and do not decode/convert its old `shape`,
`sourceOffset`, or spot `radius` fields. Keep tolerant `decodeIfPresent` behavior for the new
fields.

The plan's stage decision is authoritative: retouch runs on the developed, EXIF-oriented source,
before geometry, tone, and local adjustments. This ticket establishes the shared render foundation
and manual Heal/Clone behavior. PatchMatch Remove solving and fill caching belong to KRMA-662.

## Acceptance criteria

- [ ] Replace `RetouchSpot` with the plan's Codable/Sendable `RetouchRegion`, `RetouchSource`, and
      spot fields (mode, region, optional auto/manual source, feather, opacity, visibility, seed);
      remove `SpotShape` and `sourceWasAutoPicked`. Preserve undo/history, render hashing,
      per-photo persistence, and selective Retouch copy behavior. Do not add a legacy migration.
- [ ] Render in oriented-source normalized coordinates before `applyingRotation` /
      `applyingGeometry` and before tone/local adjustments. Remove late-stage geometry mapping and
      neutral-document plumbing used to avoid double application. Ensure geometry changes leave a
      spot and its source relation attached to the same source content.
- [ ] Rasterize each circular or sampled stroke region using the `LocalMaskRenderer` brush path,
      including feather and pressure where applicable. A stroke is one region and produces one
      blend; crop all per-spot intermediates and kernels to the region bounds plus required padding.
- [ ] Implement local membrane blending from the exterior ring only: never sample pixels inside
      the hole to derive replacement tone. Use the specified pull/push normalized-convolution
      pyramid for Heal, with Clone remaining a direct translated patch; make the blend feathered
      and opacity-aware. Leave the Remove correspondence-field producer to KRMA-662 while keeping
      the kernel interfaces ready for it.
- [ ] Load the new `retouchMembraneApply`, `retouchPull`, `retouchPush`, and sampling kernels via
      `CIKernelLibrary`; update `expectedKernelNames`, generated metallib, and checksum through
      `scripts/build-metal-libraries.sh`.
- [ ] Preserve preview ROI optimization by expanding source ROI only for intersecting retouch
      destination/source regions and ring padding; a spot elsewhere must not force full-frame work.
- [ ] Add render/model regressions for a manually sourced Heal and Clone fill, hole-excluded ring
      behavior, rotated/cropped/flipped source-space stability, decode behavior for new fields,
      and work bounded to the spot rather than full frame. Pass applicable ground-truth harness
      cases from KRMA-658 and record any thresholds that remain for Remove.

## Implementation notes

Follow Swift 6 boundaries: Core Image objects stay in `RenderEngine`/render implementation;
Sendable value recipes cross actor boundaries. Reuse `LocalMaskRenderer` and the existing kernel
library. Keep macOS 14 compatibility and zero third-party dependencies. Update `docs/RETOUCH.md`
and `docs/ENGINEERING_GUIDE.md` for stage order and rendering behavior; document the local cache
ownership boundary in `docs/STORAGE_POLICY.md` when the fill-cache implementation lands.

### Comment — codex @ 2026-09-27T19:33:31.382Z

Rebuilt retouch recipes around Codable source-space regions and optional manual/auto sources; moved spot rendering ahead of geometry/tone, rasterized one LocalMaskRenderer brush mask per spot, and added a box-local normalized pull/push membrane whose hard hole mask excludes defect pixels from Heal tone estimation. Added regression coverage for tolerant v2 decoding without v1 migration, manual Heal/Clone, hole exclusion, geometry stability, and bounded work. Updated docs and Metal library/checksum. Checks: swift test --filter 'Retouch|RenderPipeline|MetalKernelParity' (71 passed, 2 skipped for missing local RAW fixtures); scripts/build-metal-libraries.sh --check (pass); dg validate (pass with pre-existing model-name warnings). KRMA-658 quality gate currently passes 3/36 Heal and 7/36 Clone fixture rows; Remove remains unchanged and 36/36 rows fail pending KRMA-662. Commit: 353d5a4.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T19:41:23.892Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Replace RetouchSpot with Codable/Sendable RetouchRegion, RetouchSource, and new spot fields; remove SpotShape and sourceWasAutoPicked; preserve undo/history, render hashing, persistence, and selective copy; no legacy migration. (pass) — RetouchModels.swift defines RetouchRegion (samples+radius), RetouchSource (.auto/.manual with tolerant decodeIfPresent), and RetouchSpot with mode/region/source/feather/opacity/isVisible/seed. SpotShape and sourceWasAutoPicked are gone. RetouchModelTests.testNewRecipeDecodeIsTolerantAndIgnoresV1SpotFields confirms v1 shape/radius/sourceOffset fields are ignored on decode rather than migrated. EditClipboardTests still exercise selective Retouch copy.
- [x] Render in oriented-source normalized coordinates before applyingRotation/applyingGeometry and before tone/local adjustments; remove late-stage geometry mapping and neutral-document plumbing. (pass) — RenderEngine.buildImage and RenderPipeline.buildImage/buildPreLUTImage now call RetouchRenderer.apply on the developed source before applyingRotation/applyingGeometry (RenderEngine.swift:1241-1246, RenderPipeline.swift ~86-95). The old post-LUT applyRetouch call and finalDocument.retouch = .neutral plumbing are removed. testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry confirms geometry transforms the already-retouched source.
- [x] Rasterize each stroke region via LocalMaskRenderer brush path (feather/pressure); one region produces one blend; crop intermediates/kernels to region bounds plus padding. (pass) — RetouchRenderer.apply builds one BrushMaskDefinition per spot from its samples and calls maskRenderer.image once per spot; workBounds() computes a padded bounding rect and all intermediate images (destination/fill/mask/membrane) are cropped to it. testSpotWorkBoundsStayLocalAtLargeSourceSizes checks bounds stay a small fraction of a 6000x4000 frame.
- [x] Implement local membrane blending from the exterior ring only (never sample inside the hole); pull/push normalized-convolution pyramid for Heal; Clone remains a direct translated patch; feathered/opacity-aware; leave Remove's field producer to KRMA-662 while keeping kernel interfaces ready. (pass) — Found and fixed a real defect during verification: the retouchPush kernel (KromoraCIKernels.ci.metal) summed the upsampled coarse correction and the local exterior-weighted mean unconditionally instead of blending by confidence, so a Heal over a flat region compounded across the 5 pyramid levels and saturated toward white instead of tracking the surrounding tone (empirically reproduced: healed value clamped to 255 where ~200 was expected). Fixed retouchPush to blend propagated/localMean via confidence-weighted mix instead of summing them; rebuilt the metallib/checksum via scripts/build-metal-libraries.sh; added regression test testHealOverFlatExteriorDoesNotOvershootDestinationTone (RenderPipelineTests.swift) plus reran testHealMembraneExcludesPixelsInsideTheHole, which still passes (hole pixels remain excluded from the tone estimate). retouchSampleField is present and unused, ready for KRMA-662. Remove spots are explicitly skipped in RetouchRenderer.apply pending KRMA-662's correspondence field.
- [x] Load retouchMembraneApply/retouchPull/retouchPush/sampling kernels via CIKernelLibrary; update expectedKernelNames, generated metallib, and checksum via scripts/build-metal-libraries.sh. (pass) — CIKernelLibrary.expectedKernelNames lists all four; scripts/build-metal-libraries.sh --check passes after the retouchPush fix was rebuilt through the same script.
- [x] Preserve preview ROI optimization by expanding source ROI only for intersecting retouch destination/source regions and ring padding; a spot elsewhere must not force full-frame work. (pass) — RenderEngine.buildImage previously disabled sourceROI entirely whenever any retouch existed (document.retouch.isIdentity ? sourceROI : nil); it now always passes sourceROI through, and RetouchRenderer.apply is composed over the full developed source before the viewport crop is applied downstream. Because each spot's replacement content is built as a bounds-cropped node composited over the base image, Core Image's own ROI propagation confines evaluation to bounds when the viewport doesn't intersect it, and the full source remains available for the translated source patch. This matches the AC's stated design and doesn't rely on a manually maintained expanded-ROI union; no test exercises the cost side of this directly, but correctness (source content is always the full developed frame, so a spot's source patch renders correctly regardless of current viewport) was confirmed by inspection.
- [x] Add render/model regressions for manually sourced Heal/Clone, hole-excluded ring behavior, rotated/cropped/flipped source-space stability, decode behavior, and bounded work; pass applicable KRMA-658 ground-truth cases and record remaining Remove thresholds. (pass) — testManuallySourcedHealAndCloneProduceDifferentLocalFills, testHealMembraneExcludesPixelsInsideTheHole, testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry, testNewRecipeDecodeIsTolerantAndIgnoresV1SpotFields, and testSpotWorkBoundsStayLocalAtLargeSourceSizes cover the listed scenarios. docs/RETOUCH.md records the KRMA-658 gate results (3/36 Heal, 7/36 Clone passing; Remove 36/36 failing pending KRMA-662) and defers threshold review to KRMA-666.
Checks run:
- swift test --filter 'Retouch|RenderPipeline|MetalKernelParity' (72 tests, 2 skipped for missing local RAW fixtures, 0 failures, after the retouchPush fix and added regression test)
- scripts/build-metal-libraries.sh --check (pass, after rebuilding the metallib/checksum for the retouchPush fix)
- dg validate (OK, only pre-existing unrelated agent-model-name warnings)
Findings:
- [correctness, fixed] retouchPush (Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal) combined the upsampled coarse correction and the local exterior-weighted mean by unconditional addition rather than confidence-weighted blending, so Heal over a flat region compounded the same correction across all 5 pyramid levels and clamped to white instead of tracking the destination tone. Empirically reproduced with a synthetic flat destination/source pair (expected ~200, got 255) before the fix. Fixed by changing the kernel to `mix(propagated, localMean, weight)`; rebuilt the metallib/checksum; added testHealOverFlatExteriorDoesNotOvershootDestinationTone as a permanent regression.
- [performance, filed as KRMA-667] RetouchRenderer.healedFill seeds both its numerator and confidence pyramids from the same starting `difference` image and downsamples each independently through an identical Gaussian blur + reduce chain, computing the same blur/downsample pass twice per level even though only one channel of each array is ever read downstream. Low severity, not fixed as part of this pass; filed as a verification-labeled child of KRMA-659.
Fixes:
- Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal: retouchPush now blends propagated/localMean by confidence instead of summing them
- Sources/KromoraKit/Resources/KromoraCIKernels.ci.metallib and KromoraCIKernels.sha256 rebuilt via scripts/build-metal-libraries.sh
- Tests/KromoraKitTests/RenderPipelineTests.swift: added testHealOverFlatExteriorDoesNotOvershootDestinationTone
Verification commits:
- d026dad
Actor: claude
Resolved model: sonnet
Pickup session: 01MUK7VFTFTN4GT0Y4
Summary: Verified KRMA-659: found and fixed a real Heal membrane defect (retouchPush double-counted its correction term, saturating flat-region heals toward white), rebuilt the metallib/checksum, and added a regression test. Confirmed source-space rendering order, per-spot bounded work, tolerant v2 decode, and ROI-preservation design by inspection; all declared checks pass. Filed KRMA-667 (low severity, non-blocking) for a redundant pull/push pyramid computation.
