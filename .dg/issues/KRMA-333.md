---
id: KRMA-333
title: Use C as the crop tool hotkey
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - feature
created: 2026-09-10T04:08:36.674Z
updated: 2026-09-10T12:53:57.660Z
order: t
board: product
---

## Objective

Use `C` as the keyboard shortcut for activating the crop tool.

## Context

Cropping is a frequent editing action and should be quickly accessible from the keyboard while
working in the image editor.

## Acceptance criteria

- [ ] Pressing `C` activates the crop tool for the current image/editor context.
- [ ] The shortcut works when focus is on the canvas and does not insert text or trigger an
      unrelated command in text-entry controls.
- [ ] The existing crop toolbar control and any current activation behavior remain functional.
- [ ] Add regression coverage for the key command and its focus/context handling.

## Implementation notes

Follow the existing menu-command and keyboard-monitor conventions. Check for conflicts with current
shortcuts before wiring the command.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
