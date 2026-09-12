# Kromora engineering guide

This is the durable contributor guide for Kromora's current architecture. The source tree and test
suite are authoritative when implementation changes; this document records the boundaries that a
change must preserve.

## Application boundaries

`AppViewModel` is the composition root. It routes commands and owns the selected source, active
`EditDocument`, navigation policy, history, and user-facing status. Focused collaborators own the
work that would otherwise make the composition root a resource owner:

| Concern | Current owner | Contract |
| --- | --- | --- |
| Library scanning and projections | `ImageCollection` | Scanning mutates the collection; selection, filtering, and ordering are deterministic projections. |
| Preview scheduling and presentation | `PreviewCoordinator` and `PreviewSurface` | Only a completion matching the current source and document revision may become visible. |
| Persistence | `EditPersistenceCoordinator` and `EditDocumentStore` | Dirty snapshots are coalesced per asset, serialized, atomically replaced, and flushed on termination. |
| Export and Look derivation | `ExportCoordinator` and `DeriveCoordinator` | Export and derivation use value snapshots and never mutate the active document. |
| Look previews and saves | `LookPreviewCoordinator` and `LookSaveCoordinator` | Sheet-specific task and result state stays out of the editor. |
| Photo analysis and masks | `PhotoAnalysisCoordinator` and `MaskStore` | Analysis is cancellable and source-keyed; durable mask pixels are disposable sidecar data. |

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

`RenderPipeline` builds one lazy Core Image graph. `RenderEngine` evaluates that graph at the
requested quality and output size; preview and export do not maintain separate edit logic. The
pipeline handles source decoding/develop, orientation and rotation, global Light and Color,
pre-Look detail effects, ordered adjustments, Looks, ordered local adjustments, crop, and
post-crop composition effects. The exact order and cache invalidation version live with
`RenderPipeline`; do not copy that volatile list into another document.

`RenderEngine` is an actor and the GPU/Core Image isolation boundary. `CIImage`, `CIFilter`,
`CIRAWFilter`, `CIContext`, mutable GPU resources, and render caches stay inside it. Only
Sendable request values and rendered values cross `RenderEngining`. New work should use the existing
request funnel and injected protocol seams rather than adding a second renderer or context.

## Persistence and masks

The edit catalog is versioned JSON under the user's Application Support directory. Writes are
serialized, coalesced, atomically replaced, and backed up. Per-photo history stores value documents;
copy/paste, reset, navigation, and export must preserve the active photo's identity and revision.

Mask definitions are part of the edit document, while generated mask pixels are a separate cache
under `~/Library/Application Support/Kromora/Masks/`. Metadata is JSON and pixels are raw Float32
sidecars. Cache keys include source identity, source fingerprint, semantic kind, quality, and
provider version. A missing or invalid sidecar is a cache miss; it must never invalidate the saved
mask recipe. Local masks use the same resolved definition for preview, overlay, histogram,
comparison, copy/paste, and full-resolution export.

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

- Keep the macOS 14 deployment target, Swift 6 language mode, and Apple-only dependency policy.
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
