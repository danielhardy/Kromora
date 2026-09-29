---
id: KRMA-704
title: Keep import, export, and share controls left of the open inspector
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - toolbar
  - sidebar
  - ui
created: 2026-09-29T03:18:56.978Z
updated: 2026-09-29T03:19:55.616Z
order: y
board: product
---

## Objective

Keep import, export, and share controls visible immediately to the left of the open inspector.

## Context

In the supplied Edit screenshot, the inspector is docked on the right. The toolbar's import,
export, and share actions should remain in the usable toolbar area to the left of the inspector as
the available content width changes.

![Edit view with the inspector open and toolbar actions along the top](../assets/KRMA-703-707/screenshot-2026-09-28-at-9-13-54-pm.png)

## Acceptance criteria

- [ ] When the inspector is open, import, export, and share controls remain visible and clickable
      to its left.
- [ ] Controls do not overlap the inspector, disappear behind it, or become clipped at supported
      window widths.
- [ ] Closing the inspector restores the normal toolbar layout without shifting unrelated controls
      unexpectedly.

## Implementation notes

Check the toolbar's layout against both inspector states and narrower window widths; retain the
existing actions and menu behavior.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
