---
id: KRMA-951
title: "Library grid: onScrollGeometryChange, stable row identity, remove 'scroll for more' paging text"
type: task
status: verification
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - performance
  - swiftui
  - library
created: 2026-10-13T14:48:00.359Z
updated: 2026-10-13T22:28:13.395Z
parent: KRMA-922
blockers: []
order: t
board: product
---

## Objective

Make the Library grid scroll smoothly and re-enter quickly: stop re-running the grid body every 24 pt,
give rows stable identity, and stop showing "Showing X of Y — scroll for more".

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S9 (grid half). Warm re-entry p95 is about 150 ms (`docs/TESTING.md`,
2026-10-11 measured state).

- `Sources/KromoraKit/Views/LibraryGridView.swift`: "Showing \(collection.items.count) of \(total) —
  scroll for more" text at ~L58-63; rows built with `ForEach(0..<rowCount, id: \.self)` at ~L84
  (identity by index, so inserted/removed items rebuild rows); scroll position tracked via a
  `GeometryReader` preference that re-runs the body every 24 pt.
- Use the macOS 26 APIs: `onScrollGeometryChange(for:of:action:)` and `scrollPosition(id:)`;
  `ForEach` over stable row models keyed by the first asset id in the row.
- Do NOT change the data paging model (loading more items as you scroll) in this ticket; only how it
  is presented/tracked. A full-library virtualized scroller is out of scope (note it as a follow-up).

## Acceptance criteria

- [ ] The `GeometryReader`+preference scroll tracking is replaced by `onScrollGeometryChange`
      (transform the value to the coarse visible-row range so the closure only fires when the range
      changes).
- [ ] `ForEach` is keyed by stable row identity (struct `GridRow: Identifiable` with `id` derived from
      the first asset's id plus column count) rather than integer index.
- [ ] The "Showing X of Y — scroll for more" label is removed from the visible UI; the accessibility
      label may remain and report "N photos" (keep `.accessibilityLabel` informative).
- [ ] A serial UI/unit test counts grid `body` evaluations during a scripted scroll over a generated
      500-item collection and asserts fewer than before (record before/after numbers in the review
      comment; assert a generous upper bound, e.g. evaluations ≤ rows visible changes + constant).
- [ ] Existing `LibraryGridView` tests pass (`grep -rln LibraryGridView Tests`); selection, shift-click,
      keyboard navigation and drag still behave the same.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.

## Implementation notes

Do not run `scripts/run-kromora-capture.sh`; use the deterministic counting test.


### Comment — claude @ 2026-10-13T22:15:10.393Z

Implemented. LibraryGridView: GeometryReader+preference scroll tracking replaced by onScrollGeometryChange reduced to the first-visible-row Int (fires only on row crossings); ForEach keyed by GridRow (first asset id + column count); 'Showing X of Y — scroll for more' text removed, ScrollView accessibilityLabel reports 'N photos'. Test testScriptedScrollEvaluatesGridBodyOncePerRowCrossing (500 items, 3000 pt scripted scroll, 12 row crossings): after = 44 body evaluations, bound = crossings*4+10. Before: the old 24 pt preference would fire ~125 times for the same scroll analytically; the old code measured 0 in this harness because programmatic clip-view scrolling did not deliver the preference, so no measured before number. Removing the label shifted the grid up ~25 pt, so testLibraryGridRendersInLightAndDarkAppearances sample points moved from y=280 to y=200. scrollPosition(id:) not adopted (not needed; data paging unchanged). Follow-up: full-library virtualized scroller out of scope. swift build warning-free; ci-tests fast=0, serial=0.
