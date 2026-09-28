# Retouch recipes

Retouch values are part of `EditDocument` and are persisted with each photo. A spot stores its
Remove/Heal/Clone mode, one `RetouchRegion` of oriented-source normalized brush samples and pressure,
a normalized short-side radius, optional `RetouchSource` (manual or auto), feather, opacity,
visibility, and deterministic seed. These values participate in rendering hashes, undo, and
selective copy/paste under the Retouch category. V1 `shape`, spot `radius`, and `sourceOffset`
fields are not decoded or migrated.

Spots render against the developed, EXIF-oriented source before user rotation, straighten, flips,
perspective, crop, Light/Color, or local adjustments. This keeps a spot and its source relation
attached to the same source content as geometry changes. Preview and export share this stage.

Each spot's samples are rasterized as one feathered brush mask through `LocalMaskRenderer`; an
entire stroke produces one fill and one blend. The renderer crops the fill, mask, membrane, and
blend to the region bounds plus ring padding. Clone uses a direct translated source patch. Heal
builds a normalized-convolution pull/push field from destination-minus-fill values weighted only
outside the hole, then adds that field to the translated fill and composites with the feathered,
opacity-scaled mask. Pixels under the hole do not contribute to the replacement tone. Remove uses
the engine-resolved correspondence field; an unresolved spot remains unchanged until its field
publishes.

Heal and Clone spots without a source are resolved during rendering by `RetouchSourcePicker` over a
cached neutral-decode Lab proxy with a 1024 px maximum long edge. The picker searches deterministic
nearby spiral and coarse-frame positions, excludes the destination and other visible holes, ranks
ring colour/gradient and texture similarity with a distance cost, then requests a bounded neutral
full-resolution Lab crop and refines leading choices within ±2 pixels. Automatic rank is carried by
`RetouchSource.auto`; manually selected offsets remain authoritative. The same picker supplies a
deterministic initial offset for the correspondence-field solver. Analysis pixels and Core Image
values stay inside `RenderEngine`; only Lab value buffers enter the Sendable analysis code.

`PatchMatchInpainter` produces Remove correspondence fields from bounded, full-resolution neutral
Lab crops. `RenderEngine` excludes dilated holes from source patches, solves visible Remove spots
in document order, and samples the live developed image through the resulting RG field before the
shared membrane composite. The field cache is process-local and keyed by source fingerprint,
region digest, seed, solver version, and earlier overlapping spot recipes. It is discarded with the
engine and never enters the edit document or portable package. A changed source, including a pasted
spot on another photo, therefore resolves a new field. Interactive frames can leave a spot
unfilled while a settled preview or export resolves it.

The solver's three shrinking random-search windows, forward/reverse propagation, Lab SSD, gradient
cost, seeded SplitMix generator, stable ties, and weighted field vote are deterministic.
Cancellation throws `SolverError.cancelled` without returning a partial field. Thin masks select
5×5 patches; other masks use 7×7. The standalone solver has not passed every quality row; the
remaining gaps are listed below. Engine-level miss/hit timings and the complete integration quality
run remain to be measured against KRMA-665's targets.

Solver-only optimized Swift timings on an Apple M4 Pro (12 CPU cores), measured with `swiftc -O`
and standalone synthetic buffers: a 60 × 60 dust mask in a 192 × 144 region took 24.1 ms; a
3,000 × 12 px wire in a 3,000 × 64 region took 238.4 ms. These exclude decode, Lab conversion,
and the renderer's membrane composite.

Engine timing capture: `KROMORA_RUN_RETOUCH_ENGINE_BENCHMARK=1 swift test -Xswiftc -O --filter
RetouchEnginePerformanceTests/testRecordEngineRemoveTimings` runs the XCTest bundle with Swift
optimization enabled. On the Apple M4 Pro reference setup, a 60 px dust spot on a 3,200 × 900
source measured 15.0 ms solve / 85.6 ms cache-miss total and 24.0 ms cache-hit total. A 3,000 px
wire measured 189.7 ms solve / 252.2 ms cache-miss total and 35.5 ms cache-hit total. Both
optimized solve times meet KRMA-665's targets (< 50 ms for dust and < 400 ms for wire); cache hits
add no solve time. These totals include full-resolution rendering, so they exceed solver time.
The plain `swift test -c release --filter ...` command still cannot link the test bundle with this
Xcode beta SDK (`SwiftUICore` opaque symbols are unavailable to the XCTest bundle); `-Xswiftc -O`
provides an optimized test build without that release-bundle linker failure. The benchmark is
opt-in so normal CI does not run the large synthetic source generation and solve.

The Retouch inspector edits mode, size, feather, opacity, and visibility. Canvas strokes and pins are
available; source handles apply to Heal and Clone. `A` toggles the in-canvas Visualize Spots mode;
its threshold only changes the orange analysis overlay and is not saved to the edit recipe or render.
Detect Dust creates dashed, draggable suggestions. Clicking a pin accepts it; Accept All creates
ordinary Remove spots with stable IDs and deterministic seeds. Dismissal only removes transient
suggestions. Accepted spots use the normal source-space recipe, undo/history, renderer, and Remove
solver. The manual brush remains available for candidates the detector misses. Eye centers remain
recipe values; automatic face/pupil detection is not part of retouch.

Dust suggestions use a CPU difference-of-Gaussians response over the neutral, downsampled Lab
analysis proxy. A gradient/variance gate rejects many textured regions and strong edges. The initial
threshold is `0.025` on normalized Lab L response (adjustable from `0.005` to `0.12`). The focused
measurement is `swift test --filter RetouchDustDetectorTests`: at threshold `0.025`, the current
KRMA-658 subset (six backgrounds × 5 px soft dust and hard speck) reports candidate pixel precision
1.00 and fixture recall 0.083 (1 of 12 fixture cases contained a candidate inside the defect mask).
This is an intentionally conservative suggestion pass, not a dust guarantee: it produced no counted
false-positive pixels in this small subset, while missing most defects, especially in textured or
edge-heavy scenes. Candidates outside the measured mask are false positives by the pixel metric;
fixture recall counts a case as detected only when at least one candidate lands inside its defect
mask. The test also checks that the foliage texture gate suppresses candidates and that changing
threshold is deterministic. These numbers describe generated fixtures at 96 × 72 px, not camera
performance; inspect suggestions and use the brush for missed or rejected spots.

Selective Retouch copy/paste preserves source-normalized region samples, spot size, visibility, mode,
and deterministic seed. It clears sampled source offsets so each destination resolves its own Heal/
Clone pick and Remove fill field against that frame's source fingerprint. Remove fields are never
copied from the source frame. Batch paste reports how many photos received the recipe; a target with
no viable source remains unfilled under the existing render behavior rather than using a stale field.

## Retouch quality evaluation

Run `swift test --filter RetouchQualityEvaluationTests` for the deterministic ground-truth quality
gate. It generates clean and damaged 96 × 72 pixel pairs (192 × 144 for the 60 px dust case) in
`Tests/KromoraKitTests/Fixtures.swift` and prints one row for each background, defect, and mode.
The corpus covers a smooth noisy sky,
cloud boundary, foliage, water, brick crossed by a wire, and skin-like texture; defects include
soft dust with 5 px and 60 px diameters, a hard speck, straight and sagging edge-crossing wires, and
hair/fibre. Fixed seed 658 controls synthetic grain and fixture coordinates. No photo assets are
required.

The table reports error in the defect mask plus its 4 px boundary band:

- **ΔE2000** is mean CIEDE2000 colour difference from clean pixels.
- **Gradient** is mean absolute RGB-gradient mismatch in 8-bit channel levels across neighboring
  pixels in the measurement region.
- **Variance ratio** is output-to-clean 3 × 3 local luminance variance, averaged over the same
  region. Values near 1 retain local texture; values below the lower limit indicate smoothing.
- **Luma shift** is signed mean linearized luminance difference; the limit is absolute.

Initial limits are per background and intentionally conservative. A row passes only when it is
inside every listed limit.

| Background | ΔE2000 max | Gradient max | Variance ratio | Absolute luma shift max |
|---|---:|---:|---:|---:|
| Smooth sky | 3.0 | 28 | 0.55–1.65 | 0.025 |
| Cloud boundary | 3.5 | 32 | 0.50–1.75 | 0.030 |
| Foliage | 4.5 | 38 | 0.48–1.80 | 0.035 |
| Water | 3.5 | 30 | 0.50–1.70 | 0.030 |
| Brick/roof | 4.0 | 34 | 0.48–1.80 | 0.030 |
| Skin-like | 3.0 | 28 | 0.55–1.65 | 0.025 |

`Remove (no path)` is a baseline row that reports the unchanged damaged image; it deliberately fails
the gate. The solver-only table runs the field through a test helper that samples the live damaged
image and applies an exterior-ring-only membrane colour correction. On the Apple M4 Pro, the current
solver passes 32/36 rows. Four measured gaps
remain: cloud/60 px dust (ΔE 6.15, limit 3.5), foliage/60 px dust (ΔE 4.85, limit 4.5), brick/60 px
dust (ΔE 9.19, limit 4.0), and brick/sagging edge-crossing wire (ΔE 5.01, limit 4.0). The larger
cloud and foliage masks hide most of their underlying texture and edge context; the brick dust hides
repeating mortar/brick structure; the sagging wire still leaves too much error where it crosses the
brick edge. All reported values use the unchanged KRMA-658 thresholds. The suite also asserts that the current
Heal misses at least one case of every defect family; this records the remaining quality gap pending
threshold review and later solver work. “Current” runs the default Heal recipe through the production
renderer. The evaluation limits are intentionally not a timing benchmark.

Threshold violations include their metric names in the XCTest report table. The manual fixture
offsets passed 3/36 Heal rows and 7/36 Clone rows; the automatic picker passed 5/36 Heal rows.

`swift test --filter RetouchQualityEvaluationTests/testRemoveQualityAcrossGroundTruthCorpusThroughRenderEngine`
runs the same 36 KRMA-658 cases through `RenderEngine.makeCGImage`, including engine extraction,
`retouchSampleField`, and the production `RetouchRenderer` membrane/composite. Each damaged render is
compared with a clean render through the same engine pipeline to factor out decode and color
conversion. In the current Apple M4 Pro run, only 5/36 engine rows pass the unchanged limits,
compared with 32/36 through the standalone solver and test-local composite. The pass/fail verdicts
differ on 27 rows; the engine path regresses most line defects and several small dust/speck cases.
This is an engine-path quality gap, not a changed threshold or a solver-only failure. Follow-up
KRMA-683 tracks investigation of the engine sampling/composition path; no solver internals or
thresholds were changed here. Keep the limits intact until the review tracked by KRMA-666, and
record any justified changes with the corresponding ticket. The table is a quality gate, not a
timing benchmark. For real-camera coverage, place
licensed RAW fixtures outside the checkout and opt in with `KROMORA_RAW_FIXTURE_DIR`; the normal
quality suite does not read or commit that directory. Generated fixtures are intentionally small,
seeded, and bounded. No AI-generated or licensed image assets are currently required.

## Optional wire refinement

Multi-sample Remove strokes can be analyzed with **Refine to Wire**. The cancellable CPU pass reads
the neutral Lab analysis proxy, searches across the original brush corridor for a coherent dark or
light ridge, follows the intended path with a distance prior, recenters on the ridge support, and
estimates a narrower radius. It refuses low-evidence or inconsistent corridors. The proposed
boundary is drawn on the canvas; accepting replaces the ordinary `RetouchRegion`, while keeping the
brush region clears the proposal without changing the document. The normal Remove fill pipeline
handles accepted geometry. Single-point dust/speck spots are not eligible, so the optional action
does not change that workflow.

`swift test --filter RetouchWireRefinerTests` measures the deterministic KRMA-658 wire subset with
four-pixel deliberate overspray. On the six generated backgrounds and two wire defects, 5/12
corridors were unambiguous; centerline error improved in all five, from a mean 3.93 px to 0.59 px.
The other seven were declined because the corridor evidence was ambiguous.
Separate synthetic straight-wire checks centered all tested 1–8 px widths within 0.1 px; a low
contrast sagging line crossing a horizontal edge also passed. These are centerline measurements, not
Remove fill-quality metrics, and the six small generated backgrounds do not establish camera-image
performance. The feature remains optional; use the original brush region whenever analysis declines
or the proposed boundary does not match the intended wire.
