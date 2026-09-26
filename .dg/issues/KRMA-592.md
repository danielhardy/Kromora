---
id: KRMA-592
title: Animate the Info sidebar closed when returning to Library
type: bug
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - sidebar
  - animation
created: 2026-09-26T02:56:21.124Z
updated: 2026-09-26T02:56:28.578Z
order: zzzzh
board: product
---

## Objective

Animate the Info sidebar closing when the user switches from Edit to Library.

## Context

Reproduction: open the Info panel in Edit, then switch to Library. The panel currently disappears without a closing animation. The transition should visibly animate the sidebar closed as the app moves to Library.

## Acceptance criteria

- [ ] Switching from Edit to Library with the Info sidebar open animates the sidebar closed rather than removing it abruptly.
- [ ] The transition remains smooth with the Library view and window layout.
- [ ] Switching to Library with the Info sidebar already closed continues to work normally.
