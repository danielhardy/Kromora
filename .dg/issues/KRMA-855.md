---
id: KRMA-855
title: "Test semantic mask resolver: soften/shift/strength at matte resolution before resize"
type: task
status: backlog
priority: low
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:08:33.115Z
updated: 2026-10-10T13:08:41.578Z
depends_on:
  - KRMA-852
blockers: []
order: zzx
board: product
---

## Objective

KRMA-852 moved Soften / edge shift / strength in `CoordinatorLocalMaskResolver.resolve` (Sources/KromoraKit/Models/LocalMaskRendering.swift) to run on the matte at its own resolution before the single resize to the target. Nothing asserts that the reorder preserves the result or that the payload size and values remain correct.

## Context

- Softness radius is `edgeFeather * min(mask width, height) * 0.05`, rounded, minimum 1 px, so it is resolution-independent by design. Edge shift and density are per-value affine maps and commute with bilinear resize except at the [0,1] clamp.
- Known difference: the 1 px minimum radius is relatively wider at low Soften; the matte is stretched to the photo's aspect afterwards.

## Acceptance criteria

1. A resolver-level test (fake `PhotoAnalysisCoordinator` or the existing mask test doubles) resolves a semantic definition with non-default softness, shift and strength and asserts the payload `targetSize` equals the request and all values lie in [0,1].
2. A tolerance test compares the new order against resize-then-apply for a smooth matte at 2-3 softness values; document the tolerance and why (and assert it stays within it).
3. Strength 0.5 on a binary matte yields max value 0.5 after resolution; shift +1 saturates coverage; shift -1 empties it.
4. An identity definition (softness 0, shift 0, strength 1) returns the resized matte unchanged and does not allocate the blur path.
5. Runs in the `fast` lane.

Related: KRMA-852, KRMA-847.
