---
id: KRMA-523
title: Bound brush-mask rasterization by ROI and touched area
type: task
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - performance
  - masks
created: 2026-09-21T20:33:04.494Z
updated: 2026-09-21T21:41:08.060Z
estimate: 8
order: zh
board: product
---

## Objective

Make brush-mask rasterization scale with the touched region rather than the full image, preserve coordinate/parity behavior, and add cancellation and bounded cache behavior.

## Context and evidence

LocalMaskRenderer.brushImage/cachedStrokeRaster allocate a full-frame Float buffer per stroke and then loop over every pixel and every resampled sample without a dab bounding box or radius cutoff. A 24 MP frame needs roughly 96 MB before compositing, exceeding the 64 MiB stroke cache, and the loop has no cancellation checks. Cache removal scans linearly. The required behavior includes full-frame coordinates, non-zero ROI origins, crop/rotation, and parity with linear/radial/boolean masks.

## Scope

- Limit each brush sample to its dab bounding box including radius and feather.
- Rasterize only the evaluated ROI plus a correct halo; tile/cache by stroke, transform, scale, and tile where useful.
- Check cancellation per row or tile.
- Replace O(n) cache-order removal with bounded/LRU-friendly bookkeeping.
- Evaluate whether a Metal/CI kernel is appropriate, coordinating with CQ-09, but do not trade away preview/export parity or correctness for an optimization.

## Acceptance criteria

- [ ] Brush parity tests pass for brush, linear, radial, boolean operations, crop, rotation, and non-zero ROI origin.
- [ ] Cold render time and peak allocation scale with touched area/ROI, not full frame size; before/after figures are recorded.
- [ ] Cancellation is observed within a bounded tile/row interval.
- [ ] Cache size and eviction remain bounded without quadratic behavior.
- [ ] Existing mask rendering and export tests pass.

## Dependencies and coordination

Independent of the package/library chain. It may land before CQ-09, but any shader work should be isolated so this ticket remains reviewable. CQ-15 should account for any resulting mask-resolution helper boundaries.

## Likely files and checks

LocalMaskRenderer.swift, LocalMaskModels.swift, mask math/render tests, performance baselines, and potentially RenderEngine resources if a GPU path is chosen.
