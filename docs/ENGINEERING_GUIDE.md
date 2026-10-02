# Kromora engineering guide

The product audience, MVP, release bar, and post-MVP boundaries are in
[`PRODUCT_SCOPE.md`](PRODUCT_SCOPE.md). This guide records durable implementation constraints for
the current product; completed issue sequences and dated review proposals are not requirements.

This is the durable contributor guide for Kromora's current architecture. The source tree and test
suite are authoritative when implementation changes; this document records the boundaries that a
change must preserve.

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
pipeline handles source decoding/develop, orientation and rotation, global Light and Color,
pre-Look detail effects, ordered adjustments, Looks, ordered local adjustments, crop, and
post-crop composition effects. The exact order and cache invalidation version live with
`RenderPipeline`; do not copy that volatile list into another document.

Effects persist capture sharpening radius/amount/detail/masking and luminance/chroma noise reduction
retention controls in the `detail` value. They run through the shared pre-Look Core Image graph;
local mask layers can also scope sharpening, noise cleanup, and moiré softening. Export output
sharpening is a separate delivery choice (screen, matte, or glossy, each low/standard/high) carried
by `ExportOptions` and applied after sizing, so it does not change the edit document or preview.

`RenderEngine` is an actor and the GPU/Core Image isolation boundary. `CIImage`, `CIFilter`,
`CIRAWFilter`, `CIContext`, mutable GPU resources, and render caches stay inside it. Only
Sendable request values and rendered values cross `RenderEngining`. New work should use the existing
request funnel and injected protocol seams rather than adding a second renderer or context.

Interactive preview decode budgets 1.5 MP for a fit view and 4 MP of visible pixels for a zoomed view
(a source ROI smaller than the source) so zoomed previews are not upscaled while a slider drags.
ROI scaling is capped at 36 MP across the full decoded source per 16.7 ms frame budget; longer or
shorter frame budgets scale both limits proportionally. The decoded source is cached across a drag,
so the larger decode is paid once per gesture unless the control changes RAW development.

White balance stays in the same `EditDocument`: RAW presets and samples write decoder temperature
and tint overrides before RAW rendering; standard-image edits write the existing temperature/tint
adjustment node. The Color inspector's eyedropper samples the currently rendered preview, averages
an 11 × 11 display-pixel square, and shows a 3× loupe crop before the click commits. Cancel leaves
the document untouched. Auto estimates from the currently rendered image region; As Shot clears the pair (and
the legacy post-render node on RAW); Custom leaves the current values available for fine adjustment.
These controls use normal document history and package persistence.

## Exposure and color scopes

The Info histogram describes the settled rendered preview in the active working space. Its bounded
RGBA sample (longest edge at most 512 pixels) also drives waveform, RGB parade, and vectorscope
plots. Clipping totals are counts in that same bounded
sample, not extrapolated full-resolution pixel counts: highlights mean any channel is 255, shadows
mean all channels are 0, and per-channel totals count values at 255. The canvas alert is
presentation-only and can be toggled from the Info histogram. Exposure remains available in the
Light inspector alongside the other global tone controls.

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
`PortableLibraryValidation` is the reusable read-only scrub boundary for package backup and restore.
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
## Presentation frames and freshness

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
run concurrently with index and Look startup under the same read limit and perform no decode or
render.

Rules that keep this safe:

- Lookup starts at selection, from the collection's identity, in parallel with source preparation.
  The hit enters `PreviewPresentationCoordinator` as the provisional `.storedFrame` candidate. It is
  inert: it cannot drive tools, histogram, scopes, comparison, `lastPublishedVisibleRequest`, or a
  write.
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
  immediate swap; Reduce Motion always swaps. The policy and digest are in place; the presentation
  surface does not yet animate the swap.

- `LUTFilterCache` and engine preview keys include the content hash, so a `.cube` replaced in place
  under the same `LUTID` can never be served stale; invalidation is memory hygiene, not correctness.
- `LUTLibrary` publishes a `[LUTID: contentHash]` snapshot with each scan or import and reports a
  `LookLibraryDelta` (changed, appeared, disappeared). `AppViewModel` intersects it with the Looks the
  active document and published edited thumbnails reference. A byte-identical rescan, or a change to
  an unreferenced Look, does no engine or image work; a referenced change releases only those
  `LUTID`s (`invalidateLUTCache(ids:)`) and re-admits only the affected canvas and thumbnails.

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
row in `AdjustInspectorView`.

The split between `SliderFill` (pure, deterministic lane) and the cell (AppKit, serial lane) is
deliberate: `NeutralOriginSliderTests.testTheCellsBarDrawingIsReachedWhenTheControlDraws` is the
canary for an SDK that stops routing the bar through `drawBar`, which would otherwise revert every
slider to a left-origin fill with the arithmetic still passing.

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
