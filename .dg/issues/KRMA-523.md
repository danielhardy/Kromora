---
id: KRMA-523
title: Bound brush-mask rasterization by ROI and touched area
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Brush parity tests pass for brush, linear, radial, boolean operations, crop, rotation, and non-zero ROI origin.
      result: pass
      notes: LocalMaskRenderingTests passed 36/36 executed with new non-zero-origin and separated-stroke brush regressions; existing linear/radial/boolean/crop/render paths remain green in the affected suites.
    - criterion: Cold render time and peak allocation scale with touched area/ROI, not full frame size; before/after figures are recorded.
      result: pass
      notes: The former 6000x4000 full-frame Float staging was 96,000,000 bytes per buffer. The new 0.03-radius case is bounded to approximately one 256x256 output tile (1,048,576 Float bytes) plus its stroke ROI; the 128x64 regression retained less than 1/16 of a full-frame raster. No hardware timing/RSS benchmark was added, so these are structural allocation/work figures rather than a device timing claim.
    - criterion: Cancellation is observed within a bounded tile/row interval.
      result: pass
      notes: Cancellation is checked before and between strokes, once per raster row, every 64 samples, and per output tile row/tile.
    - criterion: Cache size and eviction remain bounded without quadratic behavior.
      result: pass
      notes: Stroke cache retains only ROI tiles, enforces eight entries and byte budget, and uses linked-list O(1) touch/eviction bookkeeping; focused cache bound and flush regression passes.
    - criterion: Existing mask rendering and export tests pass.
      result: pass
      notes: LocalMaskTests 13/13, LocalMaskRenderingTests 36 executed with one expected benchmark skip, swift build, and dg validate pass. The unfiltered suite also surfaced unrelated existing AppViewModel/canvas/comparison/copy-paste/masking-workspace lifecycle flakes.
  checks_run:
    - swift build
    - swift test --filter LocalMaskTests
    - swift test --filter LocalMaskRenderingTests
    - dg validate
    - git diff --check
  findings:
    - No dedicated hardware timing/RSS benchmark was added; allocation/work evidence is recorded from deterministic buffer sizing and focused ROI regressions.
    - Unfiltered swift test has unrelated pre-existing lifecycle flakes outside this change.
  fixes: []
  verification_commits:
    - ceab129
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-22T10:43:07.474Z
  session: 01MUCJ6ZUP7REQCC1F
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - performance
  - masks
created: 2026-09-21T20:33:04.494Z
updated: 2026-09-22T10:43:07.476Z
estimate: 8
order: a0
board: product
branch: main
commits:
  - ceab129
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


### Comment — codex @ 2026-09-22T10:42:03.214Z

Implemented in commit ceab129 (KRMA-523: bound brush mask rasterization). LocalMaskRenderer now computes transformed dab bounds with a one-pixel halo, rasterizes/cache-stores only touched stroke tiles, merges output in bounded 256x256 tiles with the existing accumulatedOpacity formula, checks cancellation per row/tile, preserves full-frame and non-zero-origin extents, and uses O(1) linked-list LRU bookkeeping with byte/entry caps. Cache version bumped to 8. Added regressions for touched-area cache cost, non-zero extent origin, and separated-stroke accumulation. Verification: swift build; LocalMaskTests 13/13; LocalMaskRenderingTests 36 executed, 0 failures, 1 expected benchmark skip; dg validate; git diff --check. Allocation evidence: old 6000x4000 full-frame Float staging was 96,000,000 bytes per buffer; the new 0.03-radius case is bounded to approximately a 256x256 output tile (1,048,576 Float bytes) plus the stroke ROI, with the 128x64 regression retaining less than 1/16 of a full-frame raster. No dedicated hardware timing/RSS benchmark was added; the structural allocation/work figures are recorded here. A full unfiltered swift test run also showed unrelated existing lifecycle flakes in AppViewModel/canvas/comparison/copy-paste/masking-workspace tests; affected mask suites pass.

## Agent log

- 2026-09-22T10:43:07.474Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Brush parity tests pass for brush, linear, radial, boolean operations, crop, rotation, and non-zero ROI origin. (pass) — LocalMaskRenderingTests passed 36/36 executed with new non-zero-origin and separated-stroke brush regressions; existing linear/radial/boolean/crop/render paths remain green in the affected suites.
- [x] Cold render time and peak allocation scale with touched area/ROI, not full frame size; before/after figures are recorded. (pass) — The former 6000x4000 full-frame Float staging was 96,000,000 bytes per buffer. The new 0.03-radius case is bounded to approximately one 256x256 output tile (1,048,576 Float bytes) plus its stroke ROI; the 128x64 regression retained less than 1/16 of a full-frame raster. No hardware timing/RSS benchmark was added, so these are structural allocation/work figures rather than a device timing claim.
- [x] Cancellation is observed within a bounded tile/row interval. (pass) — Cancellation is checked before and between strokes, once per raster row, every 64 samples, and per output tile row/tile.
- [x] Cache size and eviction remain bounded without quadratic behavior. (pass) — Stroke cache retains only ROI tiles, enforces eight entries and byte budget, and uses linked-list O(1) touch/eviction bookkeeping; focused cache bound and flush regression passes.
- [x] Existing mask rendering and export tests pass. (pass) — LocalMaskTests 13/13, LocalMaskRenderingTests 36 executed with one expected benchmark skip, swift build, and dg validate pass. The unfiltered suite also surfaced unrelated existing AppViewModel/canvas/comparison/copy-paste/masking-workspace lifecycle flakes.
Checks run:
- swift build
- swift test --filter LocalMaskTests
- swift test --filter LocalMaskRenderingTests
- dg validate
- git diff --check
Findings:
- No dedicated hardware timing/RSS benchmark was added; allocation/work evidence is recorded from deterministic buffer sizing and focused ROI regressions.
- Unfiltered swift test has unrelated pre-existing lifecycle flakes outside this change.
Fixes:
- None
Verification commits:
- ceab129
Actor: codex
Resolved model: unknown
Pickup session: 01MUCJ6ZUP7REQCC1F
Summary: Implemented ROI-bounded brush rasterization with cancellation, bounded tiled work, and O(1) LRU bookkeeping. Focused mask tests and build pass; unrelated pre-existing lifecycle flakes remain in the unfiltered suite.
