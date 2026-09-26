---
id: KRMA-613
title: Add soft proofing, wider output spaces, and an HDR workflow
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
created: 2026-09-26T13:56:37.913Z
updated: 2026-09-26T13:56:43.381Z
blockers: []
order: tzzzzzz6
board: product
---

## Objective

Let photographers judge output color and dynamic range against their target display or delivery format.

## Context

WorkingSpace currently covers sRGB and Display P3; the evaluation found no soft-proof or end-to-end HDR story.

Derived from §2.4 Color science depth; §8 Export, output, and sharing; §9 Viewing in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Support Adobe RGB and ProPhoto RGB export targets and evaluate Rec. 2020 with profile conversion and embedding controls.
- [ ] Provide a soft-proof toggle with rendering intent, paper simulation, gamut warning, and out-of-gamut feedback.
- [ ] Define HDR canvas, histogram, and export behavior, including a supported gain-map format where feasible.
- [ ] Link proof settings to export presets and preserve existing sRGB/P3 behavior.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
