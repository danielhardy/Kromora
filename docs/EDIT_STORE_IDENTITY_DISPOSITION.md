# EditStore identity cutover and current-data disposition

Status: implemented for KRMA-399. The decision below is governed by
[ADR-001](../.dg/decisions/ADR-001-portable-library-package-sequencing-and-safety-b.md).

## What was found

Kromora is a development-stage macOS app. It has no shipped user data or supported upgrade
population. The current local `EditStore.store` is SwiftData development data under Application
Support; it is not a released library format. Before this change, an `EditRecord` used a string
derived from `PhotoAssetID` as its unique key and stored source path/bookmark fields for folder
relinking.

## Approved disposition

On 2026-09-13, a human approved the no-shipped-user-data clean-slate disposition and acknowledged
the risk that existing local development edits need not survive the identity cutover. A migration
of those records was not approved or implemented.

## Implementation

The app now opens `EditStore.v2.store`, whose `EditRecord.assetID` is an opaque UUID derived from
`PortablePhotoAssetID`. Direct load, save, and delete lookups use that UUID exclusively. The former
`EditStore.store` is not opened, migrated, deleted, or overwritten by the app factory; it remains
available for support inspection or a future separately approved migration. This makes the
clean-slate reset explicit and reversible at the file boundary, rather than silently dropping or
rewriting records.

Source paths and bookmarks remain only as operational relinking hints for the referenced-folder
editor. They are not persistence keys or portable identity fields. KRMA-371 deletion behavior is
unchanged and is deliberately outside this cutover.

Tests cover UUID-keyed round trips across relocated URLs, direct-key precedence, collision/relink
behavior, corrupt documents, failed writes, and the existing editor/import persistence paths using
synthetic data only.
