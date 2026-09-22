---
id: KRMA-519
title: Drive the library UI from paged queries instead of full-library materialization
type: task
status: done
priority: high
agent: pi
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - performance
  - library
created: 2026-09-21T20:33:00.855Z
updated: 2026-09-21T23:15:04.347Z
depends_on:
  - KRMA-518
estimate: 13
order: t
board: product
commits:
  - 6dfc38d
---

## Objective

Make launch, reload, filtering, sorting, selection, grid, and filmstrip presentation use the paged LibraryQueryController projection instead of materializing every asset record and ObservableObject.

## Context and evidence

AppViewModel initialization and reloadPortableCollection call portableLibrary.materializedAssets. That walks every page and opens/decodes one JSON asset record per item on the main actor, then creates ImageCollection.Item objects for the entire library. At 100,000 assets this means 100,000 reads and observable objects at launch and after each import/deletion. The scale document's fast warm launch measures a paged query path that production does not actually use, so it currently gives false assurance.

LibraryQueryController already owns paging, sort, filter, and UUID selection, while ImageCollection duplicates filtering and selection. The two selection states can diverge.

## Scope, staged

1. Stop reading full asset records during materialization; derive grid metadata from LibraryIndexEntry.summary and resolve full records lazily for opening, exporting, and edit reads.
2. Make grid and filmstrip consume a windowed/page-backed data source keyed by PortablePhotoAssetID.
3. Move filter, sort, and selection to LibraryQueryController as the single authority; make ImageCollection a thin thumbnail/visible-window adapter or remove it if appropriate.
4. Update the scale fixture and LIBRARY_SCALE_REGRESSION.md to measure the actual AppViewModel production launch, first grid frame, and import/reload path at 10k and 100k assets.

## Acceptance criteria

- [ ] Launch and reload do not open non-visible asset records; a read observer in the scale fixture proves this.
- [ ] Grid and filmstrip render the visible page/window and preserve stable identity across page changes.
- [ ] Only one selection model remains authoritative, including keyboard navigation, culling, and opening an asset.
- [ ] Filtering and sorting preserve current user-visible behavior and do not materialize the full collection.
- [ ] Production-path scale results at 10k/100k are recorded and reproducible; import/reload does not regress to full materialization.
- [ ] Fast, serial, and relevant UI/model tests pass.

## Dependencies and coordination

Depends on CQ-03's asynchronous index delta and should be completed before CQ-05 removes legacy ImageCollection behavior. This is a large staged effort; land one coherent slice at a time and keep the package-backed path working. Coordinate with KRMA-512–515 and avoid mixing unrelated UI animation changes.

## Likely files and checks

PortableLibrarySession.swift, LibraryQueryController.swift, ImageCollection.swift, LibraryGridView.swift, FilmstripView.swift, LibrarySelection.swift, LibraryFilter.swift, scale fixtures/benchmarks, and AppViewModel reload logic.


### Comment — pi @ 2026-09-21T22:37:42.406Z

Slice 1 landed on branch krma-519-browsing-projection (commit 3984511, 8 files, +409/-8, clean-worktree build + 5 new tests green without KRMA-518).

What changed (scope item 1): AppViewModel launch and reloadPortableCollection publish session.browsingAssets() (summary-derived PhotoAsset values, zero record reads, zero original hashing) instead of materializedAssets(). Full records resolve lazily via resolveEmbeddedSourceURL (derived-path fast lane, single-record fallback) on open; export/edit already resolve single records. Added session.assetRecordReadObserver, LibraryBrowsingProjectionTests (5 tests: zero-read browsing, page parity with bounded reads, filter/sort without reads, at-most-one-read open, identity non-aliasing), and a production-path probe in the scale fixture gating production-record-reads to zero. 1k capture: production-launch 240ms, production-reload 86ms, 0 reads (LIBRARY_SCALE_REGRESSION.md).

NOT done (next slices): windowed grid/filmstrip source keyed by PortablePhotoAssetID, single selection authority (ImageCollection stays the adapter), 3-sample 10k/100k production table promotion, full fast+serial lanes (ran affected suites only: 79 tests green).

Tree note: the shared working tree still holds KRMA-518's uncommitted changes plus this slice's working copies; it sits on krma-519-browsing-projection because checkout back to main would overwrite dirty files. Land 518 first, then rebase/merge this branch.


### Comment — pi @ 2026-09-21T22:50:32.566Z

Slice 2 landed on branch krma-519-browsing-projection (commit 301302c, 8 files, +1462/-183, build green + focused suites green).

What changed (scope items 2-3): launch/reload publish only the first query page via browsingWindow (bounded Items, totalCount for full query, zero record reads); further pages fault in on grid scroll (onAppear prefetch), keyboard tail (selectNext), and off-window open (page scan without records) with stable portable:<uuid> identity. LibraryQueryController is the single portable filter/sort/search/selection authority; ImageCollection is a thin window adapter (loadPortableWindow/appendPortableWindow, syncPortableSelection, portableTotalCount/pageIndex/pageSize/query). CullingBar routes portable filtering through portableQuery; selection routes through the controller then mirrors (grid, filmstrip via selectCollectionImage, keyboard, deletion sync). Scale probe now measures the windowed production path with page-size bound and cross-page disjointness; doc keeps slice-1 full-projection numbers as history. Added LibraryWindowedBrowsingTests (5 tests: bounded launch, stable pages, append preserves selection, filter/sort without reads, single authority).

Tests: LibraryWindowedBrowsingTests 5 pass, BrowsingProjection 5 pass, QueryController 10 + projection 4 pass (19 total), Selection/Culling/Grid/Filmstrip/Deletion 32 pass, Session/AppViewModel 44 pass. Full fast+serial lanes and 3-sample 10k/100k table promotion remain.

Tree note: branch holds slice 1 (3984511) + slice 2 (301302c); working tree still holds KRMA-518's uncommitted delta in 10+ files (import worker/scheduler). Overlapping files (Session, ImageCollection, AppViewModel) include 518 delta as base since 519 depends on its index-delta behavior. Land 518 first, then rebase/merge this branch.


### Comment — pi @ 2026-09-21T23:14:59.543Z

Slice 3 landed on branch krma-519-browsing-projection (commit 6dfc38d, 6 files, +205/-36, fast 1139 green + serial 409 green).

What changed (closes scope item 4 + remaining acceptance): 3-sample 1k/10k/100k production-path table promoted into LIBRARY_SCALE_REGRESSION.md (launch 282ms/2089ms/21300ms, reload 45ms/68ms/335ms, first-grid flat ~17ms across scales, mutation-reload 46ms/88ms/323ms, 0 record reads at every scale; Mac16,11 2026-09-21). Scale probe now paints the first grid frame through the real ImageCollection adapter and proves post-mutation reload stays at zero reads. Grid keyboard stepping routes through the controller authority (selectNext/PreviousPortableInGrid, no open on step, tail faults next page) with a new authority test. assetRecordReadObserver now fires on the resolveEmbeddedSourceURL record fallback so the zero-read gate is honest.

Verification: LibraryBrowsingProjection 5 + LibraryWindowedBrowsing 6 pass; scale benchmark 1k/10k/100k x3 green (0 reads, concurrency gate maxWriters==1, 32/32 revisions); scripts/ci-tests.sh fast (1139 tests, 0 failures) and serial (409 tests, 0 failures, 1 pre-existing skip) green.

Known follow-up (pre-existing, not a 519 regression): PortablePackageImportCatalog opens every asset record for duplicate detection; the record-less scale fixture throws on import instead of materializing. Needs hash-index work tracked separately.

Tree note: branch holds slices 1-3 (3984511, 301302c, 6dfc38d); working tree still holds KRMA-518's uncommitted delta untouched (11 files + 1 untracked). Land 518 first, then rebase/merge this branch.

## Agent log

- 2026-09-21T23:15:04.346Z: Paged library UI: launch/reload/first-grid/mutation-reload measured at 1k/10k/100k with zero record reads; single query-controller selection authority incl. grid keyboard; honest read gate; fast (1139) + serial (409) lanes green. Branch krma-519-browsing-projection holds slices 1-3; merge after KRMA-518 lands (its delta still uncommitted in tree).
