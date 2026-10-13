---
id: KRMA-977
title: "Observation step 6: Extract InfoState (histogram and metadata)"
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
created: 2026-10-13T19:36:57.998Z
updated: 2026-10-13T19:36:58.927Z
depends_on:
  - KRMA-976
blockers: []
order: zzzzz
board: product
---

## Objective

Move `metadata`, `histogram`, `isHistogramLoading` and `histogramErrorMessage` off `AppViewModel` into one `@Observable` `InfoState` read directly by the views that need it. A histogram refresh happens on most edits, so this is the highest-value extraction after the root flip.

## Context

Part of `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` (read it, "Additions from ticket review" and "Common rules"). Depends on KRMA-976, which removes the forwarding loop; after it, the root is still an `ObservableObject` but nothing forwards into it.

Current declarations in `AppViewModel.swift` (regenerate line numbers): `@Published var metadata` (~L653, `ImageMetadata`), `@Published var histogram` (~L656, `HistogramData?`), `@Published private(set) var isHistogramLoading` (~L659), `@Published private(set) var histogramErrorMessage` (~L660). `metadata` and `histogram` are internal `var`s, so views and coordinators may assign them; check every writer with `grep -n "histogram\b\|isHistogramLoading\|histogramErrorMessage\|\.metadata\b\|metadata =" Sources/KromoraKit/ViewModels/*.swift`.

Readers: `InfoInspectorView.swift` (all four), `PreviewView.swift` (`metadata`, `histogram`), `MaskingWorkspace.swift` (`histogram`). The histogram gate (`refreshHistogramGate()`, driven by `inspectorState.onPresentationChange`, ~L1421) decides when to compute; it stays on `AppViewModel`. Also grep `PreviewCoordinator` and other coordinators for closures that write these.

`InfoInspectorView` counts its own body in `RenderDiagnostics.noteInspectorBody()` (`InfoInspectorView.swift:18`), so the probe can measure the real view.

## Approach

1. Create `Sources/KromoraKit/ViewModels/InfoState.swift`: `@MainActor @Observable final class InfoState` with `var metadata = ImageMetadata()`, `var histogram: HistogramData?`, `private(set) var isHistogramLoading = false`, `private(set) var histogramErrorMessage: String?`, plus the small mutation methods the model needs for the `private(set)` ones (for example `beginLoading()`, `finish(histogram:)`, `fail(_:)`; derive them from the existing writes so behaviour is identical).
2. In `AppViewModel` add `let info = InfoState()`, delete the four `@Published` declarations, and re-point every writer to `info.*`. Keep the gate logic and ordering exactly as is. Do not add computed forwarders for the four names unless a non-view caller makes that substantially smaller; views must read `viewModel.info.*` so tracking is on the child.
3. Update the three views. Where a view passes histogram data to a subview, pass the value, not the whole `AppViewModel`.
4. Reset behaviour: whatever clears the histogram on source change (search `histogram = nil`) must still do so.

## Acceptance criteria

- [ ] `Sources/KromoraKit/ViewModels/InfoState.swift` exists as `@MainActor @Observable final class`; `AppViewModel` holds one `let info` and no longer declares the four `@Published` properties (structural test: the count of `^\s*@Published\b` declarations in `AppViewModel.swift` drops by 4, from 30 to 26; do not count comment mentions).
- [ ] InfoInspector, PreviewView and MaskingWorkspace read `viewModel.info.*`; histogram gating, loading and error display are unchanged (existing histogram/info tests pass; `HistogramTests` is in the serial lane).
- [ ] Probe test (KRMA-972): setting `info.histogram` re-evaluates the real `InfoInspectorView` (`inspectorBodyEvaluations` increments) and does not re-evaluate StatusBar (`toolbarBodyEvaluations` unchanged) or the Light/Color/Effects mirrors. Update the "after" column of the `histogram` row.
- [ ] A fast-lane observation test: `withObservationTracking` reading `info.histogram` fires on assignment and does not fire when `statusMessage` changes.
- [ ] `AppViewModel.swift` is not longer than before.

## Verification

```
swift build
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
```

## Risks

Until step 9 the views still hold `@ObservedObject var viewModel`; reading `viewModel.info.histogram` is tracked by Observation regardless, so this works today. If InfoInspector still re-evaluates for unrelated changes after this step, that is the root `objectWillChange`, which step 9 fixes. Record the real count in the "after" column and note it as "pending root flip" rather than forcing the assertion.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
