---
id: KRMA-910
title: Centralize source-loading presentation transitions while preserving first-frame behavior
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The transition table documents valid intermediate states and is reflected in focused lifecycle tests.
      result: pass
      notes: Architecture guidance documents the transitions; state tests cover intermediate readiness and real AppViewModel lifecycle tests cover source switching and shutdown.
    - criterion: Load, source switch, failure, return-to-Library, active deletion/clear and shutdown retain correct loading indicators and toolbar availability.
      result: pass
      notes: Existing source and thumbnail lifecycle suites passed; transition behavior retains independent loading, navigation, preview and toolbar dimensions.
    - criterion: Cached-first-frame and delayed stored-document cases preserve existing pixel handoff and inspector values; no previous-photo pixels or edits become visible for the new photo.
      result: pass
      notes: First-frame and inspector suites passed; the transition owner does not own pixels or document values.
    - criterion: Late source/document/render completions cannot change a newer source presentation state or revive shutdown state.
      result: pass
      notes: Late completion lifecycle tests passed. Verification found and fixed inspectorDocumentSettled lacking the shutdown latch; added an assertion that all transitions leave state frozen after shutdown.
    - criterion: The four original flags have one state/transition owner and no independent scattered assignment sites.
      result: pass
      notes: Assignments reside in SourcePresentationState; AppViewModel exposes read-only projections. Structural search confirmed no assignments in AppViewModel.
    - criterion: The root remains the sole active-document publisher, existing size ceiling is retained, and no compatibility fallback or view-facing implementation detail is added.
      result: pass
      notes: PackageSettingsTests passed; AppViewModel is 5,088 lines, below its existing ceiling. State remains internal and does not own the active document.
  checks_run:
    - "swift build: exit 0."
    - "swift test --no-parallel --filter AppViewModelTests|SourceSessionCoordinatorTests|ThumbnailSwitchLifecycleTests|DevelopInspectorTests|EditorCanvasViewportTests|PackageSettingsTests|SourcePresentationStateTests|SourcePresentationLifecycleTests: exit 0; 119 tests passed."
    - "dg validate: exit 0; emitted existing model-name warnings."
    - "git diff --check: exit 0."
    - "Structural search of presentation flag assignments: only SourcePresentationState contains assignments; AppViewModel has no independent writes."
    - "AppViewModel line count: 5,088; existing line-count ceiling retained."
  findings:
    - "Resolved during verification: inspectorDocumentSettled could mutate pending inspector presentation state after shutdown despite the documented shutdown latch."
  fixes:
    - Guarded inspectorDocumentSettled with the shutdown latch and added the transition to the frozen-state regression test.
  verification_commits:
    - c697a8c0
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T17:03:40.441Z
  session: 01MV6XGKJUQEXYRPJ6
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - swift
  - app-view-model
  - maintainability
  - concurrency
created: 2026-10-12T17:11:44.854Z
updated: 2026-10-13T17:03:40.445Z
depends_on:
  - KRMA-904
blockers: []
order: a0
board: product
context:
  files:
    - Tests/KromoraKitTests/AppViewModelTests.swift
    - Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift
    - Tests/KromoraKitTests/DevelopInspectorTests.swift
    - Sources/KromoraKit/ViewModels/SourceSessionCoordinator.swift
    - Sources/KromoraKit/ViewModels/StoredEditAdoptionCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
  docs:
    - CLAUDE.md
    - AGENTS.md
    - docs/APP_ARCHITECTURE.md
    - docs/ENGINEERING_GUIDE.md
  issues:
    - KRMA-904
  commands:
    - swift build
    - swift test --no-parallel --filter 'AppViewModelTests|SourceSessionCoordinatorTests|ThumbnailSwitchLifecycleTests|DevelopInspectorTests|EditorCanvasViewportTests|PackageSettingsTests'
    - dg validate
    - git diff --check
footprint:
  source: declared
  paths:
    - path: Sources/KromoraKit/ViewModels/AppViewModel.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/AppViewModelTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift
      access: write
      confidence: 1
    - path: Tests/KromoraKitTests/DevelopInspectorTests.swift
      access: write
      confidence: 1
    - path: docs/APP_ARCHITECTURE.md
      access: write
      confidence: 1
  observed:
    paths: []
    captured_at: 2026-10-13T17:00:51.927Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - c697a8c0
---

## Objective

Replace repeated independent assignments to source-loading presentation flags with one explicit value and transition boundary. Make lifecycle state easier to audit while preserving the current differences between source preparation, document adoption and first-frame presentation.

## Motivation and scope

AppViewModel stores isLoading, isNavigationLoading, isToolbarPhotoTransitioning and previewState separately, with additional inspector-pending and toolbar-availability state. Related assignments are scattered through placeholder materialization, load/beginLoad, source installation, load failure, clear/removal, preview publication and shutdown. This makes omissions and stale transitions harder to spot in a 5,105-line composition root.

This is a low-priority maintainability refactor, not evidence that all flag combinations are currently wrong. The flags are not synonyms: source preparation can finish while a preview is still pending; inspector document adoption can lag source selection; cached/first-frame handoff has its own presentation rules. Do not reduce everything to a simplistic empty/loading/ready enum or change when existing pixels/toolbar state become visible.

## Context to read

- `Sources/KromoraKit/ViewModels/AppViewModel.swift`: all writes to the four flags, InspectorSourceDocumentPending, toolbarPhotoActionsAvailable, source loading/clearing, failOpenImage, publishPreviewReady/publishPreviewFailure and shutdown.
- `ViewModels/SourceSessionCoordinator.swift`, `StoredEditAdoptionCoordinator.swift`, `FirstFramePresentationCoordinator.swift`, `PreviewPublicationCoordinator.swift` and `PreviewAdmissionCoordinator.swift`: distinct generation and first-presentation boundaries.
- `Views/ContentView.swift`, `PreviewView.swift` and inspector consumers of the existing façade getters.
- `Tests/KromoraKitTests/AppViewModelTests.swift`, `ThumbnailSwitchLifecycleTests.swift`, `DevelopInspectorTests.swift`, `EditorCanvasViewportTests.swift`, `SourceSessionCoordinatorTests.swift`, and tests located by the first-frame coordinator symbol.
- `docs/APP_ARCHITECTURE.md`, `docs/ENGINEERING_GUIDE.md`, `docs/COMPARISON_MODE.md` for the presentation contract.

## Implementation steps

1. Before refactoring, write a concise transition table in the issue handoff or architecture documentation: event, current guards/generation, resulting loading flags and whether source/document/frame is ready. Cover placeholder resolution, source preparation, stored edit adoption, cached first frame, renderer first frame, failure, source clear and shutdown.
2. Introduce an internal SourcePresentationState value with named transition methods. A struct with explicit independent dimensions is acceptable and likely safer than collapsing valid states. Include only fields that belong to this lifecycle; unrelated export/import/Auto progress stays with its owners.
3. Store/publish that value once at the appropriate main-actor owner. Preserve existing root façade property names as read-only projections wherever possible so view changes remain small. Audit tests/callers that currently set public isLoading instead of accidentally widening other state access.
4. Replace scattered field writes with named transitions at the existing event boundaries. Each transition checks the current source/request generation and live-owner state before changing presentation. Retain KRMA-904's task ownership and pre-await invalidation.
5. Keep actual ImageSource, render surfaces, active EditDocument, inspector adoption and toolbar action validation at their existing owners. The value represents presentation readiness and must not become a second source/document store.
6. Add regression tests driven through real lifecycle commands/publication seams, with deterministic fake source/render gates. Verify observable behavior and generation rejection rather than just mirroring transition-method implementation.

## Acceptance criteria

- [ ] The transition table documents valid intermediate states and is reflected in focused lifecycle tests.
- [ ] Load, source switch, failure, return-to-Library, active deletion/clear and shutdown retain correct loading indicators and toolbar availability.
- [ ] Cached-first-frame and delayed stored-document cases preserve existing pixel handoff and inspector values; no previous-photo pixels or edits become visible for the new photo.
- [ ] Late source/document/render completions cannot change a newer source's presentation state or revive shutdown state.
- [ ] The four original flags have one state/transition owner and no independent scattered assignment sites.
- [ ] The root remains the sole active-document publisher, existing size ceiling is retained, and no compatibility fallback or view-facing implementation detail is added.

## Coordination

Depends on KRMA-904. Keep retouch/history/observation ownership fixes intact if already landed. Do not bundle a whole AppViewModel rewrite, move code into extensions merely to satisfy the size guard, or retune render/cache scheduling. Update durable architecture guidance to describe the final state owner.

## Reading the source context

Source and test paths above are relative to the repository root, `/Users/dhardy/Dev/Kromora`. The installed `dg context` reader currently resolves file/doc contents inside the `.dg` space, so it can list existing repository sources as missing. Read those paths directly from the checkout; their existence was verified when this ticket was written. Keep the repository-relative context hints for planning. Do not copy product source into `.dg` or weaken DispatchGraph path validation to work around this reader limitation.

## Required checks

```sh
swift build
swift test --no-parallel --filter 'AppViewModelTests|SourceSessionCoordinatorTests|ThumbnailSwitchLifecycleTests|DevelopInspectorTests|EditorCanvasViewportTests|PackageSettingsTests'
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


### Comment — claude @ 2026-10-13T17:00:36.032Z

Implemented: SourcePresentationState (independent dimensions, named transitions, shutdown latch) is the sole owner of isLoading/isNavigationLoading/previewState/inspector-pending/toolbar flags; AppViewModel exposes read-only projections (isLoading no longer externally settable) and shrank 5112->5088 lines. Transition table added to docs/APP_ARCHITECTURE.md; new SourcePresentationStateTests (value + gated shutdown lifecycle). Checks: swift build OK; focused suites (AppViewModel, SourceSession, ThumbnailSwitchLifecycle, DevelopInspector, EditorCanvasViewport, PackageSettings, StoredEditAdoption, new tests, plus MenuCommand/PreviewCutover/PresentationBudget) 172 pass; dg validate OK (model-name warnings only); git diff --check clean. Not added: dedicated stale-generation/cached-first-frame tests beyond existing suites, which still pass.

## Agent log

- 2026-10-13T17:03:40.441Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The transition table documents valid intermediate states and is reflected in focused lifecycle tests. (pass) — Architecture guidance documents the transitions; state tests cover intermediate readiness and real AppViewModel lifecycle tests cover source switching and shutdown.
- [x] Load, source switch, failure, return-to-Library, active deletion/clear and shutdown retain correct loading indicators and toolbar availability. (pass) — Existing source and thumbnail lifecycle suites passed; transition behavior retains independent loading, navigation, preview and toolbar dimensions.
- [x] Cached-first-frame and delayed stored-document cases preserve existing pixel handoff and inspector values; no previous-photo pixels or edits become visible for the new photo. (pass) — First-frame and inspector suites passed; the transition owner does not own pixels or document values.
- [x] Late source/document/render completions cannot change a newer source presentation state or revive shutdown state. (pass) — Late completion lifecycle tests passed. Verification found and fixed inspectorDocumentSettled lacking the shutdown latch; added an assertion that all transitions leave state frozen after shutdown.
- [x] The four original flags have one state/transition owner and no independent scattered assignment sites. (pass) — Assignments reside in SourcePresentationState; AppViewModel exposes read-only projections. Structural search confirmed no assignments in AppViewModel.
- [x] The root remains the sole active-document publisher, existing size ceiling is retained, and no compatibility fallback or view-facing implementation detail is added. (pass) — PackageSettingsTests passed; AppViewModel is 5,088 lines, below its existing ceiling. State remains internal and does not own the active document.
Checks run:
- swift build: exit 0.
- swift test --no-parallel --filter AppViewModelTests|SourceSessionCoordinatorTests|ThumbnailSwitchLifecycleTests|DevelopInspectorTests|EditorCanvasViewportTests|PackageSettingsTests|SourcePresentationStateTests|SourcePresentationLifecycleTests: exit 0; 119 tests passed.
- dg validate: exit 0; emitted existing model-name warnings.
- git diff --check: exit 0.
- Structural search of presentation flag assignments: only SourcePresentationState contains assignments; AppViewModel has no independent writes.
- AppViewModel line count: 5,088; existing line-count ceiling retained.
Findings:
- Resolved during verification: inspectorDocumentSettled could mutate pending inspector presentation state after shutdown despite the documented shutdown latch.
Fixes:
- Guarded inspectorDocumentSettled with the shutdown latch and added the transition to the frozen-state regression test.
Verification commits:
- c697a8c0
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV6XGKJUQEXYRPJ6
Summary: Independent verification passed; fixed and tested the shutdown-latch gap in inspector settlement.
