---
id: KRMA-976
title: "Observation step 5: Convert clipboard and editor-document coordinators; delete forwarding loop (builds on KRMA-909)"
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: All four coordinators are @MainActor @Observable and use no ObservableObject, @Published, willSet willChange, or willChange closure plumbing.
      result: pass
      notes: Structural source scans confirmed the four coordinators contain no Combine or willChange plumbing.
    - criterion: The objectWillChange forwarding loop and every objectWillChange reference in Sources are gone.
      result: pass
      notes: The final source scan found no objectWillChange or willChange matches in Sources; the loop and comment are absent.
    - criterion: Observation tests cover canPasteEdits, isSelectiveCopyDialogPresented, canUndo, durableEditHistory, and virtualCopySourceDescription.
      result: pass
      notes: Fast tracking tests exercise all five computed projections through their observable coordinators.
    - criterion: A mounted menu holder refreshes paste availability on clipboard mutation without re-evaluating StatusBar or inspector mirrors.
      result: pass
      notes: The mounted focused-scene test observed canPaste transition false to true with zero root notifications and unchanged StatusBar and InfoInspector body counts.
    - criterion: testNoTaskPerChildNotificationRemains passes and the old low-frequency forwarding test is replaced with direct observation checks.
      result: pass
      notes: The structural child-presence test passed unchanged; direct observation tests cover the low-frequency projections.
    - criterion: Undo/redo, copy/paste, edit-history restore, and virtual-copy behavior remain covered and pass.
      result: pass
      notes: The complete fast lane passed, including existing coordinator, clipboard, stored history, and virtual-copy regression suites.
    - criterion: AppViewModel is shorter than before and KRMA-909 remains untouched.
      result: pass
      notes: Current AppViewModel is 5036 lines versus 5044 at HEAD; KRMA-909 has no working-tree diff.
  checks_run:
    - swift build — exit 0, no diagnostics
    - scripts/ci-tests.sh fast — exit 0; 1,891 tests
    - scripts/ci-tests.sh serial — exit 0; required serial lane passed
    - swift test --no-parallel --filter ObservationInvalidationTests|FocusedSceneValueTests — exit 0; 24 tests
    - dg validate — exit 0; pre-existing model-name warnings only
    - git diff --check — exit 0
    - Structural source scans for objectWillChange/willChange and coordinator Combine plumbing — no matches
  findings: []
  fixes:
    - Removed the unused cancellables collection and teardown after the final Combine sink was removed.
    - Added direct fast-lane observation checks for paste, durable-history, and virtual-copy projections, plus a mounted focused-menu refresh test.
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T04:08:07.896Z
  session: 01MV7KMWMU3ATK1HR9
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - swiftui
created: 2026-10-13T19:36:56.488Z
updated: 2026-10-14T04:08:07.900Z
depends_on:
  - KRMA-975
  - KRMA-909
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-14T03:49:38.081Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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

### Comment — claude @ 2026-10-14T03:49:37.579Z

Converted EditClipboard/EditorDocument/EditHistory/VirtualCopyMetadata/LibraryOpen coordinators to @Observable; removed willChange plumbing and every objectWillChange send in Sources (root portableLibrary/virtualCopyMetadata now @Published). Views use @Bindable. Tests rewritten with withObservationTracking plus a structural grep test. fast and serial lanes pass. Not done: mounted-view KRMA-972 menu-holder check. Uncommitted, alongside pre-existing working-tree edits.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-14T04:08:07.896Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] All four coordinators are @MainActor @Observable and use no ObservableObject, @Published, willSet willChange, or willChange closure plumbing. (pass) — Structural source scans confirmed the four coordinators contain no Combine or willChange plumbing.
- [x] The objectWillChange forwarding loop and every objectWillChange reference in Sources are gone. (pass) — The final source scan found no objectWillChange or willChange matches in Sources; the loop and comment are absent.
- [x] Observation tests cover canPasteEdits, isSelectiveCopyDialogPresented, canUndo, durableEditHistory, and virtualCopySourceDescription. (pass) — Fast tracking tests exercise all five computed projections through their observable coordinators.
- [x] A mounted menu holder refreshes paste availability on clipboard mutation without re-evaluating StatusBar or inspector mirrors. (pass) — The mounted focused-scene test observed canPaste transition false to true with zero root notifications and unchanged StatusBar and InfoInspector body counts.
- [x] testNoTaskPerChildNotificationRemains passes and the old low-frequency forwarding test is replaced with direct observation checks. (pass) — The structural child-presence test passed unchanged; direct observation tests cover the low-frequency projections.
- [x] Undo/redo, copy/paste, edit-history restore, and virtual-copy behavior remain covered and pass. (pass) — The complete fast lane passed, including existing coordinator, clipboard, stored history, and virtual-copy regression suites.
- [x] AppViewModel is shorter than before and KRMA-909 remains untouched. (pass) — Current AppViewModel is 5036 lines versus 5044 at HEAD; KRMA-909 has no working-tree diff.
Checks run:
- swift build — exit 0, no diagnostics
- scripts/ci-tests.sh fast — exit 0; 1,891 tests
- scripts/ci-tests.sh serial — exit 0; required serial lane passed
- swift test --no-parallel --filter ObservationInvalidationTests|FocusedSceneValueTests — exit 0; 24 tests
- dg validate — exit 0; pre-existing model-name warnings only
- git diff --check — exit 0
- Structural source scans for objectWillChange/willChange and coordinator Combine plumbing — no matches
Findings:
- None
Fixes:
- Removed the unused cancellables collection and teardown after the final Combine sink was removed.
- Added direct fast-lane observation checks for paste, durable-history, and virtual-copy projections, plus a mounted focused-menu refresh test.
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7KMWMU3ATK1HR9
Summary: Verification passed; all declared lanes and direct observation checks are green.
