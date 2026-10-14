# AppViewModel Observation migration plan

Status: plan (KRMA-940). No migration has started. Read "Phasing and go/no-go" first. This document is the staged route from
`ObservableObject`/`@Published` to `@Observable` for `AppViewModel` and its remaining child objects,
so a slider tick re-evaluates only the views that read the changed property.

## Phasing and go/no-go (2026-10-13)

The `@Observable` migration changes how every view tracks state and fails silently (a view that stops updating still compiles). Do it in two phases so risk is taken only where it pays.

**Phase 1: remove forwarding, keep `ObservableObject` (low risk).** KRMA-907, then KRMA-908, then KRMA-909 (already chained). Views observe each child directly with `@ObservedObject`, and the seven forwarding entries are removed one group at a time. No `@Observable` conversion, no root flip. KRMA-972 (probe and baseline) is independent and can run before, during or after; run it early to get numbers.

**Go/no-go gate.** After Phase 1 and the KRMA-972 baseline, read the table. Continue only if a slider tick or histogram refresh still re-evaluates views it should not, at a cost worth the risk. If not, stop here.

**Phase 2: `@Observable` conversion (optional, higher risk).** KRMA-973 (view-local state; independent of Phase 1), KRMA-974/975/976 (convert the same children Phase 1 touched; each now depends on its Phase 1 ticket), KRMA-977 to KRMA-979 (extract state off the root; these also help without the root flip), KRMA-980 (root flip, the riskiest step; needs a human smoke test), KRMA-981 (narrow `document` readers and close out). KRMA-977 to KRMA-979 can stop the migration early with most of the benefit.

KRMA-892 is an unrelated logging cleanup.

## Why

`AppViewModel` is an `ObservableObject` with 30 `@Published` properties (2 more on the nested
`InspectorState`). Any change fires `objectWillChange`, and seven `ObservableObject` children
(`settings`, `library`, `libraryMediaWorkflow`, `editorDocument`, `editClipboardWorkflow`, `derive`,
`lookSave`) are forwarded into it synchronously (`AppViewModel.swift`, the `for child in [...]` loop
near L1393). About 20 views hold `@ObservedObject var viewModel: AppViewModel`, so a `document`
publish re-evaluates all of them.

KRMA-521 already moved the high-frequency children (`ImageCollection`, import, export,
`CanvasNavigation`, Photos review) to `@Observable`. This plan finishes the job.

## Inventory (generated with grep on 2026-10-13; regenerate before each step)

Regenerate with:

```
grep -n "@Published" Sources/KromoraKit/ViewModels/AppViewModel.swift
grep -rn "@ObservedObject\|@EnvironmentObject\|@StateObject" Sources
grep -rlw "viewModel\.<property>" Sources/KromoraKit/Views
```

There is no `@EnvironmentObject` use anywhere in `Sources`.

### `@Published` on `AppViewModel` and who reads it directly from views

Reads through computed properties (e.g. `isInspectorSourceDocumentPending`, `canPasteEdits`) are not
listed; the step ticket must grep for them too.

| Group | Property (line) | Direct view readers |
| --- | --- | --- |
| Document | `document` (179) | Develop/Effects/Info/Light inspectors, MaskingWorkspace, PreviewView, RetouchCanvasOverlay, RetouchInspectorView |
| Source | `sourceImage` (133) | ColorInspector, InfoInspector, KeyboardSurface, LookInspector, MaskingWorkspace |
| Source | `sourceName` (134) | ContentView |
| Source | `sourceSize` (135) | InfoInspector, PreviewView |
| Source | `sourceURL` (136) | none (model only) |
| Source | `presentation` (674) | none directly (computed accessors only) |
| Source | `navigation` (650) | ContentView, KeyboardSurface |
| White balance | `isWhiteBalanceSampling` (137) | ColorInspector, PreviewView |
| White balance | `whiteBalanceSamplerPoint` (138), `whiteBalanceLoupeImage` (139) | PreviewView |
| Capabilities | `rawCapabilities` (227) | ColorInspector, DevelopInspector |
| Capabilities | `capabilitiesProbeCompleted` (232), `editStoreStatus` (203) | none directly |
| Look | `lutResolutionStatus` (432) | LookInspector |
| Compare | `isShowingOriginal` (442) | InfoInspector, PreviewView |
| Compare | `isSideBySide` (446) | ContentView, StatusBar |
| Info | `metadata` (653) | InfoInspector, PreviewView |
| Info | `histogram` (656) | InfoInspector, MaskingWorkspace, PreviewView |
| Info | `isHistogramLoading` (659), `histogramErrorMessage` (660) | InfoInspector |
| Auto | `autoAdjustmentState` (664) | none directly |
| Auto | `autoAdjustmentProgress` (669) | StatusBar |
| Chrome | `statusMessage` (689) | MaskingWorkspace, PreviewView, StatusBar |
| Chrome | `errorMessage` (694), `libraryDeletionConfirmation` (697), `isPhotosPickerPresented` (701), `isSourceBrowserPresented` (639) | ContentView |
| Chrome | `isMaskingPanelPresented` (699) | none directly |
| Library | `portableImportProgress` (713) | LibraryGridView |
| Library | `portableQuery` (787) | CullingBarView, LibraryFacetSidebar |

`InspectorState` (`@Published isPresented`, `tab`) is an `ObservableObject` observed by ContentView and
InfoInspectorView.

### Child `ObservableObject` types still in the tree

`KromoraSettings`, `LUTLibrary` (`library`), `LibraryMediaWorkflowCoordinator`,
`EditorDocumentCoordinator`, `EditClipboardCoordinator`, `DeriveCoordinator`, `LookSaveCoordinator`
(the seven forwarded into the root), plus view-local state: `InspectorState`, `MaskInteractionState`,
`RetouchInteractionState`, `MaskDiscoveryState`, `PreviewSurface`, `MaskingPanelModel`,
`AnalysisDebugPanelModel`.

### `@ObservedObject`/`@StateObject` consumers

- `AppViewModel`: InfoInspector, StatusBar, KeyboardSurface, DevelopInspector, MaskingWorkspace (4
  views), LookInspector, PreviewView, OnboardingViews, RetouchCanvasOverlay, LibraryGridView (2),
  LibraryFacetSidebar, RetouchInspector, MenuCommands (4), LightInspector (3), EffectsInspector,
  SourceBrowser, RemovableMediaSelector, CullingBar (2), ColorInspector; `@StateObject` in ContentView.
- `KromoraSettings`: PreviewView, KromoraSettingsView, LibraryGridView (2), FilmstripView (2), MenuCommands.
- Interaction/surface state: StatusBar and MaskingWorkspace (`MaskInteractionState`), PreviewView,
  RetouchCanvasOverlay, RetouchInspector, PreviewSurface (PreviewSurface.swift, AnalysisDebugPanel,
  PreviewView), MaskDiscoveryOverlay.
- Coordinators: LookSaveSheet (`LookSaveCoordinator`), RecipeExtractorSheet (`DeriveCoordinator`).
- `@StateObject` models: AnalysisDebugPanel, MaskingPanel; ContentView `@ObservedObject InspectorState`.

## Constraints

- Swift 6 mode, zero escape hatches (no `@unchecked Sendable`, `nonisolated(unsafe)`,
  `@preconcurrency`). `@Observable` classes are `@MainActor`.
- `PackageSettingsTests` caps `AppViewModel.swift` at 5,120 lines (5,101 when measured on 2026-10-13, so 19 lines of headroom). Each step must
  shrink or hold the file; none may grow it.
- `@Observable` tracks reads of stored properties. A `didSet` observer is allowed, but
  `@Published`-style `sink` on `$property` must be replaced with explicit callbacks or `withObservationTracking`
  at the owner. Existing `cancellables` usages of `$settings...` need individual treatment.
- Wrapper changes: `@ObservedObject var x` becomes plain `let`/`var x` (or `@Bindable var x` when
  `$x.prop` bindings are used); `@StateObject` becomes `@State`. `@Observable` types must not be wrapped in
  `@StateObject` (`ObservationInvalidationTests.testObservableTypesAreNotWrappedInStateObject`).
- Forwarding loop rule (see the comment in AppViewModel): an entry is removed only in the same step that
  makes every reader of that child observe it directly.

## Measuring re-evaluation without display benchmarks

Do not use `scripts/run-kromora-capture.sh`. Add one reusable probe in the test target
(step 1) and use it in the serial lane:

- **Body probe.** A test-only `BodyProbe` view wrapper increments a counter from `body`, hosted in an
  `NSHostingView` that is laid out (`layoutSubtreeIfNeeded()`) without a visible window, then
  runs a main-actor drain. Each step's test mounts the real view under test (or a probe view reading the same
  properties) against `makeAppViewModel(engine: FakeRenderEngine())`, mutates one property, and
  asserts exact body counts: views that read the property re-evaluate once, views that do not stay at 0.
- **Observation probe.** For model-level checks without SwiftUI, `withObservationTracking` on a closure
  that reads the properties a view reads, asserting `onChange` fires only for the intended property.
  Fast lane, deterministic.
- **Structural assertions.** Source-scan tests (as `ObservationInvalidationTests` already does) for
  the removal of forwarding entries, `@Published` counts, and wrapper changes.
- Step 1 records a baseline table (view × mutated property → body count) in this document; later
  steps update the "after" column. Counts are logical, not times, so they are stable across machines.

## Steps (one child ticket each, `depends_on` chained in order)

Prior art: KRMA-907 (step 3), KRMA-908 (step 4), KRMA-909 (step 5) are Phase 1 prerequisites of those steps, not superseded by them. KRMA-910 is done and independent of step 7.

1. **Re-evaluation probe + baseline.** Add `BodyProbe` / helpers and baseline tests for `document`,
   `statusMessage`, `histogram`, `settings`; record counts here. No production change.
2. **View-local state to `@Observable`.** `InspectorState`, `MaskInteractionState`,
   `RetouchInteractionState`, `MaskDiscoveryState`, `PreviewSurface`, `MaskingPanelModel`,
   `AnalysisDebugPanelModel`; `@StateObject`/`@ObservedObject` → `@State`/plain. None are forwarded to the root.
3. **Derive, Look-save, media workflow** (KRMA-907). Convert the three coordinators; views observe them
   directly; remove their forwarding entries.
4. **Settings and Look library** (KRMA-908). Convert `KromoraSettings` and `LUTLibrary`; replace the
   `settings.$maskOverlayAppearance` sink; remove both entries.
5. **Clipboard and editor-document coordinators** (KRMA-909). Convert both; remove the last two entries
   and the whole forwarding loop; delete or rewrite `testLowFrequencyChildrenForwardSynchronouslyWithoutTask`.
6. **Info state extraction.** Move `histogram`, `isHistogramLoading`, `histogramErrorMessage`, `metadata`
   into one `@Observable` `InfoState`; InfoInspector, PreviewView and MaskingWorkspace read it directly.
7. **Presentation chrome extraction** (KRMA-910 overlaps). Move `statusMessage`, `errorMessage`,
   `libraryDeletionConfirmation`, `isPhotosPickerPresented`, `isSourceBrowserPresented`,
   `isMaskingPanelPresented`, `portableImportProgress`, `portableQuery` into focused `@Observable`
   state objects read by ContentView, StatusBar, library views.
8. **White balance sampler, capabilities, Auto state.** Extract `isWhiteBalanceSampling`,
   `whiteBalanceSamplerPoint`, `whiteBalanceLoupeImage`, `rawCapabilities`, `capabilitiesProbeCompleted`,
   `autoAdjustmentState`, `autoAdjustmentProgress`, `lutResolutionStatus` into `@Observable` state.
9. **Root flip.** `AppViewModel` → `@MainActor @Observable`; remaining `@Published` (`document`, source,
   navigation, compare flags, `presentation`) become stored properties; every `@ObservedObject var viewModel`
   becomes plain/`@Bindable`; ContentView `@StateObject` → `@State`; remove `import Combine` leftovers.
   Check that slider ticks re-evaluate only views reading `document`.
10. **Narrow `document` readers and close out.** Where inspectors only need one section of `document`,
    pass a per-section value or `Binding` so a Light slider tick does not re-evaluate the Color/Effects
    inspectors; update the doc's baseline table, `APP_ARCHITECTURE.md`, `ENGINEERING_GUIDE.md`, and remove stale
    `@Published`/`ObservableObject` guidance.

Every step must leave `swift build` and `scripts/ci-tests.sh fast` + `serial` green, and the line count of
`AppViewModel.swift` no larger than before the step.

## Baseline (KRMA-972, 2026-10-13)

Body evaluations caused by one change to one `AppViewModel` property, on a fresh model with the
view hosted in an unshown `NSHostingView`. Counts are logical evaluations, not timings. "real" rows
mount the production view (it counts itself through `RenderDiagnostics`); "mirror" rows are
test-only views in `Tests/KromoraKitTests/Support/BodyProbe.swift` that read the same properties as
the production view, so they are not the production view. Reproduce with
`swift test --no-parallel --filter ObservationBodyBaselineTests` (rows print as `BODY-BASELINE`).
Steps 2-10 fill in the "after" column; KRMA-980 completed it.

| View | Kind | Property changed | Before | After |
| --- | --- | --- | --- | --- |
| StatusBar | real | document | 1 | 0 |
| StatusBar | real | statusMessage | 1 | 1 |
| StatusBar | real | histogram | 1 | 0 |
| StatusBar | real | settings.showPhotoNames | 0 | 0 |
| InfoInspectorView | real | document | 1 | 0 |
| InfoInspectorView | real | statusMessage | 1 | 0 |
| InfoInspectorView | real | histogram | 1 | 1 (reads `info.histogram`) |
| InfoInspectorView | real | settings.showPhotoNames | 0 | 0 |
| LightInspectorView | mirror | document | 1 | 1 |
| LightInspectorView | mirror | statusMessage | 1 | 0 |
| LightInspectorView | mirror | histogram | 1 | 0 |
| LightInspectorView | mirror | settings.showPhotoNames | 0 | 0 |
| ColorInspectorView | mirror | document | 1 | 1 |
| ColorInspectorView | mirror | statusMessage | 1 | 0 |
| ColorInspectorView | mirror | histogram | 1 | 0 |
| ColorInspectorView | mirror | settings.showPhotoNames | 0 | 0 |
| EffectsInspectorView | mirror | document | 1 | 1 |
| EffectsInspectorView | mirror | statusMessage | 1 | 0 |
| EffectsInspectorView | mirror | histogram | 1 | 0 |
| EffectsInspectorView | mirror | settings.showPhotoNames | 0 | 0 |
| PreviewView | mirror | document | 1 | 1 |
| PreviewView | mirror | statusMessage | 1 | 1 |
| PreviewView | mirror | histogram | 1 | 1 (reads `info.histogram`) |
| PreviewView | mirror | settings.showPhotoNames | 1 | 0 |
| PreviewView | mirror | whiteBalance.samplerPoint | 1 | 0 |
| ColorInspectorView | mirror | whiteBalance.samplerPoint | 1 | 0 |
| StatusBar | real | whiteBalance.samplerPoint | 1 | 0 |
| WhiteBalanceLoupeOverlay | mirror | whiteBalance.samplerPoint | — | 1 |
| StatusBar | real | autoLook.autoAdjustmentProgress | 1 | 1 |
| ColorInspectorView | mirror | autoLook.autoAdjustmentProgress | 1 | 0 |
| WhiteBalanceLoupeOverlay | mirror | autoLook.autoAdjustmentProgress | — | 0 |
| InfoInspectorView | real | maskInteractionState.hoverPoint | 0 | 0 |
| InfoInspectorView | real | maskInteractionState.brushRadius | 0 | 0 |
| InfoInspectorView | real | retouchInteractionState.radius | 0 | 0 |
| InfoInspectorView | real | retouchInteractionState.hover | 0 | 0 |
| LightInspectorView | mirror | maskInteractionState.hoverPoint | 0 | 0 |
| LightInspectorView | mirror | maskInteractionState.brushRadius | 0 | 0 |
| LightInspectorView | mirror | retouchInteractionState.radius | 0 | 0 |
| LightInspectorView | mirror | retouchInteractionState.hover | 0 | 0 |
| ColorInspectorView | mirror | maskInteractionState.hoverPoint | 0 | 0 |
| ColorInspectorView | mirror | maskInteractionState.brushRadius | 0 | 0 |
| ColorInspectorView | mirror | retouchInteractionState.radius | 0 | 0 |
| ColorInspectorView | mirror | retouchInteractionState.hover | 0 | 0 |
| EffectsInspectorView | mirror | maskInteractionState.hoverPoint | 0 | 0 |
| EffectsInspectorView | mirror | maskInteractionState.brushRadius | 0 | 0 |
| EffectsInspectorView | mirror | retouchInteractionState.radius | 0 | 0 |
| EffectsInspectorView | mirror | retouchInteractionState.hover | 0 | 0 |

KRMA-978 view probe results: a `statusMessage` change evaluates the real `StatusBar` once and the
`PreviewView` mirror once; `InfoInspectorView`, the Light/Color/Effects mirrors, and the
`CullingBar`/`LibraryFacetSidebar` query mirrors stay at zero. `portableQuery` evaluates its two
query mirrors once and leaves the real `StatusBar` at zero. `MaskingWorkspace` reads status text only
in its failed-preview banner branch, so it observes status changes while that branch is active.

KRMA-980 (step 9): `AppViewModel` is `@Observable`; every row above is the post-flip measurement. A
`document` change evaluates only views that read `document` (the real InfoInspector and the real
StatusBar stay at 0); a `statusMessage` change evaluates the real StatusBar and the PreviewView
mirror only; `histogram` evaluates the real InfoInspector and the PreviewView mirror only.

KRMA-979 (step 8): the sampler, capability and Auto/Look status state moved to
`WhiteBalanceSamplerState`, `EditorCapabilityState` and `AutoLookStatusState`
(`ViewModels/EditorAuxiliaryState.swift`). A `whiteBalance.samplerPoint` change evaluates only the
loupe read set (`WhiteBalanceLoupeOverlay`, mirrored by `MirrorReadSet.loupe`) and leaves the Color
mirror, `PreviewView` mirror and `StatusBar` at 0; an `autoLook.autoAdjustmentProgress` change
evaluates the real `StatusBar` and leaves the Color mirror and loupe at 0. Color/Preview mirror
rows that read `whiteBalance.isSampling` / `capabilities.rawCapabilities` are unchanged in the
table above (the flag still changes rarely). `@Published` remaining on `AppViewModel`: exactly the nine
named in the ticket; `virtualCopyMetadata` and `portableLibrary` are plain properties set once at
bind time; the open flow's `navigation`/`presentation` publishes refresh their derived readers.

## Additions from ticket review (2026-10-13)

The first inventory missed these root-invalidation paths. Each is assigned to a step below.

- **Two more `objectWillChange.send()` hooks that are not in the forwarding loop** (step 5 removes them):
  `EditHistoryCoordinator` (`willSet { willChange() }` on `history`, `currentRevision`,
  `isCreatingVirtualCopy`; constructed at `AppViewModel.swift` ~L384-399 with
  `willChange: { self?.objectWillChange.send() }`) and `VirtualCopyMetadataCoordinator`
  (`willChange()` before `presentation` changes; constructed ~L348-351). Neither is an
  `ObservableObject`, so a grep for `ObservableObject` does not find them. Step 9 cannot compile
  cleanly until both are `@Observable` and read through the root's computed forwarders
  (`durableEditHistory`, `durableCurrentEditRevision`, `virtualCopySourceDescription`).
- **A second Combine consumer of `settings`**: `KromoraWindowAppearanceController`
  (`Models/KromoraWindowAppearanceController.swift` ~L80) subscribes to `settings.$appearanceMode`.
  Step 4 replaces it together with the `$maskOverlayAppearance` sink.
- **`EditorDocumentCoordinator` has no `@Published` property.** It is forwarded but never emits;
  `canUndo`/`canRedo` refresh only because `document` publishes beside them. Converting it (step 5) makes
  those reads genuinely tracked.
- **`private lazy var` needs `@ObservationIgnored`.** `@Observable` rejects `lazy` stored properties.
  `AppViewModel` has 11 `lazy var`s (coordinators); step 9 marks each `@ObservationIgnored`.
- **31 `@ObservedObject var viewModel: AppViewModel` declarations**, not about 20: 4 are in `MenuCommands.swift`
  and several views declare it twice.
- **Existing production body counters** (`RenderDiagnostics` in `Models/ObservationInstrumentation.swift`):
  `InfoInspectorView` (`noteInspectorBody`), `StatusBar` (`noteToolbarBody`), `ContentView`, and
  `LibraryGridView` already count their own body evaluations. Light, Color, Effects and Preview have none;
  see step 1 for how the probe covers them.
- **Lane registration.** `scripts/ci-tests.sh` selects the serial lane by an explicit class-name regex
  (`serial_filter`). A new `NSHostingView` test class must be added to it, or it runs in the parallel fast lane.

## Common rules for every step ticket

1. Work on the current branch; one issue at a time; commit subject starts with the issue id.
2. Before editing, run the inventory greps above and `wc -l Sources/KromoraKit/ViewModels/AppViewModel.swift`
   and note both in the ticket comment. The file must end no larger than it started.
3. Swift 6 mode with zero escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`);
   macOS 26 only; no `#available`. `deinit` is `nonisolated`, so teardown stays in explicit methods.
4. Wrapper mapping: `@ObservedObject var x` becomes plain `let`/`var x`, or `@Bindable var x` when the view
   uses `$x.prop`; `@StateObject` becomes `@State`; an `@Observable` type is never held by `@StateObject`.
   Inside a view `init`, `_x = ObservedObject(wrappedValue:)` becomes `_x = Bindable(wrappedValue:)` or `State(wrappedValue:)`
   (`ContentView` already does this for its `@Bindable` children).
5. `@Observable` classes are `@MainActor final class`. Use `@ObservationIgnored` only for storage that views
   never read (tasks, caches, closures, injected collaborators). A property that a view reads must stay tracked.
6. A computed property on `AppViewModel` that reads a child (for example `canPasteEdits`) is tracked only if the
   child is `@Observable`. Never leave a view reading an `ObservableObject` child through an `@Observable` parent.
7. Done means `swift build` has zero diagnostics, `scripts/ci-tests.sh fast` and `scripts/ci-tests.sh serial` pass,
   and the baseline "after" column is updated. Do not run `scripts/run-kromora-capture.sh`.
8. Structural `@Published` counts match declarations (`^\s*@Published\b`) in `AppViewModel.swift`, never comment mentions. Expected root declaration counts after each step: 30 at start (steps 2-5 do not change it), 26 after step 6, 18 after step 7, 9 after step 8, 0 after step 9.
9. Converting a type to `@Observable` also removes it from the `ObservableObject` allowlist test added by KRMA-987, in the same commit.
10. If a step discovers another invalidation path not in this plan, add it here and to the owning ticket instead of
   widening the step silently.

## Ticket map

Steps 1-10 are KRMA-972 through KRMA-981, in order, each depending on the previous one.
