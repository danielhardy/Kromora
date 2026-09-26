---
id: KRMA-602
title: Broaden local adjustment controls and mask editing
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
created: 2026-09-26T13:56:30.412Z
updated: 2026-09-26T13:56:42.975Z
blockers: []
order: kkkkkkk0
board: product
---

## Objective

Bring local editing closer to global adjustment breadth and make mask changes easier to inspect.

## Context

LocalAdjustments currently cover a smaller field set than global editing. Existing masks and compositor operations should remain the foundation.

Derived from §4.2 Missing local adjustments; §4.3 Mask visualization and editing ergonomics in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Add local tone curve, HSL, color grading, sharpening/noise/moiré, vignette, grain, LUT intensity, and monochrome mixing as supported mask adjustments.
- [ ] Show which non-neutral controls changed on each layer and provide layer color, opacity, and blend intent.
- [ ] Add hold-to-preview-layer and per-component visibility, plus visible feather/density controls.
- [ ] Keep adjustment-only edits efficient and consistent across preview, histogram, comparison, and full-resolution export.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
