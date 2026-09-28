---
id: KRMA-675
title: Make Edit History collapsible below Photo Analysis
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - inspector
  - info
created: 2026-09-28T02:22:35.919Z
updated: 2026-09-28T02:22:44.749Z
order: zv
board: product
---

## Objective

Make Edit History a collapsible section in the Info panel, place it below Photo Analysis, and have it collapsed by default.

## Acceptance criteria

- In the Info panel, Photo Analysis appears above Edit History.
- Edit History has an accordion control that expands and collapses its history content.
- Edit History is collapsed by default when the Info panel is first shown.
- Expanding the section preserves access to the existing history, snapshot, and virtual-copy actions.
- Add or update focused coverage for section ordering, default collapsed state, and expand/collapse behavior.

## Checks

- swift build
- Focused Info panel/Edit History presentation tests.
