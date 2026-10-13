---
id: KRMA-972
title: "Observation step 1: Add re-evaluation probe and baseline"
type: task
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - swiftui
created: 2026-10-13T19:36:51.090Z
updated: 2026-10-13T19:36:51.090Z
blockers: []
order: zzzzh
board: product
---

## Objective

Add a reusable, window-independent re-evaluation probe to the test target and record a baseline table of how many view-body evaluations each inspector or chrome view performs when one `AppViewModel` property changes. This is the measuring stick for steps 2-10. No production code changes.

## Context

Part of the `@Observable` migration in `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` (read it, including "Additions from ticket review" and "Common rules"). Today `AppViewModel` is an `ObservableObject` with 30 `@Published` properties and a loop that forwards seven children's `objectWillChange` into it, so any change re-evaluates every view holding `@ObservedObject var viewModel`. Later steps must prove that stops happening, so we need numbers first.

**Important design constraint.** A wrapper view's `body` only runs when the wrapper's own dependencies change. It does not count evaluations of the view it wraps. So a naive "`BodyProbe` wrapper around the real view" measures nothing about the real view. Use the two mechanisms below instead.

1. **Real views that already count themselves** through `RenderDiagnostics` (`Sources/KromoraKit/Models/ObservationInstrumentation.swift`): `InfoInspectorView` (`noteInspectorBody` -> `snapshot.inspectorBodyEvaluations`), `StatusBar` (`noteToolbarBody` -> `toolbarBodyEvaluations`), `ContentView` (`contentViewBodyEvaluations`), `LibraryGridView` (`gridBodyEvaluations`). Mount the real view, call `RenderDiagnostics.reset()`, mutate, read the snapshot. See `LibraryGridTests.swift:607-620` for the pattern. Note `inspectorBodyEvaluations` is shared if more than one inspector counts into it; mount one inspector per measurement.
2. **Mirror probe views** for views with no counter (Light, Color, Effects inspectors, PreviewView). A mirror is a small test-only `View` that holds the same `@ObservedObject var viewModel` (or, after later steps, the plain reference) and reads exactly the properties the real view reads in its `body`, incrementing a counter. Declare each mirror's read set as a list next to it, copied from the real view (grep `viewModel\.` in that file). The table must label each row "real" or "mirror" so nobody mistakes a mirror for the production view.

Existing patterns to copy: `Tests/KromoraKitTests/ObservationInvalidationTests.swift` (counting `objectWillChange`), `makeAppViewModel(engine:)` at `Tests/KromoraKitTests/Fixtures.swift:768`, `FakeRenderEngine`, `NSHostingView` use in `EditorCanvasViewportTests.swift:26` and `LibraryGridTests.swift:69`, helpers in `Tests/KromoraKitTests/Support/` (e.g. `ObservationPerformance.swift`).

## Scope

New files only, all under `Tests/KromoraKitTests/`:
- `Support/BodyProbe.swift`: counter box, mirror-view helper, hosting helper.
- `ObservationBodyBaselineTests.swift` (name is a suggestion; the class name must match the serial regex below).
- Edit `scripts/ci-tests.sh` to add the new class to `serial_filter`.
- Edit `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` to add the Baseline table.

## Approach

1. **Hosting helper.** `@MainActor func host<V: View>(_ view: V, size: CGSize = .init(width: 320, height: 600)) -> NSHostingView<V>`, then `layoutSubtreeIfNeeded()`, then a drain (`await Task.yield()` a couple of times, or `RunLoop.main.run(until: .now + 0.05)`). First verify that an `NSHostingView` with no window re-evaluates `body` after an observed change. If it does not, put it in an off-screen `NSWindow` that is never ordered front (no display is needed). Do not call `makeKeyAndOrderFront`; CLAUDE.md says unattended lanes must not need an awake display.
2. **Mutations.** `document` is `private(set)`, so find the internal mutation entry point the existing tests use (grep tests for `viewModel.document`/`updateDocument`/`apply(`) rather than widening access. `histogram` and `statusMessage` are internal `var`s and can be assigned directly. For a settings value use `viewModel.settings.showPhotoNames.toggle()`.
3. **Measure.** For each (view, property) pair: host the view, reset counters, drain once to flush initial layout, record baseline, mutate once, drain, record the delta. Mutate a property to a value that really differs, otherwise nothing publishes.
4. **Views to cover:** StatusBar (real), InfoInspectorView (real), mirrors of LightInspectorView, ColorInspectorView, EffectsInspectorView, PreviewView. Properties: `document`, `statusMessage`, `histogram`, `settings.showPhotoNames`. That is 6 x 4 = 24 cells.
5. **Record.** Paste the table under a "Baseline" heading in the plan doc: columns view, real/mirror, property, before-migration count, and an empty "after" column.

## Acceptance criteria

- [ ] `Support/BodyProbe.swift` exists with a counter, a mirror-view helper, and the hosting helper; it uses no `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency`.
- [ ] The baseline test class is added to `serial_filter` in `scripts/ci-tests.sh`; `scripts/ci-tests.sh serial` runs it and `scripts/ci-tests.sh fast` does not.
- [ ] The test covers the 24 cells above and records body-count deltas.
- [ ] The table is in the plan doc with real/mirror labelled per row and an empty "after" column. Counts are logical evaluations, not timings.
- [ ] The test asserts only (a) counts are identical across two consecutive runs on fresh view models, and (b) a positive control: a mirror reading `document` increments when `document` changes, and the real `StatusBar` count increments when `statusMessage` changes. It must not assert that unrelated views re-evaluate; that is the bug later steps remove.
- [ ] `git diff --stat -- Sources` is empty.

## Verification

```
swift build
scripts/ci-tests.sh serial
scripts/ci-tests.sh fast
```

## Out of scope

Adding `RenderDiagnostics` hooks to Light/Color/Effects/Preview (that edits `Sources/`). If mirrors prove too weak, raise it as a decision in the ticket comment rather than changing production views here.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
