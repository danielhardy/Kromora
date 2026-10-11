---
id: KRMA-854
title: Add unit tests for MaskOperations.feather (reference equivalence, edges, cancellation)
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
created: 2026-10-10T13:08:32.151Z
updated: 2026-10-11T13:11:12.587Z
depends_on:
  - KRMA-847
blockers: []
order: zzv
board: product
---

## Objective

`MaskOperations.feather` (Sources/KromoraKit/Models/PhotoAnalysis/MaskOperations.swift) has no direct unit tests. KRMA-847 replaced its O(pixels x r^2) window scan with a separable running-sum blur and verified it only through existing mask tests. Pin its behavior so a future optimisation cannot silently change soften output.

## Context

- Contract: each output pixel is the mean of the in-bounds samples in the (2r+1) x (2r+1) window clipped to the mask edges (denominator is the actual in-bounds count, not (2r+1)^2).
- Output must populate `coverage` and `isBinary` consistently with `NormalizedMask.init(size:values:)`.
- `Task.checkCancellation()` runs every 64 rows in both passes.

## Acceptance criteria

1. A test-only naive reference implementation (the pre-KRMA-847 loop) lives in the test target and the optimised result matches it within 1e-5 per pixel for: a random 37x23 mask at radii 1, 2, 5; a radius larger than both dimensions; a 1xN and an Nx1 mask; an all-zero and an all-one mask.
2. A hard-edged half-plane mask blurred at radius r reads about 0.5 on the original edge and spreads r pixels each way (inside and outside).
3. `coverage` equals the mean of the output values and `isBinary` is false after a non-trivial blur, true for radius 0 on a binary mask.
4. A cancellation test: a task running feather on a large mask (for example 4000x3000) and cancelled immediately throws `CancellationError` well before completing.
5. Tests are deterministic (seeded generator) and run in the `fast` lane.

Related: KRMA-847.


### Comment — claude @ 2026-10-11T13:11:12.586Z

Scope trimmed (2026-10-11): RegionMaskTests already has clipped-window reference equivalence, cancellation, and coverage/isBinary checks. Remaining: 1xN and Nx1 masks, radius larger than the mask, half-plane edge test, isBinary at radius 0.
