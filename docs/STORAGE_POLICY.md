# Kromora storage policy

The MVP intent is summarized in [`PRODUCT_SCOPE.md`](PRODUCT_SCOPE.md). This document is the current
runtime authority for package ownership and data safety; historical format proposals do not override
the behavior described here or in the shipped code.

This is the runtime storage contract for the portable library cutover. A path is not authoritative
because it happens to be under a familiar directory: the owner and lifecycle below determine what a
backup must preserve.

The portable package is the only production library source of truth. Folder selection, Photos, and
removable-volume selection are import sources. The local index and device caches are projections.
Existing standalone `EditStore*.store` files and legacy standalone locations are left untouched and
are not opened as a fallback or alternate authority; see
[`EDIT_STORE_IDENTITY_DISPOSITION.md`](EDIT_STORE_IDENTITY_DISPOSITION.md).

| Artifact | Canonical owner | Location | Lifecycle | Backup / restore |
| --- | --- | --- | --- | --- |
| Package manifest, membership/catalog summaries, asset records | `PortableLibraryPackage` | `~/Pictures/Kromora Library.kromoralibrary/manifest.json`, `Catalog/`, `Assets/` | Durable; transactionally committed | Required and checksum-verified; restored before the local index is rebuilt |
| Managed originals | `PortableLibraryPackage` | Package `Assets/<shard>/<asset>/Original/` | Durable; copied on import | Required and checksum-verified |
| Supported metadata and XMP foreign packets | `PortableLibraryPackage` | Package `Assets/<shard>/<asset>/Metadata/` | Durable, revisioned when interoperable metadata changes | Required and checksum-verified; malformed sidecars are a critical validation finding |
| Edit revisions and embedded Look bytes | `PortableLibraryPackage` | Package `Assets/<shard>/<asset>/Edits/` and content-addressed `Looks/` blobs | Durable and immutable by revision | Required and checksum-verified; an edit never depends on the external Look browser |
| Latest presentation frame (one 2048 px preview per asset) | `LatestPreviewFrameStore` | Package `Derived/Previews/<asset-hash>.kframe` | Optional package-derived cache; one atomically replaced envelope per asset, 1 GB LRU cap, safe to delete and regenerate | Optional; omitted from verified backup and reported only as a rebuildable gap |
| Packed thumbnails | `ThumbnailFrameStore` (actor facade over `PortablePackagePackedThumbnailStore`) | Package `Derived/Thumbnails/` | Optional package-derived cache; at most two live records per asset (`original` and latest `edited`) under stable asset-UUID keys; a replacement appends bytes and moves the index pointer; compacted during maintenance | Optional; missing, stale, or corrupt records regenerate from originals and never block open |

Both frame stores accept and retain frames only when the frame identity and its signature refer to
resolved source identities. A browsing placeholder contains no source-byte fingerprint, so writes
with one are skipped; legacy placeholder records become misses and are removed when read or during
bounded, background-priority idle sweeps. Sweeps inspect at most eight records per tick and yield
to visible frame work. These records are optional presentation caches and are never package truth.
| Recovery journals, transaction staging, quarantine and audit | `PortableLibraryPackage` | Package `Recovery/` | Package-local recovery boundary; journals/staging are removed after commit, while quarantine remains until reclaim/restore | Recovery is resolved before open; the built-in backup omits transient `Recovery/` internals and restore starts with a clean recovery boundary |
| Library query/index projection | `LibraryIndexProjection` | `~/Library/Application Support/Kromora/Indexes/<library-id>/LibraryIndex.store` | Rebuildable projection; never package truth | Optional; restore rebuilds it from membership shards |
| Launch hints | `LaunchHintsStore` | `~/Library/Application Support/Kromora/LaunchHints.json` | Device-local, bounded, atomically replaced operational hint; safe to delete and regenerate | Excluded from backup; never required to open or navigate the package |
| Edit revision cache | `EditDocumentStore` (bounded in-memory cache) | In memory; no production standalone edit database is authoritative | Disposable cache updated after the package commit | Not required; edits are restored from package sidecars |
| GPU/Core Image/Metal render caches and transient render intermediates | `RenderEngine` | Process memory and system cache boundary as applicable | Device-specific and disposable | Never required; recreated on demand |
| Mask rasters | `MaskStore` | `~/Library/Caches/Kromora/Masks/` | Rebuildable device cache; mask recipes remain in edit revisions | Optional; missing or stale rasters are cache misses |
| Photo analysis and incomplete analysis | `PhotoAnalysisCache` | `~/Library/Caches/Kromora/PhotoAnalysis/` | Rebuildable and source-keyed | Optional; stale analysis is discarded/recomputed |
| Current-edit measurements | `CurrentEditMeasurementCache` | `~/Library/Caches/Kromora/CurrentEditMeasurement/` | Rebuildable, edit-specific device cache | Optional; recomputed from the current edit |
| User-visible exported images | `ExportCoordinator` | Configured folder, otherwise `~/Pictures/Kromora Exports/` (created when the export panel opens) | User-owned output; never hidden Application Support | Finder/Time Machine/iCloud behavior follows the chosen folder; Kromora does not claim it as package data |
| User-created/imported reusable Looks | `LUTLibrary` | Configured folder, otherwise `~/Pictures/Kromora Looks/` | User-owned output; visible and independently reusable | Finder/Time Machine/iCloud behavior follows the chosen folder; edits remain safe through embedded Look bytes |
| Preferences and security-scoped bookmarks | `KromoraSettings` / workflow owners | `UserDefaults` | Operational configuration, not library content | Not required for package portability; users may need to reselect external folders on another Mac |
| Import/save scratch files and partial export files | Coordinating workflow | System temporary directory or destination-adjacent `.partial` file | Transient; removed on completion/failure | Never required; cancellation cleanup is best-effort |

## Latest presentation frame

`Derived/Previews/` holds at most one `<asset-hash>.kframe` per asset, named from the portable asset
UUID only (never a path, URL, or source fingerprint), so a replaced source overwrites its
predecessor. Each file is one envelope — magic, `storageFormatVersion`, bounded header length, JSON
metadata, JPEG — written atomically, so a crash can never pair new metadata with an old raster.
Every length is validated against the file size before any buffer is allocated.

- **Two independent versions.** `RenderPipeline.pixelEpoch` changes when identical inputs would
  render different pixels; it is stored in each frame's `FrameSignature`, and a mismatch makes the
  frame *stale-compatible* (shown, then refined once). `PresentationFrameEnvelope.storageFormatVersion`
  changes only when the container cannot be decoded; a mismatch is a per-entry miss. Neither value
  ever wipes the directory.
- **Damage is per entry.** A corrupt or truncated file is removed and reported as a miss; an
  unsupported container version is ignored until the next write replaces it. No error reaches
  presentation.
- **Budget.** The 1 GB cap is enforced incrementally from an in-memory index loaded off the main
  actor on first use (construction performs no I/O). Eviction is strict LRU except for pinned assets
  (the active photo). Writes coalesce per asset.
- **Legacy files.** `preview-*.jpg` and the old `version` file are never read. They are deleted a few
  at a time after the index loads, off the main actor.
- **Truth.** A frame is a hint for presentation only. It is never used for export, masks, analysis,
  or full-resolution work, and deleting all of `Derived/Previews/` costs render time, never
  correctness.

## Packed thumbnail frames

`Derived/Thumbnails/` stores at most the live original and latest edited frame per asset. Writes
coalesce by stable asset key and rewrite the packed index once per batch: after 250 ms with no new
write, at 32 pending records, on an explicit flush, or at the two-second maximum pending age
measured from the first write in the batch. The age deadline is fixed while the batch receives more
writes, so continuous activity cannot keep settled frames in memory indefinitely. Under a successful
cache write, the newest batch has a two-second maximum in-memory loss window; count-triggered writes
may publish it earlier. A failed append keeps the batch pending for retry and leaves the last
published index as the readable state. These frames remain disposable cache data and can always be
regenerated from package originals.

## Backup and restore semantics

The built-in verified backup copies the manifest, catalog, originals, metadata, edit revisions, and
Look blobs, then writes its own verified `Recovery/Backup/` metadata. It excludes transient package
recovery internals and may omit `Derived/` because previews and thumbnails are optional. Validation
therefore has two explicit buckets: `criticalFailures` for package truth and
`rebuildableGaps` for derived/package caches and supplied local projections. A missing cache, stale
index, or incomplete analysis must never make a package fail to open.

Finder and Time Machine see the package as an ordinary Pictures package and therefore copy whatever
package-derived files happen to be present. iCloud Documents sync is out of scope; if a user puts a
package or an export/Look folder in an iCloud-managed directory, macOS/iCloud owns that behavior and
Kromora still treats only the package's canonical components as required. On restore to a clean
profile, the package is validated and the local index is rebuilt from membership shards; GPU,
preview, thumbnail, mask, analysis, and current-edit caches are regenerated as needed.

No production package operation reads or writes the legacy Application Support library folder,
standalone edit store, or hidden standalone Look folder as an authoritative copy. Those paths remain
untouched for support/disposition purposes.

## Membership summary source identity

Each live membership summary stores the complete `PortablePhotoSourceFingerprint` from its asset
record: content hash, source revision, decoder version, and optional decoded geometry. This field is
denormalized package truth for browsing, not a second authority. It lets the launch index and grid
construct the exact same `PortablePhotoIdentity` as Edit without opening every asset record. The
membership shard and asset record are updated in one package transaction when import or source
replacement changes identity.

Older packages decode a missing fingerprint as `nil`; the package format version does not change.
After the library index is published, a background, resumable repair reads missing records with at
most two concurrent reads and commits fingerprints in small transactions. Each committed batch is
valid on its own, and a later launch resumes the remaining summaries. The disposable local index
round-trips this optional field and can always be rebuilt from the membership shards. The summary
field is rebuildable from `asset.json`, so a missing or stale summary remains safe and is repaired
without making the package unavailable.
