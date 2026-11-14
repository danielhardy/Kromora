# Kromora engineering guide

This is the durable contributor guide for Kromora's current architecture. It records the
implementation constraints a change must preserve; completed issue sequences and dated review
proposals are not requirements. The source tree and test suite are authoritative when
implementation changes.

## Application boundaries

`AppViewModel` is the composition root and façade for the main window. It routes commands and owns
the selected source, active published `EditDocument`, navigation policy, and user-facing status.
Focused collaborators own the value-state, asynchronous work, and resource lifecycles that would
otherwise make the composition root a resource owner:

| Concern | Current owner | Contract |
| --- | --- | --- |
| Library queries and imports | `PortableLibrarySession`, `LibraryQueryController`, `ImageCollection`, and `PhotosImportCoordinator` | The package owns membership and records; its local index drives paged queries. `ImageCollection` adapts visible windows and thumbnails. Folder, Photos, and removable-volume inputs import into the open package. |
| Editor document and history | `AppViewModel` and `EditorDocumentCoordinator` | AppViewModel publishes the active document; the coordinator owns per-photo sessions, history, revisions, and clipboard values. |
| Preview scheduling and presentation | `PreviewCoordinator`, `PreviewSurface`, and `ComparisonFramePolicy` | Only a completion matching the current source and document revision may become visible; pure comparison-baseline rules stay outside the renderer. |
| Persistence | `EditPersistenceCoordinator`, `EditDocumentStore`, and `PortableLibraryPackage` | Dirty snapshots are coalesced per asset and appended as package edit revisions. The package sidecar is canonical; `EditDocumentStore` is a bounded in-memory cache. Writes flush on termination. |
| Export and Look derivation | `ExportCoordinator` and `DeriveCoordinator` | Export and derivation use value snapshots and never mutate the active document. |
| Look previews and saves | `LookPreviewCoordinator` and `LookSaveCoordinator` | Sheet-specific task and result state stays out of the editor. |
| Photo analysis, Auto, and masks | `PhotoAnalysisCoordinator`, `ContentAwareAutoEngine`, and `MaskStore` | Analysis and Auto are cancellable and source-keyed; Auto returns a value-only result and durable mask pixels remain disposable sidecar data. |

High-frequency presentation state belongs to the narrowest observable object available. Canvas
navigation and crop drafts live in `CanvasInteractionState`; inspector chrome lives in
`AppViewModel.InspectorState`; library surfaces observe `ImageCollection`. Committed crop, history,
persistence, and render scheduling remain at the document boundary.

## Observation

Application state is `@Observable` throughout; there is no Combine-based observation, publisher
forwarding or `objectWillChange` anywhere. SwiftUI tracks the stored properties a `body` reads, so a
view re-evaluates only for values it displays.

- Wrapper mapping: a view holds an observable model as a plain `let`/`var`, uses `@Bindable` when it
  needs `$model.property` bindings, and owns view-local models with `@State`. An `@Observable`
  type is never held by the legacy object-owning wrapper (`ObservationInvalidationTests` enforces this).
- `@Observable` classes are `@MainActor final class`. Mark storage views never read (tasks, caches,
  closures, injected collaborators, `lazy` coordinators) `@ObservationIgnored`; a property a view reads
  stays tracked.
- Child state that changes at a different rate than the document lives in its own `@Observable`
  (`info`, `whiteBalance`, `capabilities`, `autoLook`, interaction states), so a histogram refresh or
  pointer move does not invalidate unrelated views.
- `document` is one stored `EditDocument`, so tracking is per property, not per section: any edit
  re-evaluates every view that reads any part of it. Keep `document` reads (including computed
  accessors such as `selectedLook` or `isComparisonAvailable`) out of container views such as the
  inspector shell by putting them in a small leaf subview. Splitting a mounted inspector into row
  subviews does not narrow this on its own; it would need a per-section projection that updates
  only when its section changes.
- Verify with the body-count probe (`Tests/KromoraKitTests/Support/BodyProbe.swift`,
  `ObservationBodyBaselineTests`) in the serial lane; it counts logical body evaluations, not timings.

## Value document and render path

`EditDocument` is the single editable value. It is Codable, Equatable, and Sendable, and contains
RAW develop settings, Light, Color, Effects, ordered adjustment nodes, crop, rotation, Look
identity/intensity, and local mask definitions. An empty or neutral document is the identity
transform. Preview, comparison, histogram, and export consume snapshots of this value rather than
baked preview pixels.

Light tone data keeps the legacy `toneCurve` key as the master RGB curve, then stores optional
`redToneCurve`, `greenToneCurve`, `blueToneCurve`, and `parametricCurve` values. Missing keys decode
to identity, so existing edit documents retain their master curve unchanged. The renderer composes
the parametric mapping, master mapping, and per-channel mappings into its sampled 1D texture, shared
by preview and full-resolution export. Edit copy/paste transfers the full `LightAdjustments` value,
including the master, per-channel, and parametric curves.

`RenderPipeline` builds one lazy Core Image graph. `RenderEngine` evaluates that graph at the
requested quality and output size; preview and export do not maintain separate edit logic. The
pipeline handles source decoding/develop, orientation and rotation, the core global corrections
(Light, then Color, then the ordered adjustment nodes), the Look, global Effects and Detail, ordered local
adjustments, crop, and post-crop composition effects (KRMA-1178). The Look is a distinct creative
grade over the corrected photo, not a base the sliders adjust; RAW white balance and Exposure are
applied by the decoder and not again in the corrections. Corrections, the Look and global finishing
form the one graded prefix that the engine may materialize, so correction values and Look identity
and intensity are all part of the prefix cache identity, and an RGB-only change (a Look, an
intensity, a slider, an effect) never re-decodes a RAW because the developed source is keyed apart.
Local layers, crop, vignette and grain sit outside the prefix and reuse it. The exact order and
cache invalidation version live with `RenderPipeline.buildGradedImage`/`buildCorrectedImage` and
`pixelEpoch`; do not copy that volatile list into another document. `docs/LOOKS.md` records the
contract and the measured LUT-domain clipping.

Effects persist capture sharpening radius/amount/detail/masking and luminance/chroma noise reduction
retention controls in the `detail` value. On a RAW with supported luminance noise reduction, the
renderer routes global Luminance controls to the decoder before the Look; otherwise they stay in the
shared RGB graph. Global colour noise reduction and sharpening run in the RGB graph after the Look.
Local mask layers use RGB processing to scope sharpening, noise cleanup, and moiré softening.
Detail is resolution-independent (KRMA-1202): the sharpening radius is a native-source-pixel length scaled
by the render factor, so previews sharpen the same fraction of the photograph as the export. Below a 0.5
output-pixel radius the radius holds at 0.5 and the amount attenuates proportionally (the documented
fit-preview approximation; native-scale output is exact). `CINoiseReduction`'s threshold scales by the render
factor because downsampling already averages noise. Masked/local Detail uses the same render factor, and ROI
renders include spatial support for active Detail before restoring the visible crop.
Export output sharpening is a separate delivery choice (screen, matte, or glossy, each low/standard/high) carried
by `ExportOptions` and applied after sizing, so it does not change the edit document or preview.

`RenderEngine` is an actor and the GPU/Core Image isolation boundary. `CIImage` and `CIContext` are
`Sendable` on the current SDK (`CIFilter` is not), so keeping Core Image graph construction,
`CIFilter`, `CIRAWFilter`, `CIContext`, mutable GPU resources, and render caches inside the engine is
a design rule rather than a compiler requirement. Detached developed-source tasks may return a
`CIImage` because it is `Sendable`; the result stays in the engine's render flow. `makeCIImage`
returns a completed, GPU-backed `sending CIImage?` to presentation, while analysis and presentation
seams may accept completed `sending CIImage` values back into the engine. Otherwise only Sendable
request values and rendered values cross the boundary. New work should use the existing
request funnel and injected protocol seams rather than adding a second renderer or context.

Interactive preview decode budgets 1.5 MP for a fit view and 4 MP of visible pixels for a zoomed view
(a source ROI smaller than the source) so zoomed previews are not upscaled while a slider drags.
ROI scaling is capped at 36 MP across the full decoded source per 16.7 ms frame budget; longer or
shorter frame budgets scale both limits proportionally. The decoded source is cached across a drag,
so the larger decode is paid once per gesture unless the control changes RAW development.

Crop chrome animates a top-aligned visible viewport inside a stable, full-height Metal drawable.
`EditorCanvasViewport` interpolates layout for the photo and its overlays; `CanvasViewportGeometry`
converts that visible area to drawable pixels. Pointer navigation and zoom/fill ROI planning use the
visible viewport. Fit retains the full canvas resolution budget, and viewport animation never
admits preview renders. Keep the single-image representable mounted across crop entry and exit;
animating its AppKit bounds or replacing it with a conditional branch can snap or stretch the photo.

White balance stays in the same `EditDocument`: RAW presets and samples write decoder temperature
and tint overrides before RAW rendering; standard-image edits write the existing temperature/tint
adjustment node. The Color inspector's eyedropper samples the currently rendered preview, averages
an 11 × 11 display-pixel square, and shows a 3× loupe crop before the click commits. Cancel leaves
the document untouched. Auto estimates from the currently rendered image region; As Shot clears the pair (and
the legacy post-render node on RAW); Custom leaves the current values available for fine adjustment.
These controls use normal document history and package persistence.

## Exposure and color scopes

The Info histogram normally describes the settled preview sample in the presented delivery space;
the engine's active working-space tally is the fallback when a presentation sample is unavailable.
The bounded RGB sample (longest edge at most 512 pixels) also drives waveform, RGB parade, and
vectorscope plots. Clipping totals count pixels in that bounded sample, not extrapolated full-resolution
pixels. The canvas alert is presentation-only and can be toggled from the Info histogram. Exposure
remains available in the Light inspector alongside the other global tone controls.

### Histogram and scope semantics

The engine's histogram tally renders the settled preview to a bounded RGBAf buffer in the active
working space's transfer encoding (`HistogramData(rgbaFloat:)`), not an 8-bit display copy. Each
channel bins at `round(clamp(v, 0, 1) * 255)`. A channel counts as clipped high when it is at or
above 1 − 0.5/255 (the 8-bit 255 level), so extended and out-of-gamut values are counted instead
of hidden. A pixel is a clipped shadow when every channel is below 0.5/255, matching values that
round to 8-bit level 0 and including negative channels. NaN reads as 0. The retained spatial samples
use half-float values from the same encoded pixels, preserving negative and above-one values for scope
consumers.

The live Info panel reads the presentation texture directly. `PreviewSurface` downsamples the
RGBA16F presentation texture into a bounded RGBA16F sample (rendered in the presented space's
encoding, so values below 0 and above 1 survive), reads it back as half floats, and tallies it with
the same float path (`HistogramData(rgbaHalf:)` → `rgbaFloat:`). Nothing is quantized to 8 bits
before binning or retaining scope samples. Scope data uses half-float RGB values; waveform and
vectorscope plotting clamp points to the visible 0...1 plotting range, while histogram bins and
clipping totals retain the documented extended-range semantics.

The two tallies differ only in space and role. The engine tally measures the working space's
transfer encoding and is the fallback when no presentation sample exists. The live sample measures
what is delivered to the display (the presented frame's space). Both apply the clipping rules above,
so a value that clips in one reports the same clipped counts in the other whenever the two spaces
agree; a wider working space mapped into a narrower delivery space can clip in delivery only.

## RAW exposure routing

The Light **Exposure** slider is one control for every source, but it is rendered by the source's
own natural stage (KRMA-1174). A standard image applies it as `CIExposureAdjust` on developed RGB.
A RAW hands it to `CIRAWFilter.exposure`, so it runs inside the decoder, before the corrections and the Look and before
every RGB stage, and ahead of the decoder's tone curve and highlight handling.

- **Where.** `EditDocument.routedForRendering(source:)` (`RAWExposureRouting.swift`) derives the
  document the renderer builds from: `light.exposure` is folded into `rawDevelop.exposure` and zeroed.
  `RenderEngine.buildImage` and `RenderPipeline.buildImage` route first, so the identity digests,
  developed-source key, processing prefix, preview/export, histogram, Look candidates and the
  interactive RAW session all see one document. The *stored* document is never rewritten, so the
  package format, undo, copy/paste, Reset and comparison baselines are untouched.
- **Existing values.** A nonzero `rawDevelop.exposure` (written while the Develop tab was reachable)
  is kept and *added* to the calibrated slider value as one decoder exposure; the same decoder
  exposure spelled either way shares one cache entry. Nothing is applied twice, and there is no
  legacy-rendering path: existing RAW edits that carry Exposure simply re-render through the
  decoder (`pixelEpoch` 40; 42 after the ProRAW calibration).
- **Calibration (per decoder family, KRMA-1174/1180).** Decoder stops are not RGB stops on every
  file. On tone-curve decoders (five Sony ARWs and a Samsung Bayer DNG) the decoder
  applies its tone curve after exposure, and the exposure whose whole-frame median luminance equals RGB
  exposure is 0.73–0.83 of the slider below the shoulder, so `decoderStopsPerSliderStop` is 0.75. On
  Apple ProRAW DNGs (decoders reporting `isLocalToneMapSupported`) decoder exposure equals RGB exposure
  at every setting from −5 to +5 and the frames match to 0.1 level, so
  `linearDecoderStopsPerSliderStop` is 1.0. `RAWExposureRouting.stopsPerSliderStop(decoder:)` picks by
  the file's decoder state; with no state (and for any unmeasured maker) it uses 0.75. The tone-curve
  ratio is a matched-*midtone* mapping, not equal pixels: on a bright scene +2 EV cannot be matched at
  all because the decoder saturates where RGB EV keeps multiplying, and that roll-off is intended. The
  intended relationship is therefore: the same slider stop is the same RGB stop on a JPEG and a
  ProRAW, and the same midtone stop on a tone-curve RAW with a gentler shoulder. Data and the
  correlation's limits are in [`TESTING.md`](TESTING.md#calibration-beyond-sony-dng-and-per-family-mapping-krma-1180).
- **Where the decoder state comes from.** `RenderEngine.routedForRendering(_:source:)` reads it for any
  nonzero Exposure or active Luminance NR: from the live interactive session when it is the same
  file, otherwise once per file from a throwaway filter (`routingStateCache`).
  `RenderPipeline.buildImage` reads a fresh filter. The stored document never records the family.
- **What is not claimed.** The experiments in `docs/rendering-experiments/raw-exposure/` show a
  different tone response and stronger tonal separation in a bright flag crop. They do not prove
  recovered sensor highlights. The Apple ProRAW fixtures render identically under both paths
  (KRMA-1180), so there the decoder route is correctness, not a different look. Treat the decoder path
  as a tone-response choice on tone-curve RAWs, with per-camera variation, not as a recovery feature.
- **Still RGB.** Standard images, local-mask exposure, ordered `.exposure` adjustment nodes, and the
  Save-as-Look LUT export (a LUT cannot carry decoder work).
- **Cost.** Each exposure tick is a decoder re-output instead of an RGB multiply. The interactive RAW
  session reuses its filter (one construction, one property write per tick), but the developed source
  and processing prefix no longer survive a tick. Measured numbers are in
  [`TESTING.md`](TESTING.md#raw-exposure-routing-krma-1174).

## RAW noise-reduction routing

The global **Luminance** noise-reduction control follows the same rule as Exposure: one control, but a
RAW renders it in the decoder when that is the better implementation (KRMA-1175).
`EditDocument.routedForRendering(source:decoder:)` (`RAWDetailRouting.swift`) derives the render
document: Luminance Amount, Detail and Contrast are consumed into
`rawDevelop.luminanceNoiseReductionAmount` and reset on the derived `effects.detail`, so the RGB stage
has nothing left to do for that channel and the work is applied once. The stored document, undo,
copy/paste, Reset, package and comparison baselines are untouched, and routing a routed document is a
no-op.

- **Mapping.** The decoder's own default is per image (0.0015 on a low-ISO frame, 0.71 at ISO 2000), so
  slider 0 leaves it alone and the control only adds on top:
  `amount = base + (1 − base) × strength`, `strength = noise/100 × (1 − 0.65 × contrast/100) ×
  (1.5 − detail/100)` clamped to 1. `base` is an explicit `rawDevelop` amount if present, else the
  decoder default. Contrast keeps its RGB meaning (retain part of the unfiltered source), and Detail
  becomes "smooth less" because the decoder has no sharpness inside its noise reduction. Apple's
  per-image default is the floor and the control scales the same parameter, so the two never stack.
  The mapping is monotonic and stable, not an equivalence claim.
- **Where the decoder state comes from.** Routing needs the file's `isLuminanceNoiseReductionSupported`
  flag and default. `RenderEngine.routedForRendering(_:source:)` reads them from the live interactive
  session when it is the same file, otherwise once per file from a throwaway filter
  (`routingStateCache`), so an export or a neighbouring photo never evicts the interactive session.
  `RenderPipeline.buildImage` reads a fresh filter. Both only when Luminance NR is active.
- **Unsupported controls.** If the decoder reports the control unsupported the channel stays RGB and
  nothing is written; `RAWDevelopSettings.apply` and the interactive baseline keep their own gates.
- **Still RGB.** Colour noise reduction (decoder 0.5 → 1.0 changed flat-patch chroma noise by under 2%
  on all four files, so the decoder's upward range does not serve the control), Sharpening (Amount,
  Radius, Detail, Masking: the decoder has no radius or mask and its default leaves 0–0.17 headroom),
  standard images, and local-mask noise reduction and sharpness.
- **Cost.** A Luminance tick re-outputs the decoder (one filter, one property write) instead of an RGB
  blend, so the developed source and prefix no longer survive it; Sharpening and Colour ticks still do.
  Measured in [`TESTING.md`](TESTING.md#raw-noise-reduction-routing-krma-1175).
- `pixelEpoch` is 41 for this change (RAW frames rendered with RGB Luminance NR are stale) and 42 after
  the ProRAW exposure calibration (KRMA-1180).

## RAW colour routing

Global white balance is the only Color control a RAW renders in the decoder (`neutralTemperature` /
`neutralTint`; as-shot or reset is `nil`). Saturation, Vibrance, the HSL mixer and colour grading stay
RGB for every source: `CIRAWFilter` has no equivalent, and comparing gamut mapping and EDR against the
defaults (KRMA-1179, [`RAW_PIPELINE_INSPECTION.md`](RAW_PIPELINE_INSPECTION.md#follow-up-raw-colour-headroom-and-the-color-controls-krma-1179))
showed no measurable colour retained at delivery. Gamut mapping stays at the decoder default because
turning it off breaks large white-balance moves; EDR stays 0 because its extra range is clamped at
output. Explicit stored values are still applied, and every effective decoder setting is part of the
developed-source key, so a colour slider never re-develops the RAW and a gamut or EDR change always
does. Kromora never selects a decoder version. No render path changed, so `pixelEpoch` is unchanged.
Revisit when a headroom-to-display mapping or a bracketed reference exists.

## Auto and photo analysis

`PhotoAnalysisCoordinator` owns Vision-backed analysis, semantic-mask generation, caching, and
cancellation. `ContentAwareAutoEngine` consumes that evidence, measures the current rendered edit,
generates bounded native and Apple-reference candidates, evaluates them through the same renderer
used by preview/export, and can plan at most the bounded Auto-owned regional corrections. Its
`AutoEnhancementResult` is value-only and is applied atomically through the normal document/history/
persistence path. Manual edits convert touched Auto-owned layers to user-owned state; repeated runs
use the persisted fingerprint for a safe no-op when nothing has changed. See
[`AUTO_EXPOSURE_POLICY.md`](AUTO_EXPOSURE_POLICY.md) and [`AUTO_PERFORMANCE.md`](AUTO_PERFORMANCE.md)
for the behavior and dated diagnostic baseline.

## Persistence and masks

The package-backed library is the only production mode. Package edit sidecars are canonical and
`EditDocumentStore` is a bounded in-memory cache keyed by `PortablePhotoAssetID`, not a SwiftData
projection. Each package revision stores one versioned JSON-encoded `EditDocument` and
uses an opaque `PortablePhotoAssetID` UUID as its persistence key; resolved Look bytes are embedded
with the revision. `EditPersistenceCoordinator` serializes and coalesces writes and flushes them on
termination. Per-photo undo and redo remain in-memory and bounded to 100 snapshots; the editor's
visible history is the durable package revision list. Named snapshots are immutable labeled
revisions, restoring an earlier commit appends a new revision, and compaction always retains named
snapshots. Copy/paste, reset, navigation, and export preserve the active photo's identity and revision. The old development
`EditStore.store` and standalone v2 store remain untouched for support/disposition and are not opened
as a second authority when a package session is active; see
[`EDIT_STORE_IDENTITY_DISPOSITION.md`](EDIT_STORE_IDENTITY_DISPOSITION.md).

Mask definitions are part of the edit document, while generated mask pixels are a separate cache
under `~/Library/Caches/Kromora/Masks/`. Metadata is JSON and pixels are raw Float32
sidecars. Cache keys include source identity, source fingerprint, semantic kind, quality, and
provider version. A missing or invalid sidecar is a cache miss; it must never invalidate the saved
mask recipe. Local masks use the same resolved definition for preview, overlay, histogram,
comparison, copy/paste, and full-resolution export.

The masking workspace follows task order: canvas tool, mask list (a multi-part mask lists its
parts indented beneath it), then the selected mask's Adjustments and Mask sections. The overlay
starts hidden for a clean photo; the header eye or `O` toggles its visibility. Hovering
a mask row temporarily previews that mask's effective coverage, and hovering a part previews that
part alone, even while the overlay is hidden. VoiceOver can invoke the equivalent Preview Coverage
row action. Leaving the row restores the prior overlay selection. Its style, color, and opacity are
a Settings preference (`KromoraSettings.maskOverlayAppearance`); hover targets and overlay pixels
never enter an edit, history, preview render request, or export. Canvas tools are
only the pointer tools (Select, Brush, Erase, Linear, Radial); smart masks are created from
Add Mask and never capture the canvas. A gradient drag edits the selected mask only when its
target part is that same gradient; otherwise it draws a new gradient mask, and a click that never
becomes a gradient restores the previous selection. Combine controls (mode, solo, invert, ordering) live
on the part rows and appear only once a mask has more than one part.

Smart-mask creation emits presentation-only request, resolved-reference, and dismissal events to
`MaskDiscoveryState`. `MaskDiscoveryOverlay` owns the replaceable optical treatment in a separate
transparent Metal surface; `PreviewSurface` and the analysis implementation do not schedule its
frames. The waiting treatment expresses no analysis progress. A successful edit commits immediately,
then discovery reads the returned reference's existing pixels from `MaskStore` and uploads a
disposable raster capped at 512 pixels per edge. Its inverse document-geometry mapping preserves
rotation, flips, straighten, perspective, crop, and navigation. The drawable is capped at 960 pixels
per edge, runs at 24 fps (12 under power or thermal constraints), and admits one frame in flight.
Hidden/inactive windows pause animation, Reduce Motion uses a still treatment, and source changes
or presentation teardown discard discovery. Request IDs reject stale completions. This subsystem
never requests inference, rerenders the photo, changes overlay preferences, or enters edit/export
state. Its shaders are precompiled with the presentation library by `scripts/build-metal-libraries.sh`.

Range selectors are portable mask recipes. Luminance ranges keep normalized lower/upper thresholds
and smoothness; the workspace shows the current luma histogram with draggable range handles. Color
ranges retain up to eight sampled RGB values with falloff and refinement controls. Their mattes are
derived from bounded, source-oriented ImageIO thumbnails and cached by source and recipe identity.
Depth range recipes are retained, but the current import and render pipeline does not expose embedded
depth maps; rendering one reports that depth data is unavailable rather than inventing coverage.
Range selectors use the same ordered add, intersect, and subtract component composition as other
mask sources.

[`STORAGE_POLICY.md`](STORAGE_POLICY.md) is the source-of-truth matrix for the durable package,
the Application Support projection, device caches, and user-visible output destinations.
`PortableLibraryValidation` is the reusable read-only scrub boundary used by the unwired
`PortableLibraryBackup` / `PortableLibraryRestore` model code; neither operation is exposed to users.
It walks the manifest, all membership shards, reachable asset records, originals, edit revisions,
XMP companions, and embedded Look blobs, verifying structure and the checksums stored in portable
identity/reference values. These findings are reported in `criticalFailures`. Package `Derived/`
artifacts and explicitly supplied local index, mask, and analysis-cache locations are inspected as
`rebuildableGaps`; a missing or stale cache can never make a package invalid. Validation never
deletes, quarantines, rebuilds, or writes any package or cache file.

## Look identity and scans

`LookSignature` (`none`, `resolved(id, contentHash)`, `unresolved(id)`) is the one value preview and
edited-thumbnail pixel identity use for a document's Look. The hash is SHA-256 of the `.cube` file
bytes: `CubeLUT.contentHash` computes it while parsing, and `PortablePackageLookReference.contentHash`
is the same value for an embedded blob, so a live Look and a saved revision agree. `EditDocument`
carries no digest; `EditDocumentLoadResult.lookSignature` exposes the current revision's signature
from its stored reference.

- `none` never equals `unresolved`. An `unresolved` signature labels provisional (ungraded) pixels
  only: it is never written to `LatestPreviewFrameStore`, never classifies as exact, and is
  never an exact edited-thumbnail match, so those pixels are replaced when the Look resolves.
- `LUTFilterCache` and engine preview keys include the content hash, so a `.cube` replaced in place
  under the same `LUTID` can never be served stale; invalidation is memory hygiene, not correctness.
- `LUTLibrary` publishes a `[LUTID: contentHash]` snapshot with each scan or import and reports a
  `LookLibraryDelta` (changed, appeared, disappeared). `AppViewModel` intersects it with the Looks the
  active document and published edited thumbnails reference. A byte-identical rescan, or a change to
  an unreferenced Look, does no engine or image work; a referenced change releases only those
  `LUTID`s (`invalidateLUTCache(ids:)`) and re-admits only the affected canvas and thumbnails.

## Presentation frames and freshness

The editing canvas's `MTKView` is tagged with `WorkingSpace.current.cgColorSpace`, matching the
preview texture's output encoding. The tag persists across SwiftUI view updates so Core Animation
can color-match the canvas to the display, keeping it consistent with color-managed thumbnails and
exports on Display P3 screens.

**Camera sources and the Display P3 canvas.** The local samples are five iPhone
17 Pro DNGs, one 8-bit iPhone 17 Pro HEIC, and two Sony ILCE-7CR ARWs. ImageIO identifies the DNGs
as Adobe RAW, the HEIC as HEIC, and the Sony files as Sony ARW; all report Display P3. For RAW,
Display P3 is the developed `CIImage` color space, not an embedded ICC profile. The HEIC carries a
Display P3 profile. Core Image color matches decoded inputs through its working space and into the
requested output space. This preserves out-of-sRGB values in the floating-point graph, but writing
to sRGB loses colors outside its gamut; a `CIColorCubeWithColorSpace` Look also has a bounded [0, 1]
domain.

For a repeatable comparison, each default RAW or HEIC decode was rendered at an 800 px long edge to
Display P3 and sRGB. The sRGB RGBA8 raster was reopened with its sRGB tag and rendered back to P3;
that round trip was compared with the direct P3 render, using the largest encoded RGB channel delta
per pixel. Across these fixtures, 0-3.32% of pixels differed by more than 2/255, 0-1.22% by more
than 8/255, and the maximum delta was 37/255. Converting the direct P3 pixels to linear sRGB found
0% out-of-sRGB pixels in both Sony ARWs, 0-4.39% in the iPhone DNGs, and 1.81% in the HEIC. These
are bounded, 8-bit pixel comparisons, not a calibrated display measurement. Hardware (colorimeter)
validation was not performed. The accepted policy below replaces the earlier Instagram-first decision
and has been active since KRMA-1121.

**Display P3 policy (active since KRMA-1121)**
([ADR-KRMA-1115](../.dg/decisions/ADR-KRMA-1115-display-p3-export-look-and-saved-edit-policy.md),
accepted 2026-10-25). `WorkingSpace.current` is `.displayP3`. The canvas and every rendered delivery
use it: JPEG, HEIC, TIFF, PNG, Share, Copy, Photos, external-editor TIFF, and rendered bundle
companions encode pixels in Display P3 and embed its ICC profile. There is no independent
export-space picker or silent sRGB delivery path; `ExportOptions.colorSpace` defaults to `.current`
and the delivery policies (`ShareExportPolicy`, `ShareCopyPolicy`, `ExternalEditorExportPolicy`,
`OriginalBundleCompanionPolicy`) all follow it. Inputs decode according to their profiles; original
bundle bytes stay untouched. A future sRGB delivery mode must include a matching preview, HDR/EDR is
a separate follow-up (KRMA-1114 epic), and soft proofing is out of scope.

**The graph evaluates in extended linear Display P3.** The engine's retained `CIContext` is created
with `WorkingSpace.linearWorkingColorSpace` (`extendedLinearDisplayP3`). Core Image's default is
extended linear sRGB, and built-in filters such as `CIToneCurve` clamp to the working gamut: with the
default context the first Light edit clipped a P3 photo to sRGB (out-of-sRGB green came back as
sRGB green). Never pass the non-linear `cgColorSpace` as a working space; that makes every filter
blend gamma-encoded values and breaks the linear-light assumptions in `RenderPipeline`. Test
contexts that need to match the engine use `Pixels` (which picks the matching linear working space).
Golden fixtures authored in sRGB (`MetalKernelParityTests`, the retouch quality floors) pin
`space: .sRGB` so kernel parity does not depend on the delivery space.

Each cube has an authoring space and is interpolated in it; missing headers assume sRGB, while
unknown or malformed declarations fail clearly. The bundled Looks are the regenerated P3 set; new
saved and derived Looks sample/fit and stamp P3. Imported stamps are honored and imported/embedded
bytes are preserved. An sRGB Look can still constrain wide-gamut colors through its bounded table;
the stamp makes interpretation correct, not gamut-preserving (see [`LOOKS.md`](LOOKS.md)).

**Stale rendered data and resets.** Space is part of cache and frame identity
(`FrameSignature.workingSpace` and the render-cache keys), and `RenderPipeline.pixelEpoch` was bumped to 37
at the flip, so previews, thumbnails, stored frames and render caches written by an sRGB-era build
are rejected rather than shown. There is no legacy renderer and no last-rendered-space document
field. Saved edits from prerelease libraries are not guaranteed to look the same: Looks stamped
`sRGB` still render as sRGB Looks, but slider math now runs in P3. When a prerelease library needs
a clean slate, quit the app and create a new library package (or delete only the derived
thumbnail/preview caches inside it); the app never deletes a library or originals automatically.

`LatestPreviewFrameStore` keeps the latest presented 2048 px preview of each asset. Three value types
define what a stored frame means:

- `FrameSignature` — source `PortablePhotoIdentity` (including fingerprint), edit hash,
  `LookSignature`, `WorkingSpace`, and `RenderPipeline.pixelEpoch`. Container layout is not part of
  it.
- `PresentedGeometry` — crop, rotation, and oriented aspect ratio.
- `PerceptualDigest` — an 8×8×RGB fingerprint computed beside the engine's `CIContext` from the
  completed image, never from a full-size readback.

`FrameClassifier.classify(_:against:)` is the **only** freshness implementation. Callers never
compare keys themselves:

| Result | Condition | Effect |
| --- | --- | --- |
| `unusable` | different asset, source fingerprint mismatch, or raster color space not losslessly presentable | never shown |
| `provisionalOnly` | same photo, but edit hash or Look is not resolved yet | may paint; never skips a render |
| `exact` | every `FrameSignature` field equals the current inputs, Look resolved | present through the confirmed tail and skip the settled render |
| `staleCompatible` | same photo, presentable, any input differs (including `pixelEpoch`) | paint inert pixels, render once, replace |

`ThumbnailFrameStore` applies the same signature and classifier to Library and filmstrip cells. It is
an actor facade over the packed thumbnail store and keeps at most two records per asset, `original`
and latest `edited`, under stable keys derived from the asset UUID and kind (never from an edit or
Look). Reads for the visible window are admitted before any source decode or render, through the
scheduler's frame-read lane (`ThumbnailFrameReadPolicy`: at most 4 concurrent reads, the visible set
plus one 24-photo prefetch page). An exact edited frame is published without rendering; a
stale-compatible frame stays on screen while the cell renders and refines once; a missing or
unusable one falls back to the original inside the cell's final geometry. Cell aspect comes from the
package membership summary's `presentedAspectRatio`, written in the same transaction as the edit
revision, so raster arrival never changes a cell's size.

The preview and thumbnail stores only accept frames with resolved source identities in both the
frame identity and signature. Browsing placeholders have no source-byte identity and are skipped at
the store boundary. Older placeholder records are treated as misses, removed on read, and purged by
bounded background sweeps that yield to user-visible frame work; no launch-time placeholder scan is
performed.

`LaunchHints` is a device-local, disposable accelerator in Application Support (`LaunchHints.json`):
library ID, last active asset, and at most 64 de-duplicated visible asset IDs, validated by schema
version and bounds. It is never navigation or library truth: Kromora still launches into Library, a
missing, corrupt, or stale hint is ignored, and the real viewport supersedes it. Hinted frame reads
run concurrently with index and Look startup under their own limit (`LaunchHintReadPolicy`: two
concurrent reads) and perform no decode or render.

Rules that keep this safe:

- Lookup starts at selection, from the collection's identity, in parallel with source preparation.
  The hit enters `PreviewPresentationCoordinator` as the provisional `.storedFrame` candidate. It is
  inert: it cannot drive tools, histogram, scopes, comparison, `lastPublishedVisibleRequest`, or a
  write.
- Stored previews get a 50 ms head start over thumbnails and camera JPEGs. Edited thumbnail
  candidates use their own raster dimensions because their crop and rotation are already baked
  into the pixels. Original thumbnails and embedded JPEGs are admitted only when the selected
  document is known to have identity crop and zero rotation; unresolved or edited geometry keeps
  the departing drawable under the loading spinner until edited pixels are available. Selection
  must preserve the collection's published geometry until the actual document is adopted.
- Until stored edits have been adopted the current inputs are unresolved, so the classification is
  `provisionalOnly` and the first settled submission is *deferred* rather than rendered against the
  speculative identity document. `adoptStoredEdits` and the end of the lookup release it.
- Exact hits go through `presentSettledRaster(persistsFrame: false)`, so histogram and supporting
  work are admitted once and the frame is not re-encoded. The first confirmed frame of a session
  consumes the candidate; later edits always render.
- Only a complete, canonical (`quality == .preview`, no ROI) frame of the photo's own resolved edit
  writes. Interactive, ROI, comparison/original, crop-tool, embedded, provisional, and failed output
  never does, nor does a speculative frame rendered before stored edits were adopted.
- Bump `pixelEpoch` only when identical inputs render different pixels; bump
  `storageFormatVersion` only when the envelope cannot be decoded.
- `FrameRefinementPolicy` decides how a stale frame is replaced: one 120 ms crossfade when the digest
  distance exceeds `crossfadeDigestThreshold` (pinned by `FrameRefinementPolicyTests`), otherwise an
  immediate swap; Reduce Motion always swaps. `PreviewSurface.present` applies the policy only when a
  stale-compatible frame is being refined by a complete canonical preview.

## Presentation budget

`PresentationBudgetTests` records visible raster assignments, geometry changes, and crossfades at
the assignment points in `PreviewSurface.present` and `ImageCollection.Item.thumbnail`. A failure
prints the surface and its ordered changes with raster sources. The recorder is optional; the hooked
paths use an inlined `guard` and return before making a record or taking a lock when it is absent.
Grid and filmstrip assignments are both recorded because those views share one item thumbnail.

| Scenario | Budget |
| --- | --- |
| Exact stored Edit open at fit, when its raster covers the fit plan | 1 raster assignment, 0 render requests, 0 geometry changes |
| Stale stored Edit frame | 2 raster assignments (stored, refinement), 1 render request, at most 1 crossfade |
| Cold Edit open | At most 3 raster assignments (thumbnail or embedded, settled) and a canonical write |
| Photo A → B → A | 0 assignments of A's pixels to B's canvas; each open stays within its cold or warm row |
| Exact stored grid cell after relaunch | 1 raster assignment, 0 geometry changes, 0 renders |
| Grid edit change | Stored frame then one refinement; 0 geometry changes unless crop changes |
| Identical Look rescan | 0 render admissions, 0 raster assignments, 0 collection-projection invalidations |
| One referenced Look changes | Only photos referencing it render, once each |
| Slider drag and settle | Interactive frames are never stored; one canonical write after settle |

To add a surface, identify the single setter that makes its pixels visible, add a surface key and
source at that hook, and record geometry at the mutation that changes the surface's presented shape.
Keep a structural test proving raster assignment cannot bypass the hook, and add a budget scenario
with a named limit and a one-line reason. Every PR that changes a presentation budget must say why
in its change summary.

## Keyboard routing

Kromora has **no `NSEvent` key monitor** (`KeyboardShortcutCatalogTests` fails
if one returns). A monitor sits ahead of the responder chain and must guess whether a control owns
a key; every key it declined fell through to AppKit and played the system alert. The responder chain
now decides, and the app claims the keys it owns:

- **Plain letters, digits, brackets and Shift-letters** are `Commands` menu items with key
  equivalents (`KromoraCommands`, built from `KeyboardShortcutCatalog`). AppKit offers an unmodified
  key to the focused control first (a text field keeps typing) and falls back to the menu before the
  alert. Items stay enabled and call `KeyboardCommandRouter`; an unavailable command is a claimed
  no-op, never a dead key. Do not give these Command/Option/Control modifiers: those belong to the
  system and to text editing.
- **Arrows, Space, Return, Esc, Delete and the hold gestures (Space, ⌘\\)** arrive at
  `KeyboardChainTail`, a responder `KeyboardSurface` installs at the end of the window's chain. Any
  first responder (canvas, picker, popup, button, list) that does not consume a key passes it up to
  the tail, which hands it to the router and always claims a key the app owns, including an
  intentional no-op, so nothing reaches `noResponder(for:)`. `KeyboardOwnership` is asked first:
  text input keeps every key, sliders and steppers keep arrows. Arrows cannot be menu key
  equivalents because AppKit would deliver them even while a text field edits.
- **Command-C / Command-V / Command-A** use the standard Edit-menu commands (`onCopyCommand`,
  `onCommand`), so a text field keeps ordinary copy, paste and select-all; ⌥⌘V also pastes edits.
  Do not rely on a key handler for Command-V: a Paste item with no responder swallows it.
- **One table.** `KeyboardShortcutCatalog` binds every key: `.menuKey` entries carry the
  `KeyboardCommand` that the router executes and that `KromoraCommands` renders; `.surface` entries
  list the `KeyInput`s the tail must claim. `KeyboardCommand.isAvailable(in: KeyboardContext)` is the
  one predicate behind both menu enablement and the router's claimed-no-op decision. The surface
  publishes the router and context with `focusedSceneValue`; a disabled menu item still swallows its
  key, so enablement is truthful and silent.
- **Hold gestures** ignore auto-repeat and end on key-up, on focus moving to a text field, and when
  the window or app resigns (`KeyboardCommandRouter.releaseHolds()`).
- Pure-click controls (workspace picker, filmstrip thumbnails) use `.focusable(false)` so arrows are
  never stranded on an `NSControl`.

`KeyboardInventoryMatrixTests` drives the whole inventory against each kind of first responder in
a real window, with `KeyRoutingProbeTests` / `KeyboardSurfaceWindowTests` as the underlying probes;
they drive synthesized key events through the window and treat `NSWindow.noResponder(for:)` — the call that plays the alert — as the
machine-checkable "no boop". Silence itself is confirmed by ear.

## Inspector controls

Every inspector slider is `NeutralOriginSlider`, not `SwiftUI.Slider`. It wraps `NSSlider` and
overrides only `NSSliderCell.drawBar(inside:flipped:)`, so the knob, hit-testing, drag tracking,
keyboard handling, and the native accessibility element stay AppKit's. What it changes is where the
active fill starts: at the control's own neutral rather than at the left edge, so a bipolar row at
neutral shows an empty track and a drag fills only the side between neutral and the thumb.

A new row must pass its baseline through `neutral:`, and that baseline belongs to the control model
(`LightControl.neutral`, `VignetteControl.neutral`, `LocalAdjustments.neutral[keyPath:]`, the
decoder default from `developNeutral(for:)`) rather than being derived from the range. Neither the
range's midpoint nor zero is reliable: `AdjustmentControl.highlights` is neutral at its *maximum*,
`ColorGradingGlobalControl.blending` is neutral at 50 within an unsigned 0…100, and a genuinely
unipolar control passes `range.lowerBound` to get the ordinary left-origin fill from the same path.
Controls in slider space must map the neutral the same way the binding does — see the temperature
row in `ColorInspectorView`.

The split between `SliderFill` (pure, deterministic lane) and the cell (AppKit, serial lane) is
deliberate: `NeutralOriginSliderTests.testTheCellsBarDrawingIsReachedWhenTheControlDraws` is the
canary for an SDK that stops routing the bar through `drawBar`, which would otherwise revert every
slider to a left-origin fill with the arithmetic still passing.

## Library grid and the AppKit constraint-pass crash

On macOS 27 (SwiftUI 8.1) the Library has crashed intermittently on the main thread with
`NSGenericException: The window has been marked as needing another Update Constraints in Window
pass, but it has already had more Update Constraints in Window passes than there are views in the
window`, thrown from `-[NSWindow(NSDisplayCycle) _postWindowNeedsUpdateConstraints]`. Two shapes
appear: `NSHostingView.updateConstraints` re-marking itself during the display-cycle
update-constraints observer, and `ScrollViewCommitMutation.commit` requesting an update while AppKit
computes window drag regions (`_regionForOpaqueDescendants`). At the throw the only view flagged
as needing constraints is the SwiftUI navigation-pane hosting view that fills the window, so the
loop is SwiftUI re-invalidating the pane, not an app-owned `NSView`.

The crash needs a library large enough to scroll (the 134-photo personal library, not a 12-photo
one) and happens while scrolling the grid. It was bisected by hand-scrolling dev builds with
features switched off: removing the per-cell AppKit overlay views did not help, and removing the
scroll-driven row windowing stopped it. The grid used to declare only the rows around the viewport
(`firstVisibleRow` from `onScrollGeometryChange` selected a window, with fixed-height spacer gaps
standing in for the rest), so every row-boundary crossing changed the `LazyVStack`'s children. On
macOS 27 that made the pane hosting view re-invalidate its constraints within one display cycle
until AppKit aborted. The remaining mechanism inside SwiftUI is not proven and is not reproducible
under a debugger that slows the main thread.

Rule: do not change the Library grid's view structure from scroll position. Declare every row and
let `LazyVStack` virtualize; keep `firstVisibleRow` for thumbnail admission only. Rows are pinned
to the height `LibraryGridLayout` budgets so the scroll extent stays fixed.

## Change checklist

- Keep the macOS 26 (Tahoe) Apple Silicon deployment target, Swift 6 language mode, and Apple-only dependency policy. Do not add fallbacks for earlier macOS releases or Intel hardware.
- Keep non-Sendable image/GPU objects behind the render actor; do not add concurrency escape hatches.
- Preserve source/document/revision checks at every asynchronous publication boundary.
- Keep neutral documents and unsupported optional capabilities as no-ops.
- Give every new inspector slider its control's own neutral; see "Inspector controls" above.
- Add deterministic value or fake-engine coverage for new behavior; use opt-in RAW/UI/hardware lanes
  for framework or performance claims.
- Run `swift build`, the relevant `swift test` filter, `scripts/ci-tests.sh fast` or `serial` as
  appropriate, and `git diff --check` before handoff.

Useful entry points are [`EditDocument`](../Sources/KromoraKit/Models/EditDocument.swift),
[`RenderPipeline`](../Sources/KromoraKit/Models/RenderPipeline.swift),
[`RenderEngine`](../Sources/KromoraKit/Models/RenderEngine.swift),
[`AppViewModel`](../Sources/KromoraKit/ViewModels/AppViewModel.swift), and
[`EditDocumentStore`](../Sources/KromoraKit/Models/EditDocumentStore.swift).


## Retouch stage

Retouch consumes the developed, EXIF-oriented source before user rotation and crop geometry and
before global or local tone adjustments. Spots carry normalized oriented-source brush regions and
an optional source relation, so a geometry edit transforms the finished retouch together with its
source content. The renderer rasterizes one brush mask per spot and limits its fill and membrane
graph to the spot bounds plus padding. Heal derives its correction from the exterior ring only;
Clone uses the translated patch directly.

## Quality step-up transitions (KRMA-1206)

`PreviewSurface.present` crossfades (`FrameRefinementPolicy.crossfadeDuration`, 120 ms) when a frame of
higher `FrameFidelity` replaces a lower one for the same asset and presentation extent: interactive →
settled always (the 8×8 digest cannot see the resolution and sharpening step), thumbnail/embedded →
settled unless both digests are within `crossfadeDigestThreshold` (a missing digest animates). Equal or
lower fidelity, a different asset or geometry, and Reduce Motion swap immediately. The stale stored-frame
path keeps its own digest rule.

`InteractiveBudgetAdapter` defines the adaptive interactive pixel-budget policy (×1.15 while renders take
under 50 % of the frame budget, ×0.8 above 85 %, clamped to 1.0…2.5× the 1.5 MP fit-view budget). It is
deliberately not wired into `RenderRequest.renderScale` yet: raising the budget changes the render cache
key and stored-frame comparison, and the audit gave no measurements. Wire it only with release-time
numbers in `docs/TESTING.md`.
