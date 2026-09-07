---
id: LUMO-266
title: Build mask bitmaps at 8-bit instead of RGBAf
type: task
status: backlog
priority: high
labels:
  - masking
  - performance
created: 2026-09-07T01:14:45.729Z
updated: 2026-09-07T01:15:36.474Z
order: zzzzzzzv
board: product
---

## Objective

Stop allocating ~1GB transient and looping 60M times to turn a mask into a `CIImage`.
`LocalMaskRenderer.rasterImage` builds `[Float](repeating: 0, count: values * 4)` — 960MB for a
60MP mask — writes every fourth float in Swift, then copies the whole thing into `Data` for an
RGBAf bitmap whose RGB channels are always zero. Only the alpha channel carries information.

## Context

This runs on *every* full-resolution render with a semantic layer, including cache-hit
payloads: the payload cache can never hold a 240MB entry (64MB budget), and even the
MaskStore `.render` reuse still funnels through this conversion. It is pure overhead —
typically larger than the upscale that produced the mask.

## Work

- Convert to 8-bit in a single fused pass (clamp + quantize while writing bytes, no Float
  staging buffer): 60MB transient instead of ~2GB including the `Data` copy.
- Target format must be proven equivalent downstream: today the value rides the alpha channel
  of RGBAf into `blendWithAlphaMask`. An RGBA8 bitmap with the value in alpha is the
  conservative choice; single-channel (R8) is smaller still if the blend chain accepts it —
  verify, don't assume.
- If LUMO-265 (vImage) lands first, use `vImageConvert_PlanarFtoPlanar8` (with dithering
  explicitly off — masks must stay deterministic) instead of a Swift loop; otherwise a Swift
  byte loop is still ~4× less memory traffic than today and acceptable as a stepping stone.
- Visual parity is load-bearing: extend the existing top-down orientation test
  (`testRasterPayloadRowsRenderTopDownInOverlay`) or add a render-comparison test asserting
  identical output for float vs 8-bit paths on a feathered fixture.

## Acceptance criteria

- [ ] Peak transient allocation for a 60MP raster conversion ≤ 256MB (measure or compute from
      formats; no 4-channel Float staging buffer).
- [ ] Pixel-identical (or ≤1 LSB) end-to-end render vs the current path on gradient/feathered
      fixtures, covered by a test.
- [ ] `swift build`, `swift test` pass with zero Swift 6 diagnostics and zero opt-outs.
