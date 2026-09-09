---
id: LUMO-277
title: Grain kernel likely shares vignette's samplerCoord tiled-Metal seam defect
type: bug
status: ready
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-07T15:01:14.861Z
updated: 2026-09-09T14:10:41.734Z
parent: LUMO-271
depends_on:
  - LUMO-271
order: z8
board: product
---

## Objective

`RenderPipeline.grainKernel` (`Sources/LumoKit/Models/RenderPipeline.swift:804-`) is a general
`CIKernel` that reads `sampler image` and computes `vec2 coordinate = samplerCoord(image);`, then
derives its noise field from that coordinate combined with extent-relative `geometry`
(`Sources/LumoKit/Models/RenderPipeline.swift:507`, `applyGrain`).

This is the same shape of defect LUMO-271 just fixed in `vignetteKernel`: a sampler kernel's
`samplerCoord(image)` is not guaranteed to equal `destCoord()` once Core Image splits a large
render into GPU tiles, so a kernel whose output depends on the *absolute* frame position (rather
than only on locally-sampled neighbor pixels) can produce rectangular seams in the completed Metal
presentation path — exactly the symptom LUMO-271 reproduced for vignette on a large zoomed RAW.

`grainKernel`'s noise (`grainHash`/`grainValueNoise`) is keyed off `coordinate`, which is derived
from `samplerCoord(image)`, and `geometry` folds in `extent.midX/midY` and `shortestSide`. That
combination is position-dependent in the same way the old vignette kernel was, so film grain on a
large RAW at deep zoom levels may show the same class of tile-boundary artifacts.

## Context

Found during LUMO-271 counterpoint verification. Not fixed there because it's outside that ticket's
acceptance criteria (vignette only) and converting `grainKernel` to a `CIColorKernel`-style,
`destCoord()`-based formulation — if that turns out to be the right fix — is a non-trivial kernel
rewrite (grain's noise function samples multiple neighboring lattice cells per pixel, which a plain
`CIColorKernel` can still do via `destCoord()`, but it needs its own verification pass and
regression test, analogous to `testLargeVignetteCompletedTextureHasNoZoomTileSeams`).

## Acceptance criteria

- [ ] Confirm whether grain actually exhibits tile-boundary seams on a large image across repeated
      zoom transitions (reuse the LUMO-271 regression methodology: large source, nonzero Grain
      amount, `PreviewSurfaceView.Coordinator.presentationImage` across zoom levels, assert no
      step discontinuities at likely GPU tile boundaries).
- [ ] If confirmed, rework `grainKernel` to use `destCoord()`-based, tile-stable geometry instead of
      `samplerCoord(image)`, following the same rationale documented on `vignetteKernel`.
- [ ] Add a deterministic regression test analogous to
      `RenderEngineTests.testLargeVignetteCompletedTextureHasNoZoomTileSeams`.
- [ ] Existing effects/preview/render-cache/export tests pass without weakening assertions.

## Implementation notes

- See `Sources/LumoKit/Models/RenderPipeline.swift:765-769` for the rationale comment written for
  the vignette fix (commit 6f14b45) — it explains exactly why `samplerCoord` is unsafe here.
- If grain turns out not to reproduce the seam in practice (e.g. because its per-tile ROI is always
  large enough that Core Image never splits the destination for typical preview sizes), downgrade
  or close with that finding recorded rather than forcing a speculative rewrite.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
