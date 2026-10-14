---
id: KRMA-909
title: Isolate clipboard presentation updates and remove dormant editor notification forwarding
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Clipboard-only payload, category, and dialog changes avoid root fan-in while presentation and paste availability observe the existing clipboard coordinator directly.
      result: pass
      notes: Clipboard isolation observed two child events and zero root events. SelectiveCopySheetModifier and KeyboardSurface directly observe the same coordinator owned by AppViewModel.
    - criterion: Copy, selective copy, single and batch paste, remembered categories, and cancellation preserve behavior.
      result: pass
      notes: EditClipboardCoordinatorTests (5) and EditClipboardTests (7) passed, covering category memory, cancellation, active and batch paste, and per-photo history.
    - criterion: Undo and redo availability and gesture grouping update across document and history transitions.
      result: pass
      notes: Existing edit, reset, source-switch, and per-photo history coverage passed. The history-only group-close test confirms root publication when a changed gesture group makes canUndo available.
    - criterion: The dormant editor notification subscription is removed without an unused observation wrapper.
      result: pass
      notes: EditorDocumentCoordinator no longer conforms to ObservableObject, and AppViewModel has no child notification forwarding loop. The coordinator remains value-state only.
    - criterion: The former seven-child fan-in is removed while legitimate root document and status updates remain observable.
      result: pass
      notes: The final forwarding loop is removed. AppViewModel remains the active EditDocument publisher, with workflow sinks and callbacks intact.
    - criterion: Per-photo history, revisions, persistence, and rendering retain one document owner without a broad framework migration.
      result: pass
      notes: AppViewModel remains the published document owner and EditorDocumentCoordinator owns per-photo value history and revisions; the targeted regression suite passed.
  checks_run:
    - swift build — exit 0
    - swift test --no-parallel --filter ObservationInvalidationTests|EditClipboardCoordinatorTests|EditClipboardTests|AppViewModelTests|MenuCommandTests|PackageSettingsTests — 97 tests passed, exit 0
    - swift test --no-parallel --filter ObservationInvalidationTests — 16 tests passed after the verification comment fix, exit 0
    - dg validate — exit 0; existing model-name warnings only
    - git diff --check — exit 2 on pre-existing trailing whitespace in unrelated .dg/issues/KRMA-914.md; both KRMA-909 commit diffs passed git diff --check
    - git diff --check -- Tests/KromoraKitTests/ObservationInvalidationTests.swift — exit 0
  findings: []
  fixes:
    - Updated the stale observation-boundary comment in ObservationInvalidationTests.swift; committed as ce8910d3.
  verification_commits:
    - ce8910d3
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-14T01:55:22.283Z
  session: 01MV7GG185L6WB6HCM
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - app-view-model
  - maintainability
  - observation
created: 2026-10-12T17:11:44.129Z
updated: 2026-10-14T01:55:22.286Z
depends_on:
  - KRMA-908
blockers: []
order: zz
board: product
context:
  files:
    - Sources/KromoraKit/ViewModels/EditorDocumentCoordinator.swift
    - Sources/KromoraKit/Views/ContentView.swift
    - Sources/KromoraKit/Views/OnboardingViews.swift
    - Tests/KromoraKitTests/ObservationInvalidationTests.swift
    - Tests/KromoraKitTests/EditClipboardCoordinatorTests.swift
    - Sources/KromoraKit/ViewModels/EditClipboardCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - AGENTS.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-908
    - KRMA-521
    - KRMA-529
    - KRMA-907
    - KRMA-903
  commands:
    - swift build
    - swift test --no-parallel --filter 'ObservationInvalidationTests|EditClipboardCoordinatorTests|EditClipboardTests|AppViewModelTests|MenuCommandTests|PackageSettingsTests'
    - dg validate
    - git diff --check
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/ViewModels/EditorDocumentCoordinator.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Views/ContentView.swift
      access: write
      confidence: 1
    - path: Sources/KromoraKit/Views/OnboardingViews.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/ObservationInvalidationTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/EditClipboardCoordinatorTests.swift
      access: write
      confidence: 1
    - path: docs/APP_ARCHITECTURE.md
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-14T01:44:34.415Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - ce8910d3
---

## Objective

Finish the remaining root child-notification cleanup by observing clipboard state in its actual consumers and explicitly documenting how undo/redo availability updates. Preserve AppViewModel as the single active EditDocument publisher and EditorDocumentCoordinator as its value-state companion.

## Evidence and important distinction

The AppViewModel forwarding loop includes editClipboardWorkflow and editorDocument (approximately 1384-1385). Clipboard has @Published payload/category/dialog properties, and ContentView binds the selective-copy sheet through root projections. Its local changes therefore cause broad root notifications.

EditorDocumentCoordinator currently conforms to ObservableObject but has no @Published properties or explicit objectWillChange.send calls. Its activeHistory/session values are ordinary stored properties. The review's forwarding inventory therefore does not prove that this child currently emits redundant events. Treat its subscription as potentially dormant: adding @ObservedObject in a view alone would not make its mutations observable. Verify existing document-publication ordering and undo/redo availability before removing the unused subscription/conformance or introducing a narrowly justified history-availability value.

This low-priority ticket is an observation/maintainability follow-up, not a measured editor performance regression. KRMA-521 and KRMA-529 provide historical ownership context. Keep the existing document mutation/persistence/render pipeline.

## Context to read

- `Sources/KromoraKit/ViewModels/EditClipboardCoordinator.swift`: clipboard, selective dialog, destination routing and publication.
- `ViewModels/EditorDocumentCoordinator.swift`: activeHistory, grouping, undo/redo and per-photo revisions.
- `ViewModels/AppViewModel.swift`: clipboard projections, copy/paste actions, canUndo/canRedo/undoDepth, updateDocument/history adoption and forwarding loop.
- `Views/ContentView.swift`: selective-copy sheet and undo controls; `Views/OnboardingViews.swift`: undo availability.
- `Views/KeyboardShortcuts.swift` and `MenuCommands.swift`: command validation and imperative state reads.
- `Tests/KromoraKitTests/EditClipboardCoordinatorTests.swift`, `EditClipboardTests.swift`, `ObservationInvalidationTests.swift`, `AppViewModelTests.swift`, `MenuCommandTests.swift`.
- `docs/APP_ARCHITECTURE.md` and `docs/ENGINEERING_GUIDE.md`: sole document owner and copy/paste boundaries.

## Implementation steps

1. Inventory clipboard UI consumers and give their smallest presentation/menu containers the existing clipboard instance as a direct observation dependency. Bind the selective-copy dialog/categories there while routing copy/paste effects through current root/coordinator commands.
2. Remove clipboard from root fan-in only after payload/category/dialog and paste-availability consumers update independently. Imperative keyboard guards may continue to read root façade projections when executed.
3. Trace every history availability transition: document commit, gesture end, undo, redo, stored-document adoption, photo switch, reset and session removal. Identify which root document/source publications currently refresh UI availability and add a behavior test for transitions that change history without a document change.
4. Remove the dormant editor forwarding subscription if the inventory confirms no event dependency. Keep EditorDocumentCoordinator a value-state owner; remove its unused ObservableObject conformance/import if no consumer needs it. If a genuine history-only UI update is missing, publish a narrow availability snapshot at the appropriate owner rather than broadcasting all session internals or duplicating EditDocument.
5. After KRMA-907 and KRMA-908, remove the fan-in loop/comment only when all seven entries are accounted for. Preserve functional sinks and callbacks elsewhere, including settings behavior and workflow status/document effects.
6. Update tests that currently assert clipboard root forwarding and architecture notes. Tests must verify both isolated child events and live UI state; zero root events alone does not prove correctness.

## Acceptance criteria

- [ ] Clipboard-only payload/category/dialog changes do not publish through the root and still refresh selective-copy presentation and paste availability.
- [ ] Copy, selective copy, single/batch paste, remembered categories and cancellation retain existing behavior.
- [ ] Undo/redo availability and grouping update correctly across document edits, photo changes, restore/reset and history-only transitions.
- [ ] The dormant editor subscription is removed or justified by a documented actual event dependency; no unused observation wrapper is added.
- [ ] Once prerequisites are present, the old seven-child fan-in is fully removed while legitimate root document/status changes remain observable.
- [ ] Per-photo history, revisions, persistence and rendering still share one active document owner; no broad framework migration is introduced.

## Coordination

Depends on KRMA-908, which depends on KRMA-907. This orders the shared forwarding/test cleanup. Keep KRMA-903's durable-history task owner separate from this in-memory editor-history presentation work.

## Reading the source context

Source and test paths above are relative to the repository root, `/Users/dhardy/Dev/Kromora`. The installed `dg context` reader currently resolves file/doc contents inside the `.dg` space, so it can list existing repository sources as missing. Read those paths directly from the checkout; their existence was verified when this ticket was written. Keep the repository-relative context hints for planning. Do not copy product source into `.dg` or weaken DispatchGraph path validation to work around this reader limitation.

## Required checks

```sh
swift build
swift test --no-parallel --filter 'ObservationInvalidationTests|EditClipboardCoordinatorTests|EditClipboardTests|AppViewModelTests|MenuCommandTests|PackageSettingsTests'
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


### Comment — claude @ 2026-10-14T01:44:30.953Z

Clipboard now observed directly by SelectiveCopySheetModifier and KeyboardSurface; root fan-in loop removed; EditorDocumentCoordinator no longer ObservableObject (it had no publishers); endUndoGrouping publishes explicitly. Tests added (clipboard child 2 events/root 0; group close publishes). swift build and focused filter (122 tests) pass; dg validate only pre-existing model warnings.

## Agent log

- 2026-10-14T01:55:22.283Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Clipboard-only payload, category, and dialog changes avoid root fan-in while presentation and paste availability observe the existing clipboard coordinator directly. (pass) — Clipboard isolation observed two child events and zero root events. SelectiveCopySheetModifier and KeyboardSurface directly observe the same coordinator owned by AppViewModel.
- [x] Copy, selective copy, single and batch paste, remembered categories, and cancellation preserve behavior. (pass) — EditClipboardCoordinatorTests (5) and EditClipboardTests (7) passed, covering category memory, cancellation, active and batch paste, and per-photo history.
- [x] Undo and redo availability and gesture grouping update across document and history transitions. (pass) — Existing edit, reset, source-switch, and per-photo history coverage passed. The history-only group-close test confirms root publication when a changed gesture group makes canUndo available.
- [x] The dormant editor notification subscription is removed without an unused observation wrapper. (pass) — EditorDocumentCoordinator no longer conforms to ObservableObject, and AppViewModel has no child notification forwarding loop. The coordinator remains value-state only.
- [x] The former seven-child fan-in is removed while legitimate root document and status updates remain observable. (pass) — The final forwarding loop is removed. AppViewModel remains the active EditDocument publisher, with workflow sinks and callbacks intact.
- [x] Per-photo history, revisions, persistence, and rendering retain one document owner without a broad framework migration. (pass) — AppViewModel remains the published document owner and EditorDocumentCoordinator owns per-photo value history and revisions; the targeted regression suite passed.
Checks run:
- swift build — exit 0
- swift test --no-parallel --filter ObservationInvalidationTests|EditClipboardCoordinatorTests|EditClipboardTests|AppViewModelTests|MenuCommandTests|PackageSettingsTests — 97 tests passed, exit 0
- swift test --no-parallel --filter ObservationInvalidationTests — 16 tests passed after the verification comment fix, exit 0
- dg validate — exit 0; existing model-name warnings only
- git diff --check — exit 2 on pre-existing trailing whitespace in unrelated .dg/issues/KRMA-914.md; both KRMA-909 commit diffs passed git diff --check
- git diff --check -- Tests/KromoraKitTests/ObservationInvalidationTests.swift — exit 0
Findings:
- None
Fixes:
- Updated the stale observation-boundary comment in ObservationInvalidationTests.swift; committed as ce8910d3.
Verification commits:
- ce8910d3
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV7GG185L6WB6HCM
Summary: Independent verification passed with focused checks green; corrected a stale test comment in ce8910d3.
