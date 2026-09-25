---
id: KRMA-564
title: Extract library window, selection, and culling from AppViewModel
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: LibraryBrowsingCoordinator owns portable window paging, query/selection sync, off-window opens, culling persistence, and deletion confirmation; does not store AppViewModel
      result: pass
      notes: LibraryBrowsingCoordinator.swift holds only ImageCollection, a LibraryBrowsingProviding library, and a weak LibraryBrowsingDestination. AppViewModel's portableLibrary is a let set once at init, so the lazy-var capture at first coordinator access is safe.
    - criterion: AppViewModel retains source/edit handoff, deleteLibraryItems cross-feature sequencing, and clearActiveSourceAfterLibraryDeletion
      result: pass
      notes: AppViewModel.swift deleteLibraryItems (widened from private to internal for protocol conformance) still calls editedThumbnailCoordinator.removeAssets, editorDocument.removeSessions, preview-cache invalidation, and engine.invalidateRenderCaches; openImage, load, openActiveCollectionImage, and clearActiveSourceAfterLibraryDeletion untouched.
    - criterion: "Behavior preserved: page-0 reload on filter/sort/search no-op skip, keyboard tail paging, off-window open page-fault with 200_000 bound, shift/command/click selection semantics, culling persistence and rapid-cull advance, grid-only deletion confirmation"
      result: pass
      notes: Verified by reading LibraryBrowsingCoordinator.swift against the ticket's behavior spec; all details (200_000 scan bound, portablePageSize tail threshold, weak destination Task in confirmDeleteSelectedLibraryItems) match.
    - criterion: LibraryBrowsingCoordinatorTests.swift covers all 5 required cases with fakes only, no AppViewModel, no package I/O
      result: pass
      notes: testFilterSortAndSearchReloadPageZeroAndSkipNoOp, testKeyboardNextAtWindowTailLoadsNextPageBeforeSelecting, testOffWindowOpenFaultsItsPageAndMissingAssetDoesNotOpen, testCullingPersistsOnlyWhenStateChanges, testDeletionConfirmationIsRefusedOutsideGrid all present and pass.
    - criterion: Existing suites (LibraryWindowedBrowsingTests, LibraryCullingTests, LibraryDeletionTests, LibrarySelectionTests) stay green; docs/APP_ARCHITECTURE.md updated
      result: pass
      notes: 26/26 focused tests pass. docs/APP_ARCHITECTURE.md boundaries table row and a new Library browsing ownership section accurately describe the split.
    - criterion: swift build, focused tests, scripts/ci-tests.sh fast, dg validate, git diff --check all pass
      result: pass
      notes: All five re-run independently this session; see checks_run.
  checks_run:
    - "swift build: pass"
    - "swift test --filter 'LibraryBrowsingCoordinatorTests|LibraryWindowedBrowsingTests|LibraryCullingTests|LibraryDeletionTests|LibrarySelectionTests': 26/26 pass"
    - "scripts/ci-tests.sh fast: pass (exit 0, 1205/1205)"
    - "dg validate: OK (only pre-existing unrelated model-name/context-completeness warnings)"
    - "git diff --check: pass (exit 0)"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T05:16:29.791Z
  session: 01MUGI6Y7W9DBON9DO
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - architecture
  - maintainability
  - appviewmodel
created: 2026-09-24T15:18:52.736Z
updated: 2026-09-25T05:16:29.794Z
depends_on:
  - KRMA-467
blockers: []
order: a0
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


### Comment — codex @ 2026-09-25T05:11:22.421Z

Implemented LibraryBrowsingCoordinator for portable window paging, query and selection sync, off-window opens, culling persistence, and deletion confirmation. AppViewModel retains source/edit handoff and cross-feature deletion cleanup. Added five fake-driven coordinator tests and documented ownership. Checks passed: swift build; focused library suites (26 tests); scripts/ci-tests.sh fast (1,205 tests); dg validate; git diff --check. Commit: 2789196.

## Agent log

- 2026-09-25T05:16:29.791Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] LibraryBrowsingCoordinator owns portable window paging, query/selection sync, off-window opens, culling persistence, and deletion confirmation; does not store AppViewModel (pass) — LibraryBrowsingCoordinator.swift holds only ImageCollection, a LibraryBrowsingProviding library, and a weak LibraryBrowsingDestination. AppViewModel's portableLibrary is a let set once at init, so the lazy-var capture at first coordinator access is safe.
- [x] AppViewModel retains source/edit handoff, deleteLibraryItems cross-feature sequencing, and clearActiveSourceAfterLibraryDeletion (pass) — AppViewModel.swift deleteLibraryItems (widened from private to internal for protocol conformance) still calls editedThumbnailCoordinator.removeAssets, editorDocument.removeSessions, preview-cache invalidation, and engine.invalidateRenderCaches; openImage, load, openActiveCollectionImage, and clearActiveSourceAfterLibraryDeletion untouched.
- [x] Behavior preserved: page-0 reload on filter/sort/search no-op skip, keyboard tail paging, off-window open page-fault with 200_000 bound, shift/command/click selection semantics, culling persistence and rapid-cull advance, grid-only deletion confirmation (pass) — Verified by reading LibraryBrowsingCoordinator.swift against the ticket's behavior spec; all details (200_000 scan bound, portablePageSize tail threshold, weak destination Task in confirmDeleteSelectedLibraryItems) match.
- [x] LibraryBrowsingCoordinatorTests.swift covers all 5 required cases with fakes only, no AppViewModel, no package I/O (pass) — testFilterSortAndSearchReloadPageZeroAndSkipNoOp, testKeyboardNextAtWindowTailLoadsNextPageBeforeSelecting, testOffWindowOpenFaultsItsPageAndMissingAssetDoesNotOpen, testCullingPersistsOnlyWhenStateChanges, testDeletionConfirmationIsRefusedOutsideGrid all present and pass.
- [x] Existing suites (LibraryWindowedBrowsingTests, LibraryCullingTests, LibraryDeletionTests, LibrarySelectionTests) stay green; docs/APP_ARCHITECTURE.md updated (pass) — 26/26 focused tests pass. docs/APP_ARCHITECTURE.md boundaries table row and a new Library browsing ownership section accurately describe the split.
- [x] swift build, focused tests, scripts/ci-tests.sh fast, dg validate, git diff --check all pass (pass) — All five re-run independently this session; see checks_run.
Checks run:
- swift build: pass
- swift test --filter 'LibraryBrowsingCoordinatorTests|LibraryWindowedBrowsingTests|LibraryCullingTests|LibraryDeletionTests|LibrarySelectionTests': 26/26 pass
- scripts/ci-tests.sh fast: pass (exit 0, 1205/1205)
- dg validate: OK (only pre-existing unrelated model-name/context-completeness warnings)
- git diff --check: pass (exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGI6Y7W9DBON9DO
Summary: Re-verified LibraryBrowsingCoordinator extraction: correct ownership boundaries, all 5 required fake-based tests present and green, focused suite (26/26), fast CI lane (1205/1205), dg validate, and git diff --check all pass; docs updated accurately.
