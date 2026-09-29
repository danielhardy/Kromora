---
id: KRMA-707
title: Replace the histogram dropdown with a full-width tab selector
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - histogram
  - inspector
  - ui
created: 2026-09-29T03:19:00.294Z
updated: 2026-09-29T03:19:58.353Z
order: zq
board: product
---

## Objective

Replace the histogram mode dropdown with a full-width tab selector integrated into the histogram.

## Context

In the supplied Edit screenshot, the compact RGB dropdown sits below the histogram and looks
detached from it. The user wants a custom tab system attached to the plot, spanning its full width
edge to edge, with a monospaced typeface. The available modes are RGB, Luma, R, G, B, Wave, Parade,
and Vector.

![Histogram inspector with the current RGB mode dropdown](../assets/KRMA-703-707/screenshot-2026-09-28-at-9-13-54-pm.png)

## Acceptance criteria

- [ ] Histogram modes appear as a connected, full-width selector integrated with the plot.
- [ ] Labels use a monospaced typeface and remain legible at the inspector's supported widths.
- [ ] All existing modes remain selectable and the active mode is clearly indicated.
- [ ] Selection remains accessible to keyboard and assistive technology users.

## Implementation notes

Preserve each mode's current histogram behavior and avoid adding horizontal overflow at narrow
inspector widths.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
