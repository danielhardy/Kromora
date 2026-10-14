---
id: KRMA-951
title: "Library grid: onScrollGeometryChange, stable row identity, remove 'scroll for more' paging text"
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Replace GeometryReader and PreferenceKey scroll tracking with onScrollGeometryChange reduced to a coarse row position.
      result: pass
      notes: The continuous offset is transformed to the first visible row index. scrollPosition(id:) was not added because this path uses the row index to refresh thumbnail demand and does not require programmatic row targeting or scroll restoration.
    - criterion: Use stable row identity based on the first asset ID and column count.
      result: pass
      notes: GridRow conforms to Identifiable and ForEach consumes the row models.
    - criterion: Remove the visible paging text and keep an informative accessibility label.
      result: pass
      notes: The Showing X of Y label is removed; the scroll view reports the photo count.
    - criterion: Add a scripted 500-item scroll test that bounds grid body evaluations.
      result: pass
      notes: The new run measured 44 evaluations over 12 row crossings with an upper bound of 58. The handoff records an estimated 125 legacy 24-point preference updates; its old harness measured zero body evaluations, so the test now also requires a positive count to reject inert scroll tracking.
    - criterion: Existing grid tests pass and selection, keyboard navigation, shift-click, and drag behavior remain intact.
      result: pass
      notes: Both required CI lanes passed, including LibraryGridTests and the selection and keyboard suites.
    - criterion: swift build is warning-free and Swift 6 remains clean without forbidden escape hatches or availability branches.
      result: pass
      notes: swift build exited 0 without warnings; fast lane includes PackageSettingsTests.
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
      notes: 1,852 tests completed; exit 0.
    - criterion: scripts/ci-tests.sh serial exits 0.
      result: pass
      notes: 543 tests completed; exit 0.
  checks_run:
    - swift build — exit 0, warning-free
    - scripts/ci-tests.sh fast — exit 0, 1,852 tests
    - scripts/ci-tests.sh serial — exit 0, 543 tests
    - swift test --filter LibraryGridTests/testScriptedScrollEvaluatesGridBodyOncePerRowCrossing — exit 0, 1 test
    - git show --stat --oneline HEAD — verification fix is isolated to LibraryGridTests.swift
  findings:
    - The scripted scroll test previously accepted zero body evaluations, which the old preference-based harness also produced. A positive lower-bound assertion was added so inactive scroll tracking fails.
    - LibraryGridView eagerly constructs a GridRow model for every currently loaded thumbnail entry on each body update. This remains outside KRMA-951 scope and is tracked as backlog child KRMA-990.
  fixes:
    - Added a positive body-evaluation assertion to the scripted scroll regression test.
  verification_commits:
    - e2d48fabcdab3622d212169df6bd5bfe38cea992
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T23:32:26.931Z
  session: 01MV7B4LFCHCCMXY62
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
updated: 2026-10-13T23:32:26.934Z
parent: KRMA-922
blockers: []
order: t
board: product
commits:
  - e2d48fabcdab3622d212169df6bd5bfe38cea992
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

## Agent log

- 2026-10-13T23:32:26.931Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Replace GeometryReader and PreferenceKey scroll tracking with onScrollGeometryChange reduced to a coarse row position. (pass) — The continuous offset is transformed to the first visible row index. scrollPosition(id:) was not added because this path uses the row index to refresh thumbnail demand and does not require programmatic row targeting or scroll restoration.
- [x] Use stable row identity based on the first asset ID and column count. (pass) — GridRow conforms to Identifiable and ForEach consumes the row models.
- [x] Remove the visible paging text and keep an informative accessibility label. (pass) — The Showing X of Y label is removed; the scroll view reports the photo count.
- [x] Add a scripted 500-item scroll test that bounds grid body evaluations. (pass) — The new run measured 44 evaluations over 12 row crossings with an upper bound of 58. The handoff records an estimated 125 legacy 24-point preference updates; its old harness measured zero body evaluations, so the test now also requires a positive count to reject inert scroll tracking.
- [x] Existing grid tests pass and selection, keyboard navigation, shift-click, and drag behavior remain intact. (pass) — Both required CI lanes passed, including LibraryGridTests and the selection and keyboard suites.
- [x] swift build is warning-free and Swift 6 remains clean without forbidden escape hatches or availability branches. (pass) — swift build exited 0 without warnings; fast lane includes PackageSettingsTests.
- [x] scripts/ci-tests.sh fast exits 0. (pass) — 1,852 tests completed; exit 0.
- [x] scripts/ci-tests.sh serial exits 0. (pass) — 543 tests completed; exit 0.
Checks run:
- swift build — exit 0, warning-free
- scripts/ci-tests.sh fast — exit 0, 1,852 tests
- scripts/ci-tests.sh serial — exit 0, 543 tests
- swift test --filter LibraryGridTests/testScriptedScrollEvaluatesGridBodyOncePerRowCrossing — exit 0, 1 test
- git show --stat --oneline HEAD — verification fix is isolated to LibraryGridTests.swift
Findings:
- The scripted scroll test previously accepted zero body evaluations, which the old preference-based harness also produced. A positive lower-bound assertion was added so inactive scroll tracking fails.
- LibraryGridView eagerly constructs a GridRow model for every currently loaded thumbnail entry on each body update. This remains outside KRMA-951 scope and is tracked as backlog child KRMA-990.
Fixes:
- Added a positive body-evaluation assertion to the scripted scroll regression test.
Verification commits:
- e2d48fabcdab3622d212169df6bd5bfe38cea992
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7B4LFCHCCMXY62
Summary: Verification passed: build and both CI lanes are green. Tightened the scripted scroll test and recorded the full-library row-model follow-up as KRMA-990.
