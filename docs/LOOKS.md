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

## P3 release authoring policy

[ADR-KRMA-1115](../.dg/decisions/ADR-KRMA-1115-display-p3-export-look-and-saved-edit-policy.md)
was accepted on 2026-10-25. This is the implementation target for KRMA-1117/KRMA-1121; current
shipping output stays sRGB until the final flip.

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

`Sources/KromoraKit/Resources/StarterLooksP3` holds a prepared, **inactive** Display P3 set of the
13 starter Looks (same ids, names and categories; `BundledLookLibrary.preparedP3ResourceSubdirectory`).
KRMA-1121 activates it. The active set in `StarterLooks` is unchanged by preparation.

They are regenerated, not retagged, by `scripts/generate-p3-starter-looks.swift generate`: each
Look's sRGB control lattice is the defined source parameter, resampled onto a 17³ Display P3 lattice
through an explicit sRGB↔P3 conversion (with bounded linear extrapolation outside the sRGB domain),
and stamped `displayP3`. `scripts/generate-p3-starter-looks.swift review <out.png>` renders an A/B
contact sheet (neutral ramp, primaries/secondaries, skin, sky, foliage) of the sRGB Look versus its
P3 counterpart and prints the maximum 8-bit difference. Visual review (2026-10-25): neutrals agree
within 4/255 for every Look (asserted by `BundledP3LookTests`); in-gamut colors match closely, while
fully saturated primaries differ most (up to about 18/255, in Warm Slide, Evening Cinema, Muted Film
and Honey Negative) because the P3 lattice samples a nonlinear conversion. The film-Look generator
(KRMA-1103) should emit and stamp the same authoring space.

### Save as Look and Derive

Save as Look and Derive sample or fit in one explicit authoring space and stamp it:
`LookLUTConverter.convert(space:)`, `LookSaveCoordinator(authoringSpace:)`, and
`RecipeExtractor.Options.authoringSpace` / `DeriveCoordinator(authoringSpace:)`. The default is
`WorkingSpace.current`, still sRGB during preparation; the neutral RAW baseline, JPG, edge mask and
measurement buffers of Derive are all color-matched into the chosen space, and the result is stamped
with it. The flip changes only the default. Existing prerelease libraries and edits may be reset
instead of migrated; source originals and imported files are not deleted by this policy.

## Save and derive

Save as Look/LUT exports the supported global portion of the current value document as a 33³ cube
in the chosen authoring space (sRGB until the P3 flip). The confirmation sheet names omitted source-dependent or
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
