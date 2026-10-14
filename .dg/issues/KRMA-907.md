---
id: KRMA-907
title: Observe derive, Look-save and removable-media state at their feature surfaces
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Child-only presentation/progress changes from each migrated child cause no root.objectWillChange event and still update their owning feature surface.
      result: pass
      notes: The direct observers are FeatureSheetsModifier, RemovableMediaMenu, and RemovableMediaSelectorView. ObservationInvalidationTests verifies each child publisher emits synchronously while root event count stays zero.
    - criterion: Derive and Look-save sheets open, close, cancel, and report results; removable-media menus, selector counts, scan/progress and cancellation remain live.
      result: pass
      notes: Presentation bindings and callbacks are preserved; feature views read the same coordinator instances directly. RecipeExtractorTests, PackageSourceImportCoordinatorTests, and MediaVolumeTests pass.
    - criterion: Both ContentView initializers inject the same existing instances and do not create duplicate coordinators.
      result: pass
      notes: Both initializers retain the supplied AppViewModel; FeatureSheetsModifier and RemovableMediaMenu reference its existing coordinators.
    - criterion: Existing keyboard sheet guards continue to read current state; legitimate root status/document notifications are preserved.
      result: pass
      notes: KeyboardCommandRouter still reads current derive/look-save state. Status/error callbacks and unrelated root forwarding entries remain intact.
    - criterion: ObservationInvalidationTests accurately distinguish migrated children from still-forwarded children; existing high-frequency isolation tests stay green.
      result: pass
      notes: The tests split migrated child publisher isolation from synchronous forwarding assertions for remaining children; all 14 ObservationInvalidationTests pass.
    - criterion: No blanket root @Observable conversion, detached notification task, changed workflow ownership or new dependencies.
      result: pass
      notes: Review of the implementation diff confirms only the three requested forwarding entries and their view consumers changed.
  checks_run:
    - swift build — exit 0
    - swift test --no-parallel --filter 'ObservationInvalidationTests|PackageSourceImportCoordinatorTests|MediaVolumeTests|RecipeExtractorTests|PackageSettingsTests' — 39 tests passed, 0 failures
    - dg validate — exit 0; existing model-name warnings only
    - git diff --check — clean
    - git diff --check 02e70997^ 02e70997 — clean
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T01:25:37.853Z
  session: 01MV7FEUAVHZJZNZAM
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - app-view-model
  - maintainability
  - observation
created: 2026-10-12T17:11:42.743Z
updated: 2026-10-14T01:25:37.857Z
blockers: []
order: zq
board: product
context:
  files:
    - Sources/KromoraKit/Views/ContentView.swift
    - Sources/KromoraKit/Views/RemovableMediaSelectorView.swift
    - Tests/KromoraKitTests/ObservationInvalidationTests.swift
    - Sources/KromoraKit/Views/RecipeExtractorSheet.swift
    - Sources/KromoraKit/Views/LookSaveSheet.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - AGENTS.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-521
    - KRMA-908
    - KRMA-909
    - KRMA-896
  commands:
    - swift build
    - swift test --no-parallel --filter 'ObservationInvalidationTests|PackageSourceImportCoordinatorTests|MediaVolumeTests|RecipeExtractorTests|PackageSettingsTests'
    - dg validate
    - git diff --check
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Views/ContentView.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Views/RemovableMediaSelectorView.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/ObservationInvalidationTests.swift
      access: write
      confidence: 1
    - path: docs/APP_ARCHITECTURE.md
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-14T01:15:54.240Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Complete direct observation for the derive sheet, Look-save sheet and removable-media workflow so their local state no longer invalidates unrelated root observers. Preserve every presentation, cancellation and menu update while removing only these three forwarding subscriptions.

## Evidence and priority

AppViewModel's forwarding loop around lines 1380-1393 merges seven ObservableObject child publishers into root.objectWillChange. The comment explicitly says forwarding remains until consumers observe children directly. ContentView binds derive.isSheetPresented and lookSave.isSheetPresented through the root, and uses root projections for the removable-media selector/menu. RemovableMediaSelectorView reads many root forwarding properties. These indirect dependencies currently require broad notification.

This is a low-priority performance/maintainability follow-up, not a measured UI regression or a claim that ObservableObject is unsupported. KRMA-521 already isolated high-frequency collection/import/export/canvas state. Preserve those improvements and the remaining child forwarding until its consumers are migrated. Apple describes dependency-scoped updates at https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app.

## Context to read

- `Sources/KromoraKit/ViewModels/AppViewModel.swift`: forwarding-loop rationale, derive/lookSave/media instances, removable-media façade and coordinator callbacks.
- `Sources/KromoraKit/Views/ContentView.swift`: both initializers, sheet bindings, import/menu toolbar sections.
- `Views/RemovableMediaSelectorView.swift`, `RecipeExtractorSheet.swift`, and `LookSaveSheet.swift` (locate by symbol if moved).
- `ViewModels/DeriveCoordinator.swift`, `LookSaveCoordinator.swift`, `LibraryMediaWorkflowCoordinator.swift`.
- `Views/KeyboardShortcuts.swift`: presentation guards and command routing.
- `Tests/KromoraKitTests/ObservationInvalidationTests.swift`: testLowFrequencyChildrenForwardSynchronouslyWithoutTask explicitly expects the old forwarding for these children; split/update those expectations intentionally.
- `PackageSourceImportCoordinatorTests`, `MediaVolumeTests`, `RecipeExtractorTests`, and `docs/APP_ARCHITECTURE.md`.

## Implementation steps

1. Inventory every consumer of the three child objects and their root projections, including presentation bindings, toolbar menus, errors/progress, cancel actions and selector contents. Distinguish UI observation from keyboard handlers that read state imperatively and do not need subscriptions.
2. Let focused feature containers observe the actual child instance using @ObservedObject while it remains ObservableObject. Keep stable ownership in AppViewModel. Prefer a small sheet/menu host over adding all child objects as broad observed properties to the entire ContentView.
3. Read/bind presentation and feature state directly in those containers. Route commands through existing façade methods when they coordinate other owners. Keep dismiss/cancel behavior, including Look-save cancellation, exactly as today.
4. Once all affected views have a direct dependency, remove only derive, lookSave and libraryMediaWorkflow from the root forwarding list. Preserve synchronous will-change timing for untouched entries; never replace forwarding with Task-based notifications.
5. Retain legitimate root status/error/document effects emitted by workflow callbacks. Isolate child-only changes in tests by detaching destination/status callbacks before asserting zero root events.
6. Add narrow observation/body-evaluation probes or existing performance-helper counters to prove the receiving surface updates and an unrelated inspector stays unaffected. Update architecture notes and the forwarding comment.

## Acceptance criteria

- [ ] Child-only presentation/progress changes from each migrated child cause no root.objectWillChange event and still update their owning feature surface.
- [ ] Derive and Look-save sheets open, close, cancel, and report results; removable-media menus, selector counts, scan/progress and cancellation remain live.
- [ ] Both ContentView initializers inject the same existing instances and do not create duplicate coordinators.
- [ ] Existing keyboard sheet guards continue to read current state; legitimate root status/document notifications are preserved.
- [ ] ObservationInvalidationTests accurately distinguish migrated children from still-forwarded children; existing high-frequency isolation tests stay green.
- [ ] No blanket root @Observable conversion, detached notification task, changed workflow ownership or new dependencies.

## Coordination

KRMA-908 handles library/settings and KRMA-909 handles editor/clipboard. They touch the same forwarding loop/test, so apply sequentially and retain earlier migrations. KRMA-896 remains the separate derive-cancellation correctness fix; this ticket must not silently change that task lifecycle.

## Reading the source context

Source and test paths above are relative to the repository root, `/Users/dhardy/Dev/Kromora`. The installed `dg context` reader currently resolves file/doc contents inside the `.dg` space, so it can list existing repository sources as missing. Read those paths directly from the checkout; their existence was verified when this ticket was written. Keep the repository-relative context hints for planning. Do not copy product source into `.dg` or weaken DispatchGraph path validation to work around this reader limitation.

## Required checks

```sh
swift build
swift test --no-parallel --filter 'ObservationInvalidationTests|PackageSourceImportCoordinatorTests|MediaVolumeTests|RecipeExtractorTests|PackageSettingsTests'
dg validate
git diff --check
```

Run any newly added collaborator suite as well. These are targeted regression checks; broaden them only when the changed boundary or new failures justify it.

## Repository constraints and implementation handoff

- Read `CLAUDE.md` and `.dg/AGENTS.md`, then claim this issue before code changes. Work on the current branch and preserve unrelated working-tree changes. Execute one issue at a time; dependency tickets must be implemented before dependent work.
- Target macOS 26+ on Apple Silicon, Swift 6, Apple frameworks only. No backwards-compatibility fallback, third-party dependency, @unchecked Sendable, nonisolated(unsafe), or @preconcurrency. Keep application implementation inside KromoraKit and retain AppViewModel's existing line-count ceiling.
- Use generated temporary fixtures and deterministic continuation/event gates. Put package/index/cache paths under test-owned temporary directories. Do not run display-bound release capture scripts or use arbitrary sleeps as proof of cancellation correctness.
- Run the focused checks below plus `dg validate` and `git diff --check`. Record commands, outcomes and any environmental limitation. Existing green tests do not replace new regression coverage for this issue.
- Commit coherent issue work with this issue ID followed by a colon in the subject. Follow the implementation handoff to `review`; do not mark done or bypass independent verification. Update architecture guidance only for the final ownership/behavior.


### Comment — claude @ 2026-10-14T01:15:51.006Z

Added FeatureSheetsModifier/RemovableMediaMenu observing derive, lookSave and libraryMediaWorkflow directly; removed those three from the root forwarding list; selector observes the media coordinator. Test split into forwarded vs migrated children. swift build and the focused test filter pass (39 tests); dg validate shows only pre-existing model warnings; git diff --check clean.

## Agent log

- 2026-10-14T01:25:37.853Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Child-only presentation/progress changes from each migrated child cause no root.objectWillChange event and still update their owning feature surface. (pass) — The direct observers are FeatureSheetsModifier, RemovableMediaMenu, and RemovableMediaSelectorView. ObservationInvalidationTests verifies each child publisher emits synchronously while root event count stays zero.
- [x] Derive and Look-save sheets open, close, cancel, and report results; removable-media menus, selector counts, scan/progress and cancellation remain live. (pass) — Presentation bindings and callbacks are preserved; feature views read the same coordinator instances directly. RecipeExtractorTests, PackageSourceImportCoordinatorTests, and MediaVolumeTests pass.
- [x] Both ContentView initializers inject the same existing instances and do not create duplicate coordinators. (pass) — Both initializers retain the supplied AppViewModel; FeatureSheetsModifier and RemovableMediaMenu reference its existing coordinators.
- [x] Existing keyboard sheet guards continue to read current state; legitimate root status/document notifications are preserved. (pass) — KeyboardCommandRouter still reads current derive/look-save state. Status/error callbacks and unrelated root forwarding entries remain intact.
- [x] ObservationInvalidationTests accurately distinguish migrated children from still-forwarded children; existing high-frequency isolation tests stay green. (pass) — The tests split migrated child publisher isolation from synchronous forwarding assertions for remaining children; all 14 ObservationInvalidationTests pass.
- [x] No blanket root @Observable conversion, detached notification task, changed workflow ownership or new dependencies. (pass) — Review of the implementation diff confirms only the three requested forwarding entries and their view consumers changed.
Checks run:
- swift build — exit 0
- swift test --no-parallel --filter 'ObservationInvalidationTests|PackageSourceImportCoordinatorTests|MediaVolumeTests|RecipeExtractorTests|PackageSettingsTests' — 39 tests passed, 0 failures
- dg validate — exit 0; existing model-name warnings only
- git diff --check — clean
- git diff --check 02e70997^ 02e70997 — clean
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7FEUAVHZJZNZAM
Summary: Independent verification passed: required build and focused checks are green; no defects or follow-up findings.
