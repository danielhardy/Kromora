---
id: KRMA-908
title: Observe Look-library and settings changes directly in their consuming views
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Library-only scan/import state changes and settings-only preferences produce zero root fan-in events while their UI consumers receive updates.
      result: pass
      notes: ObservationInvalidationTests observed 1 settings event and 2 library events with 0 root events. LookInspectorView observes the existing LUTLibrary directly; FilmstripView observes the existing settings object directly.
    - criterion: Look counts, categories, scan/import errors, disabled import controls and missing-reference state update correctly after rescans.
      result: pass
      notes: The inspector reads these library values directly. Rendered LookInspectorView tests cover scanning, unavailable folder, missing reference, empty and populated states at multiple widths; import/error and disabled-control state use the same observed library instance.
    - criterion: Same-ID changed Look bytes still trigger existing render/cache invalidation and selected-Look resolution behavior.
      result: pass
      notes: The missing-reference rescan and same-path changed-bytes AppViewModel regression tests both passed. The scan callback and targeted invalidation path remain intact.
    - criterion: showPhotoNames, view appearance and existing settings menu bindings refresh without root forwarding.
      result: pass
      notes: FilmstripView uses settings.showPhotoNames for its caption and height; PreviewView, grid cells and settings commands continue to use the same settings object. Settings, menu and rendered-view tests passed.
    - criterion: Child identities remain stable; no second settings/library instance or persisted schema change is introduced.
      result: pass
      notes: The views receive viewModel.library and viewModel.settings. Review found no new instances or persisted schema changes.
    - criterion: Existing LUT projection memoization and high-frequency observation tests pass with explicit revised expectations for these two removed subscriptions.
      result: pass
      notes: The focused filter passed all 69 tests, including LUT projection memoization, direct library/settings isolation, and the existing high-frequency observation checks.
  checks_run:
    - swift build — exit 0
    - swift test --no-parallel --filter ObservationInvalidationTests|LookInspectorViewTests|LUTWorkflowTests|KromoraSettingsTests|MenuCommandTests|PackageSettingsTests — 69 tests passed, exit 0
    - swift test --no-parallel --filter testACompletedScanReResolvesTheOpenDocumentAndReportsMissingLUTsOnce|testAScanThatReplacesAReferencedLookReleasesOnlyThatLook — 2 tests passed, exit 0
    - dg validate — exit 0; existing model-name warnings only
    - git diff --check — exit 2 due to pre-existing trailing whitespace in .dg/issues/KRMA-914.md; git diff --check 98ea9fe9^ 98ea9fe9 — clean, exit 0
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T01:42:44.083Z
  session: 01MV7FZJ4HHKODEDC4
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - app-view-model
  - maintainability
  - observation
created: 2026-10-12T17:11:43.446Z
updated: 2026-10-14T01:42:44.086Z
depends_on:
  - KRMA-907
blockers: []
order: zx
board: product
context:
  files:
    - Sources/KromoraKit/Views/LookInspectorView.swift
    - Sources/KromoraKit/Views/ContentView.swift
    - Sources/KromoraKit/Views/FilmstripView.swift
    - Tests/KromoraKitTests/ObservationInvalidationTests.swift
    - Tests/KromoraKitTests/LookInspectorViewTests.swift
    - Sources/KromoraKit/Models/LUTLibrary.swift
    - Sources/KromoraKit/Models/KromoraSettings.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - AGENTS.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-907
    - KRMA-909
    - KRMA-898
  commands:
    - swift build
    - swift test --no-parallel --filter 'ObservationInvalidationTests|LookInspectorViewTests|LUTWorkflowTests|KromoraSettingsTests|MenuCommandTests|PackageSettingsTests'
    - dg validate
    - git diff --check
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Views/LookInspectorView.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Views/ContentView.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Views/FilmstripView.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/ObservationInvalidationTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/LookInspectorViewTests.swift
      access: write
      confidence: 1
    - path: docs/APP_ARCHITECTURE.md
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-14T01:26:48.333Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Remove library/settings child-only notifications from AppViewModel's root fan-in after giving all affected view surfaces direct observation. Keep Look rescans, preference changes and selected-Look resolution visibly correct.

## Evidence and scope

AppViewModel forwards library.objectWillChange and settings.objectWillChange around lines 1381-1382 because some views read them indirectly. LookInspectorView uses viewModel.library throughout empty-state resolution, category filtering, counts, scan/import errors and button state. ContentView reads settings.showPhotoNames for filmstrip layout. Other surfaces already observe KromoraSettings directly, including PreviewView and filmstrip/grid cells; audit rather than duplicating these observations. The root still owns selected Look/document decisions and legitimate preview/persistence effects.

This is a low-priority narrowing of observation dependencies. Existing ObservationInvalidationTests verify required forwarding and passing throughput budgets; the review did not measure a regression caused specifically by these two children. Record before/after event or body-evaluation counts so the implementation demonstrates the intended isolation. Apple's relevant model guidance is https://developer.apple.com/documentation/SwiftUI/Managing-model-data-in-your-app.

## Context to read

- `Sources/KromoraKit/Views/LookInspectorView.swift`: every library read and filtered/memoized projection.
- `Views/ContentView.swift`, `PreviewView.swift`, `FilmstripView.swift`, `LibraryGridView.swift`, `MenuCommands.swift` and settings/preference views.
- `Sources/KromoraKit/ViewModels/AppViewModel.swift`: selectedLook/resolvedLUT, Look callbacks, applyLookLibraryDelta, settings sinks and fan-in comment.
- `Models/LUTLibrary.swift`, `Models/KromoraSettings.swift`, `ViewModels/LookSelectionCoordinator.swift`.
- `Presentation/KromoraScene.swift` and `KromoraAppDelegate.swift`: stable child identity and existing settings wiring.
- `Tests/KromoraKitTests/ObservationInvalidationTests.swift`, `LookInspectorViewTests.swift`, `LUTWorkflowTests.swift`, `KromoraSettingsTests.swift`, `MenuCommandTests.swift`.

## Implementation steps

1. Inventory actual view dependencies on library/settings, including indirect root computed properties, aliases and callbacks. Keep imperative actions and process observers intact; these are not SwiftUI observation subscriptions.
2. Observe LUTLibrary directly in the Look browser subtree and KromoraSettings directly in the smallest views that render its preferences. Update initializers to receive the existing objects. Avoid observing both children in the top-level ContentView solely to trigger broad body updates again.
3. Preserve library revision/memoization behavior and selected-Look resolution. A rescan replacing bytes under the same LUTID must still refresh both browser state and any necessary rendered/document-derived state through the existing Look-delta callbacks.
4. Migrate remaining settings-derived layout reads such as showPhotoNames to a directly observing subtree. Keep preview, appearance controller, menu bindings and persistence preferences using the same settings instance.
5. Remove only library and settings from root fan-in after the inventory is complete. Keep required functional subscriptions that update masks, rendering or package state; removing fan-in does not mean deleting behavior sinks.
6. Update the existing forwarding test and add direct-observer/isolation assertions. Use child-only scan/settings mutations to distinguish avoidable fan-in from intentional root status/document changes.

## Acceptance criteria

- [ ] Library-only scan/import state changes and settings-only preferences produce zero root fan-in events while their UI consumers receive updates.
- [ ] Look counts, categories, scan/import errors, disabled import controls and missing-reference state update correctly after rescans.
- [ ] Same-ID changed Look bytes still trigger existing render/cache invalidation and selected-Look resolution behavior.
- [ ] showPhotoNames, view appearance and existing settings menu bindings refresh without root forwarding.
- [ ] Child identities remain stable; no second settings/library instance or persisted schema change is introduced.
- [ ] Existing LUT projection memoization and high-frequency observation tests pass with explicit revised expectations for these two removed subscriptions.

## Coordination and non-goals

Depends on KRMA-907 only to serialize shared fan-in/test edits and make each remaining boundary easy to verify. KRMA-909 handles the final two editor/clipboard children. KRMA-898 independently fixes Look byte I/O and persistence ordering; this ticket changes observation only and must preserve that work. A project-wide Observation macro migration is unnecessary for this scope.

## Reading the source context

Source and test paths above are relative to the repository root, `/Users/dhardy/Dev/Kromora`. The installed `dg context` reader currently resolves file/doc contents inside the `.dg` space, so it can list existing repository sources as missing. Read those paths directly from the checkout; their existence was verified when this ticket was written. Keep the repository-relative context hints for planning. Do not copy product source into `.dg` or weaken DispatchGraph path validation to work around this reader limitation.

## Required checks

```sh
swift build
swift test --no-parallel --filter 'ObservationInvalidationTests|LookInspectorViewTests|LUTWorkflowTests|KromoraSettingsTests|MenuCommandTests|PackageSettingsTests'
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


### Comment — claude @ 2026-10-14T01:26:45.352Z

LookInspectorView now observes LUTLibrary directly; FilmstripView owns its settings-driven height; library and settings removed from root fan-in. Test added (child events 1/2, root 0 vs. previously forwarded). swift build + focused filter pass (68 tests); dg validate shows only pre-existing model warnings; git diff --check clean for changed paths (pre-existing trailing whitespace in .dg/issues/KRMA-914.md).

## Agent log

- 2026-10-14T01:42:44.083Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Library-only scan/import state changes and settings-only preferences produce zero root fan-in events while their UI consumers receive updates. (pass) — ObservationInvalidationTests observed 1 settings event and 2 library events with 0 root events. LookInspectorView observes the existing LUTLibrary directly; FilmstripView observes the existing settings object directly.
- [x] Look counts, categories, scan/import errors, disabled import controls and missing-reference state update correctly after rescans. (pass) — The inspector reads these library values directly. Rendered LookInspectorView tests cover scanning, unavailable folder, missing reference, empty and populated states at multiple widths; import/error and disabled-control state use the same observed library instance.
- [x] Same-ID changed Look bytes still trigger existing render/cache invalidation and selected-Look resolution behavior. (pass) — The missing-reference rescan and same-path changed-bytes AppViewModel regression tests both passed. The scan callback and targeted invalidation path remain intact.
- [x] showPhotoNames, view appearance and existing settings menu bindings refresh without root forwarding. (pass) — FilmstripView uses settings.showPhotoNames for its caption and height; PreviewView, grid cells and settings commands continue to use the same settings object. Settings, menu and rendered-view tests passed.
- [x] Child identities remain stable; no second settings/library instance or persisted schema change is introduced. (pass) — The views receive viewModel.library and viewModel.settings. Review found no new instances or persisted schema changes.
- [x] Existing LUT projection memoization and high-frequency observation tests pass with explicit revised expectations for these two removed subscriptions. (pass) — The focused filter passed all 69 tests, including LUT projection memoization, direct library/settings isolation, and the existing high-frequency observation checks.
Checks run:
- swift build — exit 0
- swift test --no-parallel --filter ObservationInvalidationTests|LookInspectorViewTests|LUTWorkflowTests|KromoraSettingsTests|MenuCommandTests|PackageSettingsTests — 69 tests passed, exit 0
- swift test --no-parallel --filter testACompletedScanReResolvesTheOpenDocumentAndReportsMissingLUTsOnce|testAScanThatReplacesAReferencedLookReleasesOnlyThatLook — 2 tests passed, exit 0
- dg validate — exit 0; existing model-name warnings only
- git diff --check — exit 2 due to pre-existing trailing whitespace in .dg/issues/KRMA-914.md; git diff --check 98ea9fe9^ 98ea9fe9 — clean, exit 0
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7FZJ4HHKODEDC4
Summary: Independent verification passed: implementation and focused regression checks are sound.
