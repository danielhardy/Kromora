---
id: KRMA-430
title: Activate the Pictures-backed portable library as the production canonical store
type: feature
status: claimed
priority: high
agent: codex
model: gpt-5.6-luna
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - library
  - storage
  - architecture
  - import
created: 2026-09-14T03:06:01.414Z
updated: 2026-09-14T03:54:50.383Z
order: n
board: product
claim:
  actor: codex
  session: 01MU0PLUVJRY43UURV
  claimed_at: 2026-09-14T03:54:50.382Z
  expires_at: 2026-09-14T04:54:50.382Z
  model: gpt-5.6-luna
---

## Objective

Make the portable package implemented by KRMA-391 through KRMA-415 the real, user-visible Kromora library. A clean first launch should create or open one canonical package at:

`~/Pictures/Kromora Library.kromoralibrary`

The package, not Application Support and not the legacy folder-backed collection, must become the source of truth for managed originals, catalog membership, edits, embedded Looks, previews, thumbnails, and recovery metadata.

## Context

The package format, transactions, import primitives, index, backup/restore, validation, and maintenance exist, but production wiring is incomplete. `KromoraStorage.defaultPortableLibraryPackageURL` currently points to Application Support, and `AppViewModel` only schedules maintenance when an already-existing package is present. The ordinary import/open/edit flow still uses the legacy folder-backed library and standalone SwiftData store.

Relevant existing work:

- KRMA-391 through KRMA-415
- `Sources/KromoraKit/Models/KromoraStorage.swift`
- `Sources/KromoraKit/Models/PortableLibraryPackage.swift`
- `Sources/KromoraKit/Models/EditDocumentStore.swift`
- `Sources/KromoraKit/Models/LibraryQueryController.swift`
- `docs/LIBRARY_PACKAGE_PLAN.md`
- `.dg/decisions/ADR-001-portable-library-package-sequencing-and-safety-b.md`

## Acceptance criteria

- [ ] Resolve the default package through the user's Pictures directory and use the exact documented package name/extension; create it safely on first launch and reuse it on later launches.
- [ ] Add the required package/document declaration and sandbox Pictures entitlement, with packaging/signing tests or an explicit manual verification artifact.
- [ ] Open the package before exposing the library UI; use the package-backed index/query session for membership, paging, filtering, sorting, and UUID selection.
- [ ] Make package-backed edits canonical through the existing projection boundary; deleting SwiftData/Application Support projection data must not lose edits or Looks.
- [ ] Route folder, single-image, Photos, and removable-media imports through copy-on-import before an asset becomes editable or visible as a managed asset. External sources remain untouched.
- [ ] Define and implement clean behavior for a missing, placeholder, corrupt, locked, or conflicting package: no silent overwrite, empty-library fallback, or second hidden library.
- [ ] Preserve backup, restore, validation, quarantine, deletion, cancellation, and termination-flush guarantees from the completed package tickets.
- [ ] Keep legacy development data untouched because the product is pre-release; no implicit migration or destructive cleanup is allowed.
- [ ] Add integration coverage for clean-profile first launch, relaunch, package relocation, package copy to another path, package-open failure, and import/edit/relaunch.
- [ ] Run `swift build`, focused package/application tests, `scripts/ci-tests.sh fast`, `scripts/ci-tests.sh serial`, `dg validate`, and `git diff --check`.

## Out of scope

- iCloud Documents synchronization and multi-device conflict merge.
- Rewriting the package format or changing the established transaction protocol.
- Removing rebuildable caches; that is covered by the durable-data boundary ticket.
