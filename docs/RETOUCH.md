# Retouch recipes

Retouch is a current capability with a small-defect target, not a promise of generative
large-object removal. The measured limitations below are specific to their generated fixtures and methods.

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

Run `swift test --filter RetouchQualityEvaluationTests` for the deterministic ground-truth stress
report and supported-class shipping gate. It generates clean and damaged 96 × 72 pixel pairs
(192 × 144 for the 60 px dust case) in
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

### Threshold achievability for wires, hair, dust, and speck

The focused `swift test --filter RetouchQualityEvaluationTests` run passes its three test methods.
The current renderer measures 4 passing wire/hair rows out of 72 mode/background/defect rows:
Heal, Clone, and the duplicate `Current` Heal row on foliage hair, plus Clone on brick straight
wire. The other 68 rows fail at least one limit. Those results describe current renderer behavior,
not the achievable quality ceiling.

A separate deterministic experiment now checks that ceiling with a hand-built repair for straight
wire on every background. For masked pixels, it takes an inverse-square weighted color estimate
from undamaged pixels 2–5 px away, then adds independent deterministic high-frequency grain with
the fixture's 0.055 amplitude and seed 9191. It reads no clean-reference pixels; the only known
inputs are the defect mask and the synthetic grain scale. This is a controlled interpolation and
texture-synthesis example, not evidence that the production renderer or a real photograph will
always admit this repair. It passes all four limits on all six backgrounds:

| Background | ΔE2000 | Gradient | Variance ratio | Luma shift |
|---|---:|---:|---:|---:|
| Smooth sky | 0.35 | 1.89 | 1.01 | -0.0006 |
| Cloud boundary | 0.75 | 3.06 | 0.85 | -0.0012 |
| Foliage | 1.42 | 4.29 | 0.73 | -0.0005 |
| Water | 0.71 | 2.66 | 0.77 | -0.0007 |
| Brick/roof | 2.39 | 5.26 | 0.91 | +0.0100 |
| Skin-like | 0.65 | 2.07 | 0.93 | +0.0034 |

The exact per-pixel grain realization is hidden inside the defect, but these limits tolerate a
statistically recreated texture when the surrounding color can be interpolated. No threshold or
fixture adjustment is indicated by this experiment; retain the fixed-seed stress corpus and its
no-photo-assets property. This experiment covers straight wire only. It does not establish
repairability for sagging wire, hair/fibre, or dust, and passing a synthetic case is not a claim
about camera-image performance.

The gap remains wider for dust and speck on three backgrounds. Sky, cloud, and skin currently pass
zero of their 24 rows each across every defect family, including soft dust and hard speck; foliage,
water, and brick each pass at least one dust or speck row. These current-renderer failures do not
show that a capable dust or speck repair cannot meet the limits. If a concrete repair later reveals
that high-frequency grain reconstruction dominates those cases, the separate profile described
below is a targeted way to isolate that effect.

The corpus still serves as a deterministic stress lane: its independent per-pixel hash grain
(amplitude 0.055) hides the exact high-frequency samples under a defect. The repairability
experiment shows that an independently synthesized texture can satisfy the existing limits for
straight wire without recovering those samples. The current renderer still passes zero of 24 rows
on sky, cloud, and skin across all defect families, including dust and hard speck, so those baseline
failures remain useful gap reports rather than proof that the limits are impossible. Keep the
current limits unless a concrete repair with visibly acceptable output fails them; if a future dust
or speck repair cannot separate texture-reconstruction error from a defect remnant, evaluate a
separate deterministic low-frequency-grain profile (for example, smooth noise sampled on an 8 px
lattice and interpolated between points) before changing thresholds.

### Stress report versus shipping gate

Two different numbers come from this suite; do not conflate them.

- **Stress report** (`testStressCorpusReportsCurrentHealAndCloneResults`): all 36 background/defect
  rows per mode, including wires and the 60 px broad-removal case that v1 does not support. It prints
  pass counts (currently Heal 22/36, automatic Heal 14/36, Clone 21/36) and asserts only that the corpus
  ran. It does not require any family to fail, so an improvement never breaks it.
- **Shipping gate** (`testShippingGateHoldsSupportedClassFloors`): only the supported small-defect
  classes. `dust/speck` is 5 px soft dust plus hard speck (12 rows per mode); `hair/fibre` is 6 rows
  per mode. Wires and 60 px dust are excluded. Each class and mode has a floor. KRMA-1003 initialised
  them at dust/speck Heal 5, automatic Heal 5, Clone 5 and hair/fibre Heal 1, automatic Heal 0,
  Clone 1; KRMA-1004 raised them to dust/speck Heal 10, automatic Heal 11, Clone 10 and hair/fibre
  Heal 2, automatic Heal 0, Clone 2. The test fails when a count drops below its floor. Raise a floor
  when a repair improves it; never lower one to turn the run green.

KRMA-1004 changed boundary handling, not thresholds. The blend mask used to feather inward from the
brush radius, so the rim of a defect the brush just covered was only partly replaced. The mask is now
opaque across the brush radius and feathers outward. The Heal pull/push correction now takes its
exterior weights from that same mask rather than a hard-edged hole, so a defect pixel at the brush
edge (a half-pixel placement error in the fixtures) can no longer be sampled as trusted ring and
drag the correction toward the dust. Still failing: cloud-boundary dust/speck for manual Heal and
Clone (the fixed manual offset lands on a cloud edge), and every automatic-Heal hair/fibre row.

KRMA-1077 fixed a dark blob in the camera-scale foliage dust Manual Heal case. The tone correction is
additive, so a manual source much brighter than the destination ring drove the source's own shadow
structure below black. The final correction step (`retouchApplyCorrection`) now lets a pixel lose at
most 65% of its value; ordinary corrections are unchanged (every existing floor holds). The cause was
the renderer's tone matching, not the source picker. `testHealFromBrighterSourceDoesNotClipShadowStructureToBlack`
covers it, and the historical human Fail for that case stands until a new visual verdict is recorded.

Both run on 96 × 72 px synthetic fixtures. Neither is a camera-scale sign-off; camera-scale
inspection is tracked in KRMA-1016.

The stress report measures Heal and Clone quality against the unchanged KRMA-658 limits. Before KRMA-1004, manual
fixture offsets passed 8/36 Heal rows and 7/36 Clone rows and the automatic picker 5/36 Heal rows
(2026-10-12); the current counts are in the stress-report bullet above. The shipping gate applies those limits only to the supported
classes and enforces the per-class floors above. These are generated-fixture results, not claims
about camera-image performance. The evaluation limits are a quality gate, not a timing benchmark. For
real-camera coverage, use local RAW fixtures in `realworldtest/` or another fixture directory with
`KROMORA_RAW_FIXTURE_DIR`; the normal quality suite does not use those images.

## Camera-scale diagnostics (KRMA-1061)

Measured 2026-10-19 with `swift test --no-parallel --filter RetouchCameraScaleDiagnosticsTests`
(serial lane; real Core Image and the production `RetouchRenderer`/`RetouchSourcePicker`). The suite
generates sixteen 1800 × 1200 crops (native pixel pitch, the size of a 1:1 region of a 24 MP frame):
sky, foliage, skin, and a soft-edged ridge, each with a 3 px hair, a long hair crossing about 73% of
the crop width, a 7 px soft dust disc, and a 5 px hard speck. Fixtures are generated from fixed
coordinates and seed 658, with a known clean reference, and graded with the same per-background limits
as the 96 × 72 corpus (`RetouchQualityMetrics`). The brush covers each defect with a 1.5 px margin.
Automatic sources are picked at declared proxy scales: 1.0 (native), 0.57 (the production 1024 px
proxy of this crop used as a whole frame), and 0.17 (this crop as a 1:1 region of a 6000 px frame).
Generated-fixture results only; camera-image acceptance is KRMA-1063.

### Reproduced counts (unchanged limits, seeds, classes)

Shipping gate on the 96 × 72 corpus, as before: dust/speck Heal 10/12, automatic Heal 11/12, Clone
10/12; hair/fibre Heal 2/6, automatic Heal 0/6, Clone 2/6. Stress report: Heal 22/36, automatic Heal
11/36, Clone 21/36.

Camera-scale crops (16 cases per row):

| Mode | Pass |
|---|---:|
| Manual Heal / Manual Clone (known clean source) | 13 / 14 |
| Auto, native proxy (1.0), coarse pick | 11 |
| Auto, proxy 0.57, shipped path (coarse + refine) | 10 |
| Auto, proxy 0.17, shipped path | 9 |
| Auto, proxy 0.57 / 0.17, coarse pick rounded to whole source pixels | 12 / 11 |

Per class, shipped path at 0.57 / 0.17: hair 2/4 and 3/4, soft dust 4/4 and 4/4, hard speck 4/4 and 2/4,
long hair 0/4 and 0/4. Manual Heal passes hair 4/4, long hair 4/4, soft dust 2/4, hard speck 3/4.

### First failed boundary

1. **Candidate generation: contamination avoidance (the 96 × 72 hair failure, and long hairs at camera
   scale).** `RetouchSourcePicker.valid` rejects any placement whose translated bounds overlap the
   *bounding box* of the whole stroke (`Shape.bounds`), so a hair that spans a large part of the frame
   leaves no placement. On every 96 × 72 hair row the picker returns **zero** candidates, the spot keeps no
   source, and the render is unchanged (luma shift −0.09 to −0.22 is the untouched hair). The same
   happens for the camera-scale long hair on all four backgrounds at every proxy scale. The sources exist:
   on the 96 × 72 rows the 6 px-grid oracle finds 44 defect-free, in-frame whole-pixel placements per
   background. On foliage and water (where manual Heal already passes), all 44 pass every limit. On
   the other four backgrounds not even a defect-free source passes, because the fixture brush has no
   margin over the hair; that is a fixture limit, not a picker one. Manual Heal and automatic Heal
   with a defect-free source repair the camera-scale long hair on all four backgrounds.
2. **Source ranking is not the limiting factor.** At camera scale the ranked list holds 24 defect-free
   sources for every case and the first passing rank is 0 on 10 of 12 cases (rank 1 on edge hair, rank 3 on
   skin hair); no case contaminates its own source.
3. **Offset quantization (variance failures).** The coarse pick is normalized by the *proxy* size, so at
   0.57 or 0.17 it is a fractional source-pixel offset (e.g. −45.6, 140.4). Core Image resamples the fill,
   which smooths the grain: skin and edge hair and sky speck fail the variance limit at 0.46–0.52. Rounding
   the same offset to whole source pixels passes them (hair 2/4 → 4/4 at 0.57, 3/4 → 4/4 at 0.17;
   hard speck 2/4 → 4/4 at 0.17). A residual failure remains for sky soft dust at 0.17 (variance 1.71).
4. **Refinement crop origin (`RenderEngine.pickRetouchSource` / `retouchAnalysisCrop`).** The crop is chosen
   in Core Image y-up coordinates and its `originY` is `crop.minY`, but `RetouchAnalysisRegion.lab`
   and `RetouchSourcePicker.Shape` use top-down rows (the bitmap's first row is the crop's *top*). With
   the top-down origin (`sourceHeight - crop.maxY`) the refined winner differs on 11 of the 24 non-long-hair
   rows (12 cases at scales 0.57 and 0.17), and on foliage dust/speck the shipped path returns the vertical mirror
   (e.g. (−10.5, 42.1) against (10.0, −43.0)). Both choices pass here, so this is an evidence-backed
   correctness defect rather than a measured quality failure.
5. **Blend, secondary.** Manual Heal on sky soft dust fails variance (1.83 against a 1.65 limit) and on
   foliage dust/speck fails luminance (+0.036/+0.038): a halo from the dust tail past the brush and a
   fixed-offset source on textured ground. Auto sources pass those rows, so this is not on the
   hair-repair path.

### Declared acceptance for KRMA-1062

For every one of the sixteen cases, automatic Heal with the corrected picker must pass all four limits at
both proxy scales (0.57 and 0.17) with a whole-pixel offset; the suite prints a `TARGET ... met/NOT met`
line per case and currently reports 23 of 32 met (all long-hair cases and sky soft dust at 0.17 are not).
The 96 × 72 automatic-Heal hair row must pass wherever manual Heal does (foliage and water). Do not lower
limits or drop rows. The suite asserts only no-regression floors (Manual Heal 13, Manual Clone 14, shipped
path 10 at 0.57 and 9 at 0.17); KRMA-1062 turns the targets into assertions.

### Bounded corrective approach (KRMA-1062 entry points)

- `RetouchSourcePicker.valid` (and `Shape.bounds`): test overlap against the stroke geometry (sample
  segments inflated by `radius + margin`) rather than one bounding box, for the destination and for other
  spots; score against a ring around the stroke instead of only the bounding-box centre in `score`.
- `RetouchSourcePicker.candidates` / `RenderEngine.pickRetouchSource`: return offsets rounded to whole
  full-resolution pixels (`round(dx × nativeWidth) / nativeWidth`).
- `RenderEngine.retouchAnalysisCrop`: pass the top-down origin (`sourceHeight - crop.maxY`) to
  `RetouchAnalysisRegion`.
- Keep the stress-only wires and 60 px removal out of scope.

## Automatic Heal hair repair correction (KRMA-1062)

Measured 2026-10-19 on the same generated fixtures, seeds, and unchanged limits as KRMA-1061
(`RetouchQualityEvaluationTests`, `RetouchCameraScaleDiagnosticsTests`; serial lane, real Core Image).
Generated-fixture results only; camera-image acceptance is KRMA-1063.

Changes, at the boundaries KRMA-1061 identified:

- `RetouchSourcePicker.valid` now tests the translated stroke *path* (resampled at half the brush radius,
  spatially hashed) against the destination stroke and every other visible spot, instead of the whole
  stroke bounding box. A single dab reproduces the previous box test; a long hair now keeps clean
  sources. `score` judges the match around anchors spread along a long stroke and ignores ring samples
  that lie on the stroke's own path. Selection stays deterministic for a persisted recipe.
- `RetouchSourcePicker.snapped` rounds the proxy pick to whole source pixels in
  `RenderEngine.pickRetouchSource`, so Core Image copies the fill without resampling grain.
- `RenderEngine.retouchAnalysisCrop` passes the top-down origin (`extent.maxY - crop.maxY`).

| Measure | Before | After |
|---|---:|---:|
| Shipping hair/fibre automatic Heal (96 × 72, 6 rows) | 0/6 | 3/6 (foliage, water, brick) |
| Shipping dust/speck Heal / auto Heal / Clone (of 12) | 10 / 11 / 10 | 10 / 11 / 10 |
| Shipping hair/fibre Heal / Clone (of 6) | 2 / 2 | 2 / 2 |
| Stress report Heal / auto Heal / Clone (of 36) | 22 / 11 / 21 | 22 / 14 / 21 |
| Camera-scale shipped auto path, proxy 0.57 (of 16) | 10 | 16 |
| Camera-scale shipped auto path, proxy 0.17 (of 16) | 9 | 16 |

The shipping automatic hair floor is now 3/6, and both camera-scale shipped-path rows are asserted at
16/16 with no source touching the defect.

Remaining limitations: sky, cloud, and skin 96 × 72 hair rows still fail for every source (the fixture
brush has no margin over the hair, a fixture limit, not a picker one). Manual Heal on sky soft dust and
on some foliage dust/speck still fails (blend, not on the automatic hair path). The coarse, unrefined
proxy pick at 0.17 still misses sky soft dust; the shipped path refines it. Real-camera sign-off is not
claimed until KRMA-1063 is recorded.

## Camera-scale acceptance run sheet (KRMA-1063)

Status: **Human review recorded: 23 Pass, 4 Fail; skin detail Not run.** The
[2026-10-20 execution record](../.context/2026-10-20-KRMA-1063-retouch-qualification.md) records the
supplied verdicts and notes, mechanical export/persistence checks, controlled-fixture limitations,
and the durable local archive at `artifacts/retouch-review-2026-10-20/Kromora Retouch Review.html`.
All nine auto-source Heal cases passed. KRMA-1077 tracks the failed foliage Manual Heal case;
the three Clone failures retain the reviewer's minor/close assessments. This is not blanket release
approval, and the missing skin row remains explicit. Private photographs stay out of Git and uploads.

Run header (fill at run time): candidate commit; signing type (ad hoc / Apple-signed); macOS version;
machine; reviewer; date; fixture identifiers with source pixel dimensions (resolve from `realworldtest/`
filenames, for example the two ARW files for 24 MP+ coverage and the DNG files for smaller sources).

| # | Background / defect | Heal (manual) | Heal (auto source) | Clone | Notes |
|---|---|---|---|---|---|
| 1 | Sky or cloud: soft dust | Pass | Pass | Pass | 01-sky-dust |
| 2 | Sky or cloud edge: hard speck | Pass 2/2 | Pass 2/2 | Pass 2/2 | 02-cloud-speck, 08-cloud-edge-speck |
| 3 | Sky or cloud edge: hair/fibre | Pass 2/2 | Pass 2/2 | 1 Pass, 1 Fail | 10 Clone Fail is minor per reviewer; 13 Clone Pass |
| 4 | Textured foliage: dust/speck and hair | 1 Pass, 1 Fail | Pass 2/2 | Pass 2/2 | 04 manual Heal: dark branch, KRMA-1077; 11 Pass |
| 5 | Water or brick: dust/speck and hair | Pass 2/2 | Pass 2/2 | Fail 2/2 | 06 and 12 Clone: minor/close per reviewer; water tested |
| 6 | Skin-like detail: dust/speck | Not run | Not run | Not run | No representative crop available |

Per cell, inspect at 100% and record: remaining defect, halo or seam, blur or texture loss, duplicated
structure, and source-patch contamination. Omit a row only with an explicit "no representative crop
available" note.

Persistence check (representative cases): export at full resolution and reopen the file; confirm repairs,
masks, and source offsets agree with the settled preview; quit and relaunch, then confirm the repairs
persist in the package. Record Pass/Fail/Not run each.

File a focused defect for each reproducible failure. Link the completed sheet from KRMA-1016.

### Export versus harness pixel comparison (KRMA-1076)

The archived signed app's full-size PNG export differs from the Debug qualification harness in 2,023
of 48,771,072 pixels, all inside the repair bounds, at most 2/255 per channel. `RetouchExportBoundaryTests`
compares streamed and in-memory paths within each build using a generated 1200 × 900 image and a newly
constructed document. It does not replay the persisted package or compare Debug pixels directly with
Release pixels. KRMA-1085 replayed the saved package asset (8064 × 6048, Heal document revision 1,
automatic source, PNG full size) in SwiftPM Debug and Release runs. The six replay variants per build
changed one variable at a time: cold versus warm renderer, source with and without portable identity,
in-memory `render` versus streamed `encode`, and with and without `assetID`. All twelve outputs decoded
to identical pixels in a common sRGB context (0 differing pixels), matching the archived harness export.
The SwiftPM Debug and Release builds and the tested cache, identity, and encoding variations did not
change the in-process KromoraKit outputs. This does not isolate or exclude effects specific to the
signed Xcode app target: the archived signed-app export was not rerun with those variations.

Comparing that archived signed-app PNG with each replay output still gives 2,023 differing pixels,
inclusive bounds x=4646–4707, y=756–815, maximum RGB channel delta 2/255. The package contains saved
revision 1; the export-time request passed by the app was not captured, so the cause remains unknown.
The app request, app-target configuration, sandboxed runtime, and other untested evaluation differences
are possibilities, not established causes. This measured difference is not evidence of numeric noise;
no cross-build tolerance is published. Human visual approval is recorded separately and is not implied
by this comparison.
