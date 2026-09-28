---
id: KRMA-700
title: Keep zoomed image previews sharp during edit slider drags
type: bug
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - bug
  - rendering
created: 2026-09-28T23:36:50.934Z
updated: 2026-09-28T23:36:58.987Z
blockers: []
order: zq
board: product
---

## Objective

Keep the zoomed photo preview clear while edit adjustments are being dragged, without making slider interaction unresponsive.

## User report

In Edit mode, zoom into a picture and drag an adjustment slider (light, color, effects, and similar controls). The image becomes blurry or pixelated during the drag, then becomes clear again when the mouse button is released. The stronger the zoom, the more noticeable the blur/pixelation.

## Acceptance criteria

- [ ] Reproduce the quality drop while dragging adjustment controls at multiple zoom levels and record the render path and conditions.
- [ ] Identify why interactive renders lose detail during a drag and why the full clarity returns on release (for example, a preview render scale, resolution, or cache path change).
- [ ] Keep the zoomed preview acceptably sharp throughout adjustment drags, including at higher zoom levels, while preserving responsive feedback.
- [ ] Ensure the final preview after release remains correct and does not show stale or lower-resolution output.
- [ ] Add regression coverage for interactive and settled preview quality at more than one zoom level; record verification commands and results.

## Investigation notes

Compare the preview render scale and source resolution during slider changes and after commit/mouse-up. Exercise adjustments from the light, color, and effects groups, and distinguish a deliberate performance-quality tradeoff from an unintended resolution drop.
