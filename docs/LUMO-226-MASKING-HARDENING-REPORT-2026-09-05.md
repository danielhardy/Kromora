# LUMO-226 masking hardening report

## Scope and methodology

This pass covers the integrated local-mask seams: persisted value state, ordered component
composition, brush input, analytic and raster rendering, presentation-only inspection, async
request supersession, cache invalidation, accessibility state, source switching, and the user-facing
mask shortcut/help contract.

Automated checks were run on macOS 26.6 (build `25G72`) with Xcode 26.6 and the SwiftPM package's
macOS 14 deployment target. Tests use generated 8×4 and 8×8 fixtures for deterministic pixel
assertions; the UI tests use the existing fake renderer and main-actor workspace harness. Release
builds use the same package configuration as the application target.

## Implemented gates

- Brush gestures append strokes instead of replacing the selected brush definition. Live pointer
  samples are distance-resampled and capped at 4,096; mouse pressure and brush settings remain
  stroke-local.
- Brush rasterization is cached per stroke, target dimensions, and transform. The cache has both
  an eight-entry cap and a byte-cost cap, and is flushed on source/cache invalidation and memory
  pressure.
- A newer mask request revision supersedes an older resolver operation at every async boundary;
  stale payloads cannot be inserted into the cache or published into a render.
- Overlay inspection remains presentation-only. It supports composed alpha, inversion, color-wash
  and grayscale inspection, selected/solo layer/component state, and keyboard-accessible nudging.
- Component and solo controls expose labels, values, and named actions; source reset clears the
  transient masking selection/gesture state. README shortcuts now describe brush, erase, gradient,
  nudge, and brush-radius controls.

## Automated results

| Command | Result |
| --- | --- |
| `swift test --disable-sandbox --filter 'MaskingWorkspaceTests\|LocalMaskTests\|LocalMaskRenderingTests\|RenderCacheTests'` | Pass: 55 tests, 1 intentional RAW skip |
| `swift test --disable-sandbox --filter 'MaskingWorkspaceTests\|LocalMaskRenderingTests'` | Pass: 23 tests |
| `swift build -c release` | Pass |
| `scripts/build-macos-app.sh && scripts/verify-app-icon.sh && scripts/verify-app-signature.sh` | Pass: bundled assets, strict signature, and four expected entitlements |
| `dg validate` | Pass; existing warning that `gpt-5.6-luna` is not registered for `codex` |
| `git diff --check` | Pass |
| `swift test --disable-sandbox --parallel` | Fails in the known cross-test timing/state-pollution cluster tracked by LUMO-231; masking tests, including the new regressions, pass in that run |

The repository-wide format script also reports pre-existing violations across the large masking and
application files (including files changed by earlier masking tickets). Those violations are not
mechanically reformatted here because doing so would expand this issue into an unrelated repository
wide rewrite.

## Hardware performance status

The existing reference-host measurements are retained in
[`LUMO-217-MASK-OVERLAY-BASELINE-2026-09-04.md`](LUMO-217-MASK-OVERLAY-BASELINE-2026-09-04.md):
the synthetic transparent-sibling run measured p95 main-thread update work of 0.020 ms and p95
input-to-present of 40.334 ms, while the persistent preview baseline measured 24.645 ms p95. Those
are useful baselines but do not close the real-pointer or 16.7 ms overlay gate.

The Release benchmark was attempted with:

```sh
LUMO_MASK_OVERLAY_BENCHMARK=1 LUMO_MASK_OVERLAY_ITERATIONS=30 \
swift test -c release --disable-sandbox \
  --filter MaskOverlayPerformanceBenchmark/testRealMaskOverlayPresentationBenchmark
```

Compilation completed, but this session did not produce a drawable/pointer presentation callback;
therefore no new p95/p99 claim is made. The required real AppKit gesture and Instruments trace still
needs a human-driven logged-in display session. The historical wrapper used for this attempt was
retired in LUMO-230, so the real-pointer capture workflow is no longer available from this checkout.

## Remaining handoff gate

Use Instruments on the in-app Lumo mask-overlay path on the reference Mac with a human moving and
dragging over the visible editor, then attach the resulting trace/summary and record p95/p99 for
brush, gradient handles, smart refinement, source switching, zoom/pan, ten layers, 45 MP input, and
full-resolution export.
This is the only remaining action that requires a human display/gesture session rather than a code or
ordinary dependency change.
