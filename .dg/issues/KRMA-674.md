---
id: KRMA-674
title: Order inspector panels with Light first
type: task
status: done
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - inspector
  - usability
created: 2026-09-28T02:20:23.380Z
updated: 2026-09-28T14:41:39.330Z
blockers: []
order: zu1zc7wn
board: product
---

## Objective

Make Light the first inspector panel and order the inspector panels as requested.

## Acceptance criteria

- Inspector panels appear in this order: Light, Color, Effects, Masks, Heal, Looks, Info.
- Light is the initial inspector panel when Edit opens with no previously selected panel.
- Users can still select every panel, and each panel continues to open its existing controls.
- Add or update focused coverage for panel order and the initial panel selection.

## Checks

- swift build
- Focused inspector navigation or presentation tests.
