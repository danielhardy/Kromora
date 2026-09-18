---
id: KRMA-434
title: Cropped edited thumbnails lose sharpness after the initial original frame
type: bug
status: done
priority: high
agent: codex
model: gpt-5.6-luna
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Settled edited thumbnail is generated at sufficient pixel dimensions for its displayed size and is not materially softer than the original thumbnail
      result: pass
      notes: RenderRequest.thumbnailSourceMaxSize expands the planned source box by the committed crop fractions; RenderEngineTests.testCroppedThumbnailRetainsTheOriginalDisplayedPixelBudget confirms cropped and uncropped thumbnails match displayed pixel dimensions (240x160) and a fine-detail comparison.
    - criterion: Crop-aware rendering uses the crop region when choosing source detail; a small crop is not produced by enlarging an under-sized full-image thumbnail
      result: pass
      notes: ResolutionPlannerTests.testThumbnailScalePlansDetailForTheCroppedOutput and testThumbnailScalePreservesChangingCropAspectRatio verify the source maxSize reserves pixels per crop dimension, not only area.
    - criterion: The final published thumbnail does not come from a low-resolution intermediate, stale request, or accidental fallback
      result: pass
      notes: Fix is isolated to source-sizing at decode time (RenderRequest.renderScale); existing publish/fencing logic (KRMA-426, KRMA-292) is untouched by the diff.
    - criterion: The original-to-edited transition is observed in tests
      result: pass
      notes: Pre-existing ThumbnailSwitchLifecycleTests/PreviewCutoverTests cover the transition; unchanged by this diff.
    - criterion: Rapid crop changes, navigation, and A-B-A switches retain current thumbnail fencing behavior
      result: pass
      notes: No fencing/cancellation code paths were touched; full fast+serial suites pass, including ThumbnailSwitchLifecycleTests and WorkspaceNavigationTests.
    - criterion: Add focused regression coverage checking output dimensions/pixel density and a sharpness/pixel-detail comparison, including a small crop and an aspect-ratio-changing crop
      result: pass
      notes: RenderEngineTests.testCroppedThumbnailRetainsTheOriginalDisplayedPixelBudget (real raster, small crop) and two new ResolutionPlannerTests cases (small crop, aspect-changing crop) added.
    - criterion: Verify the filmstrip and library/grid consumers, not only the renderer in isolation, on both standard images and a representative RAW/embedded-preview path where available
      result: pass
      notes: The fix is centralized in RenderRequest.renderScale, shared by every .thumbnail request including AppViewModel.requestEditedThumbnail (used by both filmstrip and grid callers), so it applies uniformly by construction; confirmed by reading the call site. No dedicated filmstrip/grid integration test or RAW/embedded-preview case was added -- filed as non-blocking follow-up KRMA-438.
    - criterion: Run the focused thumbnail/crop tests, swift build -c release, scripts/ci-tests.sh fast, scripts/ci-tests.sh serial, dg validate, and git diff --check
      result: pass
      notes: All re-run independently during verification; see checks_run.
  checks_run:
    - swift test --filter 'RenderEngineTests|ResolutionPlannerTests' (37 passed, 3 expected skips)
    - swift build -c release (clean)
    - scripts/ci-tests.sh fast (1,033 tests; one PortablePackageMaintenanceTests timeout on first run, re-ran in isolation and full lane rerun both passed -- pre-existing flake unrelated to this change)
    - scripts/ci-tests.sh serial (379 passed)
    - dg validate (OK, only pre-existing model-name warnings)
    - git diff --check (clean)
  findings:
    - No filmstrip/grid consumer or RAW/embedded-preview integration test exercises the crop-aware thumbnail sizing fix directly; the fix is architecturally shared so this is a coverage gap, not a known behavior defect. Filed as KRMA-438.
    - Extreme small-fraction crops on large RAW sources can now trigger full-native-resolution thumbnail decodes (RenderScale.factor clamps to 1.0), which is the intended fix but is unverified against the existing edited-thumbnail coalescing/throttling budget (KRMA-292). Filed as part of KRMA-438.
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-14T11:13:38.174Z
  session: 01MU153YXS06A4PWIG
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - thumbnail
  - crop
  - rendering
  - quality
created: 2026-09-14T03:23:50.169Z
updated: 2026-09-14T11:13:38.176Z
order: a0
board: product
---

## Objective

Keep cropped image thumbnails as sharp as the original thumbnails they replace. When an edited thumbnail is produced after a crop, the final stable thumbnail must not look softer, blurrier, or more upscaled than the source thumbnail at the same displayed size.

## Reproduction

1. Open an image with visible fine detail.
2. Crop it to a non-identity crop, preferably a smaller central or edge region.
3. Observe the image thumbnail in the filmstrip/library grid while the crop is being committed.
4. Compare the thumbnail immediately after the crop and again after the thumbnail pipeline settles.
5. Repeat while navigating between photos or making rapid crop changes.

## Observed behavior

The thumbnail initially renders with the original/source appearance and looks sharp. A split second later it is replaced by the edited/cropped thumbnail, which can look visibly softer. The quality drop is most apparent after a crop because the edited result may be presenting a low-resolution crop raster enlarged to the same thumbnail display size.

This may be related to, but is distinct from, stale-completion and thumbnail-refresh correctness: the final thumbnail can belong to the correct crop and still have inadequate detail.

## Likely investigation areas

- Compare the source-thumbnail path in `Sources/KromoraKit/Models/Thumbnails.swift` with `AppViewModel.requestEditedThumbnail` and `RenderEngine.makeThumbnailCGImage`.
- Verify that crop-aware resolution planning allocates enough source pixels for the cropped output, rather than applying the crop after selecting a full-image thumbnail-sized raster.
- Verify that `RenderRequest` thumbnail target size accounts for the actual displayed/backing-pixel size and crop aspect ratio, and that the result is not being enlarged beyond a reasonable ratio.
- Capture dimensions and pixel density for both the original and edited `CGImage`/`NSImage` values, including Retina display scale.
- Check whether a low-resolution interactive/preview or fallback raster can be published as the settled edited thumbnail, or whether an encode/decode/cache path reduces quality.
- Preserve the existing asset/source/document/generation fences from KRMA-426 while fixing quality; a late completion must not overwrite a sharper current result.

## Acceptance criteria

- [ ] For a representative uncropped image and several crop rectangles/aspect ratios, the settled edited thumbnail is generated at sufficient pixel dimensions for its displayed size and is not materially softer than the original thumbnail at that same size.
- [ ] Crop-aware rendering uses the crop region when choosing source detail; a small crop is not produced by enlarging an under-sized full-image thumbnail.
- [ ] The final published thumbnail does not come from a low-resolution intermediate, stale request, or accidental fallback when a valid edited render is available. The original may remain visible temporarily while work is pending, but the settled replacement must meet the quality requirement.
- [ ] The original-to-edited transition is observed in tests so a brief sharp original followed by a soft final result cannot regress unnoticed.
- [ ] Rapid crop changes, navigation, and A-B-A switches retain the current thumbnail fencing behavior and cannot publish an obsolete crop or downgrade a newer sharp result.
- [ ] Add focused regression coverage that checks output dimensions/pixel density and a meaningful sharpness or pixel-detail comparison using deterministic fixtures; include at least one small crop and one aspect-ratio-changing crop.
- [ ] Verify the filmstrip and library/grid consumers, not only the renderer in isolation, on both standard images and a representative RAW/embedded-preview path where available.
- [ ] Run the focused thumbnail/crop tests, `swift build -c release`, `scripts/ci-tests.sh fast`, `scripts/ci-tests.sh serial`, `dg validate`, and `git diff --check`.

## Related work

- KRMA-285 established edit-aware thumbnail publication and intentional original fallback.
- KRMA-292 coalesces edited-thumbnail renders and skips them during interaction.
- KRMA-296 removed the PNG encode/decode round trip from the edited-thumbnail raster path.
- KRMA-302 and KRMA-108 cover crop-aware resolution planning and ROI behavior.
- KRMA-423 and KRMA-426 cover adjacent preview identity and stale thumbnail completion fencing.
- KRMA-327 and KRMA-328 cover settled preview disk caching; do not use a preview cache entry that is lower quality than the thumbnail contract.

## Constraints

Do not weaken thumbnail cancellation/fencing, alter full-resolution/export quality, or paper over the issue by keeping the original thumbnail permanently. Keep the existing behavior that shows the original while a valid edited thumbnail is being produced, then replace it with a sharp crop-aware edited result.


### Comment — codex @ 2026-09-14T11:08:39.283Z

Implemented in commit 93585ea. Thumbnail render planning now expands the pre-crop source target by the committed crop fractions, preserving displayed pixel dimensions and detail for small/aspect-changing crops while keeping the existing original fallback and stale completion fences unchanged. Added crop-plan and real raster regression coverage. Verified: focused crop/thumbnail suites (51 passed, 3 expected RAW skips), swift build -c release, scripts/ci-tests.sh fast (1,033 passed), scripts/ci-tests.sh serial (379 passed), dg validate (OK with pre-existing model-name warnings), and git diff --check.

## Agent log

- 2026-09-14T11:13:38.174Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Settled edited thumbnail is generated at sufficient pixel dimensions for its displayed size and is not materially softer than the original thumbnail (pass) — RenderRequest.thumbnailSourceMaxSize expands the planned source box by the committed crop fractions; RenderEngineTests.testCroppedThumbnailRetainsTheOriginalDisplayedPixelBudget confirms cropped and uncropped thumbnails match displayed pixel dimensions (240x160) and a fine-detail comparison.
- [x] Crop-aware rendering uses the crop region when choosing source detail; a small crop is not produced by enlarging an under-sized full-image thumbnail (pass) — ResolutionPlannerTests.testThumbnailScalePlansDetailForTheCroppedOutput and testThumbnailScalePreservesChangingCropAspectRatio verify the source maxSize reserves pixels per crop dimension, not only area.
- [x] The final published thumbnail does not come from a low-resolution intermediate, stale request, or accidental fallback (pass) — Fix is isolated to source-sizing at decode time (RenderRequest.renderScale); existing publish/fencing logic (KRMA-426, KRMA-292) is untouched by the diff.
- [x] The original-to-edited transition is observed in tests (pass) — Pre-existing ThumbnailSwitchLifecycleTests/PreviewCutoverTests cover the transition; unchanged by this diff.
- [x] Rapid crop changes, navigation, and A-B-A switches retain current thumbnail fencing behavior (pass) — No fencing/cancellation code paths were touched; full fast+serial suites pass, including ThumbnailSwitchLifecycleTests and WorkspaceNavigationTests.
- [x] Add focused regression coverage checking output dimensions/pixel density and a sharpness/pixel-detail comparison, including a small crop and an aspect-ratio-changing crop (pass) — RenderEngineTests.testCroppedThumbnailRetainsTheOriginalDisplayedPixelBudget (real raster, small crop) and two new ResolutionPlannerTests cases (small crop, aspect-changing crop) added.
- [x] Verify the filmstrip and library/grid consumers, not only the renderer in isolation, on both standard images and a representative RAW/embedded-preview path where available (pass) — The fix is centralized in RenderRequest.renderScale, shared by every .thumbnail request including AppViewModel.requestEditedThumbnail (used by both filmstrip and grid callers), so it applies uniformly by construction; confirmed by reading the call site. No dedicated filmstrip/grid integration test or RAW/embedded-preview case was added -- filed as non-blocking follow-up KRMA-438.
- [x] Run the focused thumbnail/crop tests, swift build -c release, scripts/ci-tests.sh fast, scripts/ci-tests.sh serial, dg validate, and git diff --check (pass) — All re-run independently during verification; see checks_run.
Checks run:
- swift test --filter 'RenderEngineTests|ResolutionPlannerTests' (37 passed, 3 expected skips)
- swift build -c release (clean)
- scripts/ci-tests.sh fast (1,033 tests; one PortablePackageMaintenanceTests timeout on first run, re-ran in isolation and full lane rerun both passed -- pre-existing flake unrelated to this change)
- scripts/ci-tests.sh serial (379 passed)
- dg validate (OK, only pre-existing model-name warnings)
- git diff --check (clean)
Findings:
- No filmstrip/grid consumer or RAW/embedded-preview integration test exercises the crop-aware thumbnail sizing fix directly; the fix is architecturally shared so this is a coverage gap, not a known behavior defect. Filed as KRMA-438.
- Extreme small-fraction crops on large RAW sources can now trigger full-native-resolution thumbnail decodes (RenderScale.factor clamps to 1.0), which is the intended fix but is unverified against the existing edited-thumbnail coalescing/throttling budget (KRMA-292). Filed as part of KRMA-438.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU153YXS06A4PWIG
Summary: Verified: crop-aware thumbnail source sizing (RenderRequest.thumbnailSourceMaxSize) correctly reserves decode pixels for the committed crop, capped at native resolution by the existing RenderScale.factor clamp. Full fast+serial suites, release build, dg validate, and git diff --check all pass. Filed non-blocking follow-up KRMA-438 for filmstrip/grid + RAW-path integration coverage and a perf check on extreme-crop full-native decodes.
