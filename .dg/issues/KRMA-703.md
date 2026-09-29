---
id: KRMA-703
title: Keep filmstrip thumbnails accessible with the inspector sidebar open
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - filmstrip
  - sidebar
  - ui
created: 2026-09-29T03:18:55.890Z
updated: 2026-09-29T03:19:54.734Z
order: w
board: product
---

## Objective

Keep every filmstrip thumbnail reachable while the inspector sidebar is open.

## Context

In the supplied Edit screenshot, opening the right inspector correctly narrows and shifts the main
photo. The bottom filmstrip does not adapt as clearly, and the user wants to be able to reach all
thumbnails with the sidebar open. Prefer giving the strip enough trailing space for its normal
horizontal scrolling to bring the final thumbnail fully into view; resizing the strip with the
photo is also acceptable if it fits the existing layout.

![Edit view with the inspector open and the filmstrip visible along the bottom](../assets/KRMA-703-707/screenshot-2026-09-28-at-9-13-54-pm.png)

## Acceptance criteria

- [ ] With the inspector open, every filmstrip item can be brought fully into view and selected.
- [ ] The last thumbnail is not clipped under or obscured by the sidebar or window edge.
- [ ] Opening and closing the inspector preserves sensible scroll position and does not disturb
      thumbnail selection or the main photo layout.

## Implementation notes

Keep the filmstrip's selection and thumbnail-demand behavior intact while correcting its available
viewport or trailing inset.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
