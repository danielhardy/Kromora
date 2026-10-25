---
id: ADR-KRMA-1115
title: Display P3 policy - matching preview and export, Look authoring space, prerelease reset
date: 2026-10-25T04:30:00.000Z
status: accepted
---

## Status

Accepted by the product owner on 2026-10-25 in the KRMA-1115 discussion: Display P3 preview and
rendered delivery, explicit Look authoring spaces, and no compatibility requirement for prerelease
libraries. This supersedes the initial proposal for sRGB-default exports and unchanged saved edits.
KRMA-1115 records policy only; the dependent tickets implement it.

## Context

Epic KRMA-1114 moves the editor from sRGB to Display P3. Until KRMA-1121 activates the migration,
`WorkingSpace.current` stays `.sRGB` and preparation tickets preserve current shipping output.
Input profiles, calculation space, Look authoring space, and preview/export encoding are distinct
contracts. A RAW decoder's developed P3 image is not evidence of an embedded P3 source profile.
Packages own originals, edit revisions, and embedded Look bytes.

## Decision 1: Matching preview and export

**Chosen.** Use Display P3 for the editing preview and every rendered delivery after KRMA-1121.
The app uses one preview/export target, rather than choosing it dynamically from each source.

- JPEG, HEIC/HEIF, TIFF, and PNG exports embed the ICC profile matching their encoded pixels.
  There is no independent sRGB/P3 export picker or remembered export-only color-space preference.
- Share, Copy, and Photos delivery use the same Display P3 target as the editing canvas.
- Edit in External Editor uses Display P3, retaining the existing 16-bit TIFF handoff.
- Original-plus-settings bundles preserve original bytes and their profiles. Any rendered companion
  uses the same Display P3 target as the canvas; the original is not a rendered export.
- Decode tagged inputs using their embedded profiles, then color-match into the render pipeline.
  An sRGB input does not become more saturated merely because it is represented in P3. RAW inputs
  are developed into the chosen pipeline rather than assigned an output space from a preview tag.
- Before the final flip, all normal preview/delivery paths remain sRGB. Preparation tests exercise
  explicit P3 targets without exposing a mismatched export mode.
- A future sRGB delivery mode must include a matching preview before export. It is out of scope
  for this migration, along with HDR/EDR and soft proofing.

**Rejected.**

- P3 editing with sRGB-default exports or Share/Copy exceptions: can discard colors the user saw
  while editing, violating the chosen preview/delivery contract.
- An independent per-export color-space choice without a matching preview: has the same mismatch.
- Dynamic working/output space per source: adds per-photo policy and undefined choices for RAW,
  untagged images, and other profiles without being necessary for consistent preview/export.
- Retagging source pixels as P3 without conversion: changes their interpreted colors.

## Decision 2: Look authoring space

**Chosen.** Each parsed cube has an explicit authoring space. Interpolate its table in that space
(`CIColorCubeWithColorSpace.inputColorSpace`), then continue through the app pipeline. Applying an
sRGB Look does not change the canvas or export target to sRGB.

- Recognize an optional authoring-space comment header in `.cube` files. A missing header means
  sRGB, a documented import assumption rather than inferred knowledge of the author's intent.
  An unrecognized or malformed declared value is a clear parse error.
- Regenerate Kromora's bundled starter Looks for P3 and review their appearance. Generate from
  defined source procedures and parameters; changing only a header is not regeneration. Keep
  provenance and manifest notes accurate. The film-Look generator (KRMA-1103 family) also targets
  and stamps P3 for the P3 release.
- New Save as Look and Derive results are sampled/fitted and stamped in P3 after the flip. During
  preparation they remain sampled and stamped in sRGB; Derive's baseline, measurement buffers, fit,
  and application must use the same authoring space. Do not just relabel an sRGB fit as P3.
- Imported Looks honor a recognized stamp, or assume sRGB when unstamped. Do not automatically
  rewrite or re-fit user-owned imported files. Embedded copies retain their exact bytes and header.
- Include authoring space in filter identity and cache keys. Look metadata is automatic; no new
  user-facing authoring-space setting is required.
- An sRGB cube's bounded [0, 1] domain can constrain wide-gamut colors. Correct interpretation does
  not make it a gamut-preserving P3 Look. Wide-gamut preservation tests use neutral/P3 transforms
  and do not promise that every creative Look preserves every input color.

**Rejected.**

- Interpret every table in the app's current space: applies different color meanings to imported
  Look values and can change their intended effect.
- Convert/re-fit all imports to P3: can be lossy and needlessly rewrites user-owned assets.
- Author everything in sRGB: unnecessarily constrains new Kromora Looks and derived fits.
- Preserve all bundled prerelease bytes or appearances: there is no released-library compatibility
  requirement; regenerate our own assets for the selected space.

## Decision 3: Prerelease library compatibility

**Chosen.** Existing prerelease libraries and saved edits need not retain appearance or remain
compatible. They may be reset if that simplifies the implementation. This decision does not itself
delete any library or original; implementation must document when a reset is required.

- Do not add a legacy sRGB renderer, old-package appearance guarantee, or migration solely to
  preserve prerelease edits. Regenerate fixtures for the new contract as needed.
- The edit document does not store a last-rendered color space: preview/export space is app policy.
  Cache and frame identity still include space, and the flip must invalidate stale rendered data
  through the established pixel epoch/cache identity mechanism.
- Imported-file interpretation and correct new-package/embedded-Look round trips remain required.
  Removing prerelease compatibility is not permission to corrupt originals or rewrite imports.
- This is a prerelease decision, not a policy for changing released customer libraries in future.

**Rejected.**

- Require pixel-identical rendering of every old library: adds compatibility constraints without
  released customers who need them.
- Persist the previous render space or maintain dual renderers solely for old edits: unnecessary
  persisted state and code under the agreed reset policy.

## Dependent tickets

- KRMA-1114 (epic): replace open questions and old-edit parity with this accepted release contract.
- KRMA-1116 (identity): unchanged; render, cache, and frame identity still distinguish spaces.
- KRMA-1117 (Looks): authoring-space parsing/application plus reproducible P3 bundled assets and
  visual review; prepare P3 Save/Derive fitting, then activate with KRMA-1121.
- KRMA-1118 (export): one preview/export target for all delivery paths; no independent export picker
  or fixed-sRGB Share/Copy/Photos exceptions. Test ICC tagging in every supported format.
- KRMA-1119 (preview): maintain canvas/thumbnail/histogram agreement and preview/export parity.
- KRMA-1120 (Auto): unchanged; fixed measurement space or documented recalibration remains valid
  numerical analysis and is not an sRGB export policy or an old-library compatibility promise.
- KRMA-1121 (flip): activate P3 canvas, all rendered delivery, P3 bundled Looks and Save/Derive;
  replace old-package appearance tests with new-contract parity, wide-gamut and package tests;
  invalidate stale caches and document any required prerelease library reset.
- KRMA-1103 (film-Look generator): emit/stamp the selected authoring space; P3 release cubes are P3,
  with no requirement to preserve earlier sRGB generated assets.
