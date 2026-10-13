---
id: KRMA-976
title: "Observation step 5: Convert clipboard and editor-document coordinators; delete forwarding loop (builds on KRMA-909)"
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
created: 2026-10-13T19:36:56.488Z
updated: 2026-10-13T19:36:57.430Z
depends_on:
  - KRMA-975
  - KRMA-909
blockers: []
order: zzzzy
board: product
---

## Objective

Convert `EditClipboardCoordinator` and `EditorDocumentCoordinator` to `@Observable`, convert the two *callback-based* root invalidators (`EditHistoryCoordinator`, `VirtualCopyMetadataCoordinator`) the same way, then delete the whole `objectWillChange` forwarding loop and every `objectWillChange.send()` in `AppViewModel`. Supersedes KRMA-909.

## Context

**Relationship to KRMA-909:** it must be done first (added to `depends_on`). It leaves the two `willChange` callback sites documented as intentional remaining root notifications; removing them is the part of this ticket that Phase 1 does not do.

Part of `docs/APP_VIEWMODEL_OBSERVATION_PLAN.md` (read it, "Additions from ticket review" and "Common rules"). Depends on KRMA-975. Read `.dg/issues/KRMA-909.md` first; it is the prior art and the required prerequisite.

After steps 3-4 the loop (`AppViewModel.swift` ~L1393-1417, comment included) forwards only `editorDocument` and `editClipboardWorkflow`.

**Four things to convert, not two.** Step 9 cannot make `AppViewModel` `@Observable` while any of these still call `objectWillChange.send()`:

1. `EditClipboardCoordinator` (`ViewModels/EditClipboardCoordinator.swift:32`): `@Published private(set) clipboard`, `clipboardCategories`, `@Published isSelectiveCopyDialogPresented`, `selectiveCopyCategories`. Root forwarders: `editClipboard` (L193), `canPasteEdits` (L199), `isSelectiveCopyDialogPresented`/`selectiveCopyCategories` get/set (L641-646). Readers: `MenuCommands.swift` (four `AppViewModel` holders at L226, 237, 280, 292), `OnboardingViews.swift`, `ContentView.swift` (selective-copy dialog). Re-run `grep -rn "canPasteEdits\|editClipboard\|selectiveCopy\|isSelectiveCopy" Sources/KromoraKit/Views`.
2. `EditorDocumentCoordinator` (`ViewModels/EditorDocumentCoordinator.swift:15`): **has no `@Published` property**, so its forwarding entry never fired. `canUndo`/`canRedo`/`undoDepth` (root L3873-3875) refresh today only because `document` publishes next to them. Converting it makes `activeHistory` genuinely tracked; mark `sessions`, `sessionRevisions`, `nextRevision` `@ObservationIgnored` unless a view reads them (none do: `session(for:)` is used inside `AppViewModel`).
3. `EditHistoryCoordinator` (`ViewModels/EditHistoryCoordinator.swift`): not an `ObservableObject`. `history`, `currentRevision`, `isCreatingVirtualCopy` use `willSet { willChange() }`, and the root constructs it at `AppViewModel.swift` ~L384-399 with `willChange: { [weak self] in self?.objectWillChange.send() }`. Root forwarders: `durableEditHistory` (L188), `durableCurrentEditRevision` (L189). Convert to `@Observable`, delete the `willChange` closure parameter and the three `willSet`s. Note it is a `private lazy var` on the root.
4. `VirtualCopyMetadataCoordinator` (`ViewModels/VirtualCopyMetadataCoordinator.swift`, `willChange` stored at L21, init at L27, called at L89 before `presentation` changes): same treatment; constructed at `AppViewModel.swift` ~L348-351 (`private lazy var virtualCopyMetadata`). Reader: `InfoInspectorView.swift:276` via `viewModel.virtualCopySourceDescription`.

Tests: `ObservationInvalidationTests.testLowFrequencyChildrenForwardSynchronouslyWithoutTask` (L32) and `testNoTaskPerChildNotificationRemains` (L17). The former asserts the loop and goes away or is rewritten; the latter only asserts that four children exist and must keep passing. Check tests for `EditHistoryCoordinator`/`VirtualCopyMetadataCoordinator` construction with a `willChange:` argument (`grep -rn "willChange" Tests`) and update initialisers. `EditorDocumentCoordinator` appears in two test files.

## Approach

1. Convert the four classes to `@MainActor @Observable final class` (the two callback ones are already `@MainActor`: confirm).
2. Remove `willChange` plumbing from `EditHistoryCoordinator` and `VirtualCopyMetadataCoordinator`, their initialisers, and the two construction sites in `AppViewModel`.
3. Delete the forwarding loop, its comment, and the `cancellables.append(child.sink ...)` body. Keep `cancellables` only if the `$maskOverlayAppearance` sink was somehow retained (it should be gone after step 4); if `cancellables` is now unused delete it and its `removeAll()` at ~L4439, but leave `import Combine` for step 9 unless nothing else needs it.
4. Views: `MenuCommands` holders keep reading `viewModel.canPasteEdits` and friends. Those computed properties read an `@Observable` child, which is tracked transitively. Do not add new wrappers.
5. Rewrite `testLowFrequencyChildrenForwardSynchronouslyWithoutTask` as direct observation: `withObservationTracking { _ = viewModel.canPasteEdits } onChange: { fired = true }` then mutate the clipboard, and the same for `canUndo`, `durableEditHistory`, and `virtualCopySourceDescription`.

## Acceptance criteria

- [ ] All four types are `@MainActor @Observable`; none uses `ObservableObject`, `@Published`, `willSet { willChange() }` or a `willChange` closure.
- [ ] `grep -rn "objectWillChange" Sources` is empty (structural test added to `ObservationInvalidationTests`), and the forwarding loop plus its comment are gone from `AppViewModel.swift`.
- [ ] Observation tests (fast lane, no UI) show that each of `canPasteEdits`, `isSelectiveCopyDialogPresented`, `canUndo`, `durableEditHistory` and `virtualCopySourceDescription` fires `withObservationTracking` when the underlying state changes.
- [ ] Mounted-view check with KRMA-972 helpers for the menu commands: changing clipboard state re-evaluates the paste menu holder, not StatusBar or inspector mirrors.
- [ ] `testNoTaskPerChildNotificationRemains` still passes unchanged; `testLowFrequencyChildren...` is deleted or replaced as in Approach 5.
- [ ] Undo/redo, copy/paste edits, edit-history restore and virtual-copy creation tests pass unchanged apart from `willChange:` initialiser arguments.
- [ ] `AppViewModel.swift` is shorter than before (loop, comment and two closures removed). KRMA-909 is untouched (a done prerequisite, not superseded).

## Verification

```
swift build
scripts/ci-tests.sh fast
scripts/ci-tests.sh serial
```

## Risks

The two callback coordinators were hidden: nothing in the plan's greps found them. Re-run `grep -rn "willChange\|objectWillChange\|objectWillChange.send" Sources` before starting and again before finishing; if a further site appears, add it here and to the plan doc.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
