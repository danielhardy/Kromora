# Looks and LUTs

Kromora's Look workflow supports text-based 3D LUTs, derives Looks from a RAW/JPG pair, and ships
13 read-only starter Looks. The parser and renderer are implemented in `CubeLUT`, `LUTLibrary`,
and `RenderPipeline`; this document records the supported interchange contract.

## File support

`.cube` files and plain-text `.look` files use the same 3D cube grammar. Proprietary binary or XML
Adobe `.look` packages are rejected rather than guessed at. Kromora accepts 3D tables declared by
`LUT_3D_SIZE` with 2–65 samples per axis, common `TITLE`, `DOMAIN_MIN`, and `DOMAIN_MAX` metadata,
comments, UTF-8 BOMs, CRLF endings, trailing comments, and the common
`LUT_3D_INPUT_RANGE min max` spelling.

The parser rejects 1D or mixed tables, reversed domains, non-finite values, malformed or missing
rows, truncated files, and dimensions outside 2–65. LUT application uses Core Image's
GPU-backed `CIColorCubeWithColorSpace`.

## Save and derive

Save as Look/LUT exports the supported global portion of the current value document as a 33³ cube
in the current working color space. The confirmation sheet names omitted source-dependent or
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
