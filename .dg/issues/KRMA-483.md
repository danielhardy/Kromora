---
id: KRMA-483
title: Double-click on the Edit canvas no longer toggles fit and zoom
type: bug
status: backlog
priority: high
labels:
  - preview
  - zoom
  - regression
  - ui
created: 2026-09-20T16:05:45.277Z
updated: 2026-09-20T16:05:45.277Z
order: zh
board: product
---

## Objective

Double-clicking the photo in Edit mode toggles between fit and zoom again: from fit it zooms in, and when already zoomed it returns to fit.

## Context

User report (2026-09-20): double-click on the image in Edit mode does not zoom. This is a regression; it used to work. Both directions must work: double-click at fit zooms in, double-click while zoomed returns to fit.

The intended behaviour is still implemented, so something stops the event reaching it:
- `PreviewMTKView.mouseDown` in `Sources/KromoraKit/Views/PreviewSurface.swift` (~1296) calls `onDoubleClick` when `event.clickCount == 2`.
- `PreviewView.canvasSurface` (`Sources/KromoraKit/Views/PreviewView.swift`, ~237) wires that to `viewModel.toggleCanvasZoom()`, which calls `canvasState.toggleFitAndRememberedZoom()` (`CanvasNavigation.swift`, ~315; remembered zoom, falling back to 2x) and then `schedulePreview()`.
- Existing `CanvasNavigationTests` (~417) only exercise `viewModel.toggleCanvasZoom()`, so nothing covers the click path from the view.

Hypotheses to check, none confirmed:
1. The SwiftUI `DragGesture(minimumDistance: 2)` and `contentShape(Rectangle())` wrapper around the surface (`PreviewView.swift` ~254) consume the mouse-down, so `PreviewMTKView.mouseDown` never sees `clickCount == 2`.
2. `ignoresHits` is left true (it is tied to `isCropToolActive`) after leaving the crop tool, so `hitTest` returns nil.
3. The masking overlay (`MaskCanvasOverlay`), or another overlay in the same ZStack, sits above the surface and takes the click.
4. The recent uncommitted edits to `PreviewSurface.swift`, `PreviewView.swift` and `CanvasNavigation.swift` changed hit testing or the zoom state. Bisect with `git log -S"onDoubleClick" -- Sources` and `git bisect`, and reproduce on a clean `main` first.

## Requirements

- Double-click on the photo while at fit zooms to the remembered zoom level (fallback 2x), centred as today's `toggleFitAndRememberedZoom` does. Consider centring on the click point as a follow-up, not in scope here.
- Double-click while zoomed (any custom zoom, including 800%) returns to fit.
- Works with and without a mask layer selected and with the masking overlay visible. If a mask tool owns clicks in the masking workspace, document that as the one exception.
- Works after leaving the crop tool. In the crop tool the crop overlay owns input; double-click there does not toggle zoom.
- Double-click must not also start a pan or nudge the canvas, and single-click and drag-to-pan behaviour is unchanged.
- Works in comparison (before/after) panels the same way as the single canvas.

## Acceptance criteria

- [ ] Root cause identified, and the commit that introduced the regression named in the ticket.
- [ ] In the running app: double-click at fit zooms in; double-click while zoomed returns to fit.
- [ ] A test that drives the real click path (an `NSEvent` mouse-down with `clickCount == 2` delivered to the preview view, or an equivalent seam) asserts the canvas navigation toggles, so this cannot regress silently again.
- [ ] Test covers the state after entering and leaving the crop tool.
- [ ] Drag-to-pan and scroll/pinch zoom are unaffected.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass.

## Implementation notes

- Related ticket: KRMA-482 (blank regions when panning at 800%). Both touch the same zoom and pan code, so land them in a way that lets each be verified separately.
- Prefer keeping the double-click in `PreviewMTKView` if hit-testing can be fixed. If the SwiftUI drag gesture is the culprit, an alternative is `SpatialTapGesture(count: 2)` (already used in `LightInspectorView`) on the same wrapper, ordered so it does not delay drag-to-pan.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
