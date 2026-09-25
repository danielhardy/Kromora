---
id: KRMA-564
title: Extract library window, selection, and culling from AppViewModel
type: task
status: backlog
priority: medium
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - architecture
  - maintainability
  - appviewmodel
created: 2026-09-24T15:18:52.736Z
updated: 2026-09-24T15:19:43.417Z
depends_on:
  - KRMA-467
blockers: []
order: p
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Sources/KromoraKit/ViewModels/LibraryDeletionCoordinator.swift
    - Sources/KromoraKit/ViewModels/LibraryImportCoordinator.swift
    - Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift
    - Tests/KromoraKitTests/LibraryWindowedBrowsingTests.swift
    - Tests/KromoraKitTests/LibraryCullingTests.swift
    - Tests/KromoraKitTests/LibraryDeletionTests.swift
    - Tests/KromoraKitTests/LibrarySelectionTests.swift
    - Tests/KromoraKitTests/LibraryDeletionCoordinatorTests.swift
  docs:
    - docs/APP_ARCHITECTURE.md
  issues:
    - KRMA-460
    - KRMA-467
    - KRMA-551
  commands:
    - swift build
    - swift test --filter 'LibraryBrowsingCoordinatorTests|LibraryWindowedBrowsingTests|LibraryCullingTests|LibraryDeletionTests|LibrarySelectionTests'
    - scripts/ci-tests.sh fast
    - dg validate
    - git diff --check
---

Parent: KRMA-460. Start only after KRMA-467 is `done`. Both tickets edit `AppViewModel.swift`.

## Objective

Move portable-library window, selection, and culling sequencing out of `AppViewModel` into a `LibraryBrowsingCoordinator`. The root keeps source loading and the edit handoff.

`AppViewModel.swift` is 4,560 lines after KRMA-466. Line numbers below are from 2026-09-24; search by symbol if they drift. This ticket removes the library-window cluster. It does not try to get the file under 2,000 lines by itself.

## Why this is a coordinator

`PortableLibrarySession` already owns the query index. `ImageCollection` already owns the visible window and culling values. `LibraryDeletionCoordinator` already performs the destructive delete and returns a `LibraryDeletionResult`. What remains on the root is the sequencing that reloads pages, mirrors selection, persists flag/rating, and decides what the window shows after a delete. That sequencing is the owner to extract.

Follow `LibraryDeletionCoordinator` for value results, and `MaskingWorkflowDestination` for the narrow callback back into the root. Name the type `LibraryBrowsingCoordinator`. Do not store an `AppViewModel`.

## Move these methods

Search by name. They currently sit in two mislabeled MARKs ("Image loading" and "Copy and paste"), not in one block.

Portable window and selection, about lines 1601–1794:

- `reloadPortableCollection()`
- `reloadPortableWindow(pageIndex:)`
- `loadMorePortableIfNeeded(currentIndex:)`
- `setPortableFilter`, `setPortableSort`, `setPortableSearch`
- `selectPortableItem(at:modifiers:)`
- `selectNextPortableInGrid()`, `selectPreviousPortableInGrid()`
- `portableID(for:)`
- `openPortableAsset(_:)` — page-fault the containing window, then call the destination's `openImage`. Do not move `openImage`.

Culling, about lines 3072–3125:

- `selectLibraryItem(at:modifiers:)`
- `setFocusedFlag(_:advance:)`
- `setFocusedRating(_:)`
- `undoCullingChange()`
- `persistPortableLibraryStateIfNeeded()`

Deletion confirmation, about lines 2757–2776:

- `requestDeleteSelectedLibraryItems()`
- `confirmDeleteSelectedLibraryItems()`

`@Published portableQuery` and `@Published libraryDeletionConfirmation` stay on `AppViewModel` so existing SwiftUI bindings compile. The coordinator reads and writes them through the destination. `refreshSource()` stays on the root and calls `reloadPortableCollection()` plus the existing idle-preview cancel.

## Stay on AppViewModel

These methods open a photo or reset the editor. They call into the new coordinator; their bodies stay here.

- `openImage`, `load`, `install`, `adoptStoredEdits`, `presentEmbeddedFirstFrame`
- `navigate(to:)`, `setEditMode()`, `openActiveCollectionImage`, `openLibraryImageForEditing`
- `selectCollectionImage(at:modifiers:)` and `selectPreviousImage` / `selectNextImage` — they select, then call `openImage` or `load`
- `deleteLibraryItems` remains the cross-feature sequencer. It may call the coordinator for collection and portable-selection sync. It still calls `editedThumbnailCoordinator.removeAssets`, `editorDocument.removeSessions`, preview-cache invalidation, `engine.invalidateRenderCaches`, and then either `openActiveCollectionImage` or `clearActiveSourceAfterLibraryDeletion`
- `clearActiveSourceAfterLibraryDeletion()` — it clears the document, preview surfaces, histogram, and Auto. That is composition-root teardown
- Folder drop, Photos import, and removable-volume scanning. `LibraryImportCoordinator` and `LibraryMediaWorkflowCoordinator` already own those
- `updateDocument`, `shutdown`, preview admission, preview publication

`setFocusedFlag` in Edit mode calls `selectCollectionImage` after a rapid-cull advance. That call stays a destination callback so the coordinator does not own source loading.

## Behavior to preserve

- `reloadPortableWindow` loads one query page into `ImageCollection`, mirrors `portableSelectedIDs` / `portableActiveID`, and starts thumbnail demand. Filtering, sorting, and search reload page 0.
- `loadMorePortableIfNeeded` appends the next page only when the index is within one page of the tail. Grid keyboard stepping faults that page before moving past the last loaded item.
- Shift-click uses the collection's ordered window; Command-click toggles through `portableLibrary.togglePortableSelection`. Ordinary click replaces the selection. After every path, `syncPortableSelection` runs.
- `openPortableAsset` selects in the query controller first. An on-window item opens through `resolveEmbeddedSourceURL`. An off-window item faults its page, bounded by the existing `pageIndex * pageSize > 200_000` stop, then opens. A missing asset sets the existing status string and does not call `openImage`.
- Flag and rating changes persist with `portableLibrary.updateLibraryState`. A write failure uses `presentError`. Rapid-cull advance in Edit still loads the newly focused photo.
- Delete confirmation is captured from `collection.deletionCandidates` only while the grid is showing. Confirm clears the confirmation and performs the existing async delete. An empty selection sets "Select at least one photo to remove".

## Tests and docs

Add `Tests/KromoraKitTests/LibraryBrowsingCoordinatorTests.swift`. Fakes only, no `AppViewModel`, no package I/O. Cover:

- filter/sort/search reload page 0 and skip a no-op when the query is unchanged
- keyboard next at the window tail requests one more page before selecting
- off-window `openPortableAsset` faults a page and then asks the destination to open; a missing asset does not
- culling persistence is attempted after a flag change and skipped when nothing changed
- deletion confirmation is refused outside the grid

Keep these suites green:

- `LibraryWindowedBrowsingTests`
- `LibraryCullingTests`
- `LibraryDeletionTests`
- `LibrarySelectionTests`
- `FilmstripNavigationTests` selection and open cases

Add a "Library browsing ownership" section to `docs/APP_ARCHITECTURE.md` and a row in the boundaries table. State that the root still owns the edit handoff and `clearActiveSourceAfterLibraryDeletion`.

## Checks

- `swift build`
- `swift test --filter 'LibraryBrowsingCoordinatorTests|LibraryWindowedBrowsingTests|LibraryCullingTests|LibraryDeletionTests|LibrarySelectionTests'`
- `scripts/ci-tests.sh fast`
- `dg validate`
- `git diff --check`

Swift 6: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.

## Out of scope

Preview publication (KRMA-565). Preview admission (KRMA-467). Import package writes (KRMA-551). Turning one-line export, Look, or crop forwarders into new files.
