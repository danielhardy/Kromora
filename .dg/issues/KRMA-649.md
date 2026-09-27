---
id: KRMA-649
title: Add single-pixel color-noise inspection view
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - professional-polish
created: 2026-09-27T06:28:55.340Z
updated: 2026-09-27T06:28:55.340Z
parent: KRMA-598
blockers: []
order: zzzy
board: product
---

## Objective

Add a single-pixel color-noise inspection view, matching the acceptance criteria in KRMA-598
(parent).

## Context

KRMA-598 added luminance/color noise reduction and detail/contrast retention controls
(`DetailAdjustments` in `Sources/KromoraKit/Models/EffectsAdjustments.swift`, applied through
`RenderPipeline.applyDetailControls`), but did not add the acceptance-criteria "single-pixel
color-noise inspection view" -- a 100%-zoom pixel-level readout that lets a photographer judge
residual chroma noise directly, the way `docs/COMPARISON_MODE.md`/clipping-alert style inspection
tools already let them judge other artifacts. KRMA-598's implementation comment explicitly
disclosed this as deferred.

## Acceptance criteria

- [ ] Add an inspection view that magnifies the image to single-pixel (100%/1:1) scale at the
      cursor or a fixed sample point, useful for judging color noise after luminance/color NR
      settings are applied.
- [ ] The view reflects the current noise reduction settings (before/after or live), not just
      the unprocessed source.
- [ ] Regression coverage proving the inspection view does not mutate the edit document and
      updates when noise controls change.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum,
Swift 6 safety, and zero third-party dependencies. Consider whether existing Info-tab pixel
readout plumbing (see KRMA-597) can be reused rather than building a second inspection surface.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
