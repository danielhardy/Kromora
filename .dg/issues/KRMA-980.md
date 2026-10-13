---
id: KRMA-980
title: "Observation step 9: Flip AppViewModel to @Observable"
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
created: 2026-10-13T19:37:02.475Z
updated: 2026-10-13T19:37:03.453Z
depends_on:
  - KRMA-979
blockers: []
order: zzzzzv
board: product
---

## Objective

Make `AppViewModel` itself `@MainActor @Observable`, delete `ObservableObject` and every remaining `@Published`, and migrate all view wrappers, so a slider tick re-evaluates only views that read `document`.

## Context

Part of `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` (read it, "Additions from ticket review" and "Common rules"). Depends on steps 1-8 having removed every `ObservableObject` child and every forwarding path. **Do not start until KRMA-979 is done and these are all empty:**

```
grep -rn "ObservableObject" Sources                 # only AppViewModel remains
grep -rn "objectWillChange" Sources                 # only the two sends (if any) AppViewModel still has
grep -n "@Published" Sources/KromoraKit/ViewModels/AppViewModel.swift   # exactly 9 (see below)
```

State at the start of this step (after steps 2-8): `@Published` on `AppViewModel` is `document`, `sourceImage`, `sourceName`, `sourceSize`, `sourceURL`, `navigation`, `presentation`, `isShowingOriginal`, `isSideBySide`.

Facts about the current file (`AppViewModel.swift`, 5,101 lines on 2026-10-13, ceiling 5,120):
- Declaration at L84: `@MainActor public final class AppViewModel: ObservableObject, LookPreviewProviding, PhotosImportDestination, AsyncPhotosImportDestination, PhotosImportBatchDestination, MaskingWorkflowDestination, RetouchWorkflowDestination, EditedThumbnailDestination`. Those protocols are `AnyObject`-constrained, not `ObservableObject`; they are unaffected.
- `import Combine` (L2) and `private var cancellables: [AnyCancellable] = []` (L982), cleared at ~L4439.
- `isSideBySide` has a `didSet` (L446); `didSet` is supported under `@Observable`.
- **11 `lazy var`s** (`private lazy var previewPublicationCoordinator`, `lookSelection`, `editHistory`, `virtualCopyMetadata`, ...). `@Observable` rejects `lazy` stored properties, so each needs `@ObservationIgnored` in front of it. Find them with `grep -n "lazy var" Sources/KromoraKit/ViewModels/AppViewModel.swift`.
- Other stored properties that views never read (coordinators, tasks, caches, closures, `isShuttingDown`, `activeAssetID`, `comparisonBaselineDocument`, ...) must be `@ObservationIgnored` where the macro or the "do not track" intent requires it. Default is *tracked*: leave UI-read state tracked.
- Consumers: **31** `@ObservedObject var viewModel: AppViewModel` declarations (`grep -rn "ObservedObject.*AppViewModel" Sources`): InfoInspector, StatusBar, KeyboardSurface, DevelopInspector, MaskingWorkspace (4), LookInspector, PreviewView, OnboardingViews, RetouchCanvasOverlay, LibraryGridView (2), LibraryFacetSidebar, RetouchInspector, MenuCommands (4, at L226/237/280/292), LightInspector (3), EffectsInspector, SourceBrowser, RemovableMediaSelector, CullingBar (2), ColorInspector; `@StateObject` in `ContentView.swift:32,44`.
- Public API: `ContentView.init()` and `ContentView.init(viewModel:)` (L31-48), `KromoraCommands`, `KromoraScene`, `KromoraAppDelegate` (`Presentation/`, `launch.viewModel`) and the launchers `Sources/Kromora/KromoraApp.swift` + Xcode target. `AppLaunch` is already `@Observable` and holds the view model. Keep signatures source-compatible.
- Also check `KeyboardCommandRouter(viewModel:)`, which stores the model (no wrapper) and must not depend on `objectWillChange`.
- Tests that depend on `objectWillChange`: `CanvasNavigationTests.swift` (done in step 2 for `inspectorState`; recheck for `viewModel.objectWillChange` at ~L698) and `ObservationInvalidationTests.swift` (the forwarding-count test was handled in step 5). `grep -rn "objectWillChange" Tests` must be empty at the end.

## Approach

1. Change the declaration to `@MainActor @Observable public final class AppViewModel: ...` (drop `ObservableObject`), delete `@Published` from the nine properties, keeping `private(set)`/`didSet`.
2. Add `@ObservationIgnored` to each `lazy var` and to storage views never read. Compile; the macro errors identify any lazy or wrapper-incompatible property.
3. Delete `cancellables`, its `removeAll()`, and `import Combine` if nothing else in the file needs it (the sink loop and `settings.$...` sink are gone after steps 4-5). Keep `Combine` out of the file unless a real use remains.
4. Views: every `@ObservedObject var viewModel: AppViewModel` becomes `let viewModel: AppViewModel` (or `@Bindable var viewModel` where the view uses `$viewModel.x`). `ContentView`: `@StateObject private var viewModel` becomes `@State private var viewModel`; initialise with `State(wrappedValue:)`. In `init`s, `_viewModel = ObservedObject(wrappedValue:)` becomes `State(wrappedValue:)` / `Bindable(wrappedValue:)`. `MenuCommands` holders are separate structs: convert them individually.
5. Fix `Binding(get:set:)` call sites that used `$viewModel.xxx`: use `@Bindable`.
6. Rewrite the remaining `objectWillChange`-based tests to `withObservationTracking`.
7. Fill in the baseline "after" column for **every** row from the real view or mirror counts.

## Acceptance criteria

- [ ] `AppViewModel` has no `ObservableObject` conformance, no `@Published` (`grep -c "@Published" Sources/KromoraKit/ViewModels/AppViewModel.swift` is 0 apart from comments), and `@ObservationIgnored` is used only on storage views never read (list the groups in the ticket comment).
- [ ] No `@ObservedObject`/`@StateObject` for `AppViewModel` remains (structural test: `grep -rn "ObservedObject.*AppViewModel\|StateObject.*AppViewModel" Sources` is empty). `ContentView` uses `@State`.
- [ ] Probe test (KRMA-972 table, every row): a `document` change re-evaluates only views that read `document`; a `statusMessage`, `histogram` or `settings` change does not re-evaluate the Light/Color/Effects mirrors; the real InfoInspector re-evaluates for `histogram` and not for `statusMessage`; the real StatusBar re-evaluates for `statusMessage` and not for `histogram`. Positive controls remain (each view still updates for the property it reads).
- [ ] `grep -rn "objectWillChange" Sources Tests` is empty and `import Combine` is gone from `AppViewModel.swift` unless a documented use remains. `swift build` has zero diagnostics (warnings count; Swift 6 mode).
- [ ] `PackageSettingsTests` still passes (zero escape hatches), and the public API of `ContentView`, `KromoraCommands` and `KromoraScene` is unchanged; `swift build` also builds the `Kromora` launcher and `scripts/app-store-build.sh` passes if run (it builds the Xcode target).
- [ ] `AppViewModel.swift` is shorter than before this step.
- [ ] Manual smoke with `swift run`: open a library, open an image, drag a Light slider, switch tabs, undo/redo, toggle the inspector, open Settings, present an alert. Note what was checked in the ticket comment.

## Verification

```
swift build
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
```

## Risks

- This is the highest-risk step; if it does not fit one session, stop after step 1-3 of Approach compiling green and commit, then continue. Do not split by leaving a half-converted root on `main`.
- With `@Observable`, a view re-evaluates only for properties its `body` reads *during that evaluation*. Reads inside `onChange`, gesture closures, or `.task` closures are not tracked. A UI that stops updating after this step is almost always such a read; fix the read site.
- `MenuCommands` run inside the `Commands` scene; confirm menu enablement (copy/paste, undo/redo) still updates after the flip. The step-5 observation tests should cover it.
- `deinit` is `nonisolated`; keep teardown in the explicit shutdown method as today.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
