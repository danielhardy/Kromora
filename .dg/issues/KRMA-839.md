---
id: KRMA-839
title: Show imported photos in the Library grid as they import, with per-cell progress
type: feature
status: done
priority: medium
agent: claude
verification_agent: codex
human_review_required: false
model: sonnet
thinking: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: During an import, new photos appear in the Library grid progressively, each with a spinner until its thumbnail is ready.
      result: pass
      notes: Committed index entries are published incrementally and merged into the loaded window; arriving assets start in loading state. LibraryBrowsingCoordinatorTests cover ordered progressive insertion and spinner state.
    - criterion: The count and header (N of M) update live; scroll position and selection are preserved as items arrive.
      result: pass
      notes: Incremental window merge updates total count while reusing existing cells and selection IDs; tests cover cell identity, selection preservation, ordering, and loaded-page bounds.
    - criterion: A visible, non-blocking import progress indicator is shown in the Library view with cancel; the status-bar text is no longer the only feedback.
      result: pass
      notes: LibraryGridView presents a progress bar, imported count, current name, and Cancel action while a multi-photo import runs.
    - criterion: Scrolling and selection stay responsive during a large import (no multi-frame main-actor stalls).
      result: pass
      notes: Import commits are buffered off the main actor and drained on a 250 ms cadence; scan batches are limited to 32 files or 250 ms. Fast and serial lanes passed.
    - criterion: Cancelling mid-import leaves already-committed photos in the grid and the package consistent.
      result: pass
      notes: LibraryImportCoordinatorTests exercise cancellation after live publication and confirm committed package assets remain queryable; PortableLibrarySessionTests cover committed sources surviving cancellation.
    - criterion: "Selector sheet: images stream in during the card scan, selectable immediately; final order and grouping match the fully scanned result."
      result: pass
      notes: The scan stream publishes batches, maintains date/path display order, and selects arrivals by default until the user changes selection. Fake-provider workflow tests and mounted-scanner ordering tests passed.
    - criterion: Tests for incremental window updates and ordering, cancellation, and scan batching with a fake provider; existing import/MediaVolume tests pass.
      result: pass
      notes: The fast lane includes the new coordinator, import, session, and MediaVolume tests; all 1,590 tests passed. The serial lane also passed all 511 tests.
  checks_run:
    - scripts/ci-tests.sh fast — exit 0; 1,590 tests passed
    - scripts/ci-tests.sh serial — exit 0; 511 tests passed
    - git diff --check defda32e^ defda32e — passed
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: unknown
  completed_at: 2026-10-10T07:08:15.547Z
  session: 01MV21RHWEM4CQDRYU
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-09T16:18:34.393Z
updated: 2026-10-10T07:08:15.551Z
blockers: []
order: zq
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-10T06:15:53.487Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

While photos are being imported into the library (SD card, folder, Photos), the Library grid should show them arriving: a cell appears for each photo as soon as it is committed (or as soon as it is queued), with a spinner until its thumbnail is ready, and the grid fills in progressively. Today the grid does not change until the whole import finishes, and the only feedback is a small, easily missed status line in the bottom-left corner ("Removable media import 46/111…") while the grid header still reads "19 of 19".

Secondary: the same applies to the SD card selector sheet itself, which shows only a "Scanning…" spinner until the entire card has been scanned (see "Scan phase" below).

## Context

- Import path: `AppViewModel.importRemovableMedia` -> `LibraryImportCoordinator` -> `PortableLibrarySession.importURLs` -> `PortablePackageImporter.import`. The importer already commits one package transaction per source ("progressive publication"), and streams `PortablePackageImportProgress` through `PortablePackageImportHandle.progress`, but `AppViewModel.observePortableImport` only reacts to the final result: `reloadPortableCollection()` runs once in `onSuccess`. Until then the Library window is stale.
- `ImageCollection` items are created from the portable query window (`reloadPortableWindow`, `LibraryBrowsingCoordinator`). Thumbnails come from the frame store/loader tiers and show a spinner while `thumbnailState == .loading`.
- Progress text is the status bar only; nothing in the grid indicates an import is running or which cells are new.
- Screenshot from the user: grid shows 19 of 19 photos while the status bar says import 46/111.

## Suggested approach

1. Surface per-item commits: have the importer/handle publish each committed asset (id + index delta) on the progress stream, or reload the window on a throttled cadence (for example every N items or ~250 ms) while the import runs. Apply index deltas incrementally instead of a full `reloadPortableCollection()` per item.
2. Insert new cells into the grid in sort order without disturbing scroll position or the current selection; update the "N of M" count live.
3. Show an in-progress treatment per new cell: placeholder with spinner until the original thumbnail arrives (generate the thumbnail right after each commit so it appears quickly; see KRMA-840/841 on thumbnail cost), and optionally a subtle "importing" affordance for not-yet-committed items if showing queued placeholders is feasible.
4. Make the overall progress visible: a prominent, non-blocking progress indicator in the Library view (count, bar, cancel) instead of only the status-bar text.
5. Keep import work off the main actor and batch UI updates so a 1,000+ photo import does not make scrolling or selection lag (coordinate with KRMA-841).
6. Do not run the display-bound capture benchmark (see CLAUDE.md).

### Scan phase (secondary)

`MediaVolumeScanner.scan(_:)` (`Sources/KromoraKit/Models/MediaVolume.swift`) validates every file and returns one `MediaVolumeScanResult` at the end; `openRemovableMedia` assigns `removableMediaFiles` once and `RemovableMediaSelectorView` shows the full-pane spinner until then. Stream the scan as batches into the selector grid, keep the selection and shift-click anchor valid while the list grows, keep final capture-time ordering, and keep cancellation and security-scoped access release intact. Import stays disabled until the scan finishes unless a decision is made to allow importing the partial selection.

## Acceptance criteria

- [ ] During an import, new photos appear in the Library grid progressively (not only after completion), each with a spinner until its thumbnail is ready.
- [ ] The count and header ("N of M") update live; scroll position and selection are preserved as items arrive.
- [ ] A visible, non-blocking import progress indicator is shown in the Library view with cancel; the status-bar text is no longer the only feedback.
- [ ] Scrolling and selection stay responsive during a large import (no multi-frame main-actor stalls).
- [ ] Cancelling mid-import leaves already-committed photos in the grid and the package consistent.
- [ ] Selector sheet: images stream in during the card scan, selectable immediately; final order and grouping match the fully scanned result.
- [ ] Tests for incremental window updates and ordering, cancellation, and scan batching with a fake provider; existing import/`MediaVolume*` tests pass.

### Comment — claude @ 2026-10-10T06:15:53.031Z

Implemented in defda32e. Live import: PortablePackageCommitBuffer + handle.publishCommitted() + LibraryBrowsingCoordinator.mergeCommittedImports() (250 ms throttle); progress bar with Cancel in LibraryGridView; cancel keeps committed photos. Scan: MediaVolumeProviding.scanBatches streams into the selector; selection/anchor preserved, arrivals auto-selected until the user edits the selection, import disabled until scan ends. Tests: LibraryBrowsingCoordinatorTests, LibraryImportCoordinatorTests, PortablePackageImportTests, PortableLibrarySessionTests, MediaVolumeTests, LibraryMediaWorkflowCoordinatorTests. ci-tests fast/serial pass. Not verified visually in a running window.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-10T07:08:15.547Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] During an import, new photos appear in the Library grid progressively, each with a spinner until its thumbnail is ready. (pass) — Committed index entries are published incrementally and merged into the loaded window; arriving assets start in loading state. LibraryBrowsingCoordinatorTests cover ordered progressive insertion and spinner state.
- [x] The count and header (N of M) update live; scroll position and selection are preserved as items arrive. (pass) — Incremental window merge updates total count while reusing existing cells and selection IDs; tests cover cell identity, selection preservation, ordering, and loaded-page bounds.
- [x] A visible, non-blocking import progress indicator is shown in the Library view with cancel; the status-bar text is no longer the only feedback. (pass) — LibraryGridView presents a progress bar, imported count, current name, and Cancel action while a multi-photo import runs.
- [x] Scrolling and selection stay responsive during a large import (no multi-frame main-actor stalls). (pass) — Import commits are buffered off the main actor and drained on a 250 ms cadence; scan batches are limited to 32 files or 250 ms. Fast and serial lanes passed.
- [x] Cancelling mid-import leaves already-committed photos in the grid and the package consistent. (pass) — LibraryImportCoordinatorTests exercise cancellation after live publication and confirm committed package assets remain queryable; PortableLibrarySessionTests cover committed sources surviving cancellation.
- [x] Selector sheet: images stream in during the card scan, selectable immediately; final order and grouping match the fully scanned result. (pass) — The scan stream publishes batches, maintains date/path display order, and selects arrivals by default until the user changes selection. Fake-provider workflow tests and mounted-scanner ordering tests passed.
- [x] Tests for incremental window updates and ordering, cancellation, and scan batching with a fake provider; existing import/MediaVolume tests pass. (pass) — The fast lane includes the new coordinator, import, session, and MediaVolume tests; all 1,590 tests passed. The serial lane also passed all 511 tests.
Checks run:
- scripts/ci-tests.sh fast — exit 0; 1,590 tests passed
- scripts/ci-tests.sh serial — exit 0; 511 tests passed
- git diff --check defda32e^ defda32e — passed
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: unknown
Pickup session: 01MV21RHWEM4CQDRYU
Summary: Independent verification passed; fast and serial CI lanes passed with no blocking findings.
