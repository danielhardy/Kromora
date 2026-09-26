---
id: KRMA-600
title: Add luminance, color, and depth range masks
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
created: 2026-09-26T13:56:29.045Z
updated: 2026-09-26T13:56:42.905Z
blockers: []
order: iuuuuuuc
board: product
---

## Objective

Let photographers constrain local masks by tonal range, sampled color, and available depth data.

## Context

The mask compositor already supports combination operations, but the evaluation found no range masks. One-click Sky work is already tracked in KRMA-580, KRMA-583, and KRMA-584.

Derived from §4.1 Missing selectors in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Create luminance range masks with range, smoothness, invert, and interactive histogram selection.
- [ ] Create color range masks with eyedropper, multi-sample, falloff, and refinement controls.
- [ ] Use depth range masks when depth data is available and explain unavailable depth otherwise.
- [ ] Allow range selectors to combine with existing masks through the supported intersect and subtract operations.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
