---
id: KRMA-612
title: Add named export presets and a resilient batch queue
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
created: 2026-09-26T13:56:37.227Z
updated: 2026-09-26T13:56:43.346Z
blockers: []
order: t555554c
board: product
---

## Objective

Turn one-off export into a reusable, observable delivery workflow.

## Context

Full-resolution export is already correct; this work expands configuration and queue control without changing preview/export render parity.

Derived from §8 Export, output, and sharing in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Save named export presets and fan one selection out to multiple presets.
- [ ] Queue exports with per-item progress, retry, cancel, reveal, recent history, and continuation after individual failures.
- [ ] Add short-edge, dimensions, megapixel, percentage, resolution, don't-enlarge, and crop-to-fit options.
- [ ] Add filename token templates with collision preview, watermark controls, JPEG size estimates/limits, and output sharpening.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
