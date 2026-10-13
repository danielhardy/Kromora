---
id: KRMA-973
title: "Observation step 2: Convert view-local state objects to @Observable"
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
created: 2026-10-13T19:36:52.020Z
updated: 2026-10-13T19:36:52.956Z
depends_on:
  - KRMA-972
blockers: []
order: zzzzq
board: product
---

## Objective

Convert the seven view-local state objects to `@Observable` and move their views to plain, `@Bindable` or `@State` properties. None are in the root forwarding loop, so this step is isolated and cannot change what `AppViewModel` publishes.

## Context

Part of `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` (read it, "Additions from ticket review" and "Common rules"). Depends on KRMA-972 for the probe and baseline.

The seven types, verified 2026-10-13:

| Type | Declaration | Consumers |
| --- | --- | --- |
| `AppViewModel.InspectorState` | `ViewModels/AppViewModel.swift:95` (`@Published isPresented` with a `didSet`, `@Published tab`) | `ContentView.swift:12` (`@ObservedObject`, set in both `init`s at L34 and L46), `InfoInspectorView.swift:8` |
| `MaskInteractionState` | `Models/MaskInteractionState.swift:93` | `StatusBar.swift:115`, `PreviewView.swift:18`, `MaskingWorkspace.swift:12,1060,1190,1440` |
| `RetouchInteractionState` | `Models/RetouchInteractionState.swift:7` | `RetouchCanvasOverlay.swift:7`, `RetouchInspectorView.swift:13`, `PreviewView.swift:19` |
| `MaskDiscoveryState` | `Models/MaskDiscoveryState.swift:7` | `MaskDiscoveryOverlay.swift:8` |
| `PreviewSurface` | `Views/PreviewSurface.swift:14` (lives in `Views/`, not `Models/`) | `PreviewView.swift:12-13`, `PreviewSurface.swift:1113`, `AnalysisDebugPanel.swift:8` |
| `MaskingPanelModel` | `ViewModels/MaskingPanelModel.swift:8` | `@StateObject` at `MaskingPanel.swift:56` |
| `AnalysisDebugPanelModel` | `ViewModels/AnalysisDebugPanelModel.swift:7` | `@StateObject` at `AnalysisDebugPanel.swift:7` |

Test touch points: `CanvasNavigationTests.swift:698-699` subscribes to `viewModel.inspectorState.objectWillChange` and must be rewritten with `withObservationTracking`. Types are referenced from these test files (counts of files): InspectorState 1, MaskInteractionState 4, MaskDiscoveryState 1, PreviewSurface 6, MaskingPanelModel 1, AnalysisDebugPanelModel 1. Grep each before editing.

`InspectorState.onPresentationChange` is called from `isPresented`'s `didSet` and drives `AppViewModel.refreshHistogramGate()` (wired at `AppViewModel.swift` ~L1421). Keep that callback and keep it synchronous after assignment. `@Observable` supports `didSet` on tracked properties; the existing comment about `@Published` emitting from `willSet` stops being true and should be removed or reworded.

## Approach

1. For each type: replace `: ObservableObject` with `@Observable` (add `import Observation` if the file does not already get it via SwiftUI/Foundation), keep `@MainActor final class`, delete `@Published`. Mark non-view-read storage (tasks, closures such as `onPresentationChange`, caches) `@ObservationIgnored`.
2. Rewrite each consumer per the wrapper mapping in the plan's Common rules. A type is `@Bindable` only where the view writes `$x.prop`; otherwise a plain `let`/`var`. For view `init`s that do `_x = ObservedObject(wrappedValue:)`, use `_x = Bindable(wrappedValue:)` (see the existing `_canvasState = Bindable(...)` lines in `ContentView.init`).
3. `MaskingPanelModel` and `AnalysisDebugPanelModel` become `@State private var model` initialised through `State(wrappedValue:)` in `init`, same as today.
4. Search `Sources` and `Tests` for `.objectWillChange` and `$`-publisher use on these types and replace each with observation.

## Acceptance criteria

- [ ] All seven types are `@MainActor @Observable final class` with no `ObservableObject` or `@Published`. `grep -rn "ObservableObject" Sources` no longer lists them (it still lists the other nine types until later steps).
- [ ] No `@ObservedObject`/`@StateObject` remains for any of the seven types (`grep -rn "ObservedObject.*\(InspectorState\|MaskInteractionState\|RetouchInteractionState\|MaskDiscoveryState\|PreviewSurface\)\|StateObject.*\(MaskingPanelModel\|AnalysisDebugPanelModel\)" Sources` is empty).
- [ ] `InspectorState.isPresented` still triggers the histogram gate synchronously (`CanvasNavigationTests` equivalent passes after being rewritten to `withObservationTracking`).
- [ ] Probe test (KRMA-972 helpers): changing `maskInteractionState` or `retouchInteractionState` properties does not re-evaluate the Light/Color/Effects mirrors or InfoInspector. StatusBar is excepted only for properties it actually reads (check `StatusBar.swift` around L115). Fill the "after" column for the affected rows.
- [ ] `ObservationInvalidationTests` gains a source-scan assertion that none of the seven types is declared `ObservableObject`, in the style of the existing scans.
- [ ] Masking, retouch, preview-surface and analysis-panel tests pass unmodified apart from the `objectWillChange` rewrite above.
- [ ] `AppViewModel.swift` is not longer than before (`InspectorState` shrinks).

## Verification

```
swift build
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
```

## Risks

- A view that read a published value but never ran `$x.prop` may rely on `@ObservedObject` to refresh on *any* change; with `@Observable` it refreshes only for properties its body reads. If a UI surface goes stale, the cause is a read outside `body` (for example in `init` or a closure that runs later). Fix the read site, do not restore Combine.
- `PreviewSurface` is large and touched by six test files; convert it last and run the preview/surface tests after each type.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
