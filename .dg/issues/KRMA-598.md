---
id: KRMA-598
title: Complete sharpening, noise, and moiré controls
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
created: 2026-09-26T13:56:27.694Z
updated: 2026-09-26T13:56:42.835Z
blockers: []
order: h555554o
board: product
---

## Objective

Expose the detail controls photographers need to tune sharpening, noise reduction, and moiré without losing fine texture.

## Context

Some global detail amounts exist, but the evaluation found no sharpening radius/masking controls, separate NR detail retention, or output sharpening.

Derived from §2.2 Detail: sharpening, noise, and texture in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Add sharpening Radius, Masking, and Detail, including a useful edge-mask preview.
- [ ] Add luminance and color noise detail/contrast retention controls and a single-pixel color-noise inspection view.
- [ ] Make local sharpness, noise reduction, and moiré adjustments available where mask-layer semantics support them.
- [ ] Add output-sharpening choices for screen, matte, and glossy output at Low, Standard, and High strengths.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
