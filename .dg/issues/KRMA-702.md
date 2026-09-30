---
id: KRMA-702
title: Remove unintended white stroke from library grid thumbnails
type: bug
status: review
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
updated: 2026-09-29T03:41:43.647Z
blockers:
  - id: evt_mum4qrtq_yqruda
    type: human
    reason: The referenced Library screenshot and mountain photo are not present in the issue context or checkout, and a Retina SwiftUI/AppKit snapshot of a solid thumbnail does not reproduce a white edge or implicate the selection overlay. Without the affected pixels I cannot safely identify or fix the source.
    action: Attach a readable crop of the affected Library grid tile and, if available, the original mountain photo; include whether the tile shows original or edited pixels and the display scale.
    created_at: 2026-09-29T03:41:43.647Z
order: t
board: product
blocked_reason: The referenced Library screenshot and mountain photo are not present in the issue context or checkout, and a Retina SwiftUI/AppKit snapshot of a solid thumbnail does not reproduce a white edge or implicate the selection overlay. Without the affected pixels I cannot safely identify or fix the source.
blocked_action: Attach a readable crop of the affected Library grid tile and, if available, the original mountain photo; include whether the tile shows original or edited pixels and the display scale.
blocked_from_status: ready
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
