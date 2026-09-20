---
id: KRMA-482
title: Panning at 800% zoom leaves unrendered gaps beside the visible image
type: bug
status: backlog
priority: high
labels:
  - preview
  - zoom
  - rendering
created: 2026-09-20T16:04:31.732Z
updated: 2026-09-20T16:04:31.732Z
order: z
board: product
---

## Objective

When zoomed to 800% in the Edit canvas and panning, every part of the photo that scrolls into view must render at full detail. Currently a region of the viewport stays empty (canvas background) instead of resolving.

## Context

User report (2026-09-20), with two screenshots of a chickadee RAW in the Edit view:

1. Fit view: the full image renders normally.
2. 800% zoom, panned onto the bird's head/eye: the image content only fills the right ~60% and lower ~90% of the canvas. The area to the left of the eye, and a strip along the top, is empty canvas background. That region is inside the photo (the bird's face continues to the left in the fit view) and should show pixels.

Suspicion, not yet confirmed: at high zoom the preview renders only a viewport-sized source ROI (`plan.previewSourceROI(...)` in `AppViewModel.scheduleInteractivePreview` / `displayRequest`, `sourceROI` at `AppViewModel.swift` ~3829 and ~3984). If panning moves the viewport beyond the rendered ROI, or the ROI frame is published for a stale pan offset, the uncovered part of the drawable has nothing to sample and shows background. Related pieces: the retained-detail logic and `coversPresentationExtent` in `PreviewSurface.swift` (~141), `didPresentVisibleFrame`, and the `CanvasNavigation` pan/zoom state. Note the working tree has uncommitted edits in `CanvasNavigation.swift`, `PreviewSurface.swift`, `PreviewView.swift` and `PreviewSurface.metal`, so reproduce on a clean `main` first to tell whether they are involved.

### Additional observation (2026-09-20)

Adjusting the tone curve while zoomed resets the image pan (the zoom level is kept). That points at the pan (`focalPoint`) being lost or recomputed whenever a new render is published or scheduled for an edit, and the gap when panning may be the same fault: the frame and the pan offset get out of step. Check:
- Whether an edit-triggered `schedulePreview()` / `scheduleInteractivePreview()` rebuilds `CanvasNavigation` or resets `focalPoint` (compare with `toggleFitAndRememberedZoom` and `resetForSource`, which do reset it to centre).
- Whether the ROI frame from the edit render is positioned for the centred focal point rather than the current pan.
- Whether the reset also happens for other edits (sliders, masks), or only the tone curve. The curve editor may commit through a different path.
- Whether the gap in the screenshots appears right after a curve or slider edit, not only from panning.

## Reproduction

1. Open the app, Edit mode, any RAW (seen with a 6000x4000-class bird photo).
2. Zoom to 800%.
3. Pan (drag / scroll) so a different part of the photo is under the viewport.
4. Also try editing (tone curve, then a slider) while panned, and note whether the pan resets or the gap appears/disappears.
5. Observe empty regions inside the photo bounds, also check whether they fill in after the pan settles (quiet period) or stay empty permanently.

Record: pan input type (drag, trackpad scroll, keyboard), whether the gap appears during the pan only or persists after release, and whether 100%/200%/400% show the same.

## Requirements

- At any zoom level, including 800%, all viewport area that lies inside the photo renders image pixels; only area genuinely outside the photo shows canvas background.
- During an active pan an interactive frame may be lower quality, but never blank inside the photo bounds. Retain the previous frame or cover the newly exposed region until the new ROI render lands.
- After the pan settles, the full-quality ROI render covers the viewport with no seams and no visible jump.
- Stale ROI frames must not be presented against a newer pan offset.
- No regression to memory use or to the fit-view and full-resolution export paths.

## Acceptance criteria

- [ ] Root cause identified and written into the ticket (which ROI/pan/presentation value was wrong).
- [ ] Panning at 800% never shows empty canvas inside the photo, during the pan or after it settles, verified in the running app (screenshot or recording attached).
- [ ] Editing (tone curve and sliders) while zoomed and panned keeps the pan offset; a test asserts the focal point survives an edit-triggered preview.
- [ ] Same check at 400% and at the maximum zoom, and at all four image edges (edge pans clamp correctly).
- [ ] A test with a fake render engine asserts that the ROI requested after each pan offset covers the visible viewport rect in source coordinates.
- [ ] A regression test covers a pan that moves the viewport outside the last published ROI.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass.

## Implementation notes

- Start with `plan.previewSourceROI` and how the ROI is derived from the current pan offset and zoom; check for a missing margin or an ROI computed before the pan offset is updated.
- Check the drawable/shader path (`PreviewSurface.metal`) for how an ROI frame is positioned in presentation space.
- See `docs/TESTING.md` for tracing/profiling guidance, and `docs/ENGINEERING_GUIDE.md` for render/resource boundaries.
- Report screenshots: `.dg/assets/KRMA-482/fit-view.webp` (full view) and `.dg/assets/KRMA-482/zoom-800-panned.webp` (800%, panned, gap left of the eye).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
