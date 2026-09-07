---
id: LUMO-265
title: Resample semantic masks with vImage instead of Swift loops
type: task
status: ready
priority: high
labels:
  - masking
  - performance
created: 2026-09-07T01:14:45.167Z
updated: 2026-09-07T04:16:49.593Z
order: yq
board: product
---

## Objective

Replace the hand-rolled bilinear loops in `MaskRefinementService.refine` and
`MaskOperations.resized` with Accelerate's `vImageScale_PlanarF`. Single biggest compute win
on the person-mask path, with less code, not more.

## Context

Measured in a debug build: upscaling the 768×512 analysis seed to 1920×1280 costs ~0.94s
(includes `NormalizedMask` validation passes); coverage over 2.5M values costs ~0.14s. Scaled
linearly to a 60MP source, one full-resolution resolve burns ~25s in Swift loops alone —
uncached and uncacheable (a 240MB payload can never fit the 64MB `localMaskCache` budget), so
every full-zoom preview, full-res render, and export pays it. Release builds are ~15–30×
faster on such loops, but 1–3s of single-threaded scalar resampling per render is still the
dominant cost, and Accelerate (Apple framework, zero third-party deps — repo rule satisfied)
does this SIMD and multithreaded at roughly 10–50× the throughput.

## Work

- Route both upscale sites through one shared helper (e.g. on `MaskOperations`, next to
  `resized`, keeping the existing seam tests meaningful): planar-Float scale with bilinear
 -equivalent interpolation.
- Keep the exact edge semantics the current code relies on (clamp-to-edge; the resolver's and
  refinement's `max(1, size - 1)` normalization). Any intentional behavior delta must be
  documented and covered by a test.
- Preserve cancellation points: the current `refine` checks cancellation per tile. Chunk the
  vImage work (or check between seed-fetch, scale, and store) so a superseded render still
  dies fast — vImage calls themselves are not cancellable mid-flight.
- No API changes for callers; `MaskOperations.resized` keeps its signature where feasible.

## Acceptance criteria

- [ ] `refine` and `resized` produce pixel-identical (or stated-tolerance) output vs the
      current implementation on the existing resize/union test fixtures.
- [ ] Measured wall-time improvement on a ≥2MP upscale recorded in the ticket (debug and
      release); the 60MP case must drop from tens-of-seconds to low-single-seconds in debug.
- [ ] Cancellation during a full-res refine still resolves within one tile/chunk, covered by a
      test.
- [ ] `swift build`, `swift test` pass with zero Swift 6 diagnostics and zero opt-outs.
