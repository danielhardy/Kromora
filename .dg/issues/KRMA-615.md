---
id: KRMA-615
title: Add split, reference, and survey comparison views
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
created: 2026-09-26T13:56:39.295Z
updated: 2026-09-26T13:56:43.451Z
blockers: []
order: vpppppou
board: product
---

## Objective

Make frame-to-frame matching and before/after review possible without leaving the editing context.

## Context

The app already has a comparison model and pannable/zoomable canvas; extend rather than replace those paths.

Derived from §9 Viewing, comparison, and proofing ergonomics in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Add a draggable left/right or top/bottom before/after divider in one canvas.
- [ ] Allow any two photos to be compared with zoom/pan locked for match-grade work.
- [ ] Add an N-select survey grid and lights-out/fullscreen review modes.
- [ ] Keep the existing side-by-side and hold-Space comparison behavior available.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
