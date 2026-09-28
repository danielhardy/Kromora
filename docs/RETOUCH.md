# Retouch recipes

Retouch values are part of `EditDocument` and are persisted with each photo. A spot stores its
Heal or Clone mode, one `RetouchRegion` of oriented-source normalized brush samples and pressure,
a normalized short-side radius, optional `RetouchSource` (manual or auto), feather, opacity,
visibility, and deterministic seed. These values participate in rendering hashes, undo, and
selective copy/paste under the Retouch category. V1 `shape`, spot `radius`, and `sourceOffset`
fields are not decoded or migrated.

The Retouch inspector offers Heal and Clone, selects Heal by default, and new spots also default to
Heal. Saved recipes that contain the retired `mode: "remove"` value decode as Heal and are encoded
as `mode: "heal"` on their next save. This is the compatibility migration for existing packages;
spot geometry, source offsets, visibility, opacity, and other recipe values are preserved.

Spots render against the developed, EXIF-oriented source before user rotation, straighten, flips,
perspective, crop, Light/Color, or local adjustments. This keeps a spot and its source relation
attached to the same source content as geometry changes. Preview and export share this stage.

Each spot's samples are rasterized as one feathered brush mask through `LocalMaskRenderer`; an
entire stroke produces one fill and one blend. The renderer crops the fill, mask, membrane, and
blend to the region bounds plus ring padding. Clone uses a direct translated source patch. Heal
builds a normalized-convolution pull/push field from destination-minus-fill values weighted only
outside the hole, then adds that field to the translated fill and composites with the feathered,
opacity-scaled mask. Pixels under the hole do not contribute to the replacement tone.

Heal and Clone spots without a source are resolved during rendering by `RetouchSourcePicker` over a
cached neutral-decode Lab proxy with a 1024 px maximum long edge. The picker searches deterministic
nearby spiral and coarse-frame positions, excludes the destination and other visible holes, ranks
ring colour/gradient and texture similarity with a distance cost, then requests a bounded neutral
full-resolution Lab crop and refines leading choices within ±2 pixels. Automatic rank is carried by
`RetouchSource.auto`; manually selected offsets remain authoritative. Analysis pixels and Core Image
values stay inside `RenderEngine`; only Lab value buffers enter the Sendable analysis code.

The Retouch inspector edits mode, size, feather, opacity, and visibility. Canvas strokes and pins
are available; source handles apply to Heal and Clone. `A` toggles the in-canvas Visualize Spots
mode; its threshold only changes the orange analysis overlay and is not saved to the edit recipe or
render. Detect Dust creates dashed, draggable suggestions. Clicking a pin accepts it; Accept All
creates ordinary Heal spots with stable IDs and deterministic seeds. Dismissal only removes
transient suggestions. Accepted spots use the normal source-space recipe, undo/history, and
renderer. The manual brush remains available for candidates the detector misses. Eye centers remain
recipe values; automatic face/pupil detection is not part of retouch.

Dust suggestions use a CPU difference-of-Gaussians response over the neutral, downsampled Lab
analysis proxy. A gradient/variance gate rejects many textured regions and strong edges. The initial
threshold is `0.025` on normalized Lab L response (adjustable from `0.005` to `0.12`). The focused
measurement is `swift test --filter RetouchDustDetectorTests`: at threshold `0.025`, the current
KRMA-658 subset (six backgrounds × 5 px soft dust and hard speck) reports candidate pixel precision
1.00 and fixture recall 0.083 (1 of 12 fixture cases contained a candidate inside the defect mask).
This is a conservative suggestion pass, not a dust guarantee: it produced no counted false-positive
pixels in this small subset, while missing most defects, especially in textured or edge-heavy scenes.
Candidates outside the measured mask are false positives by the pixel metric; fixture recall counts
a case as detected only when at least one candidate lands inside its defect mask. These numbers
describe generated fixtures at 96 × 72 px, not camera performance; inspect suggestions and use the
brush for missed or rejected spots.

Selective Retouch copy/paste preserves source-normalized region samples, spot size, visibility, mode,
and deterministic seed. It clears sampled source offsets so each destination resolves its own
Heal/Clone source against that frame's fingerprint. Batch paste reports how many photos received the
recipe; a target with no viable source remains unchanged under the existing render behavior.

## Retouch quality evaluation

Run `swift test --filter RetouchQualityEvaluationTests` for the deterministic ground-truth quality
gate. It generates clean and damaged 96 × 72 pixel pairs (192 × 144 for the 60 px dust case) in
`Tests/KromoraKitTests/Fixtures.swift` and prints rows for Heal, automatic Heal, Clone, and the
current Heal behavior. The corpus covers a smooth noisy sky, cloud boundary, foliage, water, brick
crossed by a wire, and skin-like texture; defects include soft dust with 5 px and 60 px diameters, a
hard speck, straight and sagging edge-crossing wires, and hair/fibre. Fixed seed 658 controls
synthetic grain and fixture coordinates. No photo assets are required.

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

The gate measures Heal and Clone quality against the unchanged KRMA-658 limits. Manual fixture
offsets passed 3/36 Heal rows and 7/36 Clone rows; the automatic picker passed 5/36 Heal rows in
the last recorded full corpus run. These are generated-fixture results, not claims about
camera-image performance. The evaluation limits are a quality gate, not a timing benchmark. For
real-camera coverage, place licensed RAW fixtures outside the checkout and opt in with
`KROMORA_RAW_FIXTURE_DIR`; the normal quality suite does not read or commit that directory.
