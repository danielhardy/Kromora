---
id: KRMA-754
title: Find the real source of the white top-edge line on edited library thumbnails (KRMA-702 follow-up)
type: bug
status: backlog
priority: urgent
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - library
  - rendering
created: 2026-10-02T01:58:33.642Z
updated: 2026-10-02T01:58:33.642Z
blockers: []
order: zzh
board: product
---

## Objective

Find and remove the real source of the white hairline along the top edge of the wide mountain-at-dusk tile in the Library grid. Parent: KRMA-702 (verification found commit 6c5f326 does not address it).

## Context

Verification of KRMA-702 found that commit 6c5f326 cannot have fixed the artifact. Before the change the overlay stroked a RoundedRectangle with Color.clear for unselected tiles, and a clear stroke draws nothing, so removing it is a no-op for unselected tiles. strokeBorder for the orange selection outlines is a reasonable cleanup but unrelated.

In the screenshot (.dg/assets/KRMA-702/screenshot-2026-10-01-at-7-49-33-pm.png) the line is straight, runs across the top of the tile, and does not follow the rounded corners. That points to pixels in the thumbnail bitmap itself, not SwiftUI chrome. Suspects, in order:

- Edited-thumbnail path (RenderEngine.makeThumbnailCGImage -> makeCGImage, rasterized from image.extent.integral): a fractional crop/rotation extent rounded outward can add a partially covered or edge-extended top row.
- Packed frame store encode/decode (ThumbnailFrameStore, ThumbnailFrameEncoding).
- Aspect-fill scaling when the thumbnail aspect differs slightly from the reserved cell (item.shouldFillLibraryThumbnail).

## Acceptance criteria

- [ ] Reproduce the line with the actual photo (or a generated fixture with fractional crop/rotation) and identify the stage that introduces it by inspecting the thumbnail CGImage's top rows.
- [ ] Fix at that stage, with a regression test on the thumbnail bitmap (edge rows match interior content) at the narrowest boundary.
- [ ] Orange active/multi-select outlines, rounded clipping and mosaic sizing unchanged.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
