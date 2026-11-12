# Kromora rendering performance, accuracy, and stability audit — 2026-11-12

Assessment of `main` at `c5057f84b4e5b84f032fcf57a01abe7ed2de695f`. The working tree was clean at the
start. This audit adds only this report; it changes no application code, tests, scripts, or issue
records. The format follows the [November 3 code-quality audit](2026-11-03-code-quality-audit.md).

**Scope.** Only the edit-canvas render path: getting from an `EditDocument` to pixels on the canvas
quickly, accurately, and without glitches. That covers `RenderEngine`, `RenderPipeline`,
`RenderEngineResources`, `ResolutionPlanner`/`RenderScale`, `PreviewCoordinator`,
`PreviewAdmissionCoordinator`, `PreviewPublicationCoordinator`, `PreviewPresentationCoordinator`,
`PreviewSurface` (including its Metal presenter and shader), and the stored-frame/thumbnail
interaction with that path. Library indexing, persistence, import, and masking UI are out of
scope except where they put work on the render actor.

**Goal used as the bar.** The photo renders quickly with accurate pixels every time, and the canvas
never shows a glitch: no blank or stale frame, no blur flash, no pop or shift when a frame is
replaced, and no resampling or edge artifact.

## Assessment

The render architecture is mature. It has one graph funnel for preview and export, explicit
revision fences, a two-level cache (developed source, then graded prefix), completed GPU textures at
the engine boundary, a persistent Metal presenter, stored-frame classification with one freshness
authority, and presentation-budget tests. Most of the hard problems already have a named owner and a
test.

The defects that remain sit at **boundaries between those parts**, and they are the defects a
photographer notices first:

1. **Live feedback during a drag.** The coordinator and the publisher both discard any in-flight
   interactive frame once a newer value arrives. Each render takes longer than the interval between
   pointer events (the recorded warm input-to-present is 24.4 ms on a 1280×800 drawable), so a
   continuous drag can show no intermediate frames at all (finding 01).
2. **One actor for every GPU job.** `RenderEngine.shared` runs the visible preview alongside export,
   thumbnails, idle warming, prefetch, canonical-frame encoding, and RAW develop. Several of those
   block the actor synchronously, and the editor-lane priority does not apply once work reaches the
   actor (finding 02).
3. **Presenter-level resampling and frame handoff.** The canvas uses 8-bit display textures, bilinear
   sampling without mipmaps, unsnapped quads, and two different draw paths per publication. These
   cause blur flashes during pans, shimmer, pops when a frame is replaced, and a 1:1 view that is
   never pixel-exact (findings 03, 05, 09, and 11).
4. **Scale-dependent pixel math.** Detail controls use radii in output pixels, and spatial filters
   are not edge-clamped. Preview therefore differs from export, interactive frames from settled
   ones, and ROI frames from full-frame ones, at the borders and in sharpening strength (findings 06
   and 07).

Fixes for findings 01–03 are small and local. I would do them before adding any further render
features.

| Dimension | Assessment | Most useful next improvement |
| --- | --- | --- |
| Interactive speed | Good warm costs and caching; the drag path discards finished work and shares one actor with every background job | Publish any newer interactive frame; move blocking work off the visible render actor |
| Pixel accuracy | Strong preview/export funnel and colour policy; scale-dependent Detail, unclamped spatial filters, and an 8-bit presentation path undermine "perfect" | Make every spatial radius photographic, edge-clamp spatial filters, and present at 16-bit |
| Frame stability (no flash, pop, or twitch) | Excellent invariants for source switches and stored frames; frame handoff inside one photo still has gaps | One presenter path, never drop detail while its texture materializes, snap to pixels, and crossfade every quality step |
| Verification | Many structural and golden tests; few tests assert timing behavior, pixel parity across scales, or border pixels | Add the specific tests listed under each finding |

## Evidence and limits

- I read the render-path source listed under scope, the presentation shader, `docs/ENGINEERING_GUIDE.md`
  (render path, presentation frames, budget), and the measured-state sections of
  `docs/TESTING.md`. I also read the relevant tests (`PreviewCoordinatorTests`, `CropROITests`,
  `EffectsPipelineTests`, `MetalKernelParityTests`, `RAWDetailRoutingRenderTests`) to see what
  they cover.
- **No code was run for this audit.** No test lane, probe, Instruments trace, or display-bound
  capture was run; per `CLAUDE.md`, capture benchmarks are release-time evidence. Timings quoted
  below come from `docs/TESTING.md` (KRMA-738, Apple M1 Pro, macOS 27.0, `DSC01019.ARW`, 1280×800
  drawable, 2026-09-30). I make no new latency or memory claims.
- **Confidence labels.** **Code-confirmed** means I traced the control flow or math end to end and
  the behavior follows from the code as written. **Code-indicated** means the code strongly
  suggests the defect, but it depends on framework behavior or product intent that a pixel or
  timing test should confirm before the fix. Neither label establishes how often the problem occurs
  or how visible it is; each finding names the test that would establish that.

**Priority.** **P0**: user-visible during ordinary editing and directly contrary to the stated
goal; fix as soon as possible. **P1**: a visible accuracy or stability defect in common scenarios;
fix before the next release. **P2**: a material quality or performance improvement. **P3**:
polish, hygiene, or verification debt.

## Summary of findings

| # | Pri | Area | Finding | Confidence |
| --- | --- | --- | --- | --- |
| 01 | P0 | Speed | A continuous drag discards every in-flight interactive frame, so the canvas can freeze until the pointer pauses | Code-confirmed |
| 02 | P0 | Speed / stability | One shared engine actor serializes export, thumbnails, warming, and RAW develop with the visible preview; several of these block the actor synchronously | Code-confirmed |
| 03 | P0 | Stability | During a zoomed pan, each new ROI frame vanishes, leaving only the blurry underlay, until its display texture materializes | Code-confirmed |
| 04 | P1 | Accuracy | An exact stored frame (a 2048 px JPEG) is treated as final and never refined, even on canvases larger than 2048 px | Code-confirmed |
| 05 | P1 | Accuracy / stability | The presenter minifies up to 2× with bilinear sampling and no mipmaps, and quads are not pixel-snapped: aliasing, shimmer, and a soft "100 %" view | Code-confirmed |
| 06 | P1 | Accuracy | The sharpening radius is in output pixels, so preview ≠ export and interactive ≠ settled; noise reduction is scale-dependent | Code-confirmed |
| 07 | P1 | Accuracy | Unsharp, sharpen-luminance, and noise-reduction filters are not edge-clamped, and the ROI margin ignores Detail: halos at photo and viewport borders | Code-indicated |
| 08 | P1 | Accuracy | The custom tone curve runs on linear working values through a 256-texel LUT clamped to [0, 1]: coarse shadows and lost highlight headroom | Code-indicated |
| 09 | P1 | Stability / speed | Each publication is drawn first by a Core Image fallback and then by a separate Metal path from an extra bgra8 copy | Code-confirmed |
| 10 | P1 | Stability | Quality step-ups (interactive → settled, embedded → settled) swap instantly between visibly different renders | Code-confirmed |
| 11 | P2 | Accuracy | The display chain is 8-bit end to end (bgra8 drawable and texture, no dither): banding in gradients | Code-confirmed |
| 12 | P2 | Stability | Drawable resize has no transaction or placement policy: stretch and jump during window or inspector resize | Code-confirmed |
| 13 | P2 | Speed | RAW developed-source materialization uses a synchronous CPU readback instead of the existing GPU texture path | Code-confirmed |
| 14 | P2 | Speed | Per-frame allocation churn: new processing texture, new presentation texture, and two `MTLBuffer`s per draw | Code-confirmed |
| 15 | P2 | Stability | ROI renders cover exactly the visible rect, with no overscan; every pan exposes the lower-detail underlay | Code-confirmed |
| 16 | P2 | Stability | The crossfade is paced by `Task.sleep(16 ms)` rather than the display link | Code-confirmed |
| 17 | P3 | Accuracy | The shader multiplies alpha on already premultiplied texels (edge darkening during crossfade or at antialiased edges) | Code-indicated |
| 18 | P3 | Accuracy | Histogram and scopes sample the 8-bit display-encoded presentation texture | Code-confirmed |
| 19 | P3 | Speed | Thumbnail fringe repair runs a CPU per-pixel loop on the render actor | Code-confirmed |
| 20 | P3 | Verification | Tests do not cover drag cadence, cross-scale Detail parity, border pixels, or the presenter's handoff | — |

---

## P0 — fix as soon as possible

### 01. P0 — A continuous drag discards every in-flight interactive frame

**Code-confirmed.** Every slider or curve tick advances the display revision in
`PreviewAdmissionCoordinator.scheduleInteractivePreview()`
([PreviewAdmissionCoordinator.swift:960](../../Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift)),
and the new value goes to `PreviewCoordinator.admit`. That method:

- cancels the in-flight interactive scheduler job and task (`cancelInteractiveJob`,
  `interactiveTask?.cancel()`), so the running render returns at its next `Task.isCancelled` check;
- replaces `latestToken`, so even a render that completes fails `isCurrent(token)` and is counted as
  stale
  ([PreviewCoordinator.swift:456](../../Sources/KromoraKit/ViewModels/PreviewCoordinator.swift), `isCurrent` at :477);
- leaves the in-flight frame with an old display revision, so
  `PreviewPublicationCoordinator.publish` would reject it anyway
  ([PreviewPublicationCoordinator.swift:84](../../Sources/KromoraKit/ViewModels/PreviewPublicationCoordinator.swift)).

The "one in flight, keep the latest pending" pacer (`pendingInteractive`, :299) prevents queue
growth, but it does not cause anything to be **shown**. Only a frame whose value is still the newest
when it finishes can reach the screen. When render time exceeds the event interval — 24.4 ms warm
on a small drawable versus 8–16 ms trackpad or slider events — the canvas holds the pre-drag frame
until the pointer pauses or is released. This is the most direct contradiction of "renders quickly"
in the code.

`PreviewCoordinatorTests.testInteractiveUpdatesDoNotStartAnotherRenderWhileOneIsInFlight` asserts the
coalescing behavior but never asserts that the first render was published, so the suite passes
with this behavior.

**Recommendation.**
- For `.interactive` frames, replace "is the latest" with "is newer than what is on screen": publish
  a completed interactive frame if its token revision is greater than the last *presented*
  interactive revision for the same asset and source generation. Keep the strict latest-only rule
  for `.settled`.
- Do not cancel the in-flight interactive job when a newer value arrives; the pacer already holds
  the pending value. Cancel it only on source change, gesture end (settle), or shutdown.
- Stop advancing the engine's source-wide display revision on every interactive tick, or give
  interactive frames their own fence. Otherwise `buildImage`'s `latestRenderRevision > requestRevision`
  check ([RenderEngine.swift](../../Sources/KromoraKit/Models/RenderEngine.swift), `buildImage`) can still
  throw on a frame worth showing.

**Test.** Use a `ControlledRenderEngine` that completes each render only after N further
submissions. Assert that every completed interactive render whose revision is newer than the
displayed one is published, and that the settled frame still replaces the last interactive frame.

### 02. P0 — One engine actor serializes the visible preview behind blocking background work

**Code-confirmed.** Editor, comparison, histogram, prefetch, idle-warm, thumbnail, and export work
all call `RenderEngine.shared`. `ImageWorkScheduler` gives the editor its own lane, but that
priority ends at the actor: a job that is already inside the actor runs to completion first. Several
of those jobs block the actor's executor synchronously rather than suspending:

| Work | Blocking call | Where |
| --- | --- | --- |
| Export, full resolution | `context.startTask(...).waitUntilCompleted()` | [ExportRasterizer.swift:43](../../Sources/KromoraKit/Models/ExportRasterizer.swift) |
| Thumbnails, edited thumbnails, idle warmer, `makeCGImage` | `context.createCGImage` (render and readback) | [RenderEngine.swift:940](../../Sources/KromoraKit/Models/RenderEngine.swift) |
| RAW developed source, every cache miss | `CIRAWFilter` output plus synchronous `render(toBitmap:)` RGBAh readback | [RenderEngine.swift:2669](../../Sources/KromoraKit/Models/RenderEngine.swift), `materializedImage` :2387 |
| Canonical stored frame, after **every** settled preview | `createCGImage` 2048 px, Lanczos digest `render(toBitmap:)`, JPEG encode | [RenderEngineResources.swift:96](../../Sources/KromoraKit/Models/RenderEngineResources.swift), :148, :167 |

Consequences:

- Starting a drag right after a settle waits behind that settle's canonical JPEG encode.
- Opening a photo or dragging while an export runs waits for the entire export rasterization.
- An idle-warmer or prefetch RAW decode that is cancelled after it enters the actor still delays
  the first interactive frame by one full decode.

The `concurrent-export-editing` capture exists, but `docs/TESTING.md` records no result for it.

**Recommendation.**
1. Move export to its own `RenderEngine` instance (its own `CIContext` and queue), or at least run
   its rasterization through a suspending completion (`CIRenderTask` wait on a detached executor,
   or `commitAndWaitForCompletion` like `makeCIImage`) rather than `waitUntilCompleted()` on the actor.
2. Move canonical-frame production (rasterize, digest, JPEG) off the engine actor: render the 2048 px
   texture on the actor asynchronously, then do readback and encoding in a detached task. This pattern
   already exists for standard-image decode.
3. Give thumbnails and the idle warmer a second engine instance, or a `@concurrent` rasterizer that
   holds only a `Sendable` completed `CIImage`, so the visible preview has an actor that only it uses.
4. Measure with `concurrent-export-editing` once, after the change, in the next supervised
   performance session.

### 03. P0 — A zoomed pan shows a blur flash on every new ROI frame

**Code-confirmed control flow; visual frequency unmeasured.** `PreviewSurface.present` sets
`presentationTexture = nil` for every new publication
([PreviewSurface.swift:249](../../Sources/KromoraKit/Views/PreviewSurface.swift)) and starts asynchronous
materialization. In `draw`, `metalFrames(in:)` (:1376) includes the detail frame only when its
texture exists, but includes the complete-frame underlay whenever `hasCompleteUnderlay` is true
(:926). That is the case for a partial ROI while the pointer is moving. Because `metalFrames` is
non-empty, the Metal path runs (:1518) and the Core Image fallback, which could draw the new
detail, is skipped.

The result: during a pan or pinch at zoom, the canvas draws **only the lower-resolution underlay**
from the moment a new ROI is published until its bgra8 copy completes, then the sharp fragment
reappears. The previous sharp ROI is no longer drawn either. The comment above the branch states
the intended invariant ("must not be the only thing drawn"), but the condition does not enforce it.

**Recommendation.** Keep drawing the previous detail texture until the new one has materialized
(promote on completion, as `lastValidPresentationTexture` already supports), or fold the detail into
the frame list through the fallback when its texture is pending. Finding 09's single-path fix
removes the gap entirely.

**Test.** A `PreviewSurface` lifecycle test that publishes a partial ROI under moving navigation
with a retained complete frame, then asserts that every drawn stack includes a detail frame.

---

## P1 — fix before the next release

### 04. P1 — An exact stored frame is final even when it is lower resolution than the canvas

**Code-confirmed.** `submitSettledPreview` presents an `.exact` stored frame and returns without
rendering
([PreviewAdmissionCoordinator.swift:871](../../Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift)).
The stored frame is a 2048 px long-edge, quality 0.9, 8-bit JPEG (`FrameClassifier.previewLongEdge`,
`canonicalJPEGQuality`). `FrameClassifier` compares source, edit, Look, space, and epoch, but not
the resolution the canvas needs. On a 5K/6K display, or any window whose fit backing size exceeds
2048 px, a reopened photo stays upsampled and JPEG-compressed until the user edits or zooms. The
presentation budget ("exact stored Edit open: 0 render requests") enshrines this.

**Recommendation.** Treat an exact frame as final only when its pixel size meets or exceeds the
fit plan's required size. Otherwise present it as provisional and admit one settled render, using
the existing stale-refinement path. Its digest distance will usually be small, so the policy swaps
it without a crossfade. Update the budget row to "0 renders when the stored raster covers the
canvas".

### 05. P1 — Presenter resampling: minification aliasing and no pixel snapping

**Code-confirmed.**
- `ResolutionPlanner` picks the first of `[0.125, 0.25, 0.5, 0.75, 1.0]` at or above the required
  scale ([ResolutionPlanner.swift:113](../../Sources/KromoraKit/Models/ResolutionPlanner.swift)), so
  the settled texture can be up to about 2× the displayed size (for example, required 0.13 → level
  0.25). The presenter then downsamples it with a linear sampler and no mipmaps
  ([PreviewSurface.swift:1318](../../Sources/KromoraKit/Views/PreviewSurface.swift)). Bilinear
  minification beyond about 1.5× aliases: moiré on fabric and foliage, jagged diagonals, and
  shimmer while a window resizes or a pinch settles. The same happens during pinch-out before the
  next render.
- `CanvasNavigation.transform` produces fractional origins
  ([CanvasNavigation.swift:553](../../Sources/KromoraKit/Models/CanvasNavigation.swift)), and
  `quadGeometry` passes them straight to the vertex shader. At 100 % the image is resampled at a
  sub-pixel offset, so "1:1" is half a pixel soft, and sharpness oscillates as a pan crosses pixel
  boundaries. Quad edges are drawn without antialiasing, so edges crawl at fractional scales and
  with view-space rotation.

**Recommendation.**
- Make the final settled output exactly the drawable's display size: after `buildImage`, apply a
  high-quality `CILanczosScaleTransform` (or an area-average downsample) to the canvas scale inside
  the engine, so the presenter samples close to 1:1. Alternatively, generate mipmaps on the
  presentation texture (`MTLBlitCommandEncoder.generateMipmaps`) and use a trilinear or anisotropic
  sampler.
- Snap the quad origin to device pixels whenever the effective scale is 1 (or an integer), and use
  nearest sampling at exactly 1:1 so 100 % is pixel-exact.

### 06. P1 — Detail controls are not resolution-independent

**Code-confirmed math.** In `applyDetailControls`, the sharpening radius is computed as
`normalizedRadius(detail.sharpeningRadius / referenceShortSide, for: referenceExtent)`
([RenderPipeline.swift:1250](../../Sources/KromoraKit/Models/RenderPipeline.swift)). This reduces to
`sharpeningRadius` **output pixels** at every scale. A 1.0 px radius therefore covers about 6× more
of the photograph in a 1.5 MP fit preview than in a 60 MP export, and it changes between the
interactive budget and the settled level. Users see the sharpening change at settle, and the
preview does not match the export. `CINoiseReduction` thresholds per-pixel noise, which
downsampling has already averaged away, so its visible strength also depends on scale. Other
spatial effects use photographic fractions, and `RenderScale`'s header says resolution
independence is a hard requirement (§5). The KRMA-1183 parity test renders preview and export at the
same `.preview(maxSize:)` scale, so it cannot detect this.

**Recommendation.** Define the sharpening radius in native-source pixels and scale it by
`renderScale.factor`. Below a threshold (for example a radius under 0.5 output pixels), either
attenuate the amount with a documented approximation, or follow the Lightroom convention: show Detail
at full fidelity only at ≥ 1:1, and label the fit view. Add a parity test that renders an ROI at
native scale and compares it with the same region of a `.full` export.

### 07. P1 — Spatial filters sample transparent pixels at photo and ROI borders

**Code-indicated; confirm with a border-pixel test.** `croppedBlur` correctly uses
`clampedToExtent()`, but `CIUnsharpMask` (Detail sharpening :1254, Dehaze :1422, output sharpening
:1300), `CISharpenLuminance` (Texture :1355, Clarity :1388) and `CINoiseReduction` (:1220, :1235)
receive unclamped images. Core Image treats pixels outside the extent as clear, so the blurred term
darkens and loses alpha toward the edge, and the unsharp result overshoots: a bright or haloed rim. At Dehaze's
radius (2.6 % of the short side) that rim can be tens of pixels wide in export.

The ROI path makes this worse when zoomed. `expandedSourceROI` adds spatial support only when
`effects.hasSpatialWork` (Texture, Clarity, or Dehaze) is set
([EffectsAdjustments.swift:261](../../Sources/KromoraKit/Models/EffectsAdjustments.swift),
[RenderPipeline.swift:729](../../Sources/KromoraKit/Models/RenderPipeline.swift)), and the
geometry-ROI path uses 0.1 % otherwise (RenderEngine.swift:1600). Detail sharpening, noise reduction,
spatial local-mask effects, and mask feathering therefore see a hard edge at the **viewport**
boundary. That shows as a seam frame around the zoomed view, which then moves when the next ROI
lands. `testEffectsPreserveExtentAndAlpha` reads only a corner pixel of a constant 17×11 image at
the 0.5 px minimum radius, so it cannot catch this.

**Recommendation.** Apply `clampedToExtent()` before every spatial filter and crop back to the
input extent afterwards; one helper can cover every site. Compute the ROI support margin from the
maximum spatial radius of **all** active stages (Detail, local spatial effects, and feathers),
converted to source pixels. **Test:** render a gradient or checker at full scale with each spatial
control at maximum, and assert that the outermost N pixels match a reference made from a padded
render. Add a zoomed-ROI-versus-full-export comparison with Detail enabled.

### 08. P1 — The tone curve runs in linear light through a 256-texel LUT and clamps highlights

**Code-indicated; confirm against the curve UI's intended domain.** `applyToneCurve` (the CI kernel in
[KromoraCIKernels.ci.metal:485](../../Sources/KromoraKit/Resources/KromoraCIKernels.ci.metal)) indexes
a 256×1 table ([ToneCurveFilterCache.swift:10](../../Sources/KromoraKit/Models/ToneCurveFilterCache.swift))
with `clamp(pixel / a, 0, 1)`. Core Image hands custom kernels values in the context's working
space, which is extended **linear** Display P3. The consequences:

- Perceptual shadows (encoded 0–0.25 ≈ linear 0–0.05) fall into about 13 texels, so the curve's
  shadow region is coarse and can posterize with steep shadow edits.
- A curve point the user places at x = 0.25 lands at linear 0.25 (about 54 % perceptual), unless
  the inspector deliberately draws in linear coordinates. The rest of the Light stage converts to
  perceptual coordinates explicitly ("CIToneCurve interpolates in a gamma-2/perceptual domain",
  :1699).
- Values above 1.0 (RAW highlight headroom, positive Whites) and negative out-of-gamut components
  are clamped whenever any curve is active, which defeats the extended-range graph.

`MetalKernelParityTests` pin `space: .sRGB` for goldens, which does not exercise the engine's
linear context.

**Recommendation.** Inside the kernel, convert to the perceptual encoding the curve UI uses, look
up the curve, and convert back. Use at least 1024 samples, or sample the curve analytically.
Extrapolate (or pass through) values outside [0, 1] instead of clamping them. Add an engine-context
test that a point at (0.25, 0.35) moves an encoded-0.25 patch to encoded 0.35.

### 09. P1 — Two presenter paths and an extra copy for every publication

**Code-confirmed path split; visual delta unmeasured.** The engine already returns a completed,
texture-backed `CIImage` (RGBA16F, or RGBA8 for interactive frames). `present` then:

1. draws it once through the Core Image fallback (`presentationImage`: CI affine transform,
   2 px edge-clamp padding, and a top-aligned translate in a full-backing destination), and
2. renders it again on the presentation queue into a new bgra8 texture plus a histogram sample
   (`makePresentationTexture`, [PreviewSurface.swift:1010](../../Sources/KromoraKit/Views/PreviewSurface.swift)),
   after which every later draw uses the Metal quad (`quadGeometry`: a separate placement
   computation, sampler, and blend).

Two placement implementations and two resamplers draw consecutive frames of the same publication.
Any disagreement shows as a one-frame shift, sharpness change, or quantization step on every edit:
the "twitch". The second pass also costs one GPU render and one allocation per published frame,
including every interactive frame.

**Recommendation.** Have the engine hand presentation the completed `MTLTexture` and extent (it
already creates them in `makeCIImage`) and draw it directly with the Metal quad from the first
draw. Compute the histogram sample from that texture in the same command buffer. Keep the Core
Image fallback only for hosts without a pipeline. That removes a render pass and an allocation per
frame, removes finding 03's window, and leaves one placement implementation to test.

### 10. P1 — Quality step-ups are hard swaps between visibly different renders

**Code-confirmed.** `FrameRefinementPolicy` crossfades only when a stale *stored* frame is refined
(`staleRefinementPending && quality == .preview && coversPresentationExtent`, PreviewSurface.swift:217).
Every other replacement swaps immediately, including the two most common ones:

- **End of every drag.** The interactive frame is 8-bit (`previewTexturePixelFormat`), capped at
  1.5 MP for a fit view (`RenderScale`, line 16), which is about a 3× upscale on a 5K canvas, and
  rendered at a different detail level (finding 06). It is then replaced at once by the 16-bit,
  higher-level settled frame. The user sees blur → sharp plus a sharpening change on release.
- **Cold open.** A thumbnail or embedded camera JPEG, rendered with the camera's own tone and
  colour, is replaced at once by Kromora's develop: a visible colour and tone jump.

**Recommendation.** Make the crossfade decision general: whenever a frame replaces one of lower
fidelity (interactive → settled, embedded or thumbnail → settled), compute the digest distance and
crossfade over a short interval (80–120 ms), honouring Reduce Motion. Separately, make the
interactive budget adaptive: raise the pixel budget while measured render time stays under the
frame budget, so a fast GPU on a large display does not drop to 1.5 MP needlessly.

---

## P2 — material improvements

### 11. P2 — The display chain is 8-bit with no dither

**Code-confirmed.** The drawable is `.bgra8Unorm` (PreviewSurface.swift:1181), the presentation copy is
`.bgra8Unorm` (:1022), and interactive engine textures are `.rgba8Unorm`. The 16-bit settled
render is therefore quantized to 8 bits before display, with no dithering, so smooth skies and
vignettes band on the canvas while the 16-bit TIFF export does not. **Recommendation:** use an
`.rgba16Float` drawable and presentation path (with finding 09, sample the engine's RGBA16F texture
directly) and keep the layer tagged Display P3. This is independent of the HDR/EDR epic
(KRMA-1114). If 8-bit output must remain for some path, add an ordered-dither step at the final
quantization.

### 12. P2 — Drawable resize stretches the last frame

**Code-confirmed.** `PreviewMTKView` sets neither `presentsWithTransaction` nor
`layerContentsPlacement`/`contentsGravity`, and uses `autoResizeDrawable = true`. During a live
window resize or an inspector toggle, Core Animation scales the previous drawable to the new bounds
until the next draw, so the photo stretches and then snaps. **Recommendation:** set
`layerContentsPlacement = .topLeft` (matching the top-aligned viewport), and draw synchronously with
`presentsWithTransaction = true` during live resize (`viewWillStartLiveResize` /
`viewDidEndLiveResize`), so the resized drawable commits with the window's layout transaction.

### 13. P2 — RAW developed sources are materialized through a CPU readback

**Code-confirmed.** A settled-cache miss for a RAW source completes the decoder output through
`materializedImage`, a synchronous `render(toBitmap:)` into an RGBAh CPU buffer that is wrapped
back into a `CIImage` ([RenderEngine.swift:2669](../../Sources/KromoraKit/Models/RenderEngine.swift),
:2387). At level 0.5 of a 61 MP ARW that is about 120 MB read back and later uploaded again, on the
actor. The interactive `InteractiveRAWFilterSession` uses the same materializer. The asynchronous
GPU-texture path (`materializedPrefixImage`) already exists. **Recommendation:** materialize the
developed source into a private texture through `commitAndWaitForCompletion`. Core Image captures
the `CIRAWFilter` graph when `render(_:to:commandBuffer:)` encodes it, so the mutable filter can be
reused once encoding returns; confirm this with the existing RAW parity tests.

### 14. P2 — Per-frame allocation churn

**Code-confirmed.** Each `makeCIImage` allocates a new private texture
(`RenderEngineResources.makeProcessingTexture`), each publication allocates a new bgra8 texture and
readback buffer, and each draw allocates two `MTLBuffer`s per quad (PreviewSurface.swift `encode`).
During a drag this is tens of MB of allocation per frame. **Recommendation:** keep a small
size-keyed texture pool (or an `MTLHeap`) for engine output and presentation, and use
`setVertexBytes`/`setFragmentBytes` for the 4-vertex quad and its uniforms.

### 15. P2 — ROI renders have no overscan

**Code-confirmed.** The preview ROI is exactly `plan.visiblePresentationRect`. Any pan immediately
uncovers the complete-frame underlay, which is a different (lower) detail level with possibly
different sharpening, so a rectangular seam follows the viewport until the next ROI lands.
**Recommendation:** render the ROI with a 15–25 % margin, clamped to the source, and reuse it
while the visible rect stays inside it. This also reduces ROI cache misses in
`processingPrefix`, whose key includes `sourceROI`.

### 16. P2 — The crossfade is paced by a sleeping task

**Code-confirmed.** `beginCrossfade` loops on `Task.sleep(for: .milliseconds(16))`
(PreviewSurface.swift:464). That is not tied to vsync and runs at less than half rate on
120 Hz ProMotion displays, so the fade steps unevenly. **Recommendation:** drive the transition
from `NSView.displayLink(target:selector:)` (`CADisplayLink`, macOS 14+) and compute alpha from the
link's target timestamp.

---

## P3 — polish and verification

### 17. P3 — Alpha is applied twice to premultiplied texels

The fragment shader multiplies only `color.a` by the uniform alpha, and the pipeline blends with
`sourceAlpha` / `oneMinusSourceAlpha`
([PreviewSurface.metal:63](../../Sources/KromoraKit/Resources/PreviewSurface.metal), PreviewSurface.swift
pipeline setup). The textures are premultiplied (Core Image output), so partially covered edge
texels are multiplied by alpha twice and darken. **Recommendation:** blend with `.one` /
`.oneMinusSourceAlpha`, and multiply all four channels by the uniform alpha in the shader.

### 18. P3 — Scopes read the display-encoded 8-bit sample

The presentation histogram is sampled from the bgra8 display texture, so it cannot show
out-of-gamut or above-1.0 values, and its bins are display-encoded rather than working-space
values. After finding 11, sample the 16-bit texture and report clipping against the delivery space
explicitly.

### 19. P3 — Thumbnail fringe repair on the actor

`fillingThumbnailCoverageFringe` redraws every thumbnail into a CPU bitmap and loops over its
columns on the render actor (RenderEngine.swift:950). It is small, but it runs once per thumbnail.
Fix the cause instead: render to an integral, pixel-aligned crop, which `canonicalPreviewRaster`
already does by flooring.

### 20. P3 — Verification gaps

The suite has no test for any of these properties:

- **Drag cadence:** completed interactive renders are published while a gesture continues (finding 01).
- **Cross-scale parity:** a native-scale ROI of a document with Detail, Texture, Clarity, and Dehaze
  matches the same region of a `.full` export within tolerance (findings 06 and 07).
- **Border pixels:** the outer rows of every spatial stage match a padded reference (finding 07).
- **Presenter handoff:** every drawn stack after a publication contains that publication's
  pixels, and consecutive draws of one publication are byte-identical (findings 03 and 09).
- **Curve domain:** an engine-context tone-curve test in the delivery space (finding 08).
- **Stored-frame sufficiency:** an exact stored frame smaller than the canvas schedules a render
  (finding 04).

Each of these is deterministic and window-independent, so it belongs in the `fast` or `serial`
lane, not the capture harness.

## Suggested sequencing

1. **Week 1 (P0):** 01 (publish newer interactive frames), 03 (never drop detail during
   materialization), then 02 in two steps: a separate export engine first, then canonical encoding
   off the actor.
2. **Next (P1 accuracy):** 07 and 06 together (both are spatial-radius policy), then 08, then 05.
   These change pixels, so bump `RenderPipeline.pixelEpoch` once for the batch.
3. **Next (P1 stability):** 09 (single presenter path), which subsumes 03's patch and enables 11
   and 14, then 10 and 04.
4. **P2 and P3** as follow-ups, each with the test from finding 20.

The `pixelEpoch` bump in step 2 intentionally invalidates stored frames and thumbnails. Do it once
per batch, not once per finding, so libraries re-render only once.
