---
id: KRMA-266
title: Build mask bitmaps at 8-bit instead of RGBAf
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Peak transient allocation for a 60MP raster conversion ≤ 256MB (no 4-channel Float staging buffer)
      result: pass
    - criterion: Pixel-identical (or ≤1 LSB) end-to-end render vs current path on gradient/feathered fixtures, covered by a test
      result: pass
    - criterion: swift build, swift test pass with zero Swift 6 diagnostics and zero opt-outs
      result: pass
  checks_run:
    - swift build — clean
    - swift test — 934 executed, 42 expected skips, 0 failures
    - swift test --filter LocalMaskRenderingTests — 20/20 passed, including new testRasterPayloadRGBA8MatchesPreviousRGBAfOverlayOnFeatheredFixture parity test
    - grep for @unchecked Sendable / nonisolated(unsafe) / @preconcurrency across Sources — no opt-outs (one unrelated comment mention)
    - "manual code review of rasterImage: single fused byte pass into a 60MB Data buffer (60MP case), no Float staging array; overflow guards added on width/values.count before the *4 byte-count computation"
    - git status --porcelain — clean tree aside from DG bookkeeping files
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-08T00:09:05.787Z
  session: 01MTRWEDE7NF5J3ABY
labels:
  - masking
  - performance
created: 2026-09-07T01:14:45.729Z
updated: 2026-09-10T12:53:51.936Z
order: a0
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
- If KRMA-265 (vImage) lands first, use `vImageConvert_PlanarFtoPlanar8` (with dithering
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


### Comment — codex @ 2026-09-07T23:54:49.740Z

Implemented in cc82d34. LocalMaskRenderer now emits an RGBA8 bitmap with clamped/rounded mask coverage in alpha via one fused byte pass, preserving top-down rows; renderer cache version bumped to 5. Added feathered end-to-end RGBA8-vs-legacy-RGBAf parity coverage. Verification: swift build; swift test (934 passed, 42 expected skips, 0 failures); dg validate.

## Agent log

- 2026-09-08T00:09:05.792Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Peak transient allocation for a 60MP raster conversion ≤ 256MB (no 4-channel Float staging buffer) (pass)
- [x] Pixel-identical (or ≤1 LSB) end-to-end render vs current path on gradient/feathered fixtures, covered by a test (pass)
- [x] swift build, swift test pass with zero Swift 6 diagnostics and zero opt-outs (pass)
Checks run:
- swift build — clean
- swift test — 934 executed, 42 expected skips, 0 failures
- swift test --filter LocalMaskRenderingTests — 20/20 passed, including new testRasterPayloadRGBA8MatchesPreviousRGBAfOverlayOnFeatheredFixture parity test
- grep for @unchecked Sendable / nonisolated(unsafe) / @preconcurrency across Sources — no opt-outs (one unrelated comment mention)
- manual code review of rasterImage: single fused byte pass into a 60MB Data buffer (60MP case), no Float staging array; overflow guards added on width/values.count before the *4 byte-count computation
- git status --porcelain — clean tree aside from DG bookkeeping files
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTRWEDE7NF5J3ABY
Summary: Independent verification: build/tests green (934 passed, 42 skips, 0 failures), targeted mask suite (20/20) including new RGBA8-vs-RGBAf parity test, no Swift 6 opt-outs, fused single-pass byte conversion confirmed to meet the ≤256MB transient budget. No fixes needed.
