# Portable library package format

Phase 2.1 defines the format-only layer. It is a read/write contract; transaction journals, import,
edit sidecars, and catalog canonicalisation are separate phases.

```text
<library>.kromoralibrary/
  manifest.json
  Catalog/Membership/00.json … ff.json
  Assets/<first-two-uuid-hex>/<asset-uuid>/asset.json
  Assets/<first-two-uuid-hex>/<asset-uuid>/Original/source.<ext>
  Assets/<first-two-uuid-hex>/<asset-uuid>/Edits/<revision>.json
  Assets/<first-two-uuid-hex>/<asset-uuid>/Metadata/<revision>.xmp
  Looks/<sha256>.cube
  Recovery/Quarantine/<asset-uuid>/          # package-owned removed assets
```

All JSON objects are UTF-8. Writers emit sorted known keys. Unknown top-level members are retained
as their original JSON member bytes when a record is read and rewritten; this permits additive
schema evolution without silently deleting fields from a newer producer.

`manifest.json` contains:

| Key | Type | Meaning |
| --- | --- | --- |
| `formatVersion` | integer | Package format version. |
| `libraryID` | UUID string | Opaque package identity. |
| `createdAt`, `createdBy` | ISO-8601 string | Creation information. |
| `writerVersion`, `minimumReaderVersion` | string | Compatibility markers. |
| `membershipShardCount`, `membershipShardPrefixLength` | integers | `256` shards selected by two lowercase hex UUID characters. |
| `featureFlags` | string → boolean | Additive capabilities. |
| `recoveryFormatVersion` | integer | Reserved for the transaction/recovery phase. |

Each membership shard has `shard` and `entries`. An entry contains `assetID`, the package-relative
`recordPath`, `addedRevision`, optional `deletedRevision`, `isTombstone`, and a `summary`. The summary
contains capture date, rating, flag, label, camera make/model, lens, pixel dimensions, aspect ratio,
display name, and the current asset revision. It is sufficient for membership, rough-state, sort,
and filter work without opening `asset.json`.

An `asset.json` record contains `identity` (the KRMA-390 opaque UUID plus immutable source
fingerprint), `source` (embedded relative path or reserved referenced bookmark), `isRemoved`,
`currentRevision`, and `editHistory` pointers. `isRemoved` is false for active records and true for
records retained in package-native quarantine (older records without the field decode as false).
Each edit pointer has a revisioned Kromora JSON path and an optional XMP path. Paths are locators
only. They are resolved against the package root at the render boundary and never enter portable
identity or cache keys.

## Edit revisions and Looks

Every edit commit appends a new immutable `Edits/<revision>.json` document. The document contains
the complete `EditDocument` plus content-addressed Look references. The matching
`Metadata/<revision>.xmp` packet carries the asset UUID, revision, and the exact Kromora document in
the `kromora:` namespace, so an XMP-aware tool can identify the revision without understanding
Kromora's render graph. A reader validates that the two representations agree.

Malformed or truncated XMP is a critical edit-data error: it is reported as a typed read failure and
can be moved to `Recovery/Quarantine/` for support/rebuild workflows. It is never replaced with a
neutral document silently.

Look bytes are embedded in `Looks/<sha256>.cube`. Multiple assets and revisions can point to the
same content hash, so one byte-identical Look is stored once while each revision remains
self-contained from the user-facing Look browser.

The `source.storage = "referenced"` form and its optional security-scoped bookmark are reserved
schema fields. This phase round-trips them but exposes no referenced-asset UI or resolver behavior;
copy-on-import remains the only product workflow.

The format creates all 256 shard files, including empty shards. Asset and shard writes validate UUID
shard placement and reject absolute paths, backslashes, empty path components, and `..` traversal.

## Package-native trash

Package-native trash is separate from KRMA-371's existing folder-backed Library deletion workflow.
KRMA-371 continues to manage the current referenced-folder/managed-copy library, including its
existing macOS Trash behavior; this package lifecycle does not call that workflow or change it.

For a package-owned embedded asset, **Remove from library** atomically tombstones the membership
entry, marks the asset record removed, and moves the complete `Assets/<shard>/<assetID>/` directory
to `Recovery/Quarantine/<assetID>/`. The original and edit sidecars remain recoverable until the
user restores the asset or explicitly confirms **Reclaim space**. Restore reverses the move and
clears the tombstone. The tombstone remains in the membership shard after reclaim so an older backup
cannot resurrect the asset.

Referenced assets are never moved, opened, or deleted by these operations. Remove marks only the
package record and membership entry; reclaim reports the referenced asset as skipped. The external
file lifecycle remains with its owner.

Reclaim stages each quarantined directory into the transaction journal's same-volume staging area
and deletes it only when the explicitly confirmed reclaim transaction commits. No ordinary package
write, recovery rollback, edit operation, or automatic maintenance path may permanently delete an
original.
