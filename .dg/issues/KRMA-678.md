---
id: KRMA-678
title: Group parametric controls under an Advanced Curve accordion
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
  - tone-curve
  - ui
created: 2026-09-28T02:31:31.588Z
updated: 2026-09-28T02:31:46.583Z
order: zz
board: product
---

## Objective

Reduce the amount of visible Light inspector content by placing the parametric tonal-region and region-split controls under an Advanced Curve accordion.

## Acceptance criteria

- Group the Highlights, Lights, Darks, and Shadows amount controls and the Shadow, Dark, Light, and Highlight split controls under an “Advanced Curve” accordion.
- The accordion is collapsed by default; the primary tone-curve controls remain available outside it.
- Expanding the accordion exposes the existing controls and labels without changing their adjustment behavior or saved values.
- Add or update focused coverage for the default collapsed state and access to the controls when expanded.
- Review the updated inspector against the attached screenshot.

## Context

- The parametric controls were added in KRMA-595; this ticket changes their presentation, not their edit or rendering behavior.
- Screenshot attached to this issue.

## Checks

- swift build
- Focused Light inspector and tone-curve tests.

![Light inspector parametric tone-curve region and split controls](../assets/KRMA-678/screenshot-2026-09-27-at-8-30-36-pm.png)
