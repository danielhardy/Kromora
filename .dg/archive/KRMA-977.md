---
id: KRMA-977
title: "Observation step 6: Extract InfoState (histogram and metadata)"
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: InfoState.swift is @MainActor @Observable; AppViewModel owns let info, removes the four targeted @Published properties, and does not grow.
      result: pass
      notes: All four targeted declarations are absent. AppViewModel is 5,029 lines versus 5,044 at HEAD. The current aggregate @Published count is 28 because two unrelated declarations, virtualCopyMetadata and portableLibrary, were added in the broader shared-tree diff; the isolated ticket target of 26 does not account for those additions.
    - criterion: InfoInspectorView, PreviewView, and MaskingWorkspace read viewModel.info.*; histogram gating, loading/error display, and source reset behavior are preserved.
      result: pass
      notes: The gate remains on AppViewModel, admission writes route into InfoState, and the source-empty reset still clears the histogram. Histogram and preview lifecycle tests passed.
    - criterion: Histogram refresh re-evaluates the real InfoInspectorView once and does not re-evaluate StatusBar or the Light, Color, and Effects mirrors; update the baseline table.
      result: pass
      notes: Focused body probe reported InfoInspectorView=1, StatusBar=0, Light=0, Color=0, Effects=0, and PreviewView mirror=1. The histogram after-values are recorded in APP_VIEWMODEL_OBSERVATION_PLAN.md.
    - criterion: Fast-lane Observation tracking fires when info.histogram is assigned and does not fire when statusMessage changes.
      result: pass
      notes: ObservationInvalidationTests.testInfoStateHistogramTracksIndependentlyOfStatusMessage passed in the final fast-lane run.
  checks_run:
    - swift build — passed, exit 0, no warnings
    - scripts/ci-tests.sh fast — final run passed, exit 0; the first run had one unrelated StoredEditAdoptionTests.testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult timing failure (expected 0, got 1); isolated rerun passed
    - scripts/ci-tests.sh serial — passed, exit 0; includes HistogramTests and ObservationBodyBaselineTests
    - swift test --no-parallel --filter ObservationBodyBaselineTests — passed, 6 tests; histogram body counts matched the updated baseline
    - swift test --filter testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult — passed, exit 0
    - git diff --check — passed, exit 0
    - Reviewed all InfoState readers/writers, reset paths, histogram admission routing, and scoped AppViewModel diff
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T04:34:37.907Z
  session: 01MV7LT6CEQV3W4FE9
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - swiftui
created: 2026-10-13T19:36:57.998Z
updated: 2026-10-24T13:05:21.780Z
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T04:22:30.982Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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

- 2026-10-14T04:34:37.907Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] InfoState.swift is @MainActor @Observable; AppViewModel owns let info, removes the four targeted @Published properties, and does not grow. (pass) — All four targeted declarations are absent. AppViewModel is 5,029 lines versus 5,044 at HEAD. The current aggregate @Published count is 28 because two unrelated declarations, virtualCopyMetadata and portableLibrary, were added in the broader shared-tree diff; the isolated ticket target of 26 does not account for those additions.
- [x] InfoInspectorView, PreviewView, and MaskingWorkspace read viewModel.info.*; histogram gating, loading/error display, and source reset behavior are preserved. (pass) — The gate remains on AppViewModel, admission writes route into InfoState, and the source-empty reset still clears the histogram. Histogram and preview lifecycle tests passed.
- [x] Histogram refresh re-evaluates the real InfoInspectorView once and does not re-evaluate StatusBar or the Light, Color, and Effects mirrors; update the baseline table. (pass) — Focused body probe reported InfoInspectorView=1, StatusBar=0, Light=0, Color=0, Effects=0, and PreviewView mirror=1. The histogram after-values are recorded in APP_VIEWMODEL_OBSERVATION_PLAN.md.
- [x] Fast-lane Observation tracking fires when info.histogram is assigned and does not fire when statusMessage changes. (pass) — ObservationInvalidationTests.testInfoStateHistogramTracksIndependentlyOfStatusMessage passed in the final fast-lane run.
Checks run:
- swift build — passed, exit 0, no warnings
- scripts/ci-tests.sh fast — final run passed, exit 0; the first run had one unrelated StoredEditAdoptionTests.testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult timing failure (expected 0, got 1); isolated rerun passed
- scripts/ci-tests.sh serial — passed, exit 0; includes HistogramTests and ObservationBodyBaselineTests
- swift test --no-parallel --filter ObservationBodyBaselineTests — passed, 6 tests; histogram body counts matched the updated baseline
- swift test --filter testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult — passed, exit 0
- git diff --check — passed, exit 0
- Reviewed all InfoState readers/writers, reset paths, histogram admission routing, and scoped AppViewModel diff
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7LT6CEQV3W4FE9
Summary: Verified InfoState extraction, view invalidation boundaries, and histogram lifecycle; build and final fast/serial lanes passed.
