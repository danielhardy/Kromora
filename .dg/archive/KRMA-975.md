---
id: KRMA-975
title: "Observation step 4: Convert KromoraSettings and LUTLibrary (builds on KRMA-908)"
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: KromoraSettings and LUTLibrary are @MainActor @Observable with no @Published or ObservableObject declarations, and the existing public settings surface builds for the SwiftPM Kromora executable.
      result: pass
      notes: Both models compile in the SwiftPM launcher. Existing public properties remain public; the setter callback is module-internal.
    - criterion: No Combine publisher consumer or settings AnyCancellable remains for KromoraSettings or LUTLibrary.
      result: pass
      notes: Publisher and AnyCancellable source scan is clean.
    - criterion: Appearance mode applies synchronously, mask overlay appearance reaches interaction state immediately, and launch applies the persisted overlay value.
      result: pass
      notes: Immediate window appearance and mask interaction state assertions pass, including the seeded launch preference.
    - criterion: Every UserDefaults-backed setting round-trips using injected preferences.
      result: pass
      notes: KromoraSettingsTests passed all 17 tests using isolated UserDefaults suites.
    - criterion: showPhotoNames changes invalidate only readers, and the observation baseline after column records the settings result.
      result: pass
      notes: The serial probe reports zero reevaluations for StatusBar and Light/Color/Effects mirrors and zero for other non-readers; the positive-control reader reevaluates. The plan's after values are updated.
    - criterion: Settings and library are absent from root forwarding; the low-frequency forwarding test no longer asserts them.
      result: pass
      notes: The current AppViewModel has no child forwarding loop, and the legacy forwarding test is absent; direct observation tests verify settings/library changes stay out of the root.
    - criterion: AppViewModel.swift does not grow.
      result: pass
      notes: It is 5,044 lines both before and after.
  checks_run:
    - swift build — exit 0; KromoraKit and SwiftPM Kromora launcher built, including after verification fixes.
    - scripts/ci-tests.sh fast — exit 0; 1,889 required fast tests.
    - scripts/ci-tests.sh serial — exit 0; required serial lane passed, including body probes and appearance-controller tests.
    - swift test --no-parallel --filter 'ObservationInvalidationTests|KromoraSettingsTests|KromoraWindowAppearanceControllerTests|ObservationBodyBaselineTests' — 49 tests passed, exit 0 after verification fixes.
    - git diff --check on touched implementation and test files — exit 0.
    - Publisher, root-forwarding, and public-callback visibility scans — clean.
  findings:
    - The appearance callback had been made public despite only being used inside KromoraKit; that unnecessarily expanded KromoraSettings API.
    - LUT projection caches and their diagnostic counter were observable stored properties, so cache initialization could invalidate a view during its first projection read.
  fixes:
    - Made onAppearanceModeChange module-internal.
    - Marked LUT projection caches and their test diagnostic counter @ObservationIgnored, and added a regression assertion that cache fill does not notify an observer.
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T03:39:21.337Z
  session: 01MV7JXMMDUPISIGUV
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - swiftui
created: 2026-10-13T19:36:54.997Z
updated: 2026-10-24T13:05:21.232Z
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T03:30:00.088Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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

- 2026-10-14T03:39:21.337Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] KromoraSettings and LUTLibrary are @MainActor @Observable with no @Published or ObservableObject declarations, and the existing public settings surface builds for the SwiftPM Kromora executable. (pass) — Both models compile in the SwiftPM launcher. Existing public properties remain public; the setter callback is module-internal.
- [x] No Combine publisher consumer or settings AnyCancellable remains for KromoraSettings or LUTLibrary. (pass) — Publisher and AnyCancellable source scan is clean.
- [x] Appearance mode applies synchronously, mask overlay appearance reaches interaction state immediately, and launch applies the persisted overlay value. (pass) — Immediate window appearance and mask interaction state assertions pass, including the seeded launch preference.
- [x] Every UserDefaults-backed setting round-trips using injected preferences. (pass) — KromoraSettingsTests passed all 17 tests using isolated UserDefaults suites.
- [x] showPhotoNames changes invalidate only readers, and the observation baseline after column records the settings result. (pass) — The serial probe reports zero reevaluations for StatusBar and Light/Color/Effects mirrors and zero for other non-readers; the positive-control reader reevaluates. The plan's after values are updated.
- [x] Settings and library are absent from root forwarding; the low-frequency forwarding test no longer asserts them. (pass) — The current AppViewModel has no child forwarding loop, and the legacy forwarding test is absent; direct observation tests verify settings/library changes stay out of the root.
- [x] AppViewModel.swift does not grow. (pass) — It is 5,044 lines both before and after.
Checks run:
- swift build — exit 0; KromoraKit and SwiftPM Kromora launcher built, including after verification fixes.
- scripts/ci-tests.sh fast — exit 0; 1,889 required fast tests.
- scripts/ci-tests.sh serial — exit 0; required serial lane passed, including body probes and appearance-controller tests.
- swift test --no-parallel --filter 'ObservationInvalidationTests|KromoraSettingsTests|KromoraWindowAppearanceControllerTests|ObservationBodyBaselineTests' — 49 tests passed, exit 0 after verification fixes.
- git diff --check on touched implementation and test files — exit 0.
- Publisher, root-forwarding, and public-callback visibility scans — clean.
Findings:
- The appearance callback had been made public despite only being used inside KromoraKit; that unnecessarily expanded KromoraSettings API.
- LUT projection caches and their diagnostic counter were observable stored properties, so cache initialization could invalidate a view during its first projection read.
Fixes:
- Made onAppearanceModeChange module-internal.
- Marked LUT projection caches and their test diagnostic counter @ObservationIgnored, and added a regression assertion that cache fill does not notify an observer.
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7JXMMDUPISIGUV
Summary: Independent verification passed; localized callback visibility and LUT cache observation fixes verified.
