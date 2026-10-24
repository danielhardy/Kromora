---
id: KRMA-781
title: Cap canvas zoom-out at fit or 100%, whichever is smaller
type: bug
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Zoom-out floor is Fit when fit scale <= 1.0
      result: pass
      notes: min(1,1/fitScale) multiplier; covered by testZoomOutStopsAtFitWhenFitDoesNotEnlargeTheSource
    - criterion: Zoom-out floor is native 1:1 when fit scale > 1.0
      result: pass
      notes: testZoomOutStopsAtNativeScaleWhenFitWouldEnlargeTheSource
    - criterion: Toolbar, direct, pointer zoom share bound; remembered zoom clamped on restore/geometry change
      result: pass
      notes: All coordinator entry points call synchronizeCanvasGeometry first; updateGeometry clamps zoom and rememberedZoom
    - criterion: No pan/focal jump at the bound; Fit/Fill/reset/double-click coherent
      result: pass
      notes: zoom(by:) returns early when target equals current zoom; testPointerZoomAtNativeLimitDoesNotPanOnFurtherZoomOut
    - criterion: Deterministic tests cover both sides of 100%, below-bound attempts, geometry changes
      result: pass
      notes: 4 new tests in CanvasNavigationTests
  checks_run:
    - swift test --filter CanvasNavigationTests (22 passed)
    - manual diff review of commit 38d60d5
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-03T13:25:24.485Z
  session: 01MUSFC46ZSY5PYFVH
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - interaction
  - ui
created: 2026-10-03T12:55:41.542Z
updated: 2026-10-03T13:25:24.487Z
blockers: []
order: a0
board: product
---

## Objective

Set the editor canvas's minimum effective scale to the smaller of fit scale and native 1:1 scale. Zooming out should stop at Fit for images whose fit scale is below 100%, and at 100% for images whose fit scale would enlarge the source.

## Context

`CanvasNavigation.zoom` is a multiplier relative to fit, but `CanvasNavigation.minimumZoom` is currently a fixed 0.1. In custom mode, `transform` multiplies the current fit scale by that value, so the image can become smaller than both Fit and native 1:1. Derive the lower fit-relative multiplier from the current source extent and viewport (`min(1, 1 / fitScale)`) and apply it consistently. Relevant paths are `Sources/KromoraKit/Models/CanvasNavigation.swift`, `Sources/KromoraKit/ViewModels/CanvasWorkflowCoordinator.swift`, `Sources/KromoraKit/Views/ContentView.swift`, `Sources/KromoraKit/Views/PreviewSurface.swift`, and `Tests/KromoraKitTests/CanvasNavigationTests.swift`.

`zoomPercent` currently reports the fit-relative multiplier. Keep the minimum's meaning clear and ensure any affected zoom labels or accessibility values remain accurate.

## Acceptance criteria

- [ ] When fit scale is below or equal to 1.0, no zoom input can reduce the effective canvas scale below Fit.
- [ ] When fit scale is above 1.0, no zoom input can reduce the effective canvas scale below native 1:1.
- [ ] Toolbar presets, direct zoom commands, and pointer/trackpad zoom use the same dynamic lower bound; remembered zoom is clamped when restored or when source/viewport geometry changes.
- [ ] Hitting the lower bound does not introduce an unintended pan or focal-point jump. Fit, Fill, reset, and double-click toggle behavior remain coherent.
- [ ] Deterministic CanvasNavigation tests cover both sides of 100%, zoom attempts below the bound, and viewport/source changes.

## Implementation notes

Compare effective source-to-canvas scale, not the fit-relative `zoom` multiplier. A suitable lower multiplier is `min(1, 1 / fitScale)` for the current geometry.


### Comment — codex @ 2026-10-03T13:24:40.838Z

Implemented the geometry-derived zoom-out floor: Fit when Fit is at or below native scale, otherwise 100% source scale. Toolbar, direct, pointer, and remembered zoom share the bound; zoom labels identify Fit-relative percentages. Verified: swift test --filter CanvasNavigationTests (22 passed). Commit: 38d60d5.

## Agent log

- 2026-10-03T13:25:24.485Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Zoom-out floor is Fit when fit scale <= 1.0 (pass) — min(1,1/fitScale) multiplier; covered by testZoomOutStopsAtFitWhenFitDoesNotEnlargeTheSource
- [x] Zoom-out floor is native 1:1 when fit scale > 1.0 (pass) — testZoomOutStopsAtNativeScaleWhenFitWouldEnlargeTheSource
- [x] Toolbar, direct, pointer zoom share bound; remembered zoom clamped on restore/geometry change (pass) — All coordinator entry points call synchronizeCanvasGeometry first; updateGeometry clamps zoom and rememberedZoom
- [x] No pan/focal jump at the bound; Fit/Fill/reset/double-click coherent (pass) — zoom(by:) returns early when target equals current zoom; testPointerZoomAtNativeLimitDoesNotPanOnFurtherZoomOut
- [x] Deterministic tests cover both sides of 100%, below-bound attempts, geometry changes (pass) — 4 new tests in CanvasNavigationTests
Checks run:
- swift test --filter CanvasNavigationTests (22 passed)
- manual diff review of commit 38d60d5
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUSFC46ZSY5PYFVH
