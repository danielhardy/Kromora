---
id: KRMA-382
title: Decompose AppViewModel into feature-specific application coordinators
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Define and document explicit ownership boundaries
      result: pass
      notes: Added docs/APP_ARCHITECTURE.md covering source/library, editor document/history, preview/comparison, analysis/masking, export/Looks, and lifecycle/shutdown.
    - criterion: Extract highest-churn workflows into independently testable collaborators
      result: pass
      notes: Added EditorDocumentCoordinator, PhotosImportDestination injection, and ComparisonFramePolicy value boundary.
    - criterion: AppViewModel remains the composition root without duplicate state stores
      result: pass
      notes: AppViewModel owns and wires collaborators; Photos import progress and editor session/history state have one collaborator owner, with compatibility projections only.
    - criterion: Published UI state has one clear owner
      result: pass
      notes: Active EditDocument remains AppViewModel-owned; editor clipboard/history and Photos import progress are coordinator-owned.
    - criterion: Rendering keeps RenderRequest/RenderEngine and revision fences
      result: pass
      notes: Existing preview/render routing and source/document/display fences are unchanged.
    - criterion: Persistence, export, comparison, undo/redo, and navigation semantics remain unchanged
      result: pass
      notes: Existing fast and serial lanes pass.
    - criterion: Boundary tests exercise collaborators without full AppViewModel construction
      result: pass
      notes: Added EditorDocumentCoordinator session/history/clipboard tests and ComparisonFramePolicy tests.
    - criterion: Remove obsolete extension-only organization
      result: pass
      notes: Moved editor session/history/clipboard and Photos progress orchestration out of AppViewModel; retained façade methods for existing callers.
    - criterion: Run required verification
      result: pass
      notes: fast 922/922, serial 366/366, release build, dg validate, and git diff --check passed.
  checks_run:
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - swift build -c release
    - dg validate
    - git diff --check
  findings:
    - dg validate reports only pre-existing unknown-model warnings for gpt-5.6-luna/gpt-5.6-terra.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-12T18:21:44.246Z
  session: 01MTYP904GP4PVCVOQ
labels:
  - architecture
  - maintainability
  - testing
created: 2026-09-12T15:24:48.516Z
updated: 2026-09-12T18:21:44.248Z
order: zwh
board: product
---

## Objective

Reduce AppViewModel's responsibility while retaining it as the application composition root and a small façade for the main window.

## Context

AppViewModel is approximately 5,000 lines and currently combines published presentation state with source loading, Photos and removable-media imports, library deletion/navigation, edit/history mutation, preview scheduling, comparison state, histogram/capability work, export request construction, Look dialogs, persistence routing, lifecycle observers, and shutdown.

The existing coordinator extraction is a good foundation, but AppViewModel extensions are still the same type and do not create independent boundaries.

Relevant code:
- Sources/KromoraKit/ViewModels/AppViewModel.swift
- Sources/KromoraKit/ViewModels/AppViewModel+Develop.swift
- Sources/KromoraKit/ViewModels/AppViewModel+Adjust.swift
- Sources/KromoraKit/ViewModels/AppViewModel+Color.swift
- Sources/KromoraKit/ViewModels/AppViewModel+Light.swift
- Sources/KromoraKit/ViewModels/AppViewModel+Effects.swift
- Sources/KromoraKit/ViewModels/AppViewModel+Masking.swift

## Acceptance criteria

- [ ] Define and document explicit ownership boundaries for source/library, editor document/history, preview/comparison, analysis/masking, export/Looks, and lifecycle/shutdown.
- [ ] Extract at least the highest-churn workflows into independently testable collaborators with narrow protocols/value contracts.
- [ ] AppViewModel remains the composition root and does not become a second service locator or duplicate state store.
- [ ] Published UI state has one clear owner; collaborators do not mutate the same state through hidden backchannels.
- [ ] Rendering continues to use the existing RenderRequest/RenderEngine funnel and source/document/revision fences.
- [ ] Persistence, export, comparison, undo/redo, and navigation semantics remain unchanged.
- [ ] Update or add boundary tests proving collaborators can be exercised with fakes without constructing the full application model.
- [ ] Remove obsolete extension-only organization where a real collaborator now owns the behavior.
- [ ] Run the relevant fast/serial test lanes, dg validate, and git diff --check.

## Out of scope

- Rewriting the render pipeline.
- Changing product behavior or public ContentView/AppViewModel initialization APIs.
- Splitting code only to reduce file length without creating an ownership boundary.

## Agent log

- 2026-09-12T18:21:44.246Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Define and document explicit ownership boundaries (pass) — Added docs/APP_ARCHITECTURE.md covering source/library, editor document/history, preview/comparison, analysis/masking, export/Looks, and lifecycle/shutdown.
- [x] Extract highest-churn workflows into independently testable collaborators (pass) — Added EditorDocumentCoordinator, PhotosImportDestination injection, and ComparisonFramePolicy value boundary.
- [x] AppViewModel remains the composition root without duplicate state stores (pass) — AppViewModel owns and wires collaborators; Photos import progress and editor session/history state have one collaborator owner, with compatibility projections only.
- [x] Published UI state has one clear owner (pass) — Active EditDocument remains AppViewModel-owned; editor clipboard/history and Photos import progress are coordinator-owned.
- [x] Rendering keeps RenderRequest/RenderEngine and revision fences (pass) — Existing preview/render routing and source/document/display fences are unchanged.
- [x] Persistence, export, comparison, undo/redo, and navigation semantics remain unchanged (pass) — Existing fast and serial lanes pass.
- [x] Boundary tests exercise collaborators without full AppViewModel construction (pass) — Added EditorDocumentCoordinator session/history/clipboard tests and ComparisonFramePolicy tests.
- [x] Remove obsolete extension-only organization (pass) — Moved editor session/history/clipboard and Photos progress orchestration out of AppViewModel; retained façade methods for existing callers.
- [x] Run required verification (pass) — fast 922/922, serial 366/366, release build, dg validate, and git diff --check passed.
Checks run:
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- swift build -c release
- dg validate
- git diff --check
Findings:
- dg validate reports only pre-existing unknown-model warnings for gpt-5.6-luna/gpt-5.6-terra.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTYP904GP4PVCVOQ
Summary: Implemented feature-specific ownership boundaries. AppViewModel remains the composition root and published active-document owner; EditorDocumentCoordinator now owns per-photo sessions, history, revisions, and clipboard; PhotosImportCoordinator is root-owned and uses PhotosImportDestination with coordinator-owned progress; ComparisonFramePolicy isolates baseline rules; documented source/library, editor, preview/comparison, analysis/masking, export/Looks, and lifecycle/shutdown ownership. Added boundary tests for editor sessions/history/clipboard and comparison semantics while preserving RenderRequest fences, persistence, export, navigation, and import behavior.
