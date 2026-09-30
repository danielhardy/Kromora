# Last-known frame architecture and execution plan

Status: reviewed implementation plan, 2026-09-30

## Outcome

Opening Kromora, entering Edit, and moving between photos must paint the selected photo immediately
from the best trustworthy pixels already available. A photo may refine once when newer pixels are
ready. It must never show the prior photo, pass through an avoidable original-to-edited sequence,
blank a valid frame, or change cell geometry after first layout.

This work optimizes for sustained speed, deterministic behavior, crash tolerance, and simple
ownership. Migration effort and implementation convenience are secondary.

### User-visible invariants

1. A surface never shows pixels belonging to a different asset after selection changes.
2. A warm Edit open shows one cached frame, followed by at most one refinement.
3. A warm Library or filmstrip cell starts with its last presented edited appearance and its final
   aspect ratio. It never regresses to the original while newer work is pending.
4. A cached frame can suppress rendering only after all current render inputs are known and match.
5. A provisional frame cannot drive editing tools, histogram, scopes, comparison, cache writes, or
   `lastPublishedVisibleRequest`.
6. Deleting every derived frame remains safe. It costs decoding/rendering time, never correctness or
   access to an edit.

## Current system and failure modes

### Edit canvas

`AppViewModel.load` intentionally leaves the previous asset on `PreviewSurface` while the next
source prepares. `SourceSessionCoordinator` then extracts a camera JPEG for RAW sources and
`presentEmbeddedFirstFrame` displays it. Only after source preparation, stored-edit reconciliation,
Look resolution, and preview admission does the settled edited frame arrive. The visible sequence
is therefore often A -> unedited B -> edited B.

`PreviewDiskCache` cannot hide most of this latency:

- Lookup begins in `PreviewAdmissionCoordinator.submitSettledPreview`, after
  `admissionImageSource` exists. Source preparation and stored-edit adoption remain exposed.
- The key requires an exact source, document, resolved Look, working space, size, and
  `RenderPipeline.cacheVersion`. There is no same-photo fallback.
- `PreviewDiskCacheWriter` wipes the directory when the pipeline version changes. A pixel change
  therefore destroys pixels that would still be an excellent provisional frame.
- It retains multiple exact edit keys until LRU eviction even though the highest-value relaunch
  artifact is the most recently presented frame for each photo.
- ROI requests bypass the canonical cache, correctly, but there is no independent early
  presentation path for them.

### Looks

`PreviewPresentationCoordinator` and `EditedThumbnailCoordinator` use `"unresolved"` when a
document's `LUTID` has not resolved to a live `CubeLUT`. `LUTLibrary.onScanned` then invalidates the
engine LUT cache and re-admits the canvas and all materialized edited thumbnails even when the scan
found byte-for-byte identical Looks.

The package already contains the durable answer needed here. Each immutable edit revision stores a
`PortablePackageLookReference` with a SHA-256 `contentHash`, byte count, and content-addressed blob.
Do not add a second digest field to `EditDocument`.

### Library and filmstrip

Original thumbnails are decoded from source files after every process launch. The 32 MB
`Thumbnails.cache` is memory-only. `PortablePackagePackedThumbnailStore` exists under
`Derived/Thumbnails`, but production browsing does not read or write it.

Edited thumbnails are also memory-only. `EditedThumbnailCoordinator` reopens the edit, resolves the
Look, prepares the source, and renders every demanded edited item. Until that finishes, the original
is shown. `ImageCollection.Item.shouldFillLibraryThumbnail` changes only after edited pixels arrive,
and `libraryAspectRatio` changes when `presentedCrop` and `presentedRotation` are finally installed.
The result is a pixel swap plus layout reflow.

## Architectural decision

### Replace the exact preview cache; do not add a parallel cache

There will be one persistent presentation-frame concept and two storage backends:

- `LatestPreviewFrameStore` replaces `PreviewDiskCache` in package `Derived/Previews/`.
- `ThumbnailFrameStore` wraps the existing packed store in package `Derived/Thumbnails/`.

Adding `Derived/LastKnown` while retaining `Derived/Previews` would duplicate the same 2048 px
raster, perform two writes after every settle, and create two invalidation and eviction policies.
The existing exact-key, multi-entry preview behavior is removed. In-process render caches continue
to accelerate undo/redo; the durable store spends its budget on instant relaunch and navigation.

Both stores expose the same value model and classification policy. They differ only in physical
layout: previews use one replaceable file per asset for low-latency random reads, while thumbnails
use the existing append-only sharded packs for dense small records.

### Shared value model

```swift
struct PresentationFrame: Sendable {
    let identity: PortablePhotoIdentity
    let kind: Kind                 // preview2048, originalThumbnail480, editedThumbnail480
    let signature: FrameSignature
    let geometry: PresentedGeometry
    let rasterColorSpace: RasterColorSpace
    let perceptualDigest: PerceptualDigest
    let presentedAt: Date
    let rasterData: Data
}

struct FrameSignature: Codable, Equatable, Sendable {
    let source: PortablePhotoIdentity
    let editHash: String
    let look: LookSignature
    let workingSpace: WorkingSpace
    let pixelEpoch: Int
}

enum LookSignature: Codable, Equatable, Sendable {
    case none
    case resolved(id: LUTID, contentHash: String)
    case unresolved(id: LUTID)
}

struct PresentedGeometry: Codable, Equatable, Sendable {
    let crop: CropAdjustments
    let rotation: ImageRotation
    let orientedAspectRatio: Double
}
```

`FrameSignature` describes pixel meaning. Container layout has an independent
`storageFormatVersion`. `RenderPipeline.cacheVersion` is replaced by:

- `pixelEpoch`: bump only when identical source/edit/Look inputs would render different pixels.
  A mismatch makes an entry stale-compatible and preserves it for immediate display.
- `storageFormatVersion`: bump only when the frame envelope cannot be decoded. An incompatible
  individual file is ignored and lazily replaced; the store never wipes its directory at launch.

Package revisions obtain the resolved Look hash from `PortablePackageLookReference.contentHash`.
Unsaved live edits obtain it from `CubeLUT.cacheFingerprint`'s content component. An unresolved ID
is explicit and can never produce an exact hit.

### Atomic preview envelope

Each preview is one atomically replaced `<asset-hash>.kframe` file containing:

1. fixed magic and container version;
2. bounded metadata length;
3. JSON metadata without raster bytes;
4. JPEG payload produced through the existing RenderEngine-owned canonical raster boundary.

A single envelope prevents a crash from pairing new metadata with an old raster. Decode validates
magic, lengths, identity, raster dimensions, and color-space metadata before returning a frame.
Corruption is a miss and schedules lazy replacement. No exception reaches presentation.

`LatestPreviewFrameStore` is an actor. It loads its size/recency index off the main actor, serializes
reads/writes/invalidation, coalesces writes by asset identity, and maintains the existing 1 GB cap
incrementally. One preview exists per asset identity. Active and visible-window identities may be
pinned during eviction; everything else is strict LRU.

Legacy `preview-*.jpg` files and the old `version` file are deleted incrementally after the new store
is operational. They are never used as authoritative input and do not trigger a synchronous launch
scan or a whole-directory wipe.

### Freshness is a pure function

```text
classify(frame, currentInputs):
  source identity/fingerprint mismatch                 -> unusable
  raster color space cannot be presented losslessly   -> unusable
  current inputs not fully resolved                    -> provisional-only
  all FrameSignature fields equal                      -> exact
  otherwise, same source and presentable color space   -> stale-compatible
```

- **Exact:** present and skip the settled render. Route the raster through the normal confirmed
  visible-frame tail so histogram and supporting work are admitted exactly once.
- **Stale-compatible:** present inert pixels immediately, render current inputs, then replace once.
- **Provisional-only:** current edit or Look truth is not known yet. The frame may hide latency but
  cannot skip work.
- **Unusable:** do not decode/present further. Continue to the next fallback.

The classifier is independent of storage and UI. Preview, thumbnail, launch, and tests use the same
implementation. No caller reimplements key comparison.

### One transition state machine

Selection starts an asset-scoped presentation session before source preparation:

```text
selected(asset, generation)
  -> candidate loading
  -> provisional(candidate)       // optional; inert
  -> inputs resolved
       exact -> confirmed(candidate)
       stale/provisional -> rendering -> confirmed(rendered)
  -> failed                        // keep best same-asset candidate; expose error
```

Every async completion carries asset ID, source identity, and generation. A completion from an older
session is dropped. The surface is cleared synchronously on selection before any suspension, then
filled only with target-asset pixels.

Fallback order is:

1. latest preview frame;
2. latest edited thumbnail frame;
3. target asset's original packed/in-memory thumbnail;
4. embedded camera JPEG, only on a first-ever RAW open where none of the above exists;
5. neutral canvas.

The previous asset is never a fallback. Once any same-asset candidate is shown, embedded-JPEG
publication is suppressed. A canonical complete render is the only event that writes the preview
frame; interactive, ROI, comparison, provisional, and failed renders never do.

### Refinement policy

Stale replacement uses at most one 120 ms opacity crossfade. During canonical rasterization the
render boundary computes a tiny fixed-size perceptual digest. If the digest distance is below a
documented threshold, replacement is immediate with no animation. Digest computation is bounded,
deterministic, color-space aware, and never causes an extra full-size readback. Reduce Motion makes
all replacements immediate.

### Thumbnail persistence and geometry

`ThumbnailFrameStore` is an actor-isolated runtime facade over
`PortablePackagePackedThumbnailStore`. Stable keys retain at most two live records per asset:
original and latest edited. Replacing a stable key appends bytes and moves its index pointer;
maintenance compacts unreachable bytes.

The visible-window read path is memory -> packed frame -> source decode/render. It admits reads for
the whole visible window before render work. Edited demand then classifies signatures:

- exact: publish and do not render;
- stale-compatible: keep the edited frame, render at thumbnail priority, refine once;
- missing/unusable: show the original inside the final geometry, then render;
- identity edit: publish the original and replace/remove the edited record.

Final cell aspect ratio is stored in the package membership summary as an optional
`presentedAspectRatio`. Edit persistence updates it in the same package transaction that advances
the current edit revision. This is denormalized package metadata, rebuildable from the current edit
sidecar, and copied into `LibraryIndexEntry`. It is not derived from raster arrival. Old packages
without the field use source aspect until their next edit commit or a projection repair pass.

Cells always reserve this final ratio before pixels arrive. An original fallback uses `.fit` inside
that frame; edited pixels use `.fill`. Raster arrival never changes cell size.

### Look scan behavior

`LUTLibrary` publishes a scan snapshot keyed by `LUTID` with content hashes. `AppViewModel` compares
the previous and new snapshots:

- no referenced hash changed: update browser state only;
- referenced hash changed or appeared/disappeared: invalidate only affected engine LUT resources,
  mark matching frames stale, and re-admit only affected visible assets;
- unrelated Look changed: no canvas or thumbnail work.

The blanket `invalidateLUTCache` plus `schedulePreview` plus
`refreshMaterializedEditedThumbnails` wave is removed. Missing Looks remain explicit and do not
masquerade as `none` or `"unresolved"` exact keys.

### Launch hydration

A device-local `LaunchHints` record in Application Support stores only package identity, last active
asset, and a bounded ordered visible-ID window. It is a performance hint, not navigation or library
truth. Writes are coalesced and atomic. Unknown package IDs, missing assets, or corrupt data are
ignored.

Kromora continues to launch into Library. After package identity is known, frame reads for hinted
visible IDs are admitted while the library index and Look scan continue. When the real viewport is
known it supersedes the hint. Launch hydration performs no source decode or render and has a strict
I/O concurrency limit so it cannot delay index publication.

## Ownership

| Concern | Owner |
| --- | --- |
| Frame values, classifier, envelope codec | Models; pure value code |
| Preview frame I/O, LRU, migration | `LatestPreviewFrameStore` actor |
| Thumbnail pack I/O and compaction interface | `ThumbnailFrameStore` actor facade |
| Selection generation and provisional/confirmed state | `PreviewPresentationCoordinator` |
| Render admission and exact-hit bypass | `PreviewAdmissionCoordinator` |
| Canonical raster and perceptual digest generation | `RenderEngine` / `RenderEngineResources` |
| Edited thumbnail demand and refinement | `EditedThumbnailCoordinator` |
| Package geometry summary and index projection | package transaction/session layer |
| Visible-ID and launch-hint orchestration | `LibraryBrowsingCoordinator` / application shell |

`AppViewModel` wires these owners and exposes published state. It must not become the frame store,
classifier, or I/O scheduler. `CIImage`, `CIFilter`, and `CIContext` remain inside the render boundary;
stores accept and return `Data` or `sending CGImage` only.

## Performance and reliability budgets

Record hardware, OS, build configuration, source format/dimensions, cache state, and viewport for
every number. Debug timings are diagnostics; release timings are acceptance evidence.

| Scenario | Required result |
| --- | --- |
| Warm Edit navigation | Correct-photo provisional pixels in p95 <= 50 ms from selection; <= 2 ms main-actor work before first suspension |
| Exact warm Edit open | Zero preview render requests; one confirmed frame; supporting work admitted once |
| Stale warm Edit open | One provisional frame and at most one confirmed replacement; no intermediate embedded/original frame |
| Warm 30-cell grid | Frame-store reads admitted before renders; p95 visible cell hydration <= 100 ms on reference hardware |
| Pipeline pixel epoch bump | No cache wipe or blanking; entries classify stale-compatible and rebuild lazily |
| Unchanged Look rescan | Zero preview or edited-thumbnail render admissions |
| Navigation burst | Work remains bounded to current preparation plus one pending selection; obsolete frames never publish |
| Cache corruption/interrupted write | Affected entry becomes a miss; package opens and renders normally |

Observability records asset-safe identifiers, candidate source, classification, lookup/decode time,
time to first same-asset pixel, time to confirmed frame, refinement count, render suppression, stale
drop, and grid geometry changes. Do not log file paths or photo contents.

## Execution order

### Phase 1 — Stop cross-asset presentation and establish measurement (`KRMA-729`)

- Clear/fence the canvas synchronously on selection.
- Present only target-asset thumbnail/embedded candidates.
- Suppress the embedded frame after any target candidate.
- Add presentation-session state and signposts/counters.

Exit: A -> B navigation can produce B thumbnail -> B embedded -> B settled only when no better
candidate exists, and never displays A after B is selected. Baseline metrics are captured.

### Phase 2 — Make Look identity deterministic (`KRMA-730`)

- Introduce `LookSignature` and package-sidecar content-hash resolution.
- Publish hash snapshots from LUT scans.
- Replace blanket scan invalidation with referenced-hash deltas.
- Remove `"unresolved"` from all exact cache/revision identities.

Exit: an unchanged launch scan admits zero render work and exact identity is independent of scan
timing.

### Phase 3 — Replace `PreviewDiskCache` (`KRMA-731`, after phases 1 and 2)

- Add pure frame types/classifier/envelope tests.
- Implement `LatestPreviewFrameStore`, atomic one-file entries, actor isolation, pinning, LRU, and
  lazy legacy cleanup.
- Start lookup at selection, in parallel with source preparation and edit reconciliation.
- Add exact render bypass, inert stale presentation, digest-gated refinement, and canonical writes.
- Remove old exact-key cache code and version-wide wipe behavior in the same change.

Exit: warm exact opens do no preview render; pixel epoch bumps refine without blanking; only one
durable 2048 px preview exists per asset.

### Phase 4 — Persist thumbnail pixels and geometry (`KRMA-732`, after phases 2 and 3)

- Wrap and wire the packed thumbnail store into runtime reads/writes.
- Persist original and latest edited frame records with shared signatures.
- Add transactional `presentedAspectRatio` summary updates and projection decoding.
- Hydrate visible frames before admitting source decode/render.
- Remove raster-arrival-driven cell geometry and broad materialized refreshes.

Exit: relaunching a library produces no edited-thumbnail original swap and zero cell-size changes
for cached visible assets.

### Phase 5 — Add bounded launch hydration (`KRMA-733`, after phase 4)

- Persist/validate `LaunchHints`.
- Hydrate hinted frames concurrently with index and Look startup under an I/O limit.
- Supersede hints as soon as the real viewport publishes.

Exit: warm launch prioritizes the last visible window without changing launch navigation or delaying
the first index page.

### Phase 6 — Fault, performance, and soak qualification (`KRMA-734`, after phases 1–5)

- Exercise corrupt/truncated envelopes and pack indexes, interrupted writes, deleted `Derived`,
  source replacement, package relocation, Look replacement, pixel/storage version changes, cache
  pressure, and rapid navigation.
- Run deterministic lanes plus opt-in release benchmarks and manual drawable confirmation.
- Update `STORAGE_POLICY.md`, `ENGINEERING_GUIDE.md`, `APP_ARCHITECTURE.md`, and `TESTING.md` with the
  landed contract and measured reference results.

Exit: all budgets above have recorded evidence; no cache failure prevents open/edit/export; required
CI lanes and the identity gate pass.

`KRMA-728` is the tracking epic and depends on every phase ticket above. Only phases 1 and 2 begin
independently; DispatchGraph dependencies serialize all later work at their architectural seams.

## Verification matrix

### Deterministic model/coordinator coverage

- Every freshness-classifier row, including unresolved Look and raster-space mismatch.
- Envelope rejects bad magic, overflow/truncation, mismatched identity, invalid dimensions, and
  unsupported versions without throwing into presentation.
- Pixel epoch mismatch is stale-compatible; storage incompatibility is a per-entry miss; neither
  wipes unrelated frames.
- Same asset/exact inputs skip render and admit histogram/supporting work once.
- Placeholder state does not admit histogram, scopes, comparison, tools, publication telemetry, or
  a cache write.
- Source replacement and package/asset identity mismatch never show the old frame.
- Late cache, embedded, render, thumbnail, and Look-scan completions lose to the session generation.
- Unchanged Look snapshots admit zero preview/thumbnail work; one changed referenced hash affects
  only matching assets.
- Packed thumbnail exact/stale/missing/identity transitions preserve the best same-asset bitmap.
- Cell aspect is fixed before raster publication and unchanged after original/edited refinement.
- Corrupt `LaunchHints` and stale IDs are ignored; real viewport demand supersedes hinted demand.

### Integration and serial coverage

- Presentation order for cold, exact, stale, missing-Look, RAW embedded, rapid A -> B -> A, and
  renderer failure paths.
- Real ImageIO round trips with color-space and JPEG tolerance checks.
- Package transaction fault injection proves edit revision and presented aspect publish together.
- Packed-store interruption/compaction retains the last indexed record.
- Preview and thumbnail deletion/invalidation are identity-scoped.

### Manual and benchmark evidence

- Release build on representative Apple Silicon with JPEG and licensed RAW sources.
- Cold and warm launch; exact revisit; edit change; crop/rotation change; Look bytes replaced in
  place; pixel epoch bump; deleted/corrupt cache; 30+ visible cells; rapid filmstrip scrub.
- Count actual drawable presentations, distinct frames, crossfades, render requests, thumbnail
  swaps, and layout changes. Screenshots alone are insufficient for timing claims.

## Documentation and migration requirements

- `docs/STORAGE_POLICY.md`: `Derived/Previews` and `Derived/Thumbnails` are optional package-derived
  presentation caches; `LaunchHints` is disposable device state; all are omitted from verified
  backup requirements.
- `docs/ENGINEERING_GUIDE.md`: shared frame signature/classifier, provisional-state restrictions,
  pixel epoch policy, and actor/render boundaries.
- `docs/APP_ARCHITECTURE.md`: store, presentation-session, thumbnail, and launch ownership.
- `docs/TESTING.md`: benchmark method, reference hardware fields, and fault matrix.
- Remove documentation that promises exact multi-edit preview retention or directory-wide pipeline
  invalidation.

Migration is one-way and disposable: new code ignores old exact JPEGs, deletes them lazily, and
rebuilds frames through ordinary successful presentation. No package manifest migration is needed
for derived files. The optional membership-summary field must decode absent values and be populated
on the next edit write or repair.

## Explicit non-goals

- No full-resolution, export, mask, or analysis pixels in presentation-frame stores.
- No cached frame as edit or package truth.
- No synchronous cache scan, source decode, or render on the main actor.
- No restoration directly into Edit; Library remains the launch destination.
- No preservation of the old multi-key preview cache for undo/redo.
- No compatibility path for pre-macOS 26 or Intel hardware.
