---
id: KRMA-702
title: Remove unintended white stroke from library grid thumbnails
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - rendering
  - ui
created: 2026-09-29T03:11:04.112Z
updated: 2026-09-29T03:11:32.044Z
order: t
board: product
---

## Objective

Identify and remove the unintended white hairline rendered along a library thumbnail edge.

## Context

In the Library grid screenshot supplied on 2026-09-28, a thin white line runs across the top
edge of the wide mountain-at-dusk photo in the second mosaic row. The line is not part of the
source photo. The nearby orange outline around the active photo is the expected selection
indicator; the white line appears on a different, unselected tile.

The grid presents `NSImage` thumbnails in `LibraryGridView` with a fixed mosaic frame, rounded
clipping, and a selection overlay. Trace the displayed pixels through that path and any backing
thumbnail representation to find the source of the artifact; do not assume the selection overlay
is responsible without reproducing it.

## Acceptance criteria

- [ ] Reproduce the white hairline on macOS 26 and identify which part of thumbnail presentation
      or rendering introduces it.
- [ ] Remove the unintended edge from unselected library thumbnails, including at Retina scale.
- [ ] Preserve the active and multi-selected orange outlines, rounded clipping, and mosaic image
      sizing.
- [ ] Add regression coverage at the narrowest useful boundary, or record a repeatable visual
      verification procedure if the artifact is only reproducible in SwiftUI/AppKit presentation.

## Implementation notes

Keep the fix scoped to library thumbnail presentation. The screenshot's other image edges and the
orange active selection outline are expected.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
