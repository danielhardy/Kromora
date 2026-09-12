---
id: KRMA-375
title: Use effect-specific color tracks for color adjustment sliders
type: feature
status: ready
priority: medium
model: gpt-5.6-terra
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ui
created: 2026-09-12T14:49:05.651Z
updated: 2026-09-12T14:58:18.774Z
order: t
board: product
---

## Objective

Give color-adjustment sliders effect-specific track gradients so the control visually communicates the direction and character of the adjustment instead of using a generic blue bar.

## Context

The supplied reference shows color-aware tracks: Temperature transitions from cool blue through neutral toward warm yellow, Tint transitions from green through neutral toward magenta, and color-intensity controls use similarly meaningful ramps. The thumb/value behavior should remain compatible with the neutral-centered bipolar slider work in KRMA-374.

## Acceptance criteria

- [ ] Temperature uses a legible cool-to-warm track, with blue on the cool side and yellow/warm tones on the warm side.
- [ ] Tint uses a green-to-magenta track, with the neutral point visually clear.
- [ ] Saturation, Vibrance, and other color controls receive documented effect-specific ramps where a gradient materially communicates the control's direction or result; controls without a meaningful semantic gradient retain a neutral track treatment.
- [ ] Gradients represent the full control range and remain visually aligned with the thumb and neutral baseline, including zero/neutral, positive, and negative values.
- [ ] Styling is consistent across global Color controls and corresponding local-adjustment controls where applicable.
- [ ] Colors remain legible and sufficiently contrasted in supported light/dark appearances, and the control remains understandable without relying on color alone.
- [ ] Existing ranges, numeric values, direct entry, accessibility labels/values, keyboard interaction, reset behavior, undo grouping, persistence, and render semantics remain unchanged.
- [ ] Add visual/UI regression coverage or snapshot-level verification for the color ramps and manual QA against the supplied reference.
