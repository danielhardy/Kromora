---
id: KRMA-594
title: Add a white-balance eyedropper and preset choices
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
created: 2026-09-26T13:56:24.933Z
updated: 2026-09-26T13:56:42.680Z
blockers: []
order: dppppppc
board: product
---

## Objective

Let photographers neutralize a sampled area and choose common white-balance presets, while retaining fine Temperature and Tint adjustment.

## Context

Current controls expose Temperature and Tint but no neutral sampler or preset menu. Respect decoder-specific RAW white balance and the existing non-destructive document model.

Derived from §2.1 White balance and tone fundamentals in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a loupe-assisted neutral sample with a documented averaging area and a clear cancel/commit interaction.
- [ ] Offer As Shot, Auto, Daylight, Cloudy, Shade, Tungsten, Fluorescent, Flash, and Custom choices where the source supports them.
- [ ] Keep sampled and preset values editable, undoable, and persistent for standard and RAW sources.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
