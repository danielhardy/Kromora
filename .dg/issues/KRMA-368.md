---
id: KRMA-368
title: Double-clicking image in Edit mode should zoom instead of returning to original
type: bug
status: done
priority: medium
agent: claude
verification_agent: codex
model: opus
verification_model: gpt-5.6-terra
created: 2026-09-12T02:05:14.957Z
updated: 2026-09-12T02:31:36.492Z
order: n
board: product
commits:
  - ac38af7
---

## Objective

Fix double-click behavior for images in Edit mode so a double-click zooms the image as intended.

## Reproduction

1. Open an image in Edit mode.
2. Double-click the image.

## Observed behavior

The image shows a strange transition/effect and double-clicking brings the image back to the original/full view instead of zooming.

## Expected behavior

Double-clicking the image should zoom it as intended, without reverting to the original/full view or producing a visual glitch.

## Acceptance criteria

- [ ] Double-clicking an image in Edit mode zooms the current image.
- [ ] The image does not revert to the original/full view as a side effect.
- [ ] No visual glitch or unintended transition occurs during the zoom.
- [ ] Existing image editing and navigation behavior remains intact.

## Implementation notes

<!-- Two screenshots were provided with the report: the incorrect post-double-click state and the expected zoomed state. -->

### Comment — human @ 2026-09-12T02:06:27.459Z

Additional reproduction detail: the bug is worse for portrait/vertical images. The image may already appear incorrectly oriented (landscape) in Edit mode. Double-clicking produces a similar broken state, and double-clicking a second time does not recover or reset the photo's zoom—the image remains broken. This feels related to prior zoom/orientation issues and should be investigated for a shared underlying cause.

### Comment — human @ 2026-09-12T02:08:26.157Z

Additional observation: gesture-based zoom does not reproduce the same break immediately; the problem appears after zooming back out. Navigating to another photo and returning resets the broken zoom state, but the portrait image is still incorrectly oriented. This suggests separate or related state handling for zoom reset and image orientation.

### Comment — human @ 2026-09-12T02:09:02.062Z

Reproduction note: all documented problems were observed with ARW files.

### Comment — claude @ 2026-09-12T02:31:32.062Z

Root cause found and fixed in ac38af7 — one shared cause for the zoom breakage, in two places:

1. `AppViewModel.submitSettledPreview` looked every settled request up in the preview disk cache. That cache's key deliberately omits viewport state, so every entry is the complete canonical photo — while a zoomed request asks for a source ROI. The hit was published with the zoomed request's ROI geometry, so the whole photo was drawn at the wrong scale and origin: the glitchy frame that looked like a jump back to Fit. The write side already refused the symmetric case; the read side now does too and renders instead. Double-click hit this instantly and deterministically because it goes straight to the settled path, which is why pinch/scroll zoom (interactive first, settled after a debounce) did not break immediately.

2. A second double-click did not recover because `PreviewSurface.present` refuses a lower-detail frame when it already holds a sharper one for the same source/document. That rule assumed both frames cover the same pixels, which an ROI frame does not, so the broken fragment stayed on screen until the user navigated away. Coverage is now part of the published-detail record, and a complete photo is never refused for being less detailed than a retained ROI.

Tests: `PreviewDiskCacheTests.testZoomedSettledRequestRendersInsteadOfAdoptingTheCanonicalDiskEntry` and `PreviewSurfaceTests.testARetainedROIFrameDoesNotRefuseTheCompletePhoto`; both verified to fail without their respective change. `scripts/ci-tests.sh fast` and `serial` are green.

Not covered — the portrait-orientation observation: I could not reproduce or attribute "the portrait image is still incorrectly oriented (landscape)" to this cause. The orientation path reads consistent end to end (`CIRAWFilter.outputImage` is sensor-native, the EXIF tag is baked in `RenderPipeline.developedSource`, and `prepareSource` reports `orientedNativeSize`, which swaps axes for tags 5–8; `ImageDecoder.orientedDimensions` and `ImageMetadata` agree). Every ARW in the local fixture set is landscape (orientation 1), so there is nothing here to reproduce a quarter-turned file with. If it persists after this fix it is a separate defect and needs a portrait ARW attached to a new issue.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-12T02:31:36.490Z: Refuse a canonical full-photo disk-cache entry for a zoomed (ROI) settled request, and stop a retained ROI frame from refusing the complete photo for being less detailed. Adds two regression tests, each verified to fail without its change. Portrait-orientation sub-observation not reproducible with the available landscape-only ARW fixtures; noted as a likely separate defect.
