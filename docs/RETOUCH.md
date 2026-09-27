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

Engine timing capture: `KROMORA_RUN_RETOUCH_ENGINE_BENCHMARK=1 swift test --filter
RetouchEnginePerformanceTests/testRecordEngineRemoveTimings`. On the Apple M4 Pro reference setup,
the debug test configuration measured a 60 px dust spot at 972 ms solver / 1,213 ms total on a
3,200 × 900 source, with a 58 ms total cache hit. A 3,000 px wire measured 12,711 ms solver /
13,686 ms total. These debug measurements exceed the solve targets and are not representative of
the optimized app. `swift test -c release --filter ...` could not link the test bundle with this
Xcode beta SDK (`SwiftUICore` opaque symbols are unavailable to the XCTest bundle); optimized
engine timings remain unverified. The benchmark is opt-in so normal CI does not run the large
synthetic source generation and solve.

The Retouch inspector edits mode, size, feather, opacity, and visibility. Canvas strokes and pins are
available; source handles apply to Heal and Clone. The Dust Finder shows a sharpened, high-contrast
preview at pixel size, overlays visible spot markers, and scrolls between spot centers. It does not perform automatic face/pupil
detection; eye centers are recipe values.

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

`Remove (no path)` is reported as the unchanged damaged image while the correspondence-field producer
is pending in KRMA-662. That row deliberately fails the gate. The solver-only table runs the field
through a test helper that samples the live damaged image and applies an exterior-ring-only membrane
colour correction. On the Apple M4 Pro, the current solver passes 32/36 rows. Four measured gaps
remain: cloud/60 px dust (ΔE 6.15, limit 3.5), foliage/60 px dust (ΔE 4.85, limit 4.5), brick/60 px
dust (ΔE 9.19, limit 4.0), and brick/sagging edge-crossing wire (ΔE 5.01, limit 4.0). The larger
cloud and foliage masks hide most of their underlying texture and edge context; the brick dust hides
repeating mortar/brick structure; the sagging wire still leaves too much error where it crosses the
brick edge. All reported values use the unchanged KRMA-658 thresholds. The suite also asserts that the current
Heal misses at least one case of every defect family; this records the remaining quality gap pending
threshold review and later solver work. “Current” runs the default Heal recipe through the production
renderer. The evaluation limits are intentionally not a timing benchmark.

Threshold violations include their metric names in the XCTest report table. The manual fixture
offsets passed 3/36 Heal rows and 7/36 Clone rows; the automatic picker passed 5/36 Heal rows. The
remaining rows stay visible for later source-picking and quality work. Remove has no correspondence
producer yet and remains unchanged, so its 36/36 rows fail. Keep the limits intact until the review
tracked by KRMA-666, and record any justified changes with the corresponding ticket. The table is a
quality gate, not a timing benchmark. For real-camera coverage, place
licensed RAW fixtures outside the checkout and opt in with `KROMORA_RAW_FIXTURE_DIR`; the normal
quality suite does not read or commit that directory. Generated fixtures are intentionally small,
seeded, and bounded. No AI-generated or licensed image assets are currently required.
