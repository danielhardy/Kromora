---
id: KRMA-974
title: "Observation step 3: Observe derive, Look-save and media workflow directly (builds on KRMA-907)"
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
created: 2026-10-13T19:36:53.520Z
updated: 2026-10-13T19:36:54.433Z
depends_on:
  - KRMA-973
  - KRMA-907
blockers: []
order: zzzzv
board: product
---

## Objective

Convert `DeriveCoordinator`, `LookSaveCoordinator` and `LibraryMediaWorkflowCoordinator` to `@Observable`, make every reader observe them, and remove their three entries from the root forwarding loop. Supersedes KRMA-907.

## Context

**Relationship to KRMA-907:** that ticket must be done first (added to `depends_on`). If it has landed, the three loop entries are already gone and views already hold the coordinators directly, so the loop-removal and "views observe directly" parts below reduce to verification, and the remaining work is the `@Observable` conversion and wrapper changes (`@ObservedObject` -> plain/`@Bindable`). Do not close KRMA-907 from here.

Part of `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` (read it, "Additions from ticket review" and "Common rules"). Depends on KRMA-973. Read `.dg/issues/KRMA-907.md` first; it is the prior art and the required prerequisite.

**Why order matters.** The forwarding loop is `AppViewModel.swift` ~L1402-1417 (the `for child in [...]` array, with its explanatory comment above it). Its rule: an entry may be removed only in the same step that makes every reader of that child observe it, otherwise sheets stop presenting and removable-media scans stop refreshing.

Types and state (all `@Published` today):
- `ViewModels/DeriveCoordinator.swift:17`: `isSheetPresented`, `isDeriving`, `progress`, `stage`, `derivedLUT`, `report`, and more. Held as `let derive = DeriveCoordinator()` (`AppViewModel.swift:796`).
- `ViewModels/LookSaveCoordinator.swift:10`: `isSheetPresented`, `isConverting`, `conversion`, `name`, `allowsApproximateSave`, `saveError`. `let lookSave` (`AppViewModel.swift:799`).
- `ViewModels/LibraryMediaWorkflowCoordinator.swift:54`: about 15 properties (`removableMediaVolumes`, `isRemovableMediaSelectorPresented`, `removableMediaFiles`, `removableMediaSelection`, `removableMediaImportProgress`, `hidesInLibraryRemovableMedia`, ...). `let libraryMediaWorkflow` (`AppViewModel.swift:800`).

Readers that go through the root, not the child (these are the ones most likely to go stale):
- `ContentView.swift:75-84` builds `Binding`s from `viewModel.derive.isSheetPresented` / `viewModel.lookSave.isSheetPresented` and passes the coordinators to `RecipeExtractorSheet(coordinator:)` (`RecipeExtractorSheet.swift:9`, `@ObservedObject`) and `LookSaveSheet(coordinator:)` (`LookSaveSheet.swift:5`, `@ObservedObject`).
- Computed forwarders on `AppViewModel` that read `libraryMediaWorkflow` (L718-735: `removableMediaVolumes`, `isRemovableMediaSelectorPresented` get/set, `removableMediaVolume`, `mediaImportSource`, `removableMediaFiles`, `removableMediaWarnings`, `removableMediaInLibrary`, `removableMediaLibraryChecked`, `isCheckingRemovableMediaLibrary`, `visibleRemovableMediaFiles`, `hidesInLibraryRemovableMedia`, `isRemovableMediaScanning`). Views that read them: `RemovableMediaSelectorView.swift`, `OnboardingViews.swift`, `MenuCommands.swift`, `ContentView.swift`. Re-run `grep -rn "removableMedia\|mediaImportSource" Sources/KromoraKit/Views` and list every hit in the ticket comment.
- Other `viewModel.derive` / `viewModel.lookSave` reads: `grep -rn "viewModel\.\(derive\|lookSave\|libraryMediaWorkflow\)\|\.derive\.\|\.lookSave\." Sources`.

Tests: `ObservationInvalidationTests.testLowFrequencyChildrenForwardSynchronouslyWithoutTask` (L32) asserts forwarding counts for derive, look-save and removable media; those assertions go away for these three. Other test files touching the types: `DeriveCoordinatorTests`, `LookLUTExportTests`, and the media-volume tests (grep `LibraryMediaWorkflowCoordinator|removableMedia` in `Tests`).

Teardown: `AppViewModel.swift` ~L4430 nils `libraryMediaWorkflow.onStatus` etc. in an explicit shutdown. Keep those closures `@ObservationIgnored` in the coordinator; they are not UI state.

## Approach

1. Convert the three classes (`@MainActor @Observable final class`, `@ObservationIgnored` for tasks/closures/injected services; keep `private(set)` modifiers).
2. Sheets: `RecipeExtractorSheet`/`LookSaveSheet` take the coordinator as a plain `let` (or `@Bindable` if they bind to `$coordinator.name` and similar; `LookSaveSheet` binds `name` and `allowsApproximateSave` so expect `@Bindable` there).
3. `ContentView`: the sheet `Binding`s read `viewModel.derive.isSheetPresented`. Keep reading through the coordinator reference so tracking sees it. If `ContentView` should not re-evaluate on unrelated `derive` progress ticks, use `@Bindable var derive`/`lookSave` stored in `ContentView` (as `ContentView` already does for `canvasState`/`collection`) and bind with `$derive.isSheetPresented`.
4. Removable-media forwarders: leave the computed properties on `AppViewModel` (callers keep compiling), since a computed property reading an `@Observable` child is tracked transitively. Do not leave any view reading a non-converted child through them.
5. Delete the three entries from the array. The array then holds `settings`, `library`, `editorDocument`, `editClipboardWorkflow`.
6. Update the explanatory comment above the loop so it lists only the four remaining children.

## Acceptance criteria

- [ ] The three coordinators are `@MainActor @Observable`; none declares `ObservableObject` or `@Published`.
- [ ] The forwarding array no longer contains `derive`, `lookSave` or `libraryMediaWorkflow`; the comment names only the four remaining children.
- [ ] For each coordinator a test mutates the presenting property (`derive.isSheetPresented`, `lookSave.isSheetPresented`, `libraryMediaWorkflow.isRemovableMediaSelectorPresented`) and asserts that something which reads it is notified: `withObservationTracking` through the same code path the view uses (the `AppViewModel` computed forwarder or the `ContentView` binding getter), and, for at least the sheets, a mounted-view check using the KRMA-972 helpers.
- [ ] `testLowFrequencyChildrenForwardSynchronouslyWithoutTask` keeps its settings, library and clipboard assertions and drops the derive, look-save and removable-media ones, with the expected counts adjusted accordingly.
- [ ] Derive, Look-save and media-volume tests pass unchanged apart from forwarding assertions. Manually confirmed in the app (launch with `swift run`): open the Derive sheet and the Look-save sheet and dismiss each; plug or simulate a removable volume list refresh if feasible (otherwise state that this was covered by tests only).
- [ ] `AppViewModel.swift` is not longer than before.
- [ ] KRMA-907 is untouched (it is a done prerequisite, not superseded).

## Verification

```
swift build
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
```

## Risks

- The classic failure is a sheet that never presents because its `isPresented` binding reads through a non-tracked path. The per-coordinator tracking test above is the guard; do not skip it.
- `LibraryMediaWorkflowCoordinator` has many properties and `@Observable` tracks per property, so a view that reads `removableMediaFiles` no longer refreshes when only `isRemovableMediaScanning` changes. That is the intent, but check the selector view still reads every property it displays inside its `body`.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
