---
id: ADR-936
title: Drop verified backup/restore and Open Library from the MVP; add relaunch-based library location setting
date: 2026-10-13T23:11:41.372Z
status: accepted
---

## Decision

Resolves KRMA-936 (review finding M6 in `.context/2026-10-13-release-readiness-review.md`).

1. **Backup/Restore is post-MVP.** `PortableLibraryBackup` / `PortableLibraryRestore` stay in the tree, tested but unwired. README and `docs/PRODUCT_SCOPE.md` stop listing "verified backup/restore" as shipped. The supported manual path is: quit Kromora, copy the `.kromoralibrary` package (Time Machine already covers `~/Pictures`). Restore is the same in reverse. KRMA-937 is closed unbuilt.
2. **No runtime Open/Switch Library, no Finder double-click handler.** Switching the session at runtime is a lifecycle change the MVP does not need. KRMA-938 is closed unbuilt. The `CFBundleDocumentTypes` entry is removed (KRMA-939) so Finder stops offering Kromora as an opener that does nothing.
3. **Library location becomes a Settings choice applied on relaunch** (new ticket), persisted as a security-scoped bookmark. This covers "point the app at another folder / restored copy" without swapping a live session.

## Rationale

- A backup without a supported way to open the result is a half feature. Quit-and-copy gives most of the safety (no live writer) for free; what verified backup adds (checksums, skipping `Derived/`, resumable staging) is not worth a coordinator, menu items and progress UI before release.
- `PortableLibraryRestore` swaps into the active path (old library renamed aside), contradicting KRMA-937 "never overwrite in place"; wiring it would have needed its own design pass.
- `AppLaunch` already injects `packageURL`, so a relaunch-based location is a small change; `AppViewModel` is near its 5,120-line guard and must not grow.

## Consequences

- Post-MVP: revisit verified backup/restore together with an in-app Open Library.
- Keep the exported UTI `com.kromora.kromoralibrary`; only the document-type claim is removed.
