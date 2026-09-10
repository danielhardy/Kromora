---
id: KRMA-332
title: Add image rotation
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - feature
created: 2026-09-10T04:08:12.873Z
updated: 2026-09-10T12:53:57.570Z
order: m
board: product
---

## Objective

Allow the user to rotate the selected image from the editor.

## Context

Images may be imported in the wrong orientation or need to be turned for the intended
composition. Rotation should be a non-destructive edit that remains consistent across the
preview and exported result.

## Acceptance criteria

- [ ] Provide an obvious control for rotating the selected image clockwise and counterclockwise
      (at minimum in 90-degree increments).
- [ ] Apply the rotation consistently to the canvas preview and exported image, including the
      correct output dimensions for portrait/landscape changes.
- [ ] Persist the rotation as part of the edit document and restore it when revisiting the image.
- [ ] Support undo/redo and reset for the rotation without disturbing unrelated adjustments.
- [ ] Add regression coverage for rotation state, rendering/export orientation, persistence, and
      interaction with crop or other spatial edits.

## Implementation notes

Consider the existing crop, render-pipeline, edit-history, and export pathways when choosing where
rotation belongs. Preserve source pixels and keep the edit non-destructive.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
