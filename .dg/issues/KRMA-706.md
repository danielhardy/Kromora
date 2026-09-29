---
id: KRMA-706
title: Use consistent intrinsic sizing for toolbar menu buttons
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - toolbar
  - menus
  - ui
created: 2026-09-29T03:18:59.200Z
updated: 2026-09-29T03:19:57.418Z
order: zh
board: product
---

## Objective

Give toolbar controls with menus a consistent, native-looking icon and chevron treatment.

## Context

In the supplied screenshot, toolbar icons that open additional menus include small arrows, but the
combined controls look inconsistent. Their widths appear forced instead of following the icon and
menu affordance's natural size. Evaluate the standard macOS menu-button treatment and use a
consistent approach across these controls.

![Toolbar controls with menu chevrons beside the Library/Edit control](../assets/KRMA-703-707/screenshot-2026-09-28-at-9-13-54-pm.png)

## Acceptance criteria

- [ ] Menu-bearing toolbar controls show a clear, consistently aligned menu affordance.
- [ ] Controls use intrinsic sizing or a shared sizing rule instead of arbitrary per-control widths.
- [ ] Controls without menus keep their current appearance and all menu actions remain reachable.
- [ ] The treatment stays visually consistent with the Library/Edit-adjacent toolbar group and in
      both inspector states.

## Implementation notes

Prefer the standard macOS toolbar/menu presentation if it fits the design; otherwise define one
shared custom treatment rather than styling each menu button independently.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
