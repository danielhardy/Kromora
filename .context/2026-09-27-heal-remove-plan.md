# Remove / Heal / Clone — Lightroom-style brush retouch plan

> **Historical implementation plan.** Shipped Retouch behavior and measured limits are described in
> [`docs/RETOUCH.md`](../docs/RETOUCH.md). The phases below record implementation provenance and are
> not an open execution queue. Current product boundaries are in
> [`docs/PRODUCT_SCOPE.md`](../docs/PRODUCT_SCOPE.md).

Date: 2026-09-27 · Parent: KRMA-599 · Supersedes the slider-driven Retouch spot UI (29c44da, aed117d, 96a14e9)

## Goal

Paint over dust or a wire on the canvas and it is gone — cleanly, on the first try, with grain,
gradients and edges intact. Interaction matches Lightroom's Remove tool. Scope is deliberately
**small defects**: sensor dust, specks, blemishes, power lines, thin wires, small stray objects.
Within that scope the target is best-in-class quality, not "good enough".

## Decisions (recorded 2026-09-27)

1. **Retouch moves before geometry and tone.** It runs on the developed, EXIF-oriented source image,
   before rotation/straighten/perspective/crop and before all Light/Color/local adjustments.
   KRMA-599's acceptance criterion "render them after geometry and before grain" is amended to
   "render them on the oriented source before geometry and tone".
2. **Default mode is Remove.** Heal and Clone remain as alternate modes.
3. **Scope is small dust / wire removal.** No generative or Core ML inpainting. Large-object removal
   (people, cars against structured scenery) is explicitly out of scope; the tool may still accept
   large strokes, but quality is not targeted there.
4. **No migration.** Nothing has shipped. Replace the `RetouchSpot` model outright; old v1 fields
   (`shape`, `sourceOffset`, `radius` on the spot) are not decoded or converted. Keep the codebase's
   tolerant `decodeIfPresent` style for the new fields.

## Why the current implementation cannot work

Independent of the UI, the current recipe/renderer cannot remove anything reliably:

1. **New spots are no-ops.** `addSpot()` creates a circle at (0.5, 0.5) with `sourceOffset = .zero`.
   Nothing ever picks a source (`sourceWasAutoPicked` is never set by any logic), so Clone copies the
   destination onto itself and Heal returns `detail(self) + blur(self) ≈ self`.
2. **Heal's math keeps the blemish.** `healTexture` computes `detail(source) + blur(destination)`.
   The destination blur is taken *inside* the spot, so it contains the dust being removed; its tone
   comes back as a soft blob. Correct healing takes the source's texture and matches colour/light
   only from the **ring outside** the hole, interpolated inward (membrane / Poisson blending). The
   pixels being removed must never be read.
3. **Strokes render as N separate spots.** For `.stroke`, every sample is its own disk with its own
   full-frame `CIBlendWithMask`, and Heal adds two full-frame Gaussian blurs per sample. A 100-sample
   stroke = 100 blends + 200 full-image blurs (KRMA-657 is a symptom). Output is overlapping circles.
4. **Source offset lives in the wrong space.** `sourceOffset` is added in post-geometry space, so
   rotate/straighten/flip moves the source relative to the image content.
5. **Wrong pipeline stage.** Retouch runs after local adjustments in post-geometry space: every tone
   change alters what is sampled (no stable cache possible), and `RenderEngine` disables `sourceROI`
   whenever any spot exists (`document.retouch.isIdentity ? sourceROI : nil`), so zoomed previews
   render the full frame.
6. **No canvas input.** The inspector only exposes Center X/Y and Source X/Y sliders.
   `GeometryPointMapping.viewportPoint(forRetouchPoint:)` exists but has no caller.

## Reuse from masking

The masking workspace already solves most of the interaction problem; reuse, don't rebuild:

| Need | Existing piece |
|---|---|
| Native pointer, tablet pressure, coalesced touches, ⌥-scroll resize, pinch/scroll zoom | `MaskPointerSurface` / `MaskPointerNSView` (optionally rename `CanvasPointerSurface`) |
| Stroke data + resampling/simplification | `BrushSample`, `BrushStroke`, `BrushMaskMath.resampledAndSimplified` |
| Cached, tiled stroke rasterization to a feathered mask | `LocalMaskRenderer.brushImage` / `cachedStrokeRaster` |
| Draft-at-pointer-frequency, commit-once-per-gesture | `MaskInteractionState` draft pattern, `MaskingWorkflowCoordinator.begin/update/endMaskGesture` |
| Async, cancellable, cached resolution inside the render engine | semantic mask resolution (`resolvedLocalMasks`, `resolveSemanticMasks`, in-flight table) |
| Source ↔ viewport mapping under crop/rotate/zoom | `GeometryPointMapping` + `CanvasMaskTransform` |
| Bracket-key sizing, tool key routing | `KeyboardShortcuts.swift` masking cases |

## Interaction spec

### Tool
- **Q** (or opening the Retouch tab) arms the canvas brush. Esc deselects; Esc again (or Q) exits.
  Entering Retouch closes crop and the masking workspace — one canvas owner at a time.
- Inspector: mode segmented control **Remove | Heal | Clone** (default Remove), **Size**,
  **Feather**, **Opacity**. With a spot selected, the same sliders edit that spot (Lightroom behavior).
- Default brush is small (tuned for dust); size is normalized to the source's short side, so the
  on-screen ring scales with zoom. Minimum on-screen ring is a few points so it stays visible.
- Cursor: outer ring = size, inner ring = feather, crosshair centre.

### Creating
- **Click** → circular spot at brush size.
- **Drag** → free-form stroke; the whole stroke becomes **one** region with **one** blend.
- **Shift-click** → straight segment from the previous click point (core for wires: click one end,
  shift-click the other; chain shift-clicks for sagging wires).
- While painting: translucent white stroke overlay only; no re-render.
- On release: one undo entry; then
  - Heal/Clone: auto-source picked (< ~20 ms) and rendered immediately.
  - Remove: solved in the background; a small spinner at the pin until the fill publishes.
- **⌘-drag** on creation (circle) sets the source manually: drag from destination to source.

### Editing
- Each spot has a pin. Hover → outline. Selected → destination outline, and for Heal/Clone the
  source outline with an arrow source → destination.
- Drag destination → move spot (auto source re-picks; manual source stays absolute).
- Drag source outline → manual source (`source = .manual`).
- **/** → next-best source (Heal/Clone) or new seed (Remove).
- **⌥-click** pin → delete. **Delete/Backspace** → delete selected.
- **H** → overlay visibility cycle (Auto / Always / Selected / Never).
- **[ ]** / ⌥-scroll → size; **⇧[ ]** → feather. Space pans; scroll/pinch zoom.
- **A** → Visualize Spots (see Phase 5).

### Inspector (rewritten)
Mode picker, Size/Feather/Opacity, Visualize Spots toggle + threshold, Detect Dust (Phase 5),
"N spots" + Reset All. Remove every coordinate slider and the prev/next spot buttons. Red-eye keeps
its section for now and later moves to click-to-place (KRMA-651).

## Rendering design

### Stage
Apply retouch to the developed, EXIF-oriented source image, before `applyingRotation` /
`applyingGeometry` in `RenderPipeline` and before local adjustments in `RenderEngine`. Consequences:
- Spot coordinates are the same upper-left normalized oriented-source space as `BrushSample`; no
  geometry mapping at render time (fixes cause 4).
- Crop/rotate/tone never change a spot's result.
- Instead of disabling `sourceROI`, expand the ROI by each intersecting spot's box ∪ source box ∪
  ring padding.
- Remove `RetouchRenderer`'s `GeometryPointMapping` usage and the `finalDocument.retouch = .neutral`
  late-stage plumbing in `RenderEngine`/`RenderPipeline.buildImage`.

### One mask per spot
Rasterize the region through `LocalMaskRenderer`'s brush path (per-stroke cache, pressure). Every
intermediate is cropped to the spot box + padding (closes KRMA-657).

### One membrane blend for all modes
With hole mask `M` (feathered) and ring `R = dilate(M) − M`:

- `fill` = Clone/Heal: translated patch · Remove: pixels sampled through the correspondence field.
- `d = current − fill`, weighted by `R` only (never read inside `M`).
- `membrane` = smooth interpolation of `d` into the hole via a pull–push pyramid (normalized
  convolution: downsample `d·w` and `w`, divide, upsample, fill where coarse). ~4–6 levels, all
  box-local.
- Clone → `fill`; Heal and Remove → `fill + membrane`; composite with feathered `M × opacity`.
- Kernels: replace `healTexture` with `retouchMembraneApply`, `retouchPull`, `retouchPush`, and
  `retouchSampleField` in `KromoraCIKernels.ci.metal`, loaded via `CIKernelLibrary` (update
  `expectedKernelNames`, rebuild the metallib + checksum with `scripts/build-metal-libraries.sh`).

### Remove stores a correspondence field, not pixels
The solver outputs a nearest-neighbour field (NNF): per hole pixel, the source coordinate it copies.
Stored as a small RG float texture covering the hole box. At render time a kernel samples the
**live** image at those coordinates, then the membrane is added. Develop/tone changes never re-solve;
preview and export share one result.

**Solve at full source resolution.** Dust and wire holes are small, so a full-resolution solve is
cheap (a 40 px dust spot is trivial; a 3000 × 12 px wire is ~36k hole pixels). One full-res NNF,
downsampled for preview, guarantees export == preview. The solver reads a full-res crop of a neutral
decode around the hole + context window via a region render in `RenderEngine`.

## Components

### Model (`RetouchModels.swift`) — replaced outright

```swift
enum RetouchMode: String, Codable, Sendable, CaseIterable { case remove, heal, clone }

struct RetouchRegion: Codable, Sendable, Equatable {
    var samples: [BrushSample]     // oriented-source normalized; a click = one sample
    var radius: Double             // fraction of source short side
}

enum RetouchSource: Codable, Sendable, Equatable {
    case auto(offset: CGVector, rank: Int)   // oriented-source normalized offset; rank for "/"
    case manual(offset: CGVector)
}

struct RetouchSpot: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var mode: RetouchMode
    var region: RetouchRegion
    var source: RetouchSource?     // nil until picked; unused by Remove
    var feather: Double
    var opacity: Double
    var isVisible: Bool
    var seed: UInt32               // deterministic Remove solve
}
```

Participates in render hashes, undo/history, and selective copy (Retouch category) as today.
Remove the `SpotShape` enum and `sourceWasAutoPicked`.

### Analysis (new `Models/RetouchAnalysis/`, Sendable value code, off the main actor)
Only `Data`/value buffers cross the `RenderEngine` boundary (Swift 6 rules in CLAUDE.md).

- **`RetouchAnalysisProxy`** — `RenderEngine` provides a cached neutral-decode Lab float buffer
  (~1024 px long edge) per source fingerprint for search, plus full-res region crops on demand.
- **`RetouchSourcePicker`** (Heal/Clone, and Remove initialization)
  - Candidates: spiral out to ~6× spot size, plus a coarse whole-frame sample.
  - Score: ring colour SSD (Lab) + ring gradient mismatch + interior texture-energy match + small
    distance penalty.
  - Reject: leaves frame; overlaps any spot's hole (dilated); overlaps its own hole.
  - Refine top-k with ±2 px search at higher resolution; deterministic ordering and ties; `rank`
    walks the list for "/".
  - Accelerate/SIMD; target a few ms.
- **`PatchMatchInpainter`** (Remove) — tuned for thin/small holes
  - Coarse-to-fine (2–3 levels; thin wires need ~1), 7×7 patches (5×5 for holes < 6 px wide).
  - Init from the picker's best offset; propagation + random search + weighted voting (Wexler/Barnes).
  - Patch distance = Lab SSD + **gradient term** so edges crossing a wire (roof lines, branches,
    horizon) continue straight instead of smearing.
  - Sources restricted to pixels outside all holes; seeded RNG from `seed`.
  - Output: full-res NNF for the hole box.
  - Swift/SIMD first; port the inner loop to Metal compute only if profiling requires.
  - Targets: dust spot < 50 ms; 3000 px wire < 400 ms. Cancellable.

### Engine: fill cache
- Local, rebuildable cache (never package-owned, per `docs/STORAGE_POLICY.md`).
- Key: source fingerprint + region digest + seed + solver version + digest of earlier spots whose
  dilated boxes intersect (spots are applied in order; a later spot may sit on an earlier one).
- `resolveRetouchFills` flag mirrors `resolveSemanticMasks`: interactive previews show the spot
  unfilled until the field lands, then publish; export always resolves.
- Pasted spots (selective copy to other frames — common for sensor dust) re-solve automatically
  because the key includes the source fingerprint.

### Interaction
- **`RetouchInteractionState`** (`@MainActor`, pointer-frequency): mode, brush size/feather/opacity,
  draft region, selection, hover, active handle (destination/source), overlay policy, shift-click
  anchor, in-flight solve set (for spinners).
- **`RetouchWorkflowCoordinator`**: `beginGesture/updateGesture/endGesture/cancelGesture`,
  pin hit-testing, move, delete, resample, manual source; commits through `updateDocument` exactly
  once per gesture, then triggers pick/solve. Owned by `AppViewModel`
  (update `docs/APP_ARCHITECTURE.md`).
- **`RetouchCanvasOverlay`**: brush ring, live stroke wash, outlines, pins, source arrow, spinners.
  Placed in `PreviewView.canvasSurface` beside `MaskCanvasOverlay`; maps via `GeometryPointMapping`.
- **Keys** (`KeyboardShortcuts.swift`): Q, /, H, A, Delete, ⌥-click, [ ], ⇧[ ] — Q, H, A and / are
  currently unbound.

## Quality bar ("best ever" for dust and wires)

Ground-truth evaluation harness: take a clean image, composite synthetic defects with known masks,
remove them, compare to the clean original.

- **Defects:** soft sensor dust (low-contrast, soft-edged, 5–60 px), hard specks, 1–8 px dark and
  light wires (straight, sagging, crossing an edge), hair/fibre.
- **Backgrounds:** smooth sky gradient with sensor noise/grain, cloud edges, foliage texture, water,
  brick/roof edges crossed by a wire, skin-like texture.
- **Metrics** (inside hole and a 4 px band):
  - mean ΔE2000 vs ground truth;
  - gradient-continuity error across the boundary;
  - noise-spectrum / local-variance ratio (the fill must carry grain, not be smooth);
  - no mean shift (dust remnant) — mean luminance delta.
- **Pass thresholds** set per background in Phase 0 and tightened as quality improves. The harness
  prints a table so Remove vs Heal vs Clone vs the current implementation is visible.
- **Fixtures:**
  - generated in `Fixtures.swift` for synthetic backgrounds;
  - a few committed AI-generated sky/texture JPEGs under the KRMA-459 allowance (≤ 500 KB each,
    provenance manifest);
  - real dusty RAWs in the opt-in `KROMORA_RAW_FIXTURE_DIR` lane.

## Phases (each maps to a DispatchGraph issue under KRMA-599)

| # | Scope | Ticket | Done when |
|---|---|---|---|
| 0 | **Evaluation harness + failing tests.** Synthetic defect/ground-truth harness, metrics, thresholds. | [KRMA-658](../.dg/issues/KRMA-658.md) | Harness merged; Heal/Remove checks expose the current quality gaps and per-background thresholds are recorded. |
| 1 | **Render correctness.** New model; stage moved before geometry/tone; ROI expansion; one mask per spot via brush rasterizer; membrane blend kernels; box-local work (closes KRMA-657). | [KRMA-659](../.dg/issues/KRMA-659.md) | Heal/Clone harness cases pass with a manual source; spots stable under rotate/crop/flip; per-spot cost independent of image size. |
| 2 | **Automatic source.** Analysis proxy + `RetouchSourcePicker`. | [KRMA-660](../.dg/issues/KRMA-660.md) | Never overlaps holes/frame; deterministic ranking; Heal harness passes with auto source. |
| 3 | **Canvas interaction.** State, coordinator, overlay, keys, shift-click segments, inspector rewrite. | [KRMA-661](../.dg/issues/KRMA-661.md) | Coordinator tests: click = circle, drag = one stroke, shift-click = segment, one undo per gesture, ⌥-click deletes, source drag → manual, "/" resamples. Manual run in the app. **Heal/Clone now behave like Lightroom.** |
| 4a | **Remove solver (PatchMatch).** Standalone, deterministic, cancellable `PatchMatchInpainter` over value buffers → correspondence field; gradient-continuity term; hole exclusion. No engine/UI work. | [KRMA-662](../.dg/issues/KRMA-662.md) | Every harness Remove case passes standalone (field + membrane in a test helper); same seed → identical bytes; solver-only timings recorded. |
| 4b | **Remove integration.** Full-res region extraction from `RenderEngine`, field-sampling kernel, fill cache, `resolveRetouchFills`, preview/export, spinners; Remove becomes default. | [KRMA-665](../.dg/issues/KRMA-665.md) | Harness passes end to end through the engine; export == preview; cache invalidation correct; end-to-end timings recorded in `docs/RETOUCH.md`. |
| 5 | **Dust workflow polish.** In-canvas Visualize Spots (A) with threshold replaces `DustFinderSheet`; **Detect Dust** (difference-of-Gaussians blob detection restricted to smooth regions → suggested dashed pins; click to accept, Accept All); copy spots to selected frames with automatic re-solve. | [KRMA-663](../.dg/issues/KRMA-663.md) | Detection precision/recall measured on the harness's synthetic dust; accepted suggestions become normal spots. |
| 6 | **Wire assist (stretch).** "Refine to wire": after a rough stroke, snap the region to the thin ridge inside the brush corridor and tighten the width to the wire. | [KRMA-664](../.dg/issues/KRMA-664.md) | Harness wire cases pass with deliberately sloppy input strokes. |

The issues are children of KRMA-599. DispatchGraph dependencies encode the sequence: KRMA-659
depends on KRMA-658; KRMA-660 on KRMA-659; KRMA-661 on KRMA-659 and KRMA-660; KRMA-662 (solver)
on KRMA-658, KRMA-659, and KRMA-660, so it can run in parallel with KRMA-661; KRMA-665
(integration) on KRMA-659, KRMA-661, and KRMA-662; KRMA-663 on KRMA-661 and KRMA-665; and stretch
KRMA-664 on KRMA-661 and KRMA-665. Phase 0 can proceed first; implementation work stays queued
behind its prerequisites. KRMA-664 is optional stretch work and does not gate the baseline
retouch workflow.

KRMA-662 was split on 2026-09-27 so algorithm quality (hardest; suits a stronger runner) and
engine plumbing (follows existing semantic-mask resolution patterns) are implemented and verified
separately.

Phases 0–3 deliver a working Lightroom-style brush heal; Phases 4a–4b deliver Remove, the default mode.

## Documentation to update as phases land
- `docs/RETOUCH.md` — new stage, modes, membrane blend, NNF cache, interaction, timings.
- `docs/ENGINEERING_GUIDE.md` — pipeline stage order.
- `docs/APP_ARCHITECTURE.md` — `RetouchWorkflowCoordinator`.
- `docs/STORAGE_POLICY.md` — fill cache is a local projection.
- KRMA-599 acceptance criterion amendment (stage order).

## Out of scope
Generative or Core ML inpainting; large-object removal quality; Apple Photos Clean Up
(no public API known).
