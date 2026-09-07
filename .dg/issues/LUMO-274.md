---
id: LUMO-274
title: Crop overlay top-left handle, frame dragging, and portrait/landscape ratios are broken
type: bug
status: claimed
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - crop
  - editing
  - ux
created: 2026-09-07T03:46:06.834Z
updated: 2026-09-07T04:02:21.805Z
order: n
board: product
claim:
  actor: codex
  session: 01MTQPSKJ04OF3BIXM
  claimed_at: 2026-09-07T04:02:21.804Z
  expires_at: 2026-09-07T05:02:21.804Z
  model: gpt-5.6-luna
---

## Objective

Make the crop overlay reliably resize from every corner, move as a fixed-size frame, and offer
explicit quick-ratio orientation choices for portrait and landscape crops.

## Context

In the crop tool, the top-left grab handle does not respond when dragged to the right to bring the
left edge inward. The top-right handle can resize in the analogous direction, so the two corners
are not symmetric. The crop frame's interior should drag the complete frame around the photo while
keeping its width and height unchanged; it currently does not provide that dependable move
interaction.

The quick-ratio control also needs a way to switch the conventional presets between portrait and
landscape. Selecting a ratio such as 3:2 should make it possible to choose both 3:2 landscape and
2:3 portrait explicitly, regardless of the source image orientation. Square and Freeform remain
unchanged.

Relevant code is in `Sources/LumoKit/Views/CropOverlayView.swift` and
`Sources/LumoKit/Models/CropAdjustments.swift`. The fixed-ratio resize path currently derives the
new width with a `max` against the unchanged dimension, which can preserve the old width during a
top-left horizontal inward drag even though the requested width is smaller.

## Acceptance criteria

- [ ] Dragging the top-left handle right shrinks the crop from the left edge and moves `minX`
      right; dragging it left expands the crop, subject to image bounds and the selected ratio.
- [ ] All four corner handles resize symmetrically in Freeform and fixed-ratio modes, including
      inward and outward horizontal-only and vertical-only drags.
- [ ] Dragging inside the crop frame translates the entire frame without changing its width or
      height, and clamps the frame to the image bounds.
- [ ] The crop UI exposes explicit portrait and landscape quick-ratio choices for each non-square
      preset; selecting one updates the frame, preserves a sensible center when possible, and
      persists the selected orientation through Apply/reopen.
- [ ] Add model-level regression tests for the top-left inward resize, fixed-size frame movement,
      and portrait/landscape ratio selection; existing crop, render, and export tests continue to
      pass.

## Implementation notes

- Keep crop rectangles in normalized bottom-left source coordinates and keep pointer conversion in
  the overlay/model interaction boundary.
- Ensure the move gesture has priority only for the crop interior and does not steal corner-handle
  drags; maintain accessible labels/hints for the ratio and handle controls.
- Do not infer the requested portrait/landscape choice solely from the source image orientation;
  represent the selected ratio orientation in the crop state or derive it losslessly from the
  normalized frame.

### Comment — codex @ 2026-09-07T03:46:40.960Z

Reproduced from code inspection: fixed-ratio resizing uses the unchanged dimension as a max constraint, so a top-left horizontal inward drag can return the original width. The ticket also captures the required fixed-size interior move gesture and explicit portrait/landscape quick-ratio choices.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
