---
id: LUMO-222
title: Add editable radial gradient masks
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
created: 2026-09-04T21:48:30.922Z
updated: 2026-09-04T21:54:15.268Z
depends_on:
  - LUMO-221
order: z
board: product
---

## Objective

Let users draw, resize, rotate, move, feather, invert, and later re-edit an elliptical radial mask.

## Context

Radial masks need source-normalized, aspect-correct geometry and clear inner/outer falloff guides.
Without one shared geometry contract, non-square photos and zoomed/cropped canvases will make the
handles disagree with the rendered selection.

## Acceptance criteria

- [ ] Dragging creates an ellipse from an initial center; the center moves it, cardinal handles
      resize an axis, corner handles resize both axes, and a rotation handle edits angle.
- [ ] Inner and outer ellipses visualize falloff; feather can be edited from the inspector or by
      dragging the inner boundary.
- [ ] Persist normalized center, radii, rotation, feather, density, and inside/outside selection.
- [ ] Shift constrains to a circle, Option resizes symmetrically, and invert switches inside/outside
      without destroying geometry.
- [ ] The renderer evaluates an aspect-correct analytic mask consistently at interactive, preview,
      and export resolutions without a persisted raster.
- [ ] Handles retain screen-point hit sizes and align under orientation, crop, fit/fill, zoom, pan,
      window resize, Retina scale, and non-square sources.
- [ ] Keyboard nudging, VoiceOver, cancel, undo/redo, persistence, reopen, source switching, and
      deselect/reselect editing are covered.

## Implementation notes

Follow Section 4.5 and Step 5 of `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`. Reuse the linear
gradient's overlay, gesture ownership, hit testing, accessibility, and analytic-render patterns.

Pin aspect correction and rotation with pure geometry tests before wiring pointer behavior.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
