---
id: KRMA-502
title: Slider thumbs sit too low relative to the track
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - sliders
  - ui
  - ux
created: 2026-09-21T02:19:32.613Z
updated: 2026-09-21T02:29:00.432Z
order: a0
board: product
---

## Objective

Vertically center every slider thumb on its track. The current thumbs appear noticeably too low relative to the slider bar in the Edit inspectors.

## Context

The shared `NeutralOriginSliderCell` draws the custom thumb in `drawKnob` and the track in `barRect(in:)`. The reported screenshot shows the thumb sitting below the bar center rather than centered on it. This affects the shared slider family, including neutral-origin and gradient tracks, crop controls, masking, and temperature controls.

KRMA-499 intentionally reduced the drawn thumb to 80% of the native knob rect while preserving AppKit travel and hit-testing geometry. This ticket is about vertical visual alignment only; do not regress that size or interaction contract.

## Requirements

1. Align the visual thumb center with the visual bar center for every shared slider style and control size.
2. Preserve the existing 80% visual thumb scale, native knob hit target, value travel, endpoint behavior, and drag/accessibility behavior.
3. Keep neutral-origin fills, gradient tracks, and neutral markers aligned with the corrected thumb/bar geometry.
4. Verify the fix across representative Light, Color, Effects, Crop, Masking, and Temperature controls.
5. Add regression coverage for the thumb center Y coordinate relative to the bar center, plus any useful rendered-geometry check.

## Acceptance criteria

- [ ] Slider thumbs are visually centered on their bars rather than sitting low.
- [ ] Alignment is consistent across neutral, gradient, crop, masking, and temperature sliders.
- [ ] Thumb size remains the KRMA-499 80% visual scale, with unchanged hit testing and horizontal travel.
- [ ] Track endpoints, neutral markers, fills, dragging, and accessibility remain correct.
- [ ] Focused slider tests and `dg validate` pass.

## Implementation notes

Inspect the relationship between AppKit `knobRect(flipped:)`, `drawKnob(_:)`, and `barRect(in:)` in `Sources/KromoraKit/Views/NeutralOriginSlider.swift`. Treat AppKit coordinate flipping and any control-size-specific rect offsets as part of the diagnosis; avoid a blind constant offset that only fixes one slider size.
