# LUMO-217 mask overlay prototype and baseline

## Decision

Use a coordinated transparent Metal sibling view for pointer-frequency mask overlays. The image
continues to be presented by the persistent `PreviewSurfaceView`; `MaskOverlaySurfaceView` owns a
transparent `MTKView` and a small line primitive pipeline. Both use the existing
`RenderEngine.presentationDevice` and `RenderEngine.presentationQueue`. The overlay does not create
a `CIContext`, read back a texture, evaluate a mask, or mutate `EditDocument`.

The sibling is preferable to adding overlay primitives to the image pass because its state and
drawable can be invalidated independently of image-render revisions. It also gives the future
mask workspace a clear hit-test owner: the transparent sibling returns itself from `hitTest` only
while the prototype is active; crop mode disables it and leaves crop input ownership unchanged.
The sibling's one-in-flight pacer retains the newest normalized geometry and requests one redraw
after completion. Preview surface, overlay view, and renderer each own only their own view/delegate
state; the shared device/queue are the sole GPU ownership seam.

The feature is opt-in with `LUMO_MASK_OVERLAY_PROTOTYPE=1`. It draws synthetic brush, linear, and
radial geometry plus a brush cursor. `MaskOverlayInteractionState` stores only transient normalized
upper-left source coordinates. Pointer events convert viewport points once through
`CanvasMaskTransform`; they never enter `AppViewModel` or persistence.

## Coordinate contract

`ImageDecoder` applies EXIF orientation before `ImageSource.nativeExtent` is published, so the
transform's `sourceSize` is always the oriented size. `CanvasMaskTransform` uses normalized source
coordinates with an upper-left origin. `CropAdjustments` remains bottom-left/Core Image based and
is flipped exactly once at the transform boundary. Crop-relative source pixels are then passed
through the same fit/fill/custom zoom/pan transform as `PreviewSurfaceView`.

The inverse mapping deliberately permits points outside the current crop. Therefore recropping
does not move or discard a future persisted mask point. Backing scale is applied symmetrically to
the viewport and drawable transform; 1× and 2× produce the same SwiftUI point result.

## Release baseline

Captured 2026-09-04 on the shared reference host:

| Field | Value |
| --- | --- |
| Hardware | MacBook Pro `MacBookPro18,3`, Apple M1 Pro, 16 GB, 16-core GPU |
| OS | macOS 26.6, build `25G72` |
| Checkout | `d8b0b91` before this issue's working-tree changes |
| Configuration | SwiftPM Release, logged-in display |
| Viewport / backing | 1280×800 points / 2560×1600 pixels (2× Retina) |
| Source | generated standard gradient, 1280×800; overlay prototype uses 6000×4000 geometry fixture |
| Cache state | warm completed-texture path; cold decoder/render is not claimed |
| Supporting work | off; no histogram; no semantic mask pixels |

Current persistent-preview baseline (`MetalPresentationBenchmark`, 20 warm transform samples plus
5 settled adjustment samples): p95 input-to-present **24.645 ms**, p99 **24.645 ms**, warm
presentation encoding p95 **0.265 ms**, warm GPU p95 **0.228 ms**, and peak resident-memory delta
**7.75 MB**. The direct display run is retained as the current-preview comparison point; its
input stream is synthetic rather than an AppKit pointer trace.

The overlay harness is reproducible with:

```sh
LUMO_MASK_OVERLAY_BENCHMARK=1 \
LUMO_MASK_OVERLAY_ITERATIONS=30 \
swift test -c release \
  --filter MaskOverlayPerformanceBenchmark/testRealMaskOverlayPresentationBenchmark
```

On the same host, the 30-sample transparent-sibling run reported p95 overlay input-to-present
**40.334 ms** and p95 main-thread update work **0.020 ms**. The update budget is below the 2 ms
target. The end-to-end display p95 is above the 16.7 ms target, and the one-in-flight pacer
coalesces an aggressively back-to-back synthetic stream, so this issue does not claim the display
gate as met. The existing preview baseline shows a 24–25 ms presentation cadence under its direct
benchmark. The trace evidence should be rerun under Instruments with Points of Interest + Metal
System Trace using a real pointer stream before the Step 0 performance gate is treated as closed.
The overlay's CPU state-update path remains below the target budget and does not touch the image
render path.

## Verification

The transform tests cover oriented portrait dimensions, bottom-left crop storage, fit, fill, custom
zoom, pan, window resize, non-square sources, and 1×/2× Retina backing. The observation tests
confirm overlay state changes publish through the narrow overlay object without emitting
`AppViewModel.objectWillChange`.

```sh
swift test --filter 'CanvasNavigationTests|CanvasObservationTests'
swift test --filter MaskOverlayPerformanceBenchmark
```

The second command is intentionally skipped unless the benchmark environment variable is set.

## LUMO-227 trace follow-up status (historical; workflow retired)

The follow-up previously included a Release-only, standalone AppKit capture host and wrapper. That
capture workflow was retired in LUMO-230 after the historical attempts below; the host and wrapper
are no longer available from this checkout.

The host uses `LUMO_MASK_OVERLAY_PROTOTYPE=1`, a real `NSWindow` containing the same
`MaskOverlayMTKView`/`MaskOverlayRenderer` path, and `xctrace` with Metal System Trace plus Points
of Interest. It emits overlay-specific `MaskOverlayPointerInput`, `MaskOverlayPresentationEncoded`,
`MaskOverlayGPUComplete`, and `MaskOverlayDrawablePresented` events so drawable/vsync cadence,
GPU completion, and presentation scheduling can be inspected independently.

Three local capture attempts on the reference host produced valid trace files, but the available
desktop automation did not deliver pointer events to the capture process (`input_events=0`,
`presentations=0`). Those traces are diagnostic only and are not evidence for a real-pointer p95 or
p99. The last attempt is `/tmp/lumo-227-real4/LUMO-227-mask-overlay-20260904-164958.trace`.
Consequently the real-pointer p95/p99 table and the cadence-versus-sibling attribution remain
pending a human-driven gesture session; the 40.334 ms synthetic result and 24.645 ms persistent
preview comparison above remain the only measured numbers. The 16.7 ms gate is still explicitly
unclosed, and no architecture change is claimed.
