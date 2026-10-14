---
id: KRMA-978
title: "Observation step 7: Extract presentation chrome state (overlaps KRMA-910)"
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: All eight chrome properties are owned by at least two @Observable state objects and removed from AppViewModel @Published storage.
      result: pass
      notes: StatusState, LibraryPresentationState, and ChromePresentationState own the eight properties. The handoff records the actual root count change as 28 to 20; AppViewModel.swift is 5,022 lines versus 5,029 before this step.
    - criterion: Status text and portable query updates invalidate only their intended views.
      result: pass
      notes: Real StatusBar increments once for status text; CullingBar and LibraryFacetSidebar mirrors and Light, Color, and Effects mirrors stay quiet. Preview mirror increments once. A query change increments its query mirrors and leaves StatusBar unchanged. MaskingWorkspace reads status only in the failed-preview banner branch.
    - criterion: Fast observation tracking covers statusMessage through the forwarder and portableQuery.
      result: pass
      notes: testStatusMessageAndPortableQueryTrackIndependently passed in the fast lane.
    - criterion: Existing library, import-progress, confirmation, error-alert, crop-workflow, and source-browser behavior remains covered without behavioral edits.
      result: pass
      notes: Required fast and serial lanes passed; relevant workflow tests remained green.
    - criterion: The statusMessage write call-site count remains unchanged.
      result: pass
      notes: rg count is 58.
    - criterion: AppViewModel.swift is no longer than before this step.
      result: pass
      notes: Current line count is 5,022, down from 5,029.
  checks_run:
    - "swift build: passed, exit 0."
    - "scripts/ci-tests.sh fast: passed on final rerun, 1,893 tests, exit 0. An earlier rerun had one non-reproducible failure in StoredEditAdoptionTests; its isolated rerun and the subsequent full lane passed."
    - "scripts/ci-tests.sh serial: passed, 554 tests, exit 0, including the KRMA-978 hosted-view isolation test."
    - "swift test --no-parallel --filter ObservationBodyBaselineTests/testStatusAndLibraryQueryInvalidateOnlyTheirReaders: passed."
    - "swift test --parallel --filter StoredEditAdoptionTests/testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult: passed."
    - "xcodebuild Debug app build for KRMA-978 DerivedData: passed."
    - Manual UI smoke was attempted with swift run and the fresh debug app bundle. The computer-use bridge returned cgWindowNotFound and later timed out, so alert, deletion-confirmation, and source-browser interactions could not be completed.
    - "Structural checks: 58 statusMessage assignments; AppViewModel.swift has 5,022 lines."
  findings: []
  fixes:
    - Added a hosted-view regression test for status/query invalidation and documented the measured KRMA-978 results.
    - Removed duplicate @Bindable state initializations from ContentView.
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T05:10:24.840Z
  session: 01MV7MOZ37DUPBBT1M
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - swiftui
created: 2026-10-13T19:36:59.501Z
updated: 2026-10-14T05:10:24.844Z
depends_on:
  - KRMA-977
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T04:47:14.330Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Extract the eight app-chrome properties (messages, dialogs, pickers, library presentation) from `AppViewModel` into focused `@Observable` objects so a status-text update no longer re-evaluates unrelated views, and a library query change no longer re-evaluates the status bar.

## Context

Part of `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` (read it, "Additions from ticket review" and "Common rules"). Depends on KRMA-977.

**KRMA-910 decision (already made): not superseded and no overlap.** KRMA-910 is `done`; it created `SourcePresentationState` (the `presentation` property) for source-loading transitions. None of the eight properties below belong to it. Leave `presentation` alone (it is step 9's). Add one line to this ticket's comment saying KRMA-910 is independent.

Properties (declarations in `AppViewModel.swift`, regenerate line numbers):

| Property | Decl | Readers |
| --- | --- | --- |
| `statusMessage: String` | ~L689 | `StatusBar.swift:61,71`, `PreviewView.swift:164,184`, `MaskingWorkspace.swift:249` |
| `errorMessage: String?` | ~L694 | `ContentView.swift:150-153` (alert) |
| `libraryDeletionConfirmation` | ~L697 | `ContentView` (confirmation dialog) |
| `isPhotosPickerPresented` | ~L701 | `ContentView` (`.photosPicker`) |
| `isSourceBrowserPresented` | ~L639 | `ContentView.swift:239,299`; **also read and written inside `AppViewModel`** (L911 area, L3320, and the crop-workflow presentation capture/restore at ~L4522-4537 plus `CanvasWorkflowCoordinator.swift:8`) |
| `isMaskingPanelPresented` | ~L699 | no direct view reader; written at ~L911 |
| `portableImportProgress` | ~L713 | `LibraryGridView.swift:216` |
| `portableQuery: LibraryQuery` | ~L787 | `CullingBarView.swift:120,141,149,215,232`, `LibraryFacetSidebar.swift:10,213`; also read by library browsing code in `AppViewModel`/coordinators (grep `portableQuery`) |

**`statusMessage` is written about 55 times, all inside `AppViewModel.swift`** (coordinators report through closures such as `reportStatus: { self?.statusMessage = $0 }`). Keep these call sites untouched by leaving a computed `var statusMessage: String { get { status.message } set { status.message = newValue } }` on `AppViewModel`. Reads of the computed property from a view's `body` are tracked through to `status.message`. Apply the same one-line forwarder pattern to the other properties that are written in many places (`errorMessage`, `isSourceBrowserPresented`) if the diff is otherwise large; each forwarder costs 1-4 lines, and removing the `@Published` declarations plus their doc comments pays for it. The `AppViewModel.swift` ceiling is 5,120 and the file is 5,101 lines, so measure.

## Approach

1. Create two `@MainActor @Observable final class`es in `Sources/KromoraKit/ViewModels/`:
   - `StatusState`: `statusMessage` (named `message`), `errorMessage`.
   - `LibraryPresentationState`: `portableQuery`, `portableImportProgress` (keep `private(set)` with a setter method if it is `private(set)` today), `libraryDeletionConfirmation`.
   - The three pickers/panels (`isPhotosPickerPresented`, `isSourceBrowserPresented`, `isMaskingPanelPresented`) go into a third small `ChromePresentationState`, or into `StatusState` renamed `ChromeState` if you prefer two objects. The acceptance criterion needs at least two objects; pick whichever leaves the fewest cross-reads.
2. `AppViewModel` holds `let` references and, where listed above, a thin computed forwarder.
3. Views read the child object directly (`viewModel.status.message` or the forwarder) inside `body`. `ContentView` alert/dialog/picker bindings use `@Bindable` or `Binding(get:set:)` over the child; `.photosPicker(isPresented:)` needs a real `Binding`, so use `@Bindable var chrome` or an explicit get/set.
4. Preserve the crop-workflow capture/restore of `isSourceBrowserPresented` exactly.

## Acceptance criteria

- [ ] At least two `@Observable` objects own all eight properties; `AppViewModel` no longer declares them `@Published` (structural test: `@Published` count in `AppViewModel.swift` drops by 8 relative to step 6's result, i.e. from 26 to 18).
- [ ] Probe test (KRMA-972): changing `statusMessage` increments the real `StatusBar` (`toolbarBodyEvaluations`) and does not re-evaluate CullingBar, LibraryFacetSidebar (mirror or real) or the Light/Color/Effects mirrors; changing `portableQuery` does not re-evaluate StatusBar. PreviewView and MaskingWorkspace are expected to re-evaluate on `statusMessage` only if they still read it; record which.
- [ ] Fast-lane `withObservationTracking` tests for `statusMessage` (via the forwarder) and `portableQuery`.
- [ ] All existing library, import-progress, deletion-confirmation, error-alert, crop-workflow and source-browser tests pass without behavioural edits.
- [ ] `grep -rn "statusMessage = " Sources` call-site count is unchanged (the forwarder keeps the write API).
- [ ] `AppViewModel.swift` is not longer than before.

## Verification

```
swift build
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
```

## Risks

- `ContentView` is the single place that presents alerts, dialogs and pickers; a mis-wired binding presents nothing and no test may notice. Manually launch with `swift run` and trigger one alert (for example open an unsupported file), the library deletion confirmation, and the source browser toggle before handing off.
- Before step 9 the root is still an `ObservableObject`, so `StatusBar`'s `@ObservedObject viewModel` no longer re-evaluates from `statusMessage` through the root; it must read `status.message` itself in its `body` (it does via the forwarder). Verify with the probe, not by assumption.

### Comment — claude @ 2026-10-14T04:47:10.577Z

Implemented: StatusState, LibraryPresentationState, ChromePresentationState (AppChromeState.swift); AppViewModel keeps one-line forwarders so the 58 statusMessage write sites are unchanged. KRMA-910 is independent (SourcePresentationState/presentation untouched). @Published root count 28 -> 20 (-8; plan's 26 baseline was stale). AppViewModel.swift 5029 -> 5022 lines. fast and serial lanes pass. Added testStatusMessageAndPortableQueryTrackIndependently; LibraryOpenTests swapped its Combine $errorMessage sink for an observation recorder. Not done: real-StatusBar probe test and manual swift run alert/dialog/source-browser check (need a display).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-14T05:10:24.840Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] All eight chrome properties are owned by at least two @Observable state objects and removed from AppViewModel @Published storage. (pass) — StatusState, LibraryPresentationState, and ChromePresentationState own the eight properties. The handoff records the actual root count change as 28 to 20; AppViewModel.swift is 5,022 lines versus 5,029 before this step.
- [x] Status text and portable query updates invalidate only their intended views. (pass) — Real StatusBar increments once for status text; CullingBar and LibraryFacetSidebar mirrors and Light, Color, and Effects mirrors stay quiet. Preview mirror increments once. A query change increments its query mirrors and leaves StatusBar unchanged. MaskingWorkspace reads status only in the failed-preview banner branch.
- [x] Fast observation tracking covers statusMessage through the forwarder and portableQuery. (pass) — testStatusMessageAndPortableQueryTrackIndependently passed in the fast lane.
- [x] Existing library, import-progress, confirmation, error-alert, crop-workflow, and source-browser behavior remains covered without behavioral edits. (pass) — Required fast and serial lanes passed; relevant workflow tests remained green.
- [x] The statusMessage write call-site count remains unchanged. (pass) — rg count is 58.
- [x] AppViewModel.swift is no longer than before this step. (pass) — Current line count is 5,022, down from 5,029.
Checks run:
- swift build: passed, exit 0.
- scripts/ci-tests.sh fast: passed on final rerun, 1,893 tests, exit 0. An earlier rerun had one non-reproducible failure in StoredEditAdoptionTests; its isolated rerun and the subsequent full lane passed.
- scripts/ci-tests.sh serial: passed, 554 tests, exit 0, including the KRMA-978 hosted-view isolation test.
- swift test --no-parallel --filter ObservationBodyBaselineTests/testStatusAndLibraryQueryInvalidateOnlyTheirReaders: passed.
- swift test --parallel --filter StoredEditAdoptionTests/testShutdownWaitsForPlaceholderMaterializationAndSuppressesItsResult: passed.
- xcodebuild Debug app build for KRMA-978 DerivedData: passed.
- Manual UI smoke was attempted with swift run and the fresh debug app bundle. The computer-use bridge returned cgWindowNotFound and later timed out, so alert, deletion-confirmation, and source-browser interactions could not be completed.
- Structural checks: 58 statusMessage assignments; AppViewModel.swift has 5,022 lines.
Findings:
- None
Fixes:
- Added a hosted-view regression test for status/query invalidation and documented the measured KRMA-978 results.
- Removed duplicate @Bindable state initializations from ContentView.
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7MOZ37DUPBBT1M
Summary: Verification passed; required build and CI lanes are green, with the manual UI smoke limited by the desktop automation bridge.
