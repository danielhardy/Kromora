# Kromora storage policy

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
| Settled previews | `PortableLibraryPackage` | Package `Derived/Previews/` | Optional package-derived cache; safe to delete and regenerate | Optional; omitted from verified backup and reported only as a rebuildable gap |
| Packed thumbnails | `PortableLibraryPackage` | Package `Derived/Thumbnails/` | Optional package-derived cache; compacted during maintenance | Optional; missing/stale packs regenerate from originals |
| Recovery journals, transaction staging, quarantine and audit | `PortableLibraryPackage` | Package `Recovery/` | Package-local recovery boundary; journals/staging are removed after commit, while quarantine remains until reclaim/restore | Recovery is resolved before open; the built-in backup omits transient `Recovery/` internals and restore starts with a clean recovery boundary |
| Library query/index projection | `LibraryIndexProjection` | `~/Library/Application Support/Kromora/Indexes/<library-id>/LibraryIndex.store` | Rebuildable projection; never package truth | Optional; restore rebuilds it from membership shards |
| Edit revision cache | `EditDocumentStore` (bounded in-memory cache) | In memory; no production standalone edit database is authoritative | Disposable cache updated after the package commit | Not required; edits are restored from package sidecars |
| GPU/Core Image/Metal render caches and transient render intermediates | `RenderEngine` | Process memory and system cache boundary as applicable | Device-specific and disposable | Never required; recreated on demand |
| Mask rasters | `MaskStore` | `~/Library/Caches/Kromora/Masks/` | Rebuildable device cache; mask recipes remain in edit revisions | Optional; missing or stale rasters are cache misses |
| Photo analysis and incomplete analysis | `PhotoAnalysisCache` | `~/Library/Caches/Kromora/PhotoAnalysis/` | Rebuildable and source-keyed | Optional; stale analysis is discarded/recomputed |
| Current-edit measurements | `CurrentEditMeasurementCache` | `~/Library/Caches/Kromora/CurrentEditMeasurement/` | Rebuildable, edit-specific device cache | Optional; recomputed from the current edit |
| Non-package preview cache (legacy/test clients only) | `PreviewDiskCache` | `~/Library/Caches/Kromora/DevelopedPreviews/` | Disposable fallback when no package session is active | Never required |
| User-visible exported images | `ExportCoordinator` | Configured folder, otherwise `~/Pictures/Kromora Exports/` (created when the export panel opens) | User-owned output; never hidden Application Support | Finder/Time Machine/iCloud behavior follows the chosen folder; Kromora does not claim it as package data |
| User-created/imported reusable Looks | `LUTLibrary` | Configured folder, otherwise `~/Pictures/Kromora Looks/` | User-owned output; visible and independently reusable | Finder/Time Machine/iCloud behavior follows the chosen folder; edits remain safe through embedded Look bytes |
| Preferences and security-scoped bookmarks | `KromoraSettings` / workflow owners | `UserDefaults` | Operational configuration, not library content | Not required for package portability; users may need to reselect external folders on another Mac |
| Import/save scratch files and partial export files | Coordinating workflow | System temporary directory or destination-adjacent `.partial` file | Transient; removed on completion/failure | Never required; cancellation cleanup is best-effort |

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
