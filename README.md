<div align="center">

# Kromora

### A native macOS RAW photo editor — develop, grade, and export on Apple's own stack.

Kromora is a fast, non-destructive photo workflow for RAW and standard images. It is built with
SwiftUI, Core Image, Metal, AppKit, PhotosUI, Swift Charts, ImageIO, and `simd` — with **zero
third-party dependencies**.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20Core%20Image-9cf)
![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)
![GPU](https://img.shields.io/badge/rendering-Metal--accelerated-success)

</div>

---

## What is Kromora?

Kromora is a native macOS RAW editor organised around a real photo workflow:

1. **Import** a folder, individual image, drag-and-drop payload, or up to 50 Photos assets.
2. **Cull** in a grid-first Library workspace with picks, rejects, star ratings, filters, and
   multi-selection.
3. **Edit** each photo non-destructively through a shared value-based document and render pipeline.
4. **Compare** the edited result with a develop-applied baseline, or inspect it on a pannable,
   zoomable canvas.
5. **Export** the current photo or the whole collection at full source resolution.

Every edit is stored as data, never as a baked preview bitmap. Preview and export use the same
pipeline, so the image on screen and the image written to disk follow the same edit order.

The shipped product uses one portable, Pictures-backed library package for managed originals,
catalog metadata, edit revisions, embedded Looks, and recovery. The local index and device caches
are disposable projections; user-visible exports and reusable Looks default to visible Pictures
folders. The package, backup, restore, and storage-boundary contract is documented in
[`docs/STORAGE_POLICY.md`](docs/STORAGE_POLICY.md).

Kromora is also an agent-driven software project. Agents plan, claim, implement, verify, and advance
work through [DispatchGraph](.dg/README.md), making the development process part of the experiment.

## Fork and attribution

Kromora began as a fork of [LUTzy](https://github.com/tsvb/lutzy), an MIT-licensed macOS LUT
color-grading app. The original copyright notice and [MIT License](LICENSE) are retained. The fork
provided the initial `.cube` parsing/application, RAW decoding, folder/export plumbing, Look
derivation, and much of the original test foundation; the current product and package targets are
Kromora's own.

---

## Features

### Import and library workflow

- Native RAW/DNG decoding through Core Image's `CIRAWFilter`, plus JPEG, PNG, TIFF, BMP, and HEIC.
- RAW extensions: `DNG`, `CR2`, `CR3`, `NEF`, `ARW`, `ORF`, `RAF`, `RW2`, `PEF`, `SRW`, `X3F`, and
  `RAW`.
- Drag in a single image or a folder; choose a source folder (`⌘⌥I`) for recursive scanning,
  subfolder grouping, remembered folder access, and re-scan (`⌘R`).
- Streaming Photos import (`⌘⇧I`), capped at 50 selections, with cancellation and partial-failure
  handling so successful transfers remain usable.
- Grid-first Library workspace with a virtualized mosaic, async thumbnails, stable asset identities,
  multi-select, and double-click-to-edit navigation.
- Pick/reject flags, 0–5 star ratings, and combined culling filters for All, Picks, Rejected, and
  rating ranges.
- Delete selected library items with an explicit confirmation; managed originals move to the macOS
  Trash, referenced originals are left untouched, and edit records/derived thumbnails are removed.
- Edit workspace with a filmstrip, docked source browser, keyboard navigation, canvas pan/zoom,
  Fit/Fill, and resettable panel sections.

### Non-destructive editing

Each photo has a `Codable`, `Sendable`, `Equatable` `EditDocument`. Its current stages are:

- **RAW Develop** — decoder-native exposure, baseline exposure, shadow bias, tone curve, white
  balance, sharpness, contrast/detail, moiré and noise reduction, lens correction, gamut mapping,
  extended dynamic range, and highlight recovery. Controls are probed and shown only when the
  current decoder supports them; values start from that file's own defaults.
- **Light** — Exposure, Contrast, Highlights, Shadows, Whites, Blacks, and a master RGB tone curve.
- **Color** — RAW-aware white balance, Vibrance, Saturation, an eight-channel HSL mixer
  (Red/Orange/Yellow/Green/Aqua/Blue/Purple/Magenta), and three-way Shadows/Midtones/Highlights
  color grading with blending and balance.
- **Effects** — Texture, Clarity, Dehaze, post-crop Vignette (Amount, Midpoint, Roundness, Feather,
  Highlights), and deterministic film Grain (Amount, Size, Roughness).
- **Crop** — freeform, non-destructive framing in normalized oriented-image coordinates. Draft
  geometry is transient until Apply; preview and full-resolution export use the same crop.
- **Look** — an optional `.cube` 3D LUT with adjustable intensity.
- **Local masking** — ordered foreground/background, brush/erase, linear-gradient, radial-gradient,
  and smart-mask components with add, subtract, intersect, replace, invert, solo inspection, and
  non-destructive local adjustments. Brush samples are distance-resampled during the gesture and
  persisted as one compact undoable stroke; the same mask definition drives preview, overlay,
  histogram, comparison, copy/paste, and full-resolution export.
- **Auto and photo analysis** — cancellable Vision/Core Image analysis produces scene, tone, color,
  subject, and semantic-mask evidence. Content-aware Auto evaluates unchanged, native, Apple-reference,
  and reduced-strength candidates through the real renderer, rejects guardrail violations, and can
  add bounded Auto-owned regional layers. The accepted result is one editable, undoable document
  change with provenance; repeated runs can be no-ops.

Individual controls and whole sections can be reset. Slider gestures use an interactive render path
and become one undo entry when committed; numeric fields and resets use the settled path.

### Looks and LUTs

- Parses standard `.cube` 3D LUTs, including `LUT_3D_SIZE` and `DOMAIN_MIN`/`DOMAIN_MAX`.
- Applies LUTs through `CIColorCubeWithColorSpace` with Metal-backed Core Image rendering.
- Ships 13 original, read-only starter Looks across Monochrome, Cinematic, Film-inspired, Warm
  slide-inspired, Pastel, Faded, and High-contrast categories. Film-inspired
  names are descriptive only; no official camera profiles or commercial emulation data are bundled.
  Provenance, licensing, attribution, redistribution, and approval
  records live in [`docs/LOOKS.md`](docs/LOOKS.md) and the bundled manifest.
- Scans a Look folder recursively, groups files by subfolder, supports search and None, and keeps
  folder access through App Sandbox security-scoped bookmarks.
- Imports external `.cube` and `.look` files (`⌘⌥L`) and refreshes the library after files are
  replaced externally.
- Stores a stable Look reference in the edit document, so a rescan does not silently change the
  selected Look. Missing references are reported while the stored edit is preserved.

### Derive a Look from a JPG

Kromora can manufacture a portable `.cube` Look from a camera RAW and its straight-out-of-camera JPG.
Use `File ▸ Derive Look from JPG…` (`⌘D`) to choose the pair. Kromora renders the RAW through the
same neutral `CIRAWFilter` baseline used by the editor, validates the pair's aspect ratio, aligns
the images, masks JPEG edges, samples smooth regions, and builds a smoothed 33³ cube.

The report includes:

- Per-channel tone curves against identity.
- Saturation and measured sharpening ratios. Sharpening is reported but not baked into a LUT.
- Cube coverage and surviving sample count.
- Camera make/model and relevant JPEG EXIF picture-style fields.
- Alignment information and a Swift Charts visualization.

The derived Look previews immediately as a scratch result. **Save to Look Folder…** makes it a
library Look; the stable derived identity keeps the edit resolving across rescans.

### Compare, inspect, and export

- Kromora uses the always-both comparison model: when a meaningful before/after exists, the
  top-bar comparison control and `V` consistently switch between the primary side-by-side view
  and the alternate single-photo view. In single-photo view, hold `Space` to temporarily show the
  comparison baseline (the develop-applied photo without the visible Light/Color/Effects/Look
  edits); Space is inert in side-by-side view because both labeled surfaces are already visible.
  The selected single/side-by-side presentation is retained across photo switching and relaunch;
  the transient Space state clears when switching photos, resetting to identity, undoing/redoing to
  identity, or when no meaningful comparison remains. Side-by-side may remain selected after a
  reset or on an unedited photo, where both panes intentionally show the same source pixels. See
  [the comparison mode decision](docs/COMPARISON_MODE.md) for the complete interaction contract.
- Info inspector (`⌘I`) shows a live RGB/luma histogram and EXIF, TIFF, and GPS metadata.
- Export the edited document as 16-bit TIFF, JPEG, or PNG. The format is selected in the save flow
  and the last choice is retained for the session. The export panel explicitly controls camera
  metadata and location metadata separately: camera metadata is preserved by default, while GPS
  location is excluded by default as a privacy safeguard. Location is included only when selected.
- Single export (`⌘S`) and Export All (`⌘⇧E`) render from the original source at full resolution.
  Export All continues past individual failures and reports the completed/skipped counts.
- Output names include the photo name and selected Look, with collision-safe suffixes.

---

## Persistence and editing state

Edits are isolated per photo and survive navigation and relaunch. Kromora appends one versioned
JSON `EditDocument` per edit revision to the package asset's `Edits/` sidecar; the sidecar is
canonical and `EditDocumentStore` is a bounded in-memory cache, so cache eviction never discards
an edit. Writes are serialized and coalesced during slider activity. Existing standalone
`EditStore*.store` files are left untouched and are not opened as a fallback. Editing state also
supports:

- Up to 100 undo and redo snapshots per photo, containing only value-state documents.
- Copy/paste of all edits between photos, including destinations that were never opened.
- Per-revision corruption reporting without replacing the photo with an unmarked blank edit.
- Schema-version checks that refuse to decode documents written by a newer Kromora build.
- A termination flush so queued edits are durable before the app exits.

Source records use stable filesystem identities where available and cache fingerprints include file
metadata/content sampling. Photos imports use the Photos local identifier when supplied; data-only
imports use a SHA-256 identity for the delivered bytes.

## Keyboard shortcuts

| Key | Action |
|---|---|
| `G` | Switch to Library |
| `E` | Switch to Edit |
| `Return` | Open the active Library item in Edit |
| `P` | Mark the focused photo as Pick and advance |
| `X` | Mark the focused photo as Reject and advance |
| `U` | Clear the focused photo's flag and advance |
| `0`–`5` | Clear or set the focused photo's star rating |
| `←` / `→` or `[` / `]` | Previous / next image |
| `↑` / `↓` | Previous / next Look |
| `V` | Toggle single-view / side-by-side comparison |
| `Space` (hold) | Show the comparison baseline in single-photo view |
| `B` | Select the Brush mask tool |
| `E` (masking workspace) | Select the Erase mask tool |
| `L` | Select the Linear Gradient mask tool |
| `R` | Select the Radial Gradient mask tool |
| `↑` / `↓` (masking workspace) | Nudge the selected mask; hold `Shift` for a larger step |
| `[` / `]` (masking workspace) | Decrease / increase brush radius |
| `⌥` + scroll (Brush / Erase) | Resize the brush; plain scroll still zooms the canvas |
| `O` (masking workspace) | Show / hide the mask overlay (color and opacity are in Settings) |
| `⌘I` | Toggle the Info inspector |
| `⌘O` | Open an image |
| `⌘⇧I` | Import from Photos |
| `⌘⌥I` | Open a source folder |
| `⌘R` | Re-scan the source folder |
| `⌘⇧L` | Choose a Look folder |
| `⌘⌥L` | Import Look files |
| `⌘D` | Derive a Look from a JPG |
| `⌘Z` / `⌘⇧Z` | Undo / redo |
| `⌘⇧R` | Reset the current photo |
| `⌘C` / `⌘V` | Choose edit categories / paste selected edits |
| `⌘⌥C` / `⌘⌥V` | Copy all / paste all edits |
| `⌘S` | Export |
| `⌘⇧E` | Export all |

Arrow, letter, culling, and comparison shortcuts are routed by a window-level `NSEvent` monitor so
they work across the split view. They yield to text fields, sliders, buttons, pickers, system
modifiers, and the derive sheet.

---

## Build, run, and test

Kromora is a Swift Package; there is no `.xcodeproj` to maintain.

### Requirements

- **Run:** macOS 14.0 or newer.
- **Build:** Xcode 26 or newer with the macOS 26 SDK.
- **Language mode:** Swift 6.

The deployment target and build SDK are intentionally different. The package deploys to macOS 14,
while the current RAW capability surface requires the macOS 26 SDK to compile. Availability checks
keep newer APIs optional at runtime.

### Commands

```bash
# Build and launch the executable target for quick iteration.
swift run

# Build a release product.
swift build -c release

# Run the test suite.
swift test

# Check changed Swift files against the repository style.
SWIFT_FORMAT_BASE=HEAD^ scripts/check-swift-format.sh
```

`swift run` launches the bare Swift Package executable. It does not include the bundled asset
catalog or App Sandbox entitlements, so the app icon and security-scoped bookmark persistence are
not active in that mode. For bundled app behavior, open `Package.swift` in Xcode, select the
**Kromora** scheme, and run. The included [`Kromora.entitlements`](Sources/Kromora/Kromora.entitlements) is
configured for user-selected read/write access, read-only access to mounted removable media, and
app-scope bookmarks.

The removable-media import flow is intentionally read-only. `MountedMediaVolumeProvider` discovers
supported files on mounted removable/ejectable volumes under the removable-media entitlement; it
does not write to the source volume. The provider still attempts
`startAccessingSecurityScopedResource()` because a caller may supply a scoped URL, but raw mount
URLs are normally entitlement-authorized rather than security-scoped. If macOS does not authorize
a particular volume class from the entitlement alone, Kromora keeps the volume visible, asks the user
to select its root in an Open panel, and scans the resulting security-scoped bookmark. Run the full
Xcode-built app to verify this path; `swift run` does not apply the entitlement.

The suite currently contains **1,338 XCTest methods** (`swift test list`), including deterministic
regression coverage and opt-in benchmarks. Fixtures are generated in temporary directories. CI
partitions the required set into two disjoint macOS 26 lanes: the deterministic/model/fake-engine
lane runs with `--parallel`, while Core Image/render and AppKit/UI tests run with `--no-parallel`.
The lane definitions and coverage audit live in [`scripts/ci-tests.sh`](scripts/ci-tests.sh):

```bash
scripts/ci-tests.sh fast       # required deterministic lane, parallel
scripts/ci-tests.sh serial     # required render/UI lane, serial
```

RAW-fixture and benchmark methods are deliberately outside the required gate. Run
`scripts/ci-tests.sh optional` with the documented `KROMORA_*` settings; RAW/derive coverage requires
a separately licensed local fixture directory through `KROMORA_RAW_FIXTURE_DIR`, and Metal/AppKit
capture requires a logged-in display. Without those inputs the methods skip with an explanatory
message. CI builds/verifies a signed app bundle on every push and pull request using the macOS 26
runner.

Optional local benchmarks:

```bash
# Coalesced edit persistence across 10, 1,000, and 10,000-record catalogs.
KROMORA_PERSISTENCE_BENCHMARK=1 swift test --filter EditPersistenceBenchmarkTests

# Real CAMetalLayer drawable presentation and input-to-presentation latency.
KROMORA_METAL_BENCHMARK=1 swift test --filter MetalPresentationBenchmark/testRealMetalPresentationBenchmark

# The same real drawable benchmark using a licensed local RAW fixture.
KROMORA_METAL_BENCHMARK=1 \
KROMORA_METAL_BENCHMARK_RAW=/absolute/path/to/representative.ARW \
swift test -c release --filter MetalPresentationBenchmark/testRealMetalPresentationBenchmark

# Automated xctrace capture with Points of Interest + Metal System Trace.
KROMORA_RAW_FIXTURE_DIR=/absolute/path/to/fixtures \
scripts/run-kromora-capture.sh --benchmark metal-presentation \
  --source /absolute/path/to/fixtures/DSC07826.ARW

# Concurrent export/editing capture; requires the same display and fixture inputs.
scripts/run-kromora-capture.sh --benchmark concurrent-export-editing \
  --source /absolute/path/to/fixtures/DSC07826.ARW

# Tracing overhead with and without an active Instruments recording.
KROMORA_TRACE_BENCHMARK=1 swift test --filter TracingOverheadBenchmark/testMeasureTracingOverhead

```

The historical standalone mask-overlay capture host has been retired. Use the supported capture
wrapper and see [`scripts/README.md`](scripts/README.md) for the lifecycle and requirements of every
script under `scripts/`.

Hardware latency claims require a logged-in display and a Release build; the opt-in Metal benchmark
does not turn CI timings into a product claim. See [testing and profiling](docs/TESTING.md) for
capture procedure and limits.

---

## Architecture

The package is split into a thin executable and a testable `KromoraKit` library:

```text
Sources/
├── Kromora/
│   ├── KromoraApp.swift           # @main app, window, delegate, termination flush
│   ├── Assets.xcassets/        # app icon and accent color
│   └── Kromora.entitlements       # sandbox file access and bookmarks
└── KromoraKit/
    ├── Models/                 # value state, source projections, pipeline, GPU/cache resources
    ├── ViewModels/             # AppViewModel plus import, editor, preview, persistence, export, and Look coordinators
    └── Views/                  # Library, canvas, filmstrip, inspectors, menus, status bar

Tests/
└── KromoraKitTests/               # model, pipeline, integration, regression, and opt-in benchmarks

docs/                           # durable architecture, Auto, comparison, Looks, packaging, testing, and audit guidance
```

The important boundaries are:

- **Value document:** `EditDocument` contains RAW develop settings, Light, Color, Effects, crop,
  rotation, legacy ordered adjustment nodes, the Look reference, local adjustment recipes, and
  Auto provenance. Empty state is the identity transform.
- **One graph, multiple qualities:** `RenderPipeline` folds the document into one lazy Core Image
  graph. `RenderEngine` evaluates it at interactive, preview, thumbnail, or full quality; preview
  and export differ by an explicit quality/output policy rather than separate edit logic.
- **Deterministic stage order:** source/develop → orientation/rotation → Light → Color → pre-Look
  detail effects → ordered adjustments → Look → ordered local adjustments → crop → post-crop
  vignette → deterministic grain. This keeps spatial effects aligned with the final frame while
  preserving preview/export parity.
- **Actor isolation:** Core Image objects stay inside the render engine. Sendable values cross the
  boundary, and the package compiles in Swift 6 language mode without unchecked concurrency escapes.
- **GPU presentation:** live previews use a persistent Metal-backed presentation surface. Interactive
  edits are debounced/coalesced, stale work is discarded, and a valid last frame is retained when a
  replacement fails.
- **Bounded work:** developed-source, render, LUT, and thumbnail caches are bounded and respond to
  memory pressure. Thumbnail work is prioritized around the visible library neighborhood.
- **Coordinators:** `AppViewModel` is the composition root and published active-document owner.
  `EditorDocumentCoordinator` owns per-photo sessions/history/clipboard, `PhotosImportCoordinator`
  owns Photos provider interaction and progress, and dedicated preview, persistence, export, derive,
  Look, and analysis collaborators own their stable responsibilities. See
  [`docs/APP_ARCHITECTURE.md`](docs/APP_ARCHITECTURE.md) and
  [`docs/ENGINEERING_GUIDE.md`](docs/ENGINEERING_GUIDE.md).
- **Observability:** signposts and bounded live telemetry distinguish input, render, GPU completion,
  and actual drawable presentation so profiling does not confuse “render finished” with “user saw
  the frame.”

Useful starting points are [`EditDocument`](Sources/KromoraKit/Models/EditDocument.swift),
[`RenderPipeline`](Sources/KromoraKit/Models/RenderPipeline.swift),
[`RenderEngine`](Sources/KromoraKit/Models/RenderEngine.swift), and
[`EditDocumentStore`](Sources/KromoraKit/Models/EditDocumentStore.swift).

The portable library package is the implemented product: the open package owns library membership,
originals, metadata, and edit revisions, with package edit sidecars as the canonical edit store.
Folder, Photos, and removable-volume choices are import sources; the local index and device caches
are rebuildable projections. See [`docs/STORAGE_POLICY.md`](docs/STORAGE_POLICY.md) and
[`docs/APP_ARCHITECTURE.md`](docs/APP_ARCHITECTURE.md) for the storage contract and ownership
boundaries. KRMA-384 remains only as the historical planning record.

## Preparing for the App Store

1. Build and verify the product icon and signed bundle with [`scripts/build-macos-app.sh`](scripts/build-macos-app.sh), [`scripts/verify-app-icon.sh`](scripts/verify-app-icon.sh), and [`scripts/verify-app-signature.sh`](scripts/verify-app-signature.sh); see [`docs/PACKAGING.md`](docs/PACKAGING.md) for the release workflow. Packaging renders into disposable `.build/` staging paths and does not modify tracked source files.
   Release signing uses `KROMORA_CODESIGN_IDENTITY` (or `CODE_SIGN_IDENTITY`) and optionally `KROMORA_PROVISIONING_PROFILE` (or `PROVISIONING_PROFILE`). If neither is set, the script uses an ad-hoc signature for local/CI structural verification; configure the release identity and profile in CI for distribution builds.
2. Set the Bundle Identifier and Team in Xcode's Signing & Capabilities.
3. Keep App Sandbox enabled with the included entitlements.
4. Use **Product ▸ Archive ▸ Distribute App ▸ App Store Connect**.

## License

Kromora is released under the [MIT License](LICENSE). The LUTzy fork attribution and original license
terms are preserved as described above.

The Kromora name, logo, app icon, and related visual identity are project branding and are not granted
for use in modified products or in a way that implies endorsement. See [BRANDING.md](BRANDING.md).

<div align="center">
<sub>Built with SwiftUI · Core Image · Metal — and nothing else.</sub>
</div>
