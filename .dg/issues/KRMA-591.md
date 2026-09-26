---
id: KRMA-591
title: Keep the histogram unchanged when zooming
type: bug
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - histogram
  - zoom
created: 2026-09-26T02:55:36.594Z
updated: 2026-09-26T02:55:50.693Z
order: zzzz
board: product
---

## Objective

Keep the Info histogram stable during canvas navigation. Zooming the photo alone must not refresh, rescale, or otherwise change the histogram. Editing or cropping the photo should recompute it.

## Context

The histogram represents image content, not the current viewport. Reproduction: open a photo with the Info inspector visible, zoom in or out using canvas navigation, and observe that the histogram changes even though the photo pixels were not edited. Crop and image-edit operations should still refresh the histogram to reflect the changed photo.

Related but distinct: KRMA-554 fixed the histogram following the displayed temporary Space-comparison request. This ticket covers histogram invalidation caused by zoom/navigation.

## Acceptance criteria

- [ ] Zooming the canvas in or out, including fit/fill and pointer zoom, does not recompute or change the histogram.
- [ ] Editing image content recomputes the histogram for the updated photo.
- [ ] Changing or committing a crop recomputes the histogram for the cropped photo.
- [ ] A pending histogram result from before an edit or crop cannot overwrite the histogram for the newer photo state.
