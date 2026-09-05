---
id: LUMO-221
title: Add editable linear gradient masks
type: feature
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic:masking
  - masking
  - editor
  - rendering
created: 2026-09-04T21:48:30.417Z
updated: 2026-09-04T21:54:14.587Z
depends_on:
  - LUMO-220
order: y
board: product
---

## Objective

Let users draw, reshape, rotate, and later re-edit a resolution-independent linear gradient mask
with Lightroom-style falloff guides.

## Context

Linear masks need direct manipulation on the photo: the image is the clearest place to communicate
direction, full-strength edge, zero-strength edge, and transition width. Handles must stay aligned
with rendered pixels across navigation, crop, and backing-scale changes.

## Acceptance criteria

- [ ] Dragging on the canvas creates a linear mask from normalized zero-strength and full-strength
      edges and immediately selects its local-adjustment layer.
- [ ] Three parallel guide bars show the gradient; dragging the center translates it, outer bars
      edit falloff while keeping the opposite edge stable, and a rotation affordance edits angle.
- [ ] Inspector controls expose angle, falloff, density, invert, and reset with live feedback.
- [ ] The renderer evaluates the same analytic smooth falloff at interactive, preview, and export
      resolutions without persisting a raster mask.
- [ ] Handles retain screen-point hit sizes and stay visually/pixel aligned under orientation,
      crop, fit/fill, zoom, pan, window resize, Retina scale, and non-square sources.
- [ ] Arrow-key nudging, Shift acceleration, Escape/cancel, VoiceOver descriptions, undo/redo,
      persistence, reopen, and source switching are covered.
- [ ] A layer can be deselected, reselected, and fully reshaped without recreating it.

## Implementation notes

Follow Section 4.4 and Step 4 of `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`. Reuse the overlay,
coordinate-transform, draft/commit, and render seams established by LUMO-217 through LUMO-220.

Keep analytic math in a pure model/renderer helper shared by hit-test/golden tests and the GPU
implementation so the visible bars cannot drift from the effective mask.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
