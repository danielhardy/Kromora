---
id: KRMA-510
title: Zoom toward cursor for scroll-wheel and double-click
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Scroll-wheel zoom over a corner/detail keeps that detail under the cursor (manual check).
      result: pass
      notes: Not exercised interactively; verified by code review and projection-stability tests. Wheel event carries canvasPoint (y-down, same convention as pan) into CanvasNavigation.zoom.
    - criterion: Double-click on a non-centre point zooms in toward that point; double-click again returns to fit without a confusing jump (or an accepted, documented reset).
      result: pass
      notes: Zoom-in anchors on click; return to fit resets focal point to centre (documented accepted reset).
    - criterion: "Unit/model test: zoom-by-factor at a known viewport point updates focalPoint so the projected point is stable within tolerance."
      result: pass
      notes: CanvasNavigationTests cover navigation-level stability and double-click; added a view-model regression for straightened crops.
    - criterion: Existing pan and KRMA-495 / double-click toggle behaviour remain intact.
      result: pass
      notes: Existing pan/double-click tests pass; panCanvas now shares the straighten-aware extent.
    - criterion: scripts/ci-tests.sh fast and serial pass.
      result: pass
      notes: fast exit 0 (1123/1123); serial 407 executed, 1 pre-existing RAW-fixture skip, 0 failures.
  checks_run:
    - swift test --filter CanvasNavigationTests|CanvasObservationTests|PreviewSurfaceTests (67/67)
    - scripts/ci-tests.sh fast (exit 0, 1123/1123)
    - scripts/ci-tests.sh serial (407 executed, 1 skipped, 0 failures)
    - git diff --check
  findings:
    - "FIXED (medium): canvasImageExtent ignored the straighten-enlarged geometry frame used by RenderPipeline/ResolutionPlanner, so pointer zoom and pan on a committed straightened crop anchored and clamped against the wrong aspect."
    - "NOTED (low): zoom-at-point no-ops on an invalid zero viewport size, whereas the old double-click path always toggled; only reachable before first layout."
  fixes:
    - Made canvasImageExtent apply RenderPipeline.geometryExtent for the committed crop's straighten angle and made panCanvas reuse it; added testPointerZoomAnchorsAgainstTheStraightenedPresentationExtent.
  verification_commits:
    - d6e4977
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-21T19:21:05.369Z
  session: 01MUBMMS3VQ4QRT470
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - preview
  - zoom
  - ux
created: 2026-09-21T19:09:09.021Z
updated: 2026-09-21T19:21:05.371Z
order: a0
board: product
commits:
  - d6e4977
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

### Comment — codex @ 2026-09-21T19:16:53.806Z

Implemented and committed as e0a6354. Canvas zoom now anchors scroll-wheel, double-click, and pinch magnification on the event canvas point; CanvasNavigation derives a clamped focal point while preserving zoom limits and remembered zoom, and double-click back to fit resets to centre. Added projection-stability, double-click, and zoom-limit regressions. Verification: scripts/ci-tests.sh fast (1122/1122), scripts/ci-tests.sh serial (407/407, 1 pre-existing RAW-fixture skip), focused CanvasNavigationTests|PreviewSurfaceTests (57/57), git diff --check, dg validate (existing model-name warnings only).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-21T19:21:05.369Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Scroll-wheel zoom over a corner/detail keeps that detail under the cursor (manual check). (pass) — Not exercised interactively; verified by code review and projection-stability tests. Wheel event carries canvasPoint (y-down, same convention as pan) into CanvasNavigation.zoom.
- [x] Double-click on a non-centre point zooms in toward that point; double-click again returns to fit without a confusing jump (or an accepted, documented reset). (pass) — Zoom-in anchors on click; return to fit resets focal point to centre (documented accepted reset).
- [x] Unit/model test: zoom-by-factor at a known viewport point updates focalPoint so the projected point is stable within tolerance. (pass) — CanvasNavigationTests cover navigation-level stability and double-click; added a view-model regression for straightened crops.
- [x] Existing pan and KRMA-495 / double-click toggle behaviour remain intact. (pass) — Existing pan/double-click tests pass; panCanvas now shares the straighten-aware extent.
- [x] scripts/ci-tests.sh fast and serial pass. (pass) — fast exit 0 (1123/1123); serial 407 executed, 1 pre-existing RAW-fixture skip, 0 failures.
Checks run:
- swift test --filter CanvasNavigationTests|CanvasObservationTests|PreviewSurfaceTests (67/67)
- scripts/ci-tests.sh fast (exit 0, 1123/1123)
- scripts/ci-tests.sh serial (407 executed, 1 skipped, 0 failures)
- git diff --check
Findings:
- FIXED (medium): canvasImageExtent ignored the straighten-enlarged geometry frame used by RenderPipeline/ResolutionPlanner, so pointer zoom and pan on a committed straightened crop anchored and clamped against the wrong aspect.
- NOTED (low): zoom-at-point no-ops on an invalid zero viewport size, whereas the old double-click path always toggled; only reachable before first layout.
Fixes:
- Made canvasImageExtent apply RenderPipeline.geometryExtent for the committed crop's straighten angle and made panCanvas reuse it; added testPointerZoomAnchorsAgainstTheStraightenedPresentationExtent.
Verification commits:
- d6e4977
Actor: claude
Resolved model: sonnet
Pickup session: 01MUBMMS3VQ4QRT470
Summary: Verified pointer-anchored zoom; fixed straighten-aware extent for zoom/pan; fast and serial CI pass.
