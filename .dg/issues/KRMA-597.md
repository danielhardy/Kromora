---
id: KRMA-597
title: Add clipping alerts, pixel readouts, and video scopes
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
created: 2026-09-26T13:56:26.985Z
updated: 2026-09-26T13:56:42.800Z
blockers: []
order: gaaaaa9u
board: product
---

## Objective

Make exposure and color evaluation visible through clipping feedback, cursor measurements, and professional histogram scopes.

## Context

The current histogram has RGB and luminance channels but no clipping badges, cursor readouts, or waveform/parade/vectorscope modes.

Derived from §2.1 White balance and tone fundamentals; §9 Viewing, comparison, and proofing ergonomics in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Show highlight/shadow and per-channel clipping indicators on the image and histogram, with numeric clipped-pixel counts and a way to jump to Exposure.
- [ ] Show pre/post RGB and Lab cursor readouts in documented scales.
- [ ] Add waveform, RGB parade, and vectorscope modes while retaining RGB and luminance histogram views.
- [ ] Keep overlays toggleable and ensure measurement coordinates follow crop and zoom.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
