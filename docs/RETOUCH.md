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
opacity-scaled mask. Pixels under the hole do not contribute to the replacement tone. Remove is
reserved for the correspondence-field producer in KRMA-662; its field sampling kernel interface is
in place and an unresolved Remove spot currently leaves the image unchanged.

Heal and Clone spots without a source are resolved during rendering by `RetouchSourcePicker` over a
cached neutral-decode Lab proxy with a 1024 px maximum long edge. The picker searches deterministic
nearby spiral and coarse-frame positions, excludes the destination and other visible holes, ranks
ring colour/gradient and texture similarity with a distance cost, then requests a bounded neutral
full-resolution Lab crop and refines leading choices within ±2 pixels. Automatic rank is carried by
`RetouchSource.auto`; manually selected offsets remain authoritative. The same picker exposes a
deterministic initial offset for Remove's later correspondence-field solver. Analysis pixels and
Core Image values stay inside `RenderEngine`; only Lab value buffers enter the Sendable picker.

The Retouch inspector currently edits the first sample of a circular recipe and its source offset;
freehand canvas creation, pin editing, and field solving are separate follow-up work. The Dust Finder shows a sharpened, high-contrast preview at pixel size, overlays
visible spot markers, and scrolls between spot centers. It does not perform automatic face/pupil
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
is pending in KRMA-662. That row deliberately fails the gate. The suite also asserts that the current
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
