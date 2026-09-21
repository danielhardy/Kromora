---
id: KRMA-501
title: Do not record transient zoom changes in edit history
type: bug
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - history
  - zoom
  - ux
created: 2026-09-21T02:14:57.965Z
updated: 2026-09-21T02:15:20.721Z
order: z
board: product
---

## Objective

Keep transient canvas navigation out of the photo edit history. Zooming in and out changes the presentation only; it must not create or modify a persistent photo-edit history entry.

## Context

The edit history should represent changes that permanently affect the photo, such as crop, light, color, effects, masking, and other document edits. Zoom level is view state and is transitory. Repeated zoom changes should therefore leave the document history and undo stack unchanged.

## Requirements

1. Zooming in, zooming out, fitting, or returning to the prior zoom level must not create a history node or alter the current undo/redo state.
2. A sequence of zoom changes followed by a persistent edit must record only the persistent edit.
3. Undo and redo of persistent edits must continue to work normally when the canvas is zoomed, without treating zoom as an edit.
4. Existing persistent edit behavior remains unchanged for crop, light, color, effects, masking, rotation, and related document changes.
5. Add regression coverage at the model/view-model boundary for history count and undo/redo behavior across zoom transitions.

## Acceptance criteria

- [ ] Zooming in and out repeatedly leaves the document history count and current undo/redo availability unchanged.
- [ ] Zooming followed by a crop, light, or color edit produces exactly the expected persistent history entry or gesture grouping, with no extra zoom entry.
- [ ] Undo and redo restore persistent document edits without introducing or requiring a zoom history entry.
- [ ] Existing history behavior for persistent photo edits remains covered and passing.
- [ ] Focused regression tests and `dg validate` pass.

## Implementation notes

Trace the boundary between `CanvasNavigation` or other presentation state and the document history/update path in `AppViewModel`. Keep preview scheduling and render invalidation for zoom intact; this ticket concerns history persistence and undo grouping, not zoom performance or image rendering.
