---
id: KRMA-510
title: Zoom toward cursor for scroll-wheel and double-click
type: task
status: claimed
priority: medium
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - preview
  - zoom
  - ux
created: 2026-09-21T19:09:09.021Z
updated: 2026-09-21T19:09:11.173Z
order: a0
board: product
claim:
  actor: codex
  session: 01MUBMCOECIJOBH6HU
  claimed_at: 2026-09-21T19:09:11.172Z
  expires_at: 2026-09-21T20:09:11.172Z
  model: gpt-5.6-luna
---

## Objective

Scroll-wheel zoom and double-click zoom/unzoom keep the point under the cursor stable (zoom toward the pointer), instead of always re-centering on the image.

## Context

User report (2026-09-21): when double-clicking or using the scroll wheel to zoom, it should zoom to the area under the cursor. Today it zooms to the center of the image, then you have to pan to where you were hovering or clicking.

### Today

- `CanvasNavigation` already has a normalized `focalPoint` (default centre) used by `transform` / pan.
- `toggleFitAndRememberedZoom()` explicitly sets `focalPoint = Self.center` when entering custom zoom from fit (`CanvasNavigation.swift`).
- `setZoom` / `multiplyZoom` / `zoomCanvas(by:)` change scale only — they do not re-anchor the focal point to a pointer location.
- `PreviewMTKView.scrollWheel` calls `onScrollZoom?(factor)` with no cursor position (`PreviewSurface.swift`). `PreviewView` wires that to `viewModel.zoomCanvas(by:)`.
- Double-click goes `onDoubleClick` → `toggleCanvasZoom()` → `toggleFitAndRememberedZoom()` (centre).
- `PreviewMTKView` already has `canvasPoint(for:)` for converting an `NSEvent` into view coordinates — usable for both scroll and double-click.

Photos / Preview / Maps convention: zoom keeps the content under the pointer fixed in viewport space.

## Requirements

1. **Scroll-wheel zoom** — Given cursor position over the preview, adjust `focalPoint` (and zoom) so that image point stays under the cursor across the zoom step (clamp focal point so the image cannot leave empty invalid states beyond existing pan clamps).
2. **Double-click zoom-in** (fit → remembered/custom zoom) — Anchor on the click location, not image centre. Zooming back to fit can clear focal point to centre (current `fit()` behaviour) unless a better continuity is cheap.
3. Pinch / magnification should use the same toward-gesture-centre behaviour if a pinch centre is available; if not, document and keep factor-only for pinch as a follow-up.
4. Crop mode may keep current crop-owned input; cursor-zoom applies in normal Edit (and comparison panels if they share the same surface wiring).
5. No change to zoom limits, remembered zoom level, or ROI/render quality contracts beyond the navigation focal point.

## Acceptance criteria

- [ ] Scroll-wheel zoom over a corner/detail keeps that detail under the cursor (manual check).
- [ ] Double-click on a non-centre point zooms in toward that point; double-click again returns to fit without a confusing jump (or an accepted, documented reset).
- [ ] Unit/model test: zoom-by-factor at a known viewport point updates `focalPoint` so the projected point is stable within tolerance.
- [ ] Existing pan and KRMA-495 / double-click toggle behaviour remain intact.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass.

## Implementation notes

- Thread viewport point from `scrollWheel` / `mouseDown` through `PreviewSurfaceView` → `AppViewModel.zoomCanvas(by:at:)` / `toggleCanvasZoom(at:)`.
- Pure math belongs in `CanvasNavigation` (zoom about a viewport point → new focalPoint).
- Related: KRMA-483 (double-click works), KRMA-495 (pan/zoom regressions), KRMA-368 (double-click zoom feature).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
