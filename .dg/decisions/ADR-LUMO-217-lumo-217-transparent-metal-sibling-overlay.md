---
id: ADR-LUMO-217
title: LUMO-217 transparent Metal sibling overlay
date: 2026-09-04T22:13:07.777Z
status: accepted
---

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
