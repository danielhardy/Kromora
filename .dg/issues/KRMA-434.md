---
id: KRMA-434
title: Cropped edited thumbnails lose sharpness after the initial original frame
type: bug
status: ready
priority: high
agent: codex
model: gpt-5.6-luna
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
updated: 2026-09-14T03:54:30.935Z
order: z
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
