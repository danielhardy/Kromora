# Looks and LUTs

This guide describes the current Look workflow and asset policy.

Kromora's Look workflow supports text-based 3D LUTs, derives Looks from a RAW/JPG pair, and ships
13 read-only starter Looks. The parser and renderer are implemented in `CubeLUT`, `LUTLibrary`,
and `RenderPipeline`; this document records the supported interchange contract.

## Render order

A Look is a **base look**. It is applied to the developed source (after RAW develop, retouch, and
geometry), and Light, Color, Effects, Detail, and ordered adjustments then adjust the graded
result, followed by local masks, crop, vignette, and grain. Dragging Exposure after picking a Look
therefore moves the Look's output instead of feeding a fixed transform. Intensity is the same
crossfade between the Look's input and graded output, now computed at the head of the chain.
Documents saved before this order change render differently when they combine a Look with
non-neutral sliders; the stored document is unchanged. Save as Look samples the same order.

## File support

`.cube` files and plain-text `.look` files use the same 3D cube grammar. Proprietary binary or XML
Adobe `.look` packages are rejected rather than guessed at. Kromora accepts 3D tables declared by
`LUT_3D_SIZE` with 2–65 samples per axis, common `TITLE`, `DOMAIN_MIN`, and `DOMAIN_MAX` metadata,
comments, UTF-8 BOMs, CRLF endings, trailing comments, and the common
`LUT_3D_INPUT_RANGE min max` spelling.

The parser rejects 1D or mixed tables, reversed domains, non-finite values, malformed or missing
rows, truncated files, and dimensions outside 2–65. LUT application uses Core Image's
GPU-backed `CIColorCubeWithColorSpace`.

## P3 authoring policy

[ADR-KRMA-1115](../.dg/decisions/ADR-KRMA-1115-display-p3-export-look-and-saved-edit-policy.md)
was accepted on 2026-10-25 and activated by KRMA-1121: the canvas and every rendered delivery are
Display P3 (`WorkingSpace.current`), the bundled Looks are P3-authored, and new saved and derived
Looks are sampled and stamped P3.

Every parsed Look has an authoring space. Its table is interpolated in that space
(`CIColorCubeWithColorSpace.inputColorSpace`), independently of the canvas/export target, and the
space is part of the Look's content hash and of `LUTFilterCache` keys.

### Authoring-space header

A `.cube` file declares its authoring space with one comment line before the table:

```
# KROMORA_AUTHORING_SPACE: displayP3
```

- The key is exactly `KROMORA_AUTHORING_SPACE` (case-sensitive), followed by `:` and a value of
  `sRGB` or `displayP3` (case-sensitive). Surrounding whitespace is ignored.
- It is an ordinary `#` comment, so other tools ignore it. A comment that merely resembles it
  (different case or key) is just a comment.
- A file with no header is interpreted as **sRGB**. That is a documented import assumption, not
  knowledge of the author's intent.
- An unknown value, a missing value or colon, a key with a suffix (`KROMORA_AUTHORING_SPACE_X`), a
  duplicate declaration, or a declaration after table data fails parsing with an error.
- Kromora writes the header on every cube it saves (Save as Look/LUT and derived scratch/saved files).

Imported Looks are never rewritten or re-fit; embedded package copies keep their exact bytes and
header.

### Bounded gamut of sRGB Looks

An sRGB-authored cube has a bounded `[0, 1]` sRGB domain. Applied in a Display P3 editor it keeps
its sRGB meaning, but colors outside the sRGB gamut are clamped into that domain by the table, so an
sRGB Look is not a gamut-preserving P3 Look. Correct interpretation preserves the Look's intended
effect, not every wide-gamut input color.

### P3 starter assets

`Sources/KromoraKit/Resources/StarterLooks` holds the active Display P3 set of the 13 resampled starter Looks plus the directly authored slide family
(stable ids, names and categories, all stamped `displayP3`). The sRGB originals, the defined source
parameters, are kept outside the bundle in `scripts/starter-looks-srgb`.

They are regenerated, not retagged, by `swift scripts/generate-p3-starter-looks.swift generate`
(run from the repository root; the output is deterministic): each Look's sRGB control lattice is
resampled onto a 17³ Display P3 lattice through an explicit sRGB↔P3 conversion (with bounded linear
extrapolation outside the sRGB domain) and stamped `displayP3`.
`swift scripts/generate-p3-starter-looks.swift review <out.png>` renders an A/B contact sheet
(neutral ramp, primaries/secondaries, skin, sky, foliage) of each sRGB source versus its P3
counterpart and prints the maximum 8-bit difference.

Visual review (2026-10-25, recorded in each manifest entry's `approval`, record
`KRMA-1121-P3-STARTER-2026-10-25`): neutrals agree within 4/255 for every Look (asserted by
`BundledP3LookTests` against the sRGB sources); in-gamut colors match closely, while fully
saturated primaries differ most (up to about 18/255, in Warm Slide, Evening Cinema, Muted Film and
Honey Negative) because the P3 lattice samples a nonlinear conversion. The slide-family generator below
emits and stamps the same authoring space.

### Slide family generator (KRMA-1103)

`Tests/KromoraKitTests/SlideLookGenerator.swift` is a test-target tool that turns a
`SlideLookParameters` value into a 33³ `.cube`, byte-for-byte reproducible (fixed `%.6f` formatting, no
timestamps). Parameters: `toneCurve` (toe, slope, shoulder; strictly monotonic and per channel, so
the neutral axis stays neutral and mid gray is unchanged), `globalSaturation`, 12 `hueSectors`
(saturation multiplier and hue shift in degrees, smoothly and periodically interpolated),
`chromeDepth` (luminance reduction proportional to saturation, warm and blue strengths),
`shadowTint` / `highlightTint` (luma-held split tone) and `skinGuard` (removes that fraction of the
hue, saturation and chrome change in the skin-hue range).

The generator takes the authoring space (`WorkingSpace`, Display P3 by default) and an encoding
(`sRGBTransfer`, the default, or `hlg` as the extended-range HDR option). It stamps
`KROMORA_AUTHORING_SPACE` and `KROMORA_ENCODING` into the cube header, so the family can be
regenerated for another space instead of redesigned. Cube inputs stay in 0...1; colors outside the
authoring gamut are not represented. Parameters are expressed directly in P3, not converted from
sRGB tables. Cube interpolation uses the stamped authoring space (checked against `CubeLUT` and
`RenderPipeline`: `WorkingSpace.current` is Display P3, and a cube is applied in its own stamp),
independent of the canvas/export target.

Regenerate the bundled cube with
`KROMORA_WRITE_SLIDE_LOOKS=1 swift test --filter SlideLookGeneratorTests/testBundledCleanSlideMatchesTheGenerator`;
without the variable that test fails if the file is stale. The manifest entry is maintained by hand and
`scripts/generate-p3-starter-looks.swift generate` carries it forward. Parameter values are best-guess
approximations of public qualitative descriptions (`FILM_SIMULATION_LOOKS_RESEARCH.md`); there is no
reference to verify against, and tests check structure only (monotonic tone, neutrals, no clipping,
ordering), never a camera or tolerance.

First Look: **Clean Slide** (category "Slide"), gentle S-curve, slightly lifted reds, light chrome depth.
Bundle size impact: one 33³ text cube is about 970 KB (the 600 KB estimate was low), taking the starter
folder from about 1.7 MB to about 2.7 MB. Each further Look in the family adds roughly the same.

### Family structural tests (KRMA-1109)

`FilmLookStructureTests` (serial lane) covers every manifest entry whose source is `SlideLookGenerator`;
a new family Look must be added to its declarations table or the suite fails. It builds a synthetic
Display P3 chart in the test target (33-step gray ramp, a 12-hue sweep at three luminances, four
skin-hue patches, and saturated P3 primaries and secondaries beyond sRGB), renders it through each cube
in a P3 context to float output, and asserts structure only; no golden images, camera, or tolerance
against the research table. Asserted per Look:

- parses at 33³, is stamped `KROMORA_AUTHORING_SPACE: displayP3` exactly once, reports a `displayP3`
  authoring space, and records P3 authoring in its manifest notes (an unstamped or sRGB cube does not);
- the gray ramp is strictly monotonic;
- the neutral axis behaves as declared (`neutral`: R = G = B; `monochrome`: zero chroma on every patch;
  `toned`: ordered, tint allowed);
- no clipping: interior channels are not pinned to 0 or 1 (monochrome Looks are checked by luminance),
  and the gamut-edge patches stay distinct unless a monochrome Look intentionally maps them to gray;
- skin-hue patches stay within the declared chroma and hue-shift limit (the skinGuard limit);
- relative ordering between Looks (saturation and contrast) comes from one table in the test; rows
  are skipped until both Looks ship;
- no Fujifilm or film-stock trademark (word-boundary match) in any bundled Look name, manifest entry,
  bundled cube text, or the Look inspector and save-sheet source strings.

The suite shares one Display P3 `CIContext` across chart renders within each test, since context setup
is comparatively expensive and these structural checks run in the serial Core Image lane.

### Save as Look and Derive

Save as Look and Derive sample or fit in one explicit authoring space and stamp it:
`LookLUTConverter.convert(space:)`, `LookSaveCoordinator(authoringSpace:)`, and
`RecipeExtractor.Options.authoringSpace` / `DeriveCoordinator(authoringSpace:)`. The default is
`WorkingSpace.current`, which is Display P3; the neutral RAW baseline, JPG, edge mask and
measurement buffers of Derive are all color-matched into the chosen space, and the result is stamped
with it. Looks saved by a prerelease sRGB build keep their `sRGB` stamp (or none, which means sRGB)
and are still interpreted as sRGB Looks; they are not rewritten. Prerelease libraries and edits may
be reset instead of migrated (see the engineering guide); source originals and imported files are
not deleted by this policy.

## Save and derive

Save as Look/LUT exports the supported global portion of the current value document as a 33³ cube
in the chosen authoring space (Display P3 by default). The confirmation sheet names omitted source-dependent or
spatial stages, including RAW develop, crop/rotation, masking, Texture, Clarity, Dehaze, vignette,
and grain; the output does not claim pixel-identical reproduction of those stages.

Derive Look from JPG renders the RAW through the editor's neutral RAW baseline, validates the pair,
aligns the images, removes edge samples, and writes a smoothed 33³ cube. The derived result is a
scratch Look until the user saves it.

## Starter library and storage

The bundled library contains 13 original procedural cubes:

| Category | Look |
| --- | --- |
| Monochrome | Soft Mono |
| Monochrome | Silver Noir |
| Monochrome | Paper Grain |
| Monochrome | Blueprint Mono |
| Monochrome | Infrared Mono |
| Cinematic | Evening Cinema |
| Cinematic | Ember & Cyan |
| Film-inspired | Muted Film |
| Film-inspired | Honey Negative |
| Warm slide-inspired | Warm Slide |
| Pastel | Pastel Wash |
| Faded | Bleached Daylight |
| High-contrast | Hard Light |

These are intentionally distinct starting points rather than minor intensity variants. The
monochrome entries use different luminance curves, while the color entries cover cinematic
orange-and-teal, warm natural negative-film-inspired, pastel, faded, and high-contrast directions.

Their machine-readable provenance, licensing, redistribution terms, and approval metadata live
beside the assets in the bundled manifest; the package and tests fail closed for missing or
malformed approved entries. Film and manufacturer references are descriptive inspiration only:
Kromora does not bundle official camera profiles or copied commercial emulation data. The
acknowledgement shown in the Look inspector is sourced from that manifest.

Bundled Looks are read-only and visually marked as Starter Looks. Imported and saved Looks remain
user-owned and use the visible default folder `~/Pictures/Kromora Looks` unless the user chooses
another destination. Embedded Look bytes in a package edit revision remain the durable render
dependency; the browser file is only a reusable user-facing copy.

The selected Look is persisted by stable `LUTID`. A missing file leaves the edit reference intact
and renders without the unresolved LUT until it can be resolved again.
