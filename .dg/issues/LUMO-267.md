---
id: LUMO-267
title: Fuse validation and coverage into mask generation
type: task
status: backlog
priority: medium
labels:
  - masking
  - performance
created: 2026-09-07T01:14:46.343Z
updated: 2026-09-07T01:28:01.830Z
order: sssssssg
board: product
---

## Objective

Stop walking every full-resolution mask three extra times after generating it.
`NormalizedMask.init` runs `allSatisfy(isFinite)` plus a clamping `map`, and `coverage` runs a
`reduce` — three full passes over up to 60M values per resolve, on top of the compute pass.
Measured: the coverage pass alone costs ~0.14s per 2.5M values in debug (~3.5s at 60MP).

## Context

For internally generated masks the validation is provable dead weight: bilinear interpolation
of finite `[0, 1]` inputs with weights in `[0, 1]` is finite and stays in `[0, 1]`. We pay
for a guarantee the producer already provides. (External inputs — decoded files, provider
buffers — must keep full validation; the sidecar/legacy loads in `MaskStore` stay as-is.)

## Work

- Add an unchecked (or trust-but-verify-in-debug) construction path for masks produced by our
  own resampling, e.g. `NormalizedMask(trustingSize:values:)` with a `precondition` on count,
  used by `refine` and `resized`. Keep the validating initializer for all I/O boundaries.
- Compute `coverage` inline in the generation loop (running sum) instead of a separate
  `reduce`, threading it through to the returned `RegionMask` where the call sites currently
  recompute it.
- Pairs naturally with LUMO-265 (vImage): if vImage lands first, coverage-summing needs a
  home — either a vImage histogram/mean pass or a single Swift accumulation over the scaled
  buffer (one pass, not three).

## Acceptance criteria

- [ ] Full-resolve path performs at most one post-generation pass over the values (the
      coverage accumulation, if not folded into generation).
- [ ] I/O boundaries (store loads, provider buffers) still go through the validating
      initializer — covered by existing tests, plus a test that the unchecked path traps on a
      count mismatch in debug.
- [ ] Measured improvement recorded alongside LUMO-265's numbers.
