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

## Who it is for

Kromora is for individual photographers who want a focused, local-first Mac workflow for organizing
a personal or small working library that grows over time, developing RAW and standard still images,
and producing finished files. It values native Mac interaction, non-destructive editing, predictable
output, and clear ownership of originals and edits. It is not a Lightroom replacement and does not
aim for full Lightroom feature parity; competitor gap lists do not define its roadmap.

## The workflow today

1. Create or open a `.kromoralibrary` and import still images from files, folders, Photos, or
   supported mounted removable media. Imports copy accepted originals into the package.
2. Browse a virtualized Library, select several photos, and cull with picks, rejects, star ratings,
   and filters, including an advanced sidebar with camera, lens, focal length, ISO, aperture,
   capture-date, and coarse on-device location facets plus a one-action clear. Removing a managed photo sends it to package trash; referenced import sources are
   left alone.
3. Edit non-destructively. Kromora stores value-based edit documents and uses one render pipeline
   for previews and full-resolution output.
4. Export an edited photo or a batch to TIFF, JPEG, PNG, or HEIF. The save accessory
   exposes the format, metadata and GPS inclusion (GPS is excluded by default), optional delivery to
   Photos, and output sharpening. Sizing, color space, bit depth, and alpha exist on the export
   value model but are not yet panel controls.

For package ownership and data safety, including how to move or back up a library by copy, see
[`docs/STORAGE_POLICY.md`](docs/STORAGE_POLICY.md). The release bar is in
[`docs/TESTING.md`](docs/TESTING.md#release-bar).

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
  copy edits, use history and named snapshots, and create virtual copies. Each virtual copy stores
  its own full copy of the original, so the original's size is added to the library per copy.
  Package trash and recovery are available. To move or back up a library, quit Kromora and copy the
  package; Settings > Choose Library… opens a copy (see
  [`docs/STORAGE_POLICY.md`](docs/STORAGE_POLICY.md)).
- **Onboarding and export handoff:** sample photos and a short workflow tour are available. A
  rendered TIFF can be handed to an external editor and reimported as a separate library photo;
  this is a rendered-file handoff, not a live layered round trip.

See [`docs/ONBOARDING.md`](docs/ONBOARDING.md), [`docs/LOOKS.md`](docs/LOOKS.md),
[`docs/INTEROP_EXPORT.md`](docs/INTEROP_EXPORT.md), and the
[documentation map](docs/DOCUMENTATION_AUDIT.md) for detail.

## Important limits

- Kromora is a still-photo editor. It does not provide video editing, tethered capture, cloud sync
  or shared multi-user libraries, Lightroom catalog migration or XMP develop compatibility, or broad
  metadata round-tripping. Package portability is by manual copy.
- There is no in-app verified backup/restore and no Finder double-click handler for library
  packages. `PortableLibraryBackup` and `PortableLibraryRestore` remain in the tree, tested but
  unwired; the supported path is quit-and-copy.
- Proofing, print, and HDR display/export workflows are not provided. Export offers only the basic
  output-sharpening choice (screen, matte, or glossy at low, standard, or high). Embedded depth data
  is not universally supported.
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
Reconsider one only through a new product decision with a concrete user need.

## Build, run, and verify

Kromora is a Swift Package; the package has no third-party dependencies.

```bash
swift build
swift run
swift test
```

Requirements: macOS 26 (Tahoe) or newer on Apple Silicon to run, Xcode 27 or newer with the macOS 27
SDK to build, and Swift 6 language mode. `swift run` is useful for iteration but does not include
the production app's asset catalog or App Sandbox entitlements. Open
[`Xcode/Kromora.xcodeproj`](Xcode/Kromora.xcodeproj) in Xcode and run the **Kromora** scheme to
exercise the packaged app.

CI's required verification lanes are `scripts/ci-tests.sh fast` and
`scripts/ci-tests.sh serial`. `scripts/ci-tests.sh optional` includes licensed-RAW, hardware, and
benchmark checks that require local inputs or a logged-in display. See
[`docs/TESTING.md`](docs/TESTING.md) for the release bar, lane definitions, and limits, and
[`docs/PACKAGING.md`](docs/PACKAGING.md) for the signed app workflow.

## Distribution

The Mac app is distributed through the App Store, with prerelease builds tested through TestFlight.
Developers can build from source with SwiftPM; Xcode creates the signed production app and archive.
See [`docs/PACKAGING.md`](docs/PACKAGING.md) for the release workflow, signing requirements, and
App Store Connect preparation.

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

- [Documentation map](docs/DOCUMENTATION_AUDIT.md) — every guide, its role, and which are historical.
- [Architecture and engineering](docs/APP_ARCHITECTURE.md), [engineering guide](docs/ENGINEERING_GUIDE.md),
  [storage policy](docs/STORAGE_POLICY.md), and [testing](docs/TESTING.md) — current technical contracts.
- [Looks](docs/LOOKS.md), [Auto policy](docs/AUTO_EXPOSURE_POLICY.md),
  [comparison](docs/COMPARISON_MODE.md), and [retouch](docs/RETOUCH.md) — current feature details.
- [Historical package design](docs/LIBRARY_PACKAGE_PLAN.md) retains provenance and is not a live plan.

## Fork and attribution

Kromora began as a fork of [LUTzy](https://github.com/tsvb/lutzy), an MIT-licensed macOS LUT
color-grading app. The original copyright notice and [MIT License](LICENSE) are retained. LUTzy
provided an initial foundation for `.cube` parsing/application, RAW decoding, import/export, Look
derivation, and tests; the current package-backed product is Kromora's own.
