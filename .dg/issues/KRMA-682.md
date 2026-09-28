---
id: KRMA-682
title: Make inspector tab styling and grouping more consistent
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
  - ui
  - consistency
created: 2026-09-28T02:45:03.965Z
updated: 2026-09-28T02:45:20.534Z
order: zzx
board: product
---

## Objective

Make the content across the inspector tabs feel like one cohesive interface rather than a collection of unrelated panels.

## User report

The content styling currently feels unique and different in each tab. Review opportunities to align font sizes, typography, hierarchy, and grouping; use the accordion style consistently where it fits.

## Acceptance criteria

- Review the Info, Light, Color, Effects, Masks, Heal, and Looks inspector tabs for inconsistent typography, hierarchy, spacing, and grouping.
- Establish a consistent type hierarchy for panel headings, section or accordion headings, field labels, values, and helper text.
- Use a consistent accordion pattern for related groups where collapsing them improves organization, while keeping primary controls easy to find.
- Align common spacing and control presentation across tabs; retain tab-specific layouts where the content requires them.
- Preserve each tab’s existing functionality and accessibility.
- Visually review all inspector tabs at a common inspector width and document any intentional exceptions.

## Context

- Coordinate with focused inspector polish tickets KRMA-674, KRMA-675, KRMA-677, KRMA-678, KRMA-679, KRMA-680, and KRMA-681 so shared conventions reinforce those changes.

## Checks

- swift build
- Focused inspector presentation tests
- Visual review across all inspector tabs.
