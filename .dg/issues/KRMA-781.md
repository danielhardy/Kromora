---
id: KRMA-781
title: Cap canvas zoom-out at fit or 100%, whichever is smaller
type: bug
status: ready
priority: medium
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - interaction
  - ui
created: 2026-10-03T12:55:41.542Z
updated: 2026-10-03T13:00:37.972Z
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
