# Portable library package — implementation plan

> Product status (KRMA-520): the package-backed library is now the only library mode. The design
> notes below retain format and migration history; folder chooser/drop and removable media are
> import sources, not persisted referenced-folder browsing. Existing `EditStore*.store` files
> remain untouched. If referenced assets return, they will use package `.referenced` records.

> **Historical-plan notice:** the package product and its core phases have shipped. Sections below
> preserve the original design rationale and proposed sequence; normative current behavior is in
> [`APP_ARCHITECTURE.md`](APP_ARCHITECTURE.md) and [`STORAGE_POLICY.md`](STORAGE_POLICY.md). Where
> this proposal conflicts with those documents or the shipped code, the current architecture and
> tests take precedence. In particular, referenced-folder browsing has no product mode and the
> package sidecars, not `EditDocumentStore`, own durable edits.

**Status:** the Pictures-backed package and storage boundary are active. The original sequenced
implementation records were KRMA-389 (phase 0), KRMA-390 (phase 1), KRMA-391 (phase 2), KRMA-392
(phase 3), and KRMA-393 (phase 4); this phase sketch is historical, not an open execution queue.
Current follow-up lives in DispatchGraph. The sequencing and safety boundaries are recorded in
[ADR-001](../.dg/decisions/ADR-001-portable-library-package-sequencing-and-safety-b.md).
**Scope:** local-only. iCloud sync is explicitly out of scope (see [Deliberately out of scope](#deliberately-out-of-scope)).
**Target scale:** 100,000 assets on a single Mac.

This document is a historical implementation plan and format reference. Durable current architecture
belongs in [`APP_ARCHITECTURE.md`](APP_ARCHITECTURE.md); completed package work below remains as
historical context for compatibility and later format work.

The current product uses a Pictures-backed portable package for managed library data. The local
index and device caches are projections, while package edit sidecars are canonical. The approved
legacy-data disposition is documented in
[`EDIT_STORE_IDENTITY_DISPOSITION.md`](EDIT_STORE_IDENTITY_DISPOSITION.md); maintenance work must
not silently migrate or delete current library data.

---

## 1. Goal and premise

The package-backed product presents imported assets from the package query/index. The former
referenced-folder browser and its SwiftData-backed collection projection are retired. Legacy edit
stores remain on disk but are not opened as a library fallback.

That is fine for a single-machine development tool and wrong for a photo library. Moving the photos
breaks the edits. Moving to a new Mac loses everything. There is no unit a user can back up, hand to
someone, or put on an external drive.

The goal is a **self-contained, portable library package**: one filesystem object that holds
originals, metadata, edits and derived previews, such that copying it to another disk or another Mac
preserves every edit, every Look reference and every cache identity, with no repair step.

### What this does *not* change

Interactive editing and rendering are untouched. Once an asset is resolved, `RenderEngine` still
receives a local URL and an `EditDocument`; package bookkeeping stays outside the render actor.
`RenderPipeline`, `EditDocument`, the comparison/histogram/export paths and the mask recipe model are
all unaffected by this work.

### The material costs, stated honestly

- **Imports get slower.** Every original is copied and fully hashed.
- **Cold index rebuild scales with asset count.** Bounded by design (§4.2) but non-zero.
- **Verified backup scales with library bytes.** Unavoidable; it is what "verified" means.

These must be streamed, cancellable, progressive, and isolated from editor work. Warm launch,
navigation, scrolling and slider latency must remain at least as good as today.

---

## 2. Deliberately out of scope

### iCloud / cloud sync

**Not in this plan, and the plan does not pre-build for it.**

The rejected design was iCloud Documents over the package. At target scale the package holds roughly
600,000–1,000,000 files. `NSMetadataQuery` over that item count, per-file upload transactions, and
per-file eviction inside an object Finder presents as one atomic document are all well outside what
iCloud Documents is built for. Apple's own Photos uses CloudKit rather than Documents-in-iCloud for
exactly this reason.

That said, the format below does not *preclude* sync later, because the properties sync needs are the
same ones portability needs and we are building them anyway:

- opaque UUID identity for every entity,
- monotonic per-component revisions,
- immutable, content-addressed component files,
- a root manifest that changes rarely.

If sync is ever revisited it should be a CloudKit record design over this format, scoped as its own
project with its own scale spike run **first**. Nothing in phases 0–4 should be shaped around it.

### Other exclusions

- **Multiple simultaneous libraries.** One active library. The format carries a library UUID so this
  can be relaxed later.
- **Migration from current development storage.** There is no shipped user data. Existing local edits
  are discarded at phase 1. This is what makes the identity change (§3.1) tractable at all.
- **Adobe `crs:` interpretation.** Imported `crs:` values are preserved as opaque foreign metadata,
  never interpreted as Kromora adjustments.

---

## 3. Format

### 3.1 Portable identity (the load-bearing change)

Every durable identity becomes an **opaque UUID**. SHA-256 provides integrity and deduplication; it
never provides identity.

Removed from all durable, render, preview, thumbnail, mask, analysis and grain identities:

- absolute and canonical paths,
- `fileResourceIdentifier` (inode/device), currently used by `PhotoAssetID.file(_:)`,
- `contentModificationDate`, currently in `PhotoSourceFingerprint`,
- any other `URLResourceKey`-derived value.

`ImageSource` cache identity becomes: **asset UUID + immutable original SHA-256 + source revision +
decoder version + geometry**. Package-relative paths are resolved to absolute URLs exactly once,
immediately before work is submitted to the render actor, and never stored.

The blast radius is large and mostly mechanical: `PhotoAssetID`, `PhotoSourceFingerprint`,
`PhotoAssetSource.cacheKey`, `RenderCacheKey`, `MaskStore` keys, `PreviewDiskCache` keys, and
`EditRecord.sourcePath`/`sourceBookmark`. Do it **first and alone** (phase 1) so it is reviewable.

**Acceptance:** a library package copied to a different path on a different filesystem produces
byte-identical cache keys and requires zero relink.

### 3.2 Layout

```text
Kromora Library.kromoralibrary/
  manifest.json

  Catalog/
    Membership/
      00.json … ff.json          # 256 shards, first two hex chars of the asset UUID

  Assets/
    00/<asset-uuid>/             # same two-char shard as membership
      asset.json
      Original/source.<ext>      # absent for referenced assets (§3.6)
      Metadata/<rev>.xmp
      Edits/<rev>.json

  Looks/
    <look-uuid>/
      look.json
      source.cube

  Derived/                       # rebuildable; excluded from integrity gates
    Thumbnails/00.pack           # packed per shard, not one file per asset
    Previews/<asset-uuid>.jpg

  Recovery/
    Transactions/
    Quarantine/
    Audit/
```

`manifest.json` is small and changes rarely: library UUID, schema versions, shard rule, feature
flags, recovery format. It does **not** contain per-asset state.

### 3.3 Membership shards carry summaries

This is the difference between a rebuild that opens 256 files and one that opens 100,000.

Each membership shard entry contains the asset UUID, its relative record path, addition/deletion
revisions, tombstone state, **and denormalised summary fields**: capture date, rating, flag, label,
camera make/model, lens, pixel dimensions, aspect ratio, display name, and the current asset
revision.

The summary set is exactly what `LibraryQueryController` sorts and filters on (§4.1). If a query
needs a field not in the summary, either add it to the summary or accept that the query is not a
library-level query.

At 100,000 assets: ~390 entries per shard, ~40 KB per file. A rating change rewrites one 40 KB shard
plus `asset.json` — still O(1), still trivially affordable. A cold rebuild reads 256 files.

**256 shards, not 4,096.** 4,096 shards gives ~25 entries each: kilobyte files, no locality benefit,
and 4,096 opens on rebuild. Two hex characters is the right balance, and it matches the `Assets/`
shard so the two directories stay in lockstep.

### 3.4 Hybrid sidecars

| Data | Canonical form | Rewritten when |
| --- | --- | --- |
| Ratings, keywords, captions, creator, copyright, GPS, labels, supported IPTC | revisioned XMP | interoperable metadata changes |
| The exact render graph | versioned Kromora JSON (`EditDocument`) | adjustments change |
| Package identity, flags, component pointers, revisions, checksums | `asset.json` | any of the above commits |

**XMP is never rewritten because an adjustment changed.** Moving a slider touches
`Edits/<rev>.json` and `asset.json` only.

XMP is parsed only during import, metadata editing, export, or index rebuild — never during launch,
scrolling or adjustment.

### 3.5 XMP is a parser we own

Zero third-party dependencies means hand-rolling XMP/RDF. Scope it deliberately:

- Read with Foundation's `XMLParser` (libxml2-backed, Apple-provided, allowed).
  **Disable external entity resolution** (`shouldResolveExternalEntities = false`) — malformed and
  hostile XMP is a real input class.
- Support a **fixed, small, enumerated property subset**. Anything outside it is foreign metadata.
- **Preserve foreign packets byte-for-byte.** Do not round-trip unknown namespaces through a
  serialiser; store the raw bytes and splice them back. Re-serialising `crs:` will corrupt it.
- Tolerant reader, conservative writer. A truncated or malformed XMP is a recoverable import failure
  and a quarantine candidate, never a crash and never a silent empty-metadata asset.

### 3.6 Referenced assets are a v1 *format* capability

The UI ships copy-on-import only. But `asset.json` must be able to express **"the original lives
outside the package at this security-scoped bookmark"** from schema v1, with `Original/` absent.

The reason is not hypothetical: a user with 2 TB of RAW on a NAS or an external drive cannot use a
copy-only editor at all. Retrofitting a referenced-asset state later is a schema break affecting
every integrity, backup and validation path. Reserving the state now is a few fields and a branch in
the resolver; adding it later is a migration.

Phase 2 writes the fields and implements the resolver branch. No UI exposes it until it is wanted.

### 3.7 Forward and backward compatibility

- `manifest.json` carries `writerVersion` **and** `minimumReaderVersion` as separate values. Additive
  changes bump only `writerVersion`, so older builds keep working.
- If `minimumReaderVersion` exceeds what this build understands: open **read-only**, and offer
  upgrade / reveal in Finder / back up. Never a silent partial read.
- **Unknown JSON keys are preserved verbatim on rewrite**, at every level. A newer build's fields must
  survive a round-trip through an older one. Implement with an explicit passthrough dictionary in the
  Codable conformance, and test it.

### 3.8 Looks: embed, don't reference

An asset's edit referencing a globally-stored Look means deleting that Look silently breaks an
unknown number of photos.

Since edit revisions are immutable, **embed the resolved cube bytes in the edit revision** (or in a
content-addressed blob the revision points at, deduplicated by cube SHA-256). `Looks/` becomes a
user-facing library of *reusable* Looks, not a dependency of any edit. Deleting a Look then affects
the browser only, never a rendered image, and edit revisions become genuinely self-contained.

A typical `.cube` is small; at 33³ float entries this is tens of KB per distinct Look, deduplicated
across every asset using it.

### 3.9 Masks and analysis stay rebuildable

**This preserves an existing invariant — do not regress it.**

[`ENGINEERING_GUIDE.md`](ENGINEERING_GUIDE.md) states that mask *definitions* live in `EditDocument`
while generated mask pixels are disposable cache, and that "a missing or invalid sidecar is a cache
miss; it must never invalidate the saved mask recipe."

That holds here. Mask definitions are already inside the edit revision and therefore already
canonical and already portable. **Float32 mask rasters and analysis results do not enter the
package.** They stay in the device-local cache (`MaskStore`, `~/Library/Caches/Kromora`), keyed by
the new portable identity (§3.1). See [`STORAGE_POLICY.md`](STORAGE_POLICY.md) for the active matrix.

Rationale beyond the invariant: mask rasters are megabytes each, fully derivable, and would dominate
both package size and backup verification time for zero durability benefit.

The same applies to GPU caches, `CurrentEditMeasurement`, and transient analysis — all stay in
Caches.

`Derived/` in the package holds only thumbnails and settled previews, and is excluded from integrity
gates: its loss is *rebuildable loss*, never *critical loss* (§6.3).

### 3.10 Thumbnails are packed, not per-file

100,000 individual thumbnail JPEGs is the classic cold-scan killer, and file count — not bytes — is
what drives Time Machine, Spotlight indexing, Finder copy and backup verification cost.

Pack thumbnails per shard: `Derived/Thumbnails/00.pack`, an append-only file with a small offset
index, rewritten (compacted) only during low-priority maintenance. A stale or missing entry is a
regeneration, not an error, so the format can be crude.

Whole-package file count target: **under 400,000 at 100,000 assets** (1 asset.json + 1 original +
~1 XMP + ~1–3 edit revisions each, plus 256 shards and 256 thumbnail packs).

---

## 4. Runtime

### 4.1 Paged library model

The current production path uses `LibraryQueryController` with the local membership projection.
`ImageCollection` adapts the active window; launch and reload do not create one observable `Item`
per library asset. The paged/windowed path shipped under KRMA-519:

- Queries lightweight **value** summaries in pages of ~500.
- Materialises only visible, prefetched, selected and actively-edited pages.
- **Selection is stored by asset UUID, not array index.**
- Rating, flag, date, camera and text filters run in the index, not over a materialised array.
- Publishes a bounded first page immediately while the local projection rebuild continues; more
  pages load as needed.
- Decoded thumbnails are retained only for visible cells plus the existing bounded neighbourhood.
- Existing memoised projections (`CollectionProjection`) are preserved so a thumbnail completion does
  not recompute the whole collection.

The package remains fully usable with no index: a missing index triggers a streaming rebuild from the
membership shards (§3.3).

### 4.2 The index is a projection, never the truth

`Application Support/Kromora/Indexes/<library-uuid>/LibraryIndex.store`

- A local rebuildable value projection serialized outside the package; it is not a SwiftData store.
- Flattened searchable metadata, sort keys, aspect ratio, observed package revisions.
- **Never the sole copy of any edit or metadata value.**
- Paged fetches only.
- Incrementally updated after each package commit.
- Rebuilt automatically if corrupt, inconsistent, or absent.
- Deletable at any time with no data loss.
- Never inside the package.

**Package edit persistence (implemented):** package edit sidecars are the canonical edit store.
`EditDocumentStore` is a bounded in-memory cache keyed by `PortablePhotoAssetID`; cache eviction
reloads the package revision. `EditRecord` and the former SwiftData projection are retired from
production code (KRMA-531). This paragraph replaces the proposal's original pre-package assumption.

### 4.3 One scheduler, not two

**Extend `ImageWorkScheduler`; do not add a parallel package I/O scheduler.**

A second scheduler with its own priority ladder cannot honour "background work yields when editor
work is queued," because neither scheduler can see the other's backlog. Two independent admission
controls over one disk and one GPU is how you get a thumbnail sitting behind a checksum scrub.

`ImageWorkScheduler` already has `activeEditor / comparison / histogram / adjacentFilmstrip /
visibleGrid / background` and a four-worker thumbnail lane. Add I/O lanes to the same actor:

| Lane | Priority |
| --- | --- |
| Active asset record + edit read | with `activeEditor` |
| User metadata / edit commit | with `activeEditor` |
| Adjacent navigation, visible thumbnails | existing lanes, unchanged |
| Import copy + hash | below `visibleGrid` |
| Preview generation | below `visibleGrid` |
| Index rebuild, validation, cleanup, compaction | `background` |

Concurrency:

- **One serialised package commit writer.** Non-negotiable; it is what makes §5 sound.
- **Copy/hash concurrency is volume-adaptive, not a constant.** Two concurrent jobs underuses NVMe by
  3–4× and thrashes a spinning or network volume. Probe `volumeIsInternal` / measured throughput and
  adapt between 1 and 8.
- Existing four-thumbnail limit and bounded queue preserved.
- One maintenance worker, which yields whenever any editor-priority work is queued.
- **No filesystem, XMP, checksum or hashing operation on the main actor. Ever.**
- Long-running workers cross actor boundaries with value-only progress updates.

The package actor coordinates state and performs short commits. It must never be occupied while
hashing a 100 MB RAW, copying a directory or generating pixels — those run in bounded workers and
return verified staged results for the actor to commit.

### 4.4 Edit persistence

Preserve the existing coalescing behaviour exactly:

- Slider movement updates memory and preview immediately.
- Persist at gesture end, navigation, backgrounding, quit, or a bounded idle checkpoint.
- Never one revision per pointer event.
- Maximum one second of unsaved work during a long gesture, for crash protection.
- Bounded history: latest 20 revisions, plus any referenced by recovery.
- Unreachable revisions compacted only during low-priority maintenance.

### 4.5 Preview and analysis work

- A package preview is written only after a **settled full-frame render** — never per slider frame,
  never for a zoom/ROI render.
- Preview persistence is debounced; existing source/document generation fences are retained.
- Thumbnails generated only for visible or prefetched assets.
- Analysis and mask generation are cancellable, and stale completions are rejected.
- Package work never enters the render actor's interactive queue.

### 4.6 Import

All imports — Photos, removable media, one-off, folder — copy the original into the package.

- **Copy and hash in one streaming pass.** Each original is read exactly once.
- Use `clonefile()` when the source is on the same APFS volume: the copy becomes free and the import
  is bounded only by the hash read. This is the common "import a folder from the same disk" case and
  it is worth the branch.
- Read embedded metadata and any adjacent XMP during the same pass, while the file is already open.
- Build the thumbnail from the source's embedded preview during the same pass rather than reopening.
- Publish assets progressively, in import order. Already-committed assets are editable while the
  import continues.
- **Never modify or delete the external source.**

**Duplicate detection is a v1 requirement, not a v2 nicety.** Every byte is already hashed during
import, so the check is free. On a full content-hash match against an existing asset: do not silently
create a second asset — report it and let the user choose skip / import anyway. Without this,
reinserting an SD card silently doubles storage.

Import UI reports files, bytes, throughput, failures and estimated completion, and is cancellable at
any point without leaving a partial asset.

### 4.7 Deletion, trash and reclaiming space

**This is the highest-consequence area, because copy-on-import means the package holds the only
copy.**

Three distinct operations, distinct in the UI:

1. **Remove from library** — writes a tombstone in the membership shard; the asset directory is moved
   to `Recovery/Quarantine/`. Reversible.
2. **Empty trash / reclaim space** — permanently deletes quarantined asset directories. Explicit,
   confirmed, reports bytes reclaimed, and is the *only* operation in the system that destroys an
   original.
3. **Remove reference** (referenced assets, §3.6) — drops the asset record; the external file is
   never touched.

Tombstones are retained indefinitely; they are tiny and they are what keeps a restored older backup
from resurrecting deleted photos.

No other code path may delete an original. Recovery quarantines; it does not delete (§6.3).

This package-native lifecycle is the production deletion boundary. KRMA-371's earlier
folder-backed behavior is historical; production package APIs operate only inside a
`.kromoralibrary` package: embedded originals are moved to
`Recovery/Quarantine/<assetID>` and can be restored, while referenced records are tombstoned
without touching the external source. Only an explicitly confirmed package reclaim transaction may
permanently remove a quarantined directory.

---

## 5. Transactions

Every mutation uses same-volume staging:

1. Write a transaction journal entry to `Recovery/Transactions/`.
2. Stream new files into staging.
3. Flush (`F_FULLFSYNC`) and checksum staged files.
4. Move immutable components into their final paths.
5. Atomically replace `asset.json`.
6. Mark the transaction committed.
7. Clean staging asynchronously.

**A valid original is never replaced or deleted during ordinary editing.**

On launch, any uncommitted journal entry is rolled back by discarding staging. On recovery, the
newest `asset.json` whose referenced files and checksums all validate is chosen.

`asset.previous.json` from the original sketch is **dropped**. It is a single-depth undo that the
transaction journal plus immutable edit revisions already provide; keeping both means two recovery
paths that can disagree.

### 5.1 Single-writer lease

`NSFileCoordination` is advisory and handles crash recovery, not concurrent openers. A second app
instance — or the same library on an external drive plugged into two machines — needs an explicit
lease.

- `manifest.lock`: writer UUID, device name, PID, heartbeat timestamp, refreshed every 30 s.
- On open, a live lease means **open read-only** with a clear "in use on <device>" message.
- A lease stale beyond a threshold (say 3 minutes) may be broken, after confirmation, with
  transaction rollback run first.
- The lease is released explicitly on quit and on library close.

Without this you get the Lightroom catalog-in-use failure, except silent and corrupting.

### 5.2 Checksums

Do **not** rehash all originals on launch.

- Hash each original once, while it streams into the package.
- Store byte count and SHA-256 in `asset.json`.
- Trust package originals during normal launch and navigation.
- Validate a specific original only when a read fails, or when size/attributes disagree with the
  record.
- Full scrubs run only via explicit validation, verified backup, restore, or scheduled low-priority
  maintenance — always cancellable, always with progress.

---

## 6. Failure handling

### 6.1 Preflight

Check package writability and available capacity before import, backup or restore. Fail before
starting, not halfway.

### 6.2 Recoverable import failures

Cancellation, disk-full, source removal, malformed XMP and checksum mismatch are all **recoverable**:
the import continues with the remaining files and reports the failures. A partial asset is never
published.

### 6.3 Critical vs. rebuildable loss

| Critical (user must be told, may block) | Rebuildable (silently regenerate) |
| --- | --- |
| Missing original | Thumbnail |
| Missing or unparseable current edit revision | Preview |
| Corrupt `asset.json` with no valid predecessor | Local index |
| Corrupt membership shard | Mask raster, analysis result |

Note that Looks and masks are **absent from the critical column** by construction — §3.8 embeds cube
bytes in the edit revision, and §3.9 keeps mask definitions inside `EditDocument`.

### 6.4 Recovery never deletes

Uncertain files move to `Recovery/Quarantine/` with an audit entry in `Recovery/Audit/`. Destructive
cleanup is a user-initiated operation (§4.7), never an automatic one.

---

## 7. Backup and restore

With cloud sync out of scope, **verified backup is the entire redundancy story.** It carries more
weight here than it did in the original sketch and should be treated as a headline feature, not
plumbing.

"Back Up Library…" must:

1. Flush pending edits.
2. Acquire a coordinated, consistent snapshot.
3. Copy incrementally to a temporary destination (`clonefile` when same-volume; resumable otherwise).
4. **Verify every canonical component against its recorded checksum.** `Derived/` is excluded —
   copying it is optional and it is never a verification failure.
5. Atomically publish the destination package.
6. Resume or restart cleanly after cancellation.

Restore never overwrites the active package until the replacement has validated completely.

Finder copy and Time Machine remain supported and must work — that is much of the point of a package
— but the built-in operation is the guaranteed-consistent route while Kromora is writing.

---

## 8. Acceptance gates

Gates are written to be **deterministically assertable** wherever possible. A p95 latency band
narrower than thermal variance on a Mac is not a gate, it is a coin flip.

### 8.1 Hard invariants (assert directly; these are the real gates)

- Zero synchronous main-actor file I/O, hashing or XMP parsing during any edit, navigation or scroll.
- No main-thread stall exceeding one frame budget during ordinary editing.
- Editing one asset touches **O(1)** files and never rewrites an O(library-size) structure.
- Import reads each original exactly once for copy + checksum.
- A warm launch obtains its first indexed page without walking asset directories, parsing XMP, or
  reading any original.
- A 100,000-asset warm library materialises neither 100,000 observable objects nor 100,000 decoded
  thumbnails; counts are asserted directly.
- Visible thumbnail work is never queued behind index rebuild, validation, import or maintenance.
- Background work suspends or yields under editor contention.
- Package relocation to a new path and filesystem produces identical render and cache identity.
- Bounded file-descriptor count under sustained import + scroll.
- Cold index rebuild publishes its first page after reading only membership shards.

### 8.2 Performance gates (statistical; require a committed baseline)

**Capture and commit baseline numbers from the existing benchmark lane before phase 1 lands.**
Without a locked pre-package baseline, every later number is unfalsifiable.

- Interactive preview submission and first-visible latency: **p95 within 15%** of baseline, with a
  hard **p99.9 stall gate of one frame budget**. (The original 5% p95 target is inside measurement
  noise; the p99.9 stall gate is the property that actually matters to feel.)
- Filter and sort latency independent of original file size, and sublinear in library size.
- Memory bounded as the library grows: decoded thumbnails, open XMP documents and edit records all
  under explicit count/cost limits, asserted at 1k / 10k / 100k.
- Validation and backup may scale linearly with bytes, but must remain cancellable, resumable where
  safe, and honest about progress.

### 8.3 Required test coverage

- Warm and cold launch at 1,000 / 10,000 / 100,000 assets (synthetic generator, phase 0).
- Scrolling and filtering a generated 100,000-record library.
- Edit persistence concurrent with thumbnail generation, import, index rebuild and backup.
- Import throughput and peak memory with large RAW files.
- **Fault injection after every transaction boundary.**
- Disk-full, cancellation, truncated XMP, damaged edit JSON, missing original, corrupt index,
  corrupt membership shard.
- Lease contention: second opener, stale lease, lease broken mid-write.
- Unknown-key round-trip: newer-schema fields survive an older-build rewrite.
- Duplicate import detection.
- Package relocation across paths and filesystems.
- Verified backup and restore onto a profile with no Application Support, Caches, UserDefaults or
  index.
- Existing render, Metal presentation, single-view latency, concurrent export/edit, mask and
  large-library benchmarks, retained as regression gates.

---

## 9. Phasing

The original sketch was one atomic deliverable, which is how work of this size stalls. Each phase
below is independently shippable and de-risks the next.

### Phase 0 — Spike and baseline *(historical; completed)*

- Synthetic library generator: 1k / 10k / 100k assets with plausible metadata distributions. This is
  the single most reused artefact in the whole project — build it properly, and keep it.
- Capture and **commit** the pre-package performance baseline from the existing benchmark lane.
- Prototype the packed thumbnail format and measure cold-scan cost versus one-file-per-asset, to
  confirm §3.10 earns its complexity.

**Exit:** committed baseline numbers, a working generator, and a thumbnail-packing decision.

### Phase 1 — Portable identity *(historical; completed)*

Replace path/inode identity with UUIDs across `PhotoAssetID`, `PhotoSourceFingerprint`,
`RenderCacheKey`, `MaskStore`, `PreviewDiskCache` and `EditRecord`. Existing local edits are
discarded (§2).

Self-contained, mechanical, highly testable, and it unblocks everything else. Reviewable on its own.

**Exit:** relocating a source folder preserves cache identity; §8.1 relocation gate passes.

### Phase 2 — Package format, transactions, import *(historical; implemented)*

Manifest, membership shards with summaries, asset records, edit revisions, XMP, transactions, lease,
copy-on-import with dedup and `clonefile`, referenced-asset fields written but unexposed.

**No index.** Enumerate membership shards at launch. This is entirely adequate at 10k and it proves
the format without entangling the SwiftData rewrite.

**Exit:** a real library that survives copy to another disk; fault-injection suite green.

### Phase 3 — Paged library model and index demotion *(historical; implemented)*

`LibraryQueryController`, paged summaries, UUID-keyed selection, index-side filtering. `EditRecord` /
`EditDocumentStore` replaced by package sidecars plus a bounded in-memory cache (§4.2). Scheduler
coordination uses the current `ImageWorkScheduler`; this phase text is not a specification of every
current lane or concurrency limit.

The largest and riskiest phase. It is also the one that only pays off at scale, which is why it comes
after the format is stable.

**Exit:** §8.1 scale invariants pass at 100,000 assets.

### Phase 4 — Backup, restore, validation, maintenance *(historical; implemented)*

Verified backup, restore, explicit validation, trash and reclaim-space (§4.7), revision compaction,
thumbnail pack compaction.

**Exit:** restore onto a clean user profile reproduces every edit.

---

## 10. Open questions

- Does `clonefile()` on a staged-then-moved import interact badly with the transaction model on
  APFS-with-snapshots? Verify in phase 2.
- Tombstone retention is unbounded by design. At what asset-churn volume does that stop being free?
- Should `Derived/Previews/` shard like everything else, or is per-asset acceptable given previews
  exist only for recently-edited assets? Decide with phase 0 data.
- Referenced assets (§3.6) reserve the format but ship no UI. Is there a phase 5 that exposes them,
  or does copy-only remain the product position?
