---
id: KRMA-374
title: Use neutral-centered fill for bipolar adjustment sliders
type: bug
status: ready
priority: medium
agent: claude
verification_agent: codex
model: opus
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ui
created: 2026-09-12T14:46:27.995Z
updated: 2026-09-12T14:57:58.909Z
order: n
board: product
---

## Objective

Make bipolar adjustment sliders visually represent neutral values correctly: the thumb should start at the neutral midpoint with no track filled, and the active fill should extend from neutral to the current value as the user moves the thumb.

## Context

The current sliders use the standard left-origin fill, so a neutral value such as Exposure 0, Contrast 0, or Highlights 0 appears as roughly 50% filled even though no adjustment is applied. The attached reference screenshots show the desired behavior: neutral at center with an empty track, then fill only on the side between neutral and the dragged thumb.

## Acceptance criteria

- [ ] Bipolar controls with a neutral baseline start with the thumb at the neutral value and no active fill at neutral.
- [ ] Dragging above neutral fills only from the neutral baseline to the thumb on the positive side.
- [ ] Dragging below neutral fills only from the neutral baseline to the thumb on the negative side.
- [ ] The behavior is applied consistently to the global Adjust controls and local-adjustment controls where the value model is bipolar.
- [ ] Genuinely unipolar controls such as amount, opacity, size, flow, or density retain an appropriate left-origin fill and are not forced into a centered presentation.
- [ ] The visual baseline uses each control's actual neutral/default value rather than assuming every range midpoint is zero.
- [ ] Existing value ranges, precision, direct-entry behavior, accessibility values, keyboard interaction, reset actions, undo grouping, persistence, and render semantics remain unchanged.
- [ ] Add regression/UI coverage for neutral, positive, and negative bipolar values plus representative unipolar controls; include manual visual QA against the supplied reference behavior.
