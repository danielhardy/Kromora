---
id: KRMA-620
title: Add a command palette and customizable workspaces
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:44.240Z
updated: 2026-09-26T13:56:44.536Z
blockers: []
order: zk
board: product
---

## Objective

Make the growing command set searchable and let photographers shape common work layouts.

## Context

The current menu and inspector architecture should remain the source of command availability; workspace preferences should be per device.

Derived from §11 Ease of use in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a keyboard-opened command palette that searches and invokes available menu and editing actions.
- [ ] Allow inspector sections to be hidden/reordered and frequently used controls to be pinned.
- [ ] Support saved workspace layouts such as Culling, Color, Retouch, and Print.
- [ ] Ensure palette commands respect current selection, active editor state, and command availability.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
