---
id: KRMA-596
title: Add monochrome mixing and camera color calibration
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
created: 2026-09-26T13:56:26.294Z
updated: 2026-09-26T13:56:42.761Z
blockers: []
order: fffffff0
board: product
---

## Objective

Give photographers control over black-and-white channel mixing and camera-oriented shadow/primary color calibration.

## Context

The Color inspector has an HSL mixer, but the evaluation found no dedicated monochrome mixer or camera calibration panel.

Derived from §2.1 White balance and tone fundamentals; §2.4 Color science depth in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a monochrome conversion with per-color contribution controls, an Auto Mix action, and useful filter presets.
- [ ] Provide shadow tint and red, green, and blue primary hue/saturation controls.
- [ ] Persist these settings non-destructively and verify they run in the shared render pipeline.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
