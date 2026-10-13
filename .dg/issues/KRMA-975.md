---
id: KRMA-975
title: "Observation step 4: Convert KromoraSettings and LUTLibrary (builds on KRMA-908)"
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
created: 2026-10-13T19:36:54.997Z
updated: 2026-10-13T19:36:55.915Z
depends_on:
  - KRMA-974
  - KRMA-908
blockers: []
order: zzzzx
board: product
---

## Objective

Convert `KromoraSettings` and `LUTLibrary` to `@Observable`, replace every Combine consumer of their publishers, and remove their two forwarding entries. Supersedes KRMA-908.

## Context

**Relationship to KRMA-908:** it must be done first (added to `depends_on`). If landed, steps for the forwarding array and direct view observation are verification only.

Part of `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` (read it, "Additions from ticket review" and "Common rules"). Depends on KRMA-974. Read `.dg/issues/KRMA-908.md` first; it is the prior art and the required prerequisite.

Types:
- `KromoraSettings` (`Models/KromoraSettings.swift:61`, **public**, `@MainActor`). `@Published` properties: `appearanceMode` (L86), `showPhotoNames` (L93), `showClippingAlerts` (L102), `openFirstPhotoWhenEnteringEdit` (L111), `maskOverlayAppearance` (L134, internal), `sourceFolderStatus` and `exportFolderStatus` (L151-152, `public private(set)`). Most have a `didSet` that writes to `UserDefaults`. Held as `public let settings` (`AppViewModel.swift:745`). Public surface used by `KromoraScene`/`KromoraCommands`; it must keep compiling for the SwiftPM launcher (`Sources/Kromora/KromoraApp.swift`) and the Xcode launcher.
- `LUTLibrary` (`Models/LUTLibrary.swift:6`): `categories`, `allLUTs`, `folderURL`, `scanError`, `isScanning`, `isImporting`, `importError`, `bundledLoadWarnings`. Held as `let library` (`AppViewModel.swift:746`).

**Three Combine consumers must be replaced individually** (the plan listed only the first):
1. `AppViewModel.swift` ~L1427: `settings.$maskOverlayAppearance.sink { maskInteractionState.apply($0) }`. The comment there says `@Published` delivers the stored value immediately, so the replacement must also apply the *initial* value once at setup.
2. `Models/KromoraWindowAppearanceController.swift` ~L80: `settings.$appearanceMode.dropFirst().sink { desiredMode = $0; applyAppearance(...) }`. Its comment explains that it deliberately uses the value rather than `objectWillChange` so an open window does not lag behind the Settings toggle when the main actor is busy. The replacement must keep that property: apply the **new** value synchronously during the setter.
3. The forwarding loop entries `settings.objectWillChange` and `library.objectWillChange` (AppViewModel.swift ~L1403-1404).

Recommended replacement for 1 and 2: an explicit callback invoked from the setter, since `didSet` runs after the new value is stored and synchronously. For example `@ObservationIgnored var onMaskOverlayAppearanceChange: ((MaskOverlayAppearance) -> Void)?` and `var onAppearanceModeChange: ((KromoraAppearanceMode) -> Void)?`, called from the existing `didSet`. Do not use `withObservationTracking` for these; its `onChange` fires *before* the change (willSet timing) and needs a re-arm loop plus an extra main-actor hop, which reintroduces exactly the lag the comment describes.

`@Observable` and persistence: `didSet` on tracked stored properties is supported and still runs; it is **not** run during `init`, same as today. The `init(preferences:)` (L168) loads from `UserDefaults` into the stored properties directly, which already relies on that. Add a test that sets each persisted setting and reads it back from the injected `UserDefaults` to prove persistence survived. `@ObservationIgnored` only for non-observed storage (the `UserDefaults` handle, callbacks).

View consumers of settings: `PreviewView.swift:20,30`, `KromoraSettingsView.swift:6,20`, `LibraryGridView.swift:252,344`, `FilmstripView.swift:7,90`, `MenuCommands.swift:56,62`. Consumers of `library`: `LookInspectorView` (via `viewModel.library`), `LookSaveSheet`, and `LookSelectionCoordinator(library:)` at `AppViewModel.swift` ~L382 (confirm it only calls methods, not publishers). Run `grep -rn "viewModel\.library\|\.library\.\|viewModel\.settings\|\.settings\." Sources/KromoraKit/Views`.

Tests referencing the types: `KromoraSettings` in 7 test files, `LUTLibrary` in 7. `KromoraWindowAppearanceController` has its own tests (grep `KromoraWindowAppearanceControllerTests`; that class is in the serial lane).

## Approach

1. Convert both classes. Keep `public` on `KromoraSettings` and its public properties. Confirm `@Observable` on a `public` class compiles with `public private(set)` properties.
2. Replace the two sinks with the setter callbacks above, wired where the sinks are today (the controller receives the settings object in its setup; give it a callback registration instead of a publisher). Apply the initial mask-overlay value explicitly.
3. Convert views: plain/`@Bindable` per the wrapper mapping. `KromoraSettingsView` uses bindings to settings and needs `@Bindable`.
4. Remove `settings` and `library` from the forwarding array.
5. `LUTLibrary.bundledLoadWarnings` is `private(set)` and set in `init`; confirm no `@Published private(set) var x: [String]` init-order problem under the macro.

## Acceptance criteria

- [ ] Both types are `@MainActor @Observable`; no `@Published` or `ObservableObject` remains in either file; `KromoraSettings` public API is unchanged and `swift build` of the `Kromora` executable target succeeds.
- [ ] No `$`-publisher sink on either type remains (`grep -rn "settings\.\$\|library\.\$\|\$appearanceMode\|\$maskOverlayAppearance" Sources` is empty) and `KromoraWindowAppearanceController` no longer holds an `AnyCancellable` for settings.
- [ ] Behavior tests: changing `appearanceMode` applies the appearance synchronously in the same call (assert immediately after the assignment, no yield); changing `maskOverlayAppearance` updates `maskInteractionState` immediately; and at launch `maskInteractionState` holds the persisted overlay appearance before any change.
- [ ] Persistence round trip for every `UserDefaults`-backed setting passes against an injected suite.
- [ ] Probe test (KRMA-972): toggling a thumbnail/grid-name setting (`showPhotoNames`) does not re-evaluate StatusBar or the Light/Color/Effects mirrors; it does re-evaluate a view that reads it. Update the "after" column for the `settings` row.
- [ ] The forwarding array holds only `editorDocument` and `editClipboardWorkflow`; `testLowFrequencyChildrenForwardSynchronouslyWithoutTask` drops its settings and library assertions.
- [ ] `AppViewModel.swift` is not longer than before. KRMA-908 is untouched (a done prerequisite, not superseded).

## Verification

```
swift build
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
```

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
