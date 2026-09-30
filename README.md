<div align="center">

# Kromora

### A focused, native RAW photo workflow for macOS.

Browse a small or growing photo library, make non-destructive global and local edits, and export
finished images. Kromora uses SwiftUI, Core Image, Metal, AppKit, and other Apple frameworks, with
no third-party runtime dependencies.

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B%20Apple%20Silicon-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![Dependencies](https://img.shields.io/badge/runtime%20dependencies-none-brightgreen)

</div>

---

## Product scope

Kromora is for photographers who want a focused Mac workflow for organizing a working library,
developing RAW and standard still images, and producing finished files. Its MVP is a reliable
Library → Edit → Export loop with useful culling, flexible image work, and safe local ownership of
photos and edits. It is not a Lightroom replacement and does not aim for full Lightroom feature
parity.

The current intent, intended user, release bar, and post-MVP boundaries are in
[`docs/PRODUCT_SCOPE.md`](docs/PRODUCT_SCOPE.md). That page is the product-scope source of truth;
this README summarizes the running app. Deferred proposals remain recoverable in the
[professional-polish evaluation](.context/2026-09-22-professional-polish-evaluation.md) and are not
MVP commitments.

## The workflow today

1. Create or open a `.kromoralibrary` and import still images from files, folders, Photos, or
   supported mounted removable media. Imports copy accepted originals into the package.
2. Browse a virtualized Library, select several photos, and cull with picks, rejects, star ratings,
   and filters. Removing a managed photo sends it to package trash; referenced import sources are
   left alone.
3. Edit non-destructively. Kromora stores value-based edit documents and uses one render pipeline
   for previews and full-resolution output.
4. Export an edited photo or a batch to TIFF, JPEG, PNG, or HEIF. Choose supported sizing, color,
   bit-depth, alpha, and metadata options; GPS is excluded by default.

For the current release bar and explicit exclusions, see the
[MVP scope](docs/PRODUCT_SCOPE.md). For package ownership, backup, restore, and data safety, see
[`docs/STORAGE_POLICY.md`](docs/STORAGE_POLICY.md).

## Current capabilities

- **RAW and still-image development:** Core Image RAW decoding with per-file decoder controls,
  plus Light, Color, tone curves, HSL, color grading, effects, crop, rotation, and orientation-aware
  edits. Decoder-dependent controls appear only when supported by the source.
- **Local work:** brush, erase, linear and radial gradients, semantic and range masks, compositing
  operations, and regional adjustments. Heal and Clone retouch are available for local defects;
  automatic dust detection is a suggestion tool and can miss defects. See
  [`docs/RETOUCH.md`](docs/RETOUCH.md) for measured limits.
- **Content-aware Auto:** analyzes a photo, evaluates candidates through the renderer, and applies
  an undoable result with provenance. It can make no change when candidates do not pass its
  guardrails.
- **Looks:** import and organize `.cube` LUTs, use the bundled starter Looks, derive a Look from a
  RAW/JPG pair, and save it for reuse. Film-inspired names describe the look; they do not claim
  camera-profile or commercial-film emulation.
- **Review and recovery:** compare single and side-by-side views, inspect histogram and metadata,
  copy edits, use history and named snapshots, and create virtual copies. The package includes
  verified backup/restore and package trash/recovery.
- **Onboarding and export handoff:** sample photos and a short workflow tour are available. A
  rendered TIFF can be handed to an external editor and reimported as a separate library photo;
  this is a rendered-file handoff, not a live layered round trip.

See [`docs/ONBOARDING.md`](docs/ONBOARDING.md), [`docs/LOOKS.md`](docs/LOOKS.md),
[`docs/INTEROP_EXPORT.md`](docs/INTEROP_EXPORT.md), and the
[documentation map](docs/DOCUMENTATION_AUDIT.md) for detail.

## Important limits

- Kromora is a still-photo editor. It does not provide video editing, tethered capture, a cloud
  catalog, or Lightroom catalog/XMP develop compatibility.
- The library package is the sole production library mode. Folder, Photos, and removable media are
  import sources; Kromora copies accepted files into the package. This is not a live view of an
  external folder.
- Retouch is aimed at small defects. Automatic dust suggestions are conservative and can miss most
  defects; inspect them and use the brush when needed. Large-object generative removal is outside
  scope.
- Decoder and output capabilities vary by format and macOS codecs. Kromora does not promise pixel
  matching with another RAW processor or universal camera-feature parity.
- The app requires Xcode 27+ to build and macOS 26 (Tahoe) or newer on Apple Silicon to run.

These boundaries are product choices and current constraints, not a competitor parity checklist.
The deferred idea archive is not an active roadmap.

## Build, run, and verify

Kromora is a Swift Package; the package has no third-party dependencies.

```bash
swift build
swift run
swift test
```

Requirements: macOS 26 (Tahoe) or newer on Apple Silicon to run, Xcode 27 or newer with the macOS 27
SDK to build, and Swift 6 language mode. `swift run` is useful for iteration but does not include the packaged app's asset
catalog or App Sandbox entitlements. Open `Package.swift` in Xcode and run the **Kromora** scheme to
exercise bundled-app behavior.

CI's required verification lanes are `scripts/ci-tests.sh fast` and
`scripts/ci-tests.sh serial`. `scripts/ci-tests.sh optional` includes licensed-RAW, hardware, and
benchmark checks that require local inputs or a logged-in display. See
[`docs/TESTING.md`](docs/TESTING.md) for lane definitions and limits, and
[`docs/PACKAGING.md`](docs/PACKAGING.md) for the signed app workflow.

## Architecture and storage

`KromoraKit` contains the app's models, workflows, render engine, and views; `Kromora` is the thin
executable. The edit document is value data, Core Image and Metal resources stay inside the render
engine, and preview and export share the same ordered render pipeline. The codebase uses Swift 6
language mode without concurrency escape hatches.

The portable library package owns membership, imported originals, metadata, edit revisions, and
embedded Look data. Local indexes and caches are rebuildable projections. Existing standalone
`EditStore*.store` files remain untouched and are never opened as a library fallback. Current
ownership and coordinator boundaries are in [`docs/APP_ARCHITECTURE.md`](docs/APP_ARCHITECTURE.md);
rendering and contributor invariants are in [`docs/ENGINEERING_GUIDE.md`](docs/ENGINEERING_GUIDE.md);
durable storage rules are in [`docs/STORAGE_POLICY.md`](docs/STORAGE_POLICY.md).

## Documentation

- [Product scope](docs/PRODUCT_SCOPE.md) — MVP intent, audience, release bar, and post-MVP boundaries.
- [Documentation audit](docs/DOCUMENTATION_AUDIT.md) — current guides, historical records, and deferred ideas.
- [Architecture and engineering](docs/APP_ARCHITECTURE.md), [engineering guide](docs/ENGINEERING_GUIDE.md),
  [storage policy](docs/STORAGE_POLICY.md), and [testing](docs/TESTING.md) — current technical contracts.
- [Looks](docs/LOOKS.md), [Auto policy](docs/AUTO_EXPOSURE_POLICY.md),
  [comparison](docs/COMPARISON_MODE.md), and [retouch](docs/RETOUCH.md) — current feature details.
- [Historical package design](docs/LIBRARY_PACKAGE_PLAN.md) and
  [deferred professional-polish proposals](.context/2026-09-22-professional-polish-evaluation.md)
  retain provenance and are not live plans.

## Fork and attribution

Kromora began as a fork of [LUTzy](https://github.com/tsvb/lutzy), an MIT-licensed macOS LUT
color-grading app. The original copyright notice and [MIT License](LICENSE) are retained. LUTzy
provided an initial foundation for `.cube` parsing/application, RAW decoding, import/export, Look
derivation, and tests; the current package-backed product is Kromora's own.
