# Product scope

This is the current product-intent source for Kromora. It describes the MVP being prepared for
release, not a list of every capability in the source tree. Current UI behavior is summarized in
the [README](../README.md); technical contracts belong in the linked guides below.

## Audience and purpose

Kromora is for individual photographers who want a focused, local-first Mac workflow for working
through still-photo sets, making substantial RAW and image adjustments, and exporting finished
files. It is suited to a personal or small working library, including a library that grows over
time. The product values native Mac interaction, non-destructive editing, predictable output, and
clear ownership of originals and edits.

Kromora is not aiming for full Lightroom feature parity. Lightroom and other editors may be useful
reference points, but competitor gap lists do not define the Kromora roadmap.

## MVP workflow

The product's core loop is:

1. Create or open a portable library package and import still images from files, folders, Photos,
   or supported removable media.
2. Browse, select, rate, flag, filter, and remove photos from the library.
3. Develop a photo non-destructively with RAW controls, global tone/color/effects, crop/rotation,
   Looks, local masks, Auto, and small-defect retouch.
4. Review edits, copy them between photos, and export one image or a batch at full source quality
   or with supported output sizing.
5. Reopen the library with its edits and package-owned originals intact; use package backup/restore
   when moving or recovering the library.

The package is the production library mode. Folder, Photos, and removable-volume choices are import
sources that copy accepted images into the package. The app does not maintain a live folder-backed
catalog. See [application boundaries](APP_ARCHITECTURE.md) and the
[storage policy](STORAGE_POLICY.md).

## Release bar

The MVP is ready for release when the ordinary Library → Edit → Export loop is dependable and the
following properties hold:

- Imports and exports report partial failures honestly, preserve the user's source files, and
  leave recoverable package state after interrupted operations.
- Edits survive navigation, relaunch, undo/redo, and package backup/restore. A corrupt or unsupported
  edit is reported instead of silently replaced with a blank edit.
- Preview and full-resolution export use one ordered rendering pipeline; supported crop, masks,
  Looks, and retouch recipes stay aligned across both.
- Library membership and canonical data live in the package. Indexes, previews, thumbnails, masks,
  and analysis caches are disposable and can be rebuilt.
- Required deterministic/model and serial render/UI verification lanes pass on the supported
  toolchain. Hardware and licensed-camera checks are reported separately when their environment is
  unavailable; skipped work is not described as a pass.
- Distribution follows the signed-app and entitlement process in [Packaging](PACKAGING.md).

See [Testing](TESTING.md) for the commands, lane definitions, and limits. Performance numbers in
the dated diagnostics are evidence for their recorded machines and methods, not universal release
claims.

## Current scope and limits

The MVP includes package-backed library membership, local imports, culling, image metadata and
histogram inspection, non-destructive edits, comparison, copy/paste, edit history and named
snapshots, virtual copies, verified package backup/restore, reusable `.cube` Looks, and full-resolution
single/batch export. Editing includes decoder-supported RAW development, global Light/Color/Effects,
crop and rotation, local mask composition and adjustments, content-aware Auto, and Heal/Clone
retouch. Exact format options vary with the source, encoder, and macOS capabilities.

Retouch targets small defects. Dust detection presents suggestions; it is not a guaranteed cleanup
pass. See [Retouch recipes and quality evidence](RETOUCH.md). Auto is renderer-evaluated and may
leave a photo unchanged. See [Auto policy](AUTO_EXPOSURE_POLICY.md).

## Post-MVP boundaries

These are explicit boundaries, not promised roadmap items. Reconsider them only through a new
product decision with a concrete user need:

- Full Lightroom-style digital-asset-management breadth, catalog migration, and broad metadata
  round-tripping.
- Cloud sync or shared multi-user libraries; package portability and local backup are the current
  model.
- Tethered capture, video editing, generative large-object removal, or universal embedded-depth
  support.
- Comprehensive proofing, print, HDR display/export, and output-sharpening workflows.
- Every camera maker's proprietary controls, profiles, or pixel-matched output relative to another
  editor.

The [2026-09-22 professional-polish evaluation](../.context/2026-09-22-professional-polish-evaluation.md)
retains competitor-gap analysis and the original proposal specifications for possible future
reconsideration. It is an idea archive, not a roadmap or release commitment. The
[initial concept](../.context/initial_concept.md) is historical provenance and does not define the
current MVP.

## Documentation authority

For current product intent, use this page. For current behavior, start with the README and feature
guides. For implementation ownership and durable constraints, use [APP_ARCHITECTURE.md](APP_ARCHITECTURE.md),
[ENGINEERING_GUIDE.md](ENGINEERING_GUIDE.md), and [STORAGE_POLICY.md](STORAGE_POLICY.md). Historical
plans, dated evaluations, issue records, and deferred proposals must retain their provenance and
must not be read as current commitments. See the [documentation audit](DOCUMENTATION_AUDIT.md) for
the inventory and disposition.
