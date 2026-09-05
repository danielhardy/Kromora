# Lumo Masking and Local Adjustments — Implementation Plan

**Status:** planning only; no implementation has started  
**Target:** native macOS 14+, Swift 6, SwiftUI + Core Image/Metal, Apple frameworks only  
**Primary outcome:** a Lightroom-style masking workflow in which a photographer can create, select,
rename, enable/disable, invert, refine, and later re-edit any mask and its local adjustments.

## 1. Scope and product assumptions

For this plan, a **mask** is one named, ordered local-adjustment layer. Each layer has:

- one or more editable mask components;
- a compositing mode for each component (`replace`, `add`, `subtract`, or `intersect`);
- layer-level amount, invert, enabled, and overlay-display settings; and
- a non-destructive set of local tone, color, and detail adjustments.

The required mask component types are:

1. **Smart Foreground** — an on-device semantic selection of foreground content.
2. **Smart Background** — the complementary semantic background selection.
3. **Brush** — direct painting on the main canvas with size, feather, flow/intensity, and density.
4. **Linear Gradient** — a draggable, rotatable three-bar gradient with editable transition width.
5. **Radial Gradient** — a draggable, resizable, rotatable ellipse with editable falloff and
   inside/outside selection.

Existing Subject, Person, and Face semantic targets should remain available once the new workflow
replaces the current selection-only sheet, but Foreground and Background are the required smart
targets for the first complete release.

The first local-adjustment control set should be deliberately smaller than the global inspectors:

- Exposure, Contrast, Highlights, Shadows, Whites, Blacks
- Temperature, Tint, Saturation
- Texture, Clarity, Dehaze

Tone curves, color mixer/grading, LUT selection, crop, vignette, and grain remain global in the
first release. Their behavior under a soft spatial mask is either confusing, unusually expensive,
or both. The model must be extensible so more local controls can be added without changing mask
geometry or saved masks.

## 2. Current baseline to preserve

The repository already provides useful foundations:

- `MaskingPanel` can request, preview, invert, and hand off semantic `RegionMask` values, but its
  Apply action is intentionally disabled because `EditDocument` has no local-mask owner.
- `PhotoAnalysisCoordinator`, `VisionSemanticMaskProvider`, `MaskStore`, `RegionMask`, and
  `MaskOperations` provide on-device semantic generation, cancellation, deduplication, caching,
  and normalized upper-left coordinates.
- `EditDocument` is the `Codable`, `Sendable`, `Equatable` value-state spine for persistence,
  copy/paste, undo, cache identity, preview, and export.
- `RenderPipeline` builds one lazy Core Image graph for both preview and export, and
  `RenderEngine` owns the live processing `CIContext`.
- `PreviewCoordinator` already coalesces pointer-frequency interactive renders and promotes the
  final state to preview quality.
- `CanvasInteractionState` proves the correct observation boundary for pointer-frequency state:
  canvas drafts do not publish through the entire `AppViewModel`.

The implementation must preserve these invariants:

- An empty or neutral `EditDocument` remains pixel-identical to the current result.
- Preview, histogram, comparison, and export use the same document semantics.
- No `CIImage`, `CIFilter`, or `CIContext` crosses the render actor boundary.
- No new `CIContext` is introduced into the live render path.
- Analysis and masking never send image data off-device.
- No third-party dependencies or Swift concurrency escape hatches are added.

## 3. Binding architecture decisions

### 3.1 Persist recipes, not generated mask pixels

`EditDocument` must own the durable definition of every local mask. It must **not** persist a
`RegionMaskReference` as the only source of truth: `MaskStore` is a cache and may be deleted,
invalidated, or unavailable on another machine.

- Brush masks persist normalized vector strokes.
- Linear and radial masks persist normalized analytic geometry.
- Smart masks persist semantic intent, provider/version compatibility information, and refinement
  settings; pixels are regenerated when a valid cached result is unavailable.
- `MaskStore` continues to own semantic raster payloads. A separate derived-mask cache may own
  composited preview/render payloads, but all derived pixels remain disposable.

This also makes copy/paste deterministic: geometric masks retain their normalized positions, while
smart masks are re-evaluated against the destination photo rather than reusing pixels from the
source photo.

### 3.2 Coordinate system and crop behavior

All persisted mask geometry uses the existing canonical coordinate system: normalized `0...1`,
origin at the upper-left of the oriented source image, before creative edits and before crop.

- Pointer locations are converted once from viewport coordinates through `CanvasNavigation` and
  the current crop transform into source-normalized coordinates.
- Render-time mask geometry is converted once from normalized source coordinates into the current
  render extent.
- Recropping reveals or hides existing masked areas without moving them.
- Zoom, pan, window size, backing scale, and preview resolution never modify stored mask geometry.
- Points outside the visible crop are not discarded; users can reveal them by changing the crop.

### 3.3 Local-adjustment render order

Local layers are ordered and evaluated sequentially immediately before the LUT/crop/final-effects
boundary:

```text
RAW develop
  -> global Light
  -> global Color
  -> global pre-LUT Effects
  -> legacy ordered adjustment nodes
  -> ordered local-adjustment layers
  -> LUT
  -> crop
  -> vignette
  -> grain
```

For each enabled non-neutral local layer:

1. Resolve and composite its mask components into one soft alpha mask.
2. Produce an adjusted variant from the image entering that layer.
3. Blend the adjusted variant over that same input using the effective mask multiplied by layer
   amount and optional inversion.
4. Feed the result into the next local layer.

This makes layer order meaningful, keeps every operation in one lazy GPU graph, and avoids
applying global post-composition effects independently inside every mask.

### 3.4 Draft state versus committed state

Pointer-frequency edits must not rewrite and persist the full document on every event.

- A new `MaskInteractionState` owns the selected layer/component, active tool, hover/cursor,
  in-progress brush stroke, and in-progress gradient geometry.
- The state publishes only the mask inspector/canvas overlay subtrees.
- Overlay geometry follows the pointer immediately without waiting for an image render.
- A drag or stroke begins one undo group, updates a transient draft, and commits one document
  mutation at gesture end.
- Interactive adjusted previews may be paced during a gesture through `PreviewCoordinator`; the
  final mouse-up always requests a settled preview.
- Cancelling a draft restores the committed definition with no history or persistence entry.

## 4. Proposed persisted value model

Exact names may change during implementation, but these boundaries should remain.

```swift
struct LocalAdjustmentLayer: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var isInverted: Bool
    var amount: Double                 // 0...1
    var components: [MaskComponent]
    var adjustments: LocalAdjustments
}

struct MaskComponent: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var mode: MaskCombineMode          // replace/add/subtract/intersect
    var isEnabled: Bool
    var isInverted: Bool
    var source: MaskSource
}

enum MaskSource: Codable, Sendable, Equatable {
    case semantic(SemanticMaskDefinition)
    case brush(BrushMaskDefinition)
    case linear(LinearGradientDefinition)
    case radial(RadialGradientDefinition)
}
```

`EditDocument` gains `localAdjustments: [LocalAdjustmentLayer]`, with missing data decoding as an
empty array. The document schema should advance to v2 so an older build rejects a masked document
instead of silently loading it, dropping unknown local edits, and saving the loss back to disk.

`isIdentity`, `hasVisibleLookEdits`, comparison baseline, edit hash, reset, copy/paste, undo/redo,
and persistence must all include the new array. The comparison baseline excludes local layers,
matching its existing meaning of “developed and framed source without the creative look.”

### 4.1 Local adjustment values

Add a focused `LocalAdjustments` value rather than embedding all of `LightAdjustments`,
`ColorAdjustments`, and `EffectsAdjustments`. It should expose stable photographer-facing units and
clamped decoding, and should share renderer mapping functions with global controls rather than
duplicating their math.

Neutral local adjustments are retained while a mask is being shaped, so geometry can be created
before an effect is chosen. A layer only changes pixels when it is enabled, its effective mask has
nonzero coverage, its amount is nonzero, and at least one local adjustment is non-neutral.

### 4.2 Smart definitions

```swift
struct SemanticMaskDefinition: Codable, Sendable, Equatable {
    var target: SemanticTarget          // foreground/background/subject/person/face
    var edgeFeather: Double             // normalized, resolution independent
    var edgeShift: Double               // contract/expand around the semantic edge
    var density: Double                 // 0...1
    var generationVersion: Int
}
```

- Add a stable user-facing `foreground` semantic target representing the union of usable
  foreground instances; do not expose instance numbering as the primary Foreground control.
- Background should be generated from the same foreground segmentation result when possible so
  the two are complementary and share in-flight work.
- Smart selection is progressive: show cached/preview quality first, then replace it with refined
  render quality without changing the layer identity.
- Low-confidence and unavailable states remain explicit. A failed regeneration must not delete the
  definition or publish pixels from another asset.

### 4.3 Brush definitions

Persist strokes as normalized centerline samples plus settings, not raster tiles:

```swift
struct BrushStroke: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var samples: [BrushSample]          // point + optional pressure
    var radius: Double                  // fraction of source's shorter side
    var feather: Double                 // 0...1
    var flow: Double                    // alpha deposited by each stamp
    var density: Double                 // maximum accumulated opacity
}
```

- Resample points by source-space distance and simplify the committed centerline without visibly
  changing the stroke at export resolution.
- Use a smooth radial falloff; repeated stamps accumulate as `1 - product(1 - alpha)`, capped by
  density. The same formula must be used for preview and export.
- Pressure, when supplied by the device, may scale radius and flow; mouse input behaves as pressure
  `1`.
- Size, feather, flow/intensity, and density stay visible while painting. Bracket keys adjust size;
  Shift+bracket adjusts feather. Holding Space temporarily pans without ending the mask tool.
- Erasing is represented as a subtracting brush component/stroke group, preserving non-destructive
  editability.

An active stroke is accumulated in a reusable GPU texture for immediate feedback. The vector
stroke enters `EditDocument` only on mouse-up, preventing large copy-on-write document mutations,
history entries, JSON encodes, and cache hashes at pointer frequency.

### 4.4 Linear gradient definitions and controls

Persist two normalized points: the zero-strength edge and full-strength edge. Their separation is
the falloff width and their perpendicular defines the three visible guide bars.

- Dragging on the photo creates the gradient and establishes direction/falloff.
- Dragging the center bar translates the gradient.
- Dragging either outer bar changes falloff while keeping the opposite edge stable.
- Dragging the rotation handle changes angle around the center.
- The inspector exposes angle, falloff, density, invert, and reset.
- Hit targets remain usable at every zoom and are sized in screen points, not image pixels.

The render mask is analytic (`smoothstep` across the projected source position); no raster asset is
persisted.

### 4.5 Radial gradient definitions and controls

Persist normalized center, horizontal/vertical radii, rotation, feather, density, and inside/outside
selection.

- Dragging creates an ellipse from the initial center.
- The center handle translates it; cardinal handles resize one axis; corner handles resize both;
  and a rotation handle changes angle.
- An inner ellipse visualizes where falloff starts; the outer ellipse visualizes where it ends.
- Feather may be adjusted in the inspector or by dragging the inner boundary.
- Shift constrains to a circle; Option resizes symmetrically; invert switches inside/outside without
  destroying geometry.
- Radii use source-normalized geometry with aspect correction, so the displayed and rendered
  ellipse agree on non-square images.

The render mask is analytic and resolution independent.

## 5. User experience and interaction contract

Replace the modal, selection-only sheet with a persistent Masking workspace integrated with the
editor. The toolbar Mask button activates the workspace; Escape exits the active creation gesture
first and the workspace second.

### 5.1 Mask list

The inspector shows ordered mask layers with:

- color chip/overlay color, editable name, type summary, visibility, and selected state;
- create buttons for Foreground, Background, Brush, Linear, and Radial;
- duplicate, rename, invert, delete, enable/disable, and reorder actions;
- expandable component rows with Add, Subtract, and Intersect controls;
- a clear loading/error/refine state for smart components; and
- a “Show Overlay” toggle plus overlay color and opacity preferences that are presentation-only.

Selecting any existing layer restores its adjustment values and its editable component handles.
Selecting a component exposes that component's settings. Switching photos cancels transient work,
clears stale overlay state, and restores the selected layer for that photo if one exists.

### 5.2 Canvas behavior

- Brush cursor, stroke preview, gradient bars/ellipses, handles, and mask overlay render over the
  existing persistent image surface.
- The overlay supports color-wash and grayscale/black-and-white inspection modes. Overlay display
  never affects export or edit history.
- Only the selected component displays handles. All enabled layers still affect the rendered image.
- The active mask may be soloed to inspect its alpha without changing the document.
- Normal pan/zoom remains available via Space-drag, scroll/pinch, and existing fit/fill commands.
- Crop and mask creation are mutually exclusive pointer owners. Entering one tool commits or
  explicitly cancels the other's active draft before hit testing changes.
- A smart mask remains selectable and its local settings remain editable while refinement is in
  flight; loading must never freeze the inspector or canvas.

### 5.3 Accessibility and keyboard operation

- Every tool and row has a label, purpose, state, and shortcut exposed to VoiceOver.
- Geometry handles have descriptive labels and numeric accessibility values.
- Arrow keys nudge the selected gradient/radial component; Shift+arrow uses a larger increment.
- Delete removes the selected component/layer through a confirmable, undoable action.
- Sliders use the existing begin/end interaction hooks so one drag produces one undo entry.
- Focus order follows tool selection, mask list, component settings, then local-adjustment controls.

## 6. Rendering and resource resolution

Introduce a `LocalMaskResolving` actor boundary used by `RenderEngine` before graph construction.
It accepts only sendable values (`ImageSource`, target extent/quality, and mask definitions) and
returns sendable mask payloads or procedural descriptors. `RenderEngine` creates and retains all
Core Image/Metal resources on its own executor.

Resolution rules:

- Semantic: resolve through `PhotoAnalysisCoordinator`/`MaskStore`, validate the active asset and
  source fingerprint, then create a single-channel renderer-owned image at the requested quality.
- Brush: rasterize normalized vector strokes at the actual target resolution. Cache completed
  stroke groups; incrementally composite only a new active/committed stroke.
- Linear/radial: evaluate analytic kernels directly at the target extent.
- Composite: apply replace/add/subtract/intersect, component inversion, layer inversion, density,
  and amount on the GPU in a bounded single-channel representation.

Derived resource keys must include source fingerprint, layer/component definition hash, target
dimensions/quality, orientation/crop-relevant transform, and mask-renderer version. They must not
include unrelated global slider values.

Smart-mask work must be schedulable and cancellable separately from interactive image rendering so
a slow segmentation cannot block brush cursor/overlay presentation. Export waits for required
render-quality masks or reports an actionable export error; it never silently substitutes a mask
from another source. If a refined semantic mask cannot be produced but a validated preview mask is
available, the UI may offer an explicit lower-quality export choice rather than silently degrading.

## 7. Performance design and measurable budgets

“Smooth” is a measured requirement, not a subjective sign-off.

| Path | Target on supported Apple-silicon baseline |
| --- | --- |
| Brush cursor/handle/overlay response | p95 under 16.7 ms; no dropped-input bursts |
| Main-thread work per pointer event | p95 under 2 ms |
| Interactive adjusted preview after a geometry/settings change | p95 under 50 ms when source prefix is warm |
| Settled preview after gesture end | p95 under 150 ms for a typical 24 MP source |
| Cached smart-mask display | under 5 ms, matching the Phase 3 target |
| Initial/refined smart segmentation | preserve Phase 3 targets: under 300 ms for detailed/render quality |
| Mask-tool memory growth during a 30-second stroke | bounded; no growth proportional to pointer event count after resampling |

Required techniques:

- Keep pointer-frequency state out of `AppViewModel` and out of durable persistence.
- Render the overlay with Metal/Core Animation-backed primitives; retire `MaskGridView` from the
  production editing path because iterating mask cells in a SwiftUI `Canvas` does not scale.
- Reuse the existing display device/command-queue ownership and Core Image context rules.
- Precompile/cache mask kernels and reuse mask textures/buffers.
- Permit only one interactive image render in flight and retain only the newest pending state,
  matching `PreviewCoordinator`'s existing pacing.
- Use preview-resolution masks during interaction and replace them with render-quality masks only
  at settle/export boundaries.
- Avoid readback from GPU to CPU on the live editing path.
- Bound caches by cost and purge stale per-source resources on source switch/memory pressure.
- Add mask-specific signposts: pointer input, overlay present, mask resolve start/end, mask render
  start/end, adjusted frame present, cache hit/miss, stroke sample count, and dropped/coalesced work.

Budgets must be validated in Release builds on at least one baseline Apple-silicon Mac and one
large source (at least 45 MP), with hardware/OS/source/viewport recorded beside the result.

## 8. Delivery sequence

Each step should land as a reviewed vertical slice with tests. Do not begin the full UI before the
value model and render contract are pinned.

### Step 0 — Interaction prototype and benchmark baseline

- Record current preview, zoom/pan, and semantic-mask timings with existing signposts.
- Prototype only the overlay input/presentation path with synthetic brush and shape geometry.
- Decide whether overlay drawing is an added Metal pass in `PreviewSurfaceView` or a coordinated
  transparent Metal sibling view based on measured latency and lifecycle behavior.
- Pin screen-to-source coordinate transforms with tests before creating real mask values.

**Exit:** a documented architecture choice and trace proving the overlay path can meet the 16.7 ms
target without broad SwiftUI invalidation.

### Step 1 — Durable model, schema v2, and undo/persistence

- Add the local layer/component/source values and validated Codable implementations.
- Add `localAdjustments` to `EditDocument`; update identity, comparison, reset, hashing, copy/paste,
  and v1-to-v2 decoding.
- Add pure component composition semantics and stable definition hashing.
- Add `MaskInteractionState` with no rendering dependency.

**Exit:** neutral documents render/hash as before; malformed values clamp or fail predictably; a
complete mask document round-trips; a continuous draft commits as one undo entry.

### Step 2 — Render seam and one functional local layer

- Add mask resource resolution to `RenderEngine` without leaking Core Image types.
- Refactor shared global/local adjustment math into pure renderer helpers.
- Implement layer blending, amount, inversion, enable/disable, and ordered layers.
- Use a synthetic/analytic mask in tests to prove preview/export parity and soft-edge blending.
- Update cache versions and invalidate only the affected derived resources.

**Exit:** a persisted analytic mask and Exposure adjustment produce matching preview/export pixels;
neutral and disabled layers are exact no-ops.

### Step 3 — Persistent Masking workspace and layer editing

- Replace the current modal sheet with the integrated workspace and ordered mask list.
- Wire layer selection, naming, enable/disable, amount, invert, delete, duplicate, reorder, overlay,
  and local adjustment sliders.
- Preserve selection per photo and add explicit empty/loading/error states.
- Route every durable change through `AppViewModel.updateDocument`; route every continuous gesture
  through interaction and undo grouping.

**Exit:** any existing layer can be selected later and all of its saved settings can be edited,
undone, redone, persisted, reopened, and reset.

### Step 4 — Linear gradient vertical slice

- Implement normalized definition, analytic renderer, three-bar overlay, hit testing, and inspector
  controls.
- Add create/move/rotate/falloff interactions plus keyboard nudging and accessibility.
- Verify geometry under fit/fill/custom zoom, crop, Retina scale, and non-square sources.

**Exit:** the user can create, leave, reselect, and fully reshape a linear mask with live local
adjustment feedback.

### Step 5 — Radial gradient vertical slice

- Implement ellipse geometry, aspect correction, analytic renderer, inner/outer falloff guides,
  resize/rotate/translate handles, inside/outside, and modifiers.
- Reuse the tested overlay and interaction lifecycle from Step 4.

**Exit:** radial geometry and falloff remain visually aligned with rendered pixels at every zoom and
in preview/export.

### Step 6 — Brush vertical slice

- Implement native pointer capture, sample resampling/simplification, pressure normalization,
  cursor, immediate stroke texture, and vector persistence.
- Add size, feather, flow/intensity, density, subtract/erase, shortcuts, and stroke-level undo.
- Cache completed stroke groups and ensure a new stroke does not rerasterize the entire history per
  pointer event.

**Exit:** a continuous 30-second paint session meets input/overlay budgets, commits compactly, and
renders the same at interactive, preview, and export resolutions.

### Step 7 — Smart Foreground/Background vertical slice

- Add the user-facing Foreground union and shared complementary Background generation.
- Connect saved semantic definitions to progressive cache/resolve/refine behavior.
- Add edge feather, edge shift, density, invert, cancellation, source-generation guards, and
  recoverable failure UI.
- Ensure switching photos cannot publish a mask or overlay from the previous asset.

**Exit:** smart masks can be created quickly, refined asynchronously, re-edited after reopening,
regenerated after cache deletion, and exported at the correct quality.

### Step 8 — Component composition and Lightroom-style refinement

- Enable Add, Subtract, and Intersect for every component type.
- Add component rows, selection, reordering rules, component enable/invert, and solo inspection.
- Validate deterministic composition and useful names/defaults for combinations such as
  “Foreground minus Brush” and “Radial intersect Foreground.”

**Exit:** multi-component masks are fully editable and their component order/operation is clear,
undoable, persistent, and deterministic.

### Step 9 — Hardening, performance gate, and migration release

- Run the complete functional, visual, accessibility, memory, and performance matrix.
- Test corrupted documents, missing caches, provider-version changes, memory pressure, rapid source
  switching, cancellation, comparison mode, histogram, batch export, and quit-time persistence.
- Capture before/after Instruments traces and publish a mask performance report under `docs/`.
- Update user-facing shortcuts/help and replace obsolete selection-only tests/documentation.

**Exit:** all Definition of Done items below pass in CI and the recorded hardware performance lane.

## 9. Test plan

### Value and persistence tests

- Codable round trips and v1 migration for every definition and component combination.
- Clamp/reject NaN, infinity, degenerate gradients, zero radii, invalid sample counts, duplicate IDs,
  excessive names, and unsupported future versions.
- `EditDocument.isIdentity`, visible-look detection, comparison baseline, edit hash, copy/paste,
  reset, and 100-level undo behavior.
- A long brush session creates one history entry per completed stroke, not per sample.

### Geometry and interaction tests

- Bidirectional viewport/source conversion under orientation, crop, fit/fill, zoom, pan, Retina
  scale, window resize, and nonzero image extents.
- Brush stamp/falloff/accumulation golden values and path simplification error bounds.
- Linear projection/falloff and radial aspect/rotation/falloff golden values.
- Screen-space hit targets remain constant while image zoom changes.
- Tool ownership, Escape/cancel, Space-pan, modifiers, keyboard nudging, and source switching.
- Observation tests prove pointer updates do not emit broad `AppViewModel.objectWillChange` events.

### Render tests

- Exact no-op for empty, neutral, zero-amount, and disabled layers.
- Soft alpha endpoints and representative 0.25/0.5/0.75 blends.
- Component replace/add/subtract/intersect/invert results.
- Ordered-layer noncommutativity is intentional and pinned.
- Preview/export pixel agreement for brush, linear, radial, foreground, background, and combinations.
- Extent, orientation, crop, color space, finite-output, and alpha-channel contracts.
- Render stack test continues to allow only the named `CIContext` owners.

### Async and cache tests

- Concurrent semantic requests deduplicate.
- Cancelled/superseded work cannot publish.
- Asset ID, source fingerprint, request revision, and quality must all match before publication.
- Cache deletion regenerates smart pixels from the saved definition.
- Provider/mask-renderer version changes invalidate only relevant cache entries.
- Export waits for correct-quality smart data and reports failure explicitly.
- Manual and analytic masks render without any semantic cache.

### UI, accessibility, and visual tests

- Empty, loading, partial-smart-result, failure, selected, disabled, and solo states.
- Every persisted setting can be changed after deselect/reselect and reopen.
- VoiceOver names/values/actions and full keyboard traversal.
- Screenshot/golden coverage for overlays and handles on light, dark, high-detail, and low-contrast
  photos at multiple aspect ratios and backing scales.
- Overlay is presentation-only and absent from export pixels.

### Performance and memory tests

- Automated definition-hash, raster-cache, request-coalescing, and sample-count bounds.
- Release Instruments sessions for brush, linear/radial handle drags, smart refinement, rapid mask
  switching, zoom/pan while masking, 10-layer documents, large crops, and full-resolution export.
- Assert no synchronous semantic work, JSON encoding, full mask readback, or full-stroke rerasterization
  occurs on the main thread during pointer movement.

## 10. Likely file-level work

Expected new files:

- `Models/LocalAdjustments.swift`
- `Models/LocalMask.swift`
- `Models/MaskGeometry.swift`
- `Models/LocalMaskResolver.swift`
- `Models/MaskRenderCache.swift`
- `Models/MaskInteractionState.swift`
- `Views/MaskingWorkspace.swift`
- `Views/MaskLayerList.swift`
- `Views/MaskAdjustmentInspector.swift`
- `Views/MaskCanvasOverlay.swift`
- `Views/BrushMaskControls.swift`
- `Views/GradientMaskControls.swift`
- `ViewModels/AppViewModel+Masking.swift`

Expected existing integration points:

- `EditDocument.swift`, `EditHistory.swift`, `EditDocumentStore.swift`
- `RenderRequest.swift`, `RenderPipeline.swift`, `RenderEngine.swift`, render/cache resources
- `PhotoAnalysisCoordinator.swift`, `RegionMask.swift`, `MaskStore.swift`, `MaskOperations.swift`,
  `VisionSemanticMaskProvider.swift`
- `CanvasNavigation.swift`, `PreviewCoordinator.swift`, `PreviewSurface.swift`, `PreviewView.swift`
- `ContentView.swift`, inspector state/tab routing, keyboard shortcuts, menu commands
- export, histogram, comparison, copy/paste, reset, persistence, and package invariant tests

`MaskingPanel.swift` should be retired or reduced to reusable semantic-result UI once the persistent
workspace owns the full workflow; there should not be two competing mask editors.

## 11. Definition of Done

- Foreground, Background, Brush, Linear, and Radial masks can each be created from the main canvas.
- Every mask can be selected later and its geometry/refinement, amount, invert, enabled state, name,
  and local adjustments can be changed non-destructively.
- Brush painting exposes responsive size, feather, flow/intensity, and density controls.
- Linear and radial handles visually match the mask's rendered falloff.
- Add/Subtract/Intersect combinations work across component types.
- Mask edits persist per photo and survive reopen, undo/redo, cache deletion, copy/paste, and export.
- Preview, comparison, histogram behavior, and export remain source/revision safe.
- Neutral documents remain pixel-identical and existing unmasked edits migrate without change.
- No main-thread semantic work, live-path GPU readback, new render `CIContext`, third-party dependency,
  network processing, or Swift concurrency escape hatch is introduced.
- The measured latency and memory budgets in Section 7 pass on recorded hardware.
- `swift test` and the opt-in hardware/performance lanes pass, with the final trace and findings
  documented.

