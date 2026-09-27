# Retouch recipes

Retouch values are part of `EditDocument` and are persisted with each photo. A spot stores its
heal/clone mode, normalized source shape, source offset, radius, feather, opacity, and visibility.
Eye corrections store human/pet type, normalized center, pupil size, darkening, and visibility.
These values participate in rendering hashes, undo, and selective copy/paste under the Retouch
category.

`RetouchRenderer` builds Core Image graphs from those values inside the render boundary. The graph
maps source points through rotation, straighten, flips, and perspective; it then applies spots and
eye corrections before LUT, crop, vignette, and grain. Preview and export use the same render
engine path. Recipe data remains portable and contains no Core Image objects.

The Retouch inspector edits spot centers/offsets and eye parameters with normalized controls. The
Dust Finder shows a sharpened, high-contrast preview at pixel size, overlays visible spots, and
scrolls between spot centers. It does not perform automatic face/pupil detection; eye centers are
recipe values. Heal separates the sampled patch's texture detail from its broad color and light,
then recombines that detail with the destination's local appearance before feathered blending.
Clone retains the plain translated-patch result.

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

`Remove (no path)` is reported as the unchanged damaged image because `RetouchMode` currently has
only Heal and Clone. That row deliberately fails the gate and must be replaced with the real Remove
render when that mode is implemented. The suite also asserts that the current Heal misses at least
one case of every defect family; this is a passing XCTest behavior assertion documenting the
baseline, not a permanently expected-failure test. “Current” runs the default Heal recipe through
the production retouch renderer. Heal and Clone currently process each stroke sample as an
individual spot, so wire/fibre rows also expose the current stroke behavior.

Threshold violations include their metric names in the XCTest report table. The table is a quality
gate, not a timing benchmark. Tighten limits as renderer work improves and record any justified
threshold changes with the corresponding implementation ticket. For real-camera coverage, place
licensed RAW fixtures outside the checkout and opt in with `KROMORA_RAW_FIXTURE_DIR`; the normal
quality suite does not read or commit that directory. Generated fixtures are intentionally small,
seeded, and bounded. No AI-generated or licensed image assets are currently required.
