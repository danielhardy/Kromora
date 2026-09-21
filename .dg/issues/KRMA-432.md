---
id: KRMA-432
title: Extract source-session and preview orchestration from AppViewModel
type: task
status: done
priority: high
agent: codex
model: gpt-5.6-luna
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Source-session boundary
      result: pass
      notes: SourceSessionCoordinator owns preparation, stored reconciliation, metadata/capability probes, first-frame lifetime, source generations, cancellation, and shutdown.
    - criterion: Preview-presentation boundary
      result: pass
      notes: PreviewPresentationCoordinator owns planners, display/comparison generations, cache identity, async lookup, canonical writes, and lifecycle cancellation; PreviewCoordinator remains render admission owner.
    - criterion: RenderRequest/RenderEngine funnel and fences
      result: pass
      notes: Existing latest-wins publication guards are preserved and all focused/CI suites pass.
    - criterion: Active document and compatibility façade
      result: pass
      notes: AppViewModel remains the sole published active EditDocument owner; no second store or root back-reference was added.
    - criterion: Fake-constructible collaborators
      result: pass
      notes: Injected renderer/store/provider/cache seams are tested without AppViewModel, preferences, NSWorkspace, or GPU setup.
    - criterion: Workflow and race coverage
      result: pass
      notes: Added direct source/presentation boundary tests; existing first-frame, preview, comparison, cache, prefetch, thumbnail, and navigation suites remain green.
    - criterion: Ownership documentation and root reduction
      result: pass
      notes: Updated APP_ARCHITECTURE.md and removed obsolete source worker/probe/first-frame/planner/cache-task state, reducing AppViewModel by about 400 tracked lines.
    - criterion: Required verification
      result: pass
      notes: Release build, fast 1029/1029, serial 378/378, dg validate, and git diff --check passed.
  checks_run:
    - swift test --filter SourceSessionCoordinatorTests|EmbeddedFirstFrameTests|PreviewCoordinatorTests
    - swift build -c release
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - dg validate
    - git diff --check
  findings:
    - dg validate emits only existing unknown-model warnings for recorded GPT-5.6 model labels.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-14T10:37:59.419Z
  session: 01MU12D56K5N9O8UXE
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - architecture
  - maintainability
  - performance
  - preview
created: 2026-09-14T03:07:28.871Z
updated: 2026-09-21T02:09:44.690Z
depends_on:
  - KRMA-430
order: w
board: product
---

## Objective

Continue KRMA-382 by removing source-session and preview orchestration from the `AppViewModel` type while keeping the root as a small composition façade and the published active-document owner.

## Context

KRMA-382 extracted editor-document state, Photos import progress, and comparison policy, but the root still owns source preparation, stored-edit reconciliation, first-frame lifetime, capability/metadata tasks, adjacent prefetch, preview-cache lookup/building, preview request planning, display revisions, comparison presentation, and histogram scheduling. These responsibilities are high churn and share cancellation/revision rules that should be owned by independently testable collaborators.

Relevant code:

- `Sources/KromoraKit/ViewModels/AppViewModel.swift`
- `Sources/KromoraKit/ViewModels/PreviewCoordinator.swift`
- `Sources/KromoraKit/ViewModels/PreviewDiskCache.swift`
- `Sources/KromoraKit/ViewModels/SourceImportPlan.swift`
- `Sources/KromoraKit/ViewModels/ComparisonFramePolicy.swift`
- `Sources/KromoraKit/Models/ResolutionPlanner.swift`
- `docs/APP_ARCHITECTURE.md`
- `docs/REPOSITORY_IMPROVEMENT_PLAN.md`

## Acceptance criteria

- [ ] Define a source-session boundary that owns preparation, stored-document reconciliation, source/capability/metadata work, first-frame handling, cancellation, and source-generation fencing.
- [ ] Define a preview-presentation boundary that owns request planning, interactive/settled admission, disk-cache lookup/building, adjacent prefetch, comparison scheduling, and display-revision fencing.
- [ ] Keep Core Image/Metal objects inside existing render owners; collaborators exchange value-only requests, publications, and errors.
- [ ] Preserve the RenderRequest/RenderEngine funnel and latest-wins source/document/display revision semantics.
- [ ] Keep the published active `EditDocument` and user-facing compatibility methods at the root; do not create a second document store or hidden broad reference to `AppViewModel`.
- [ ] Make source and preview collaborators constructible with fakes without creating the full AppViewModel, real preferences, NSWorkspace, or GPU setup.
- [ ] Add boundary, cancellation, stale-completion, cache-hit, comparison, first-frame, adjacent-prefetch, and navigation-during-load tests.
- [ ] Remove obsolete extension-only organization where the new collaborators own behavior; document the resulting ownership table.
- [ ] Demonstrate a meaningful reduction in root-owned mutable state and responsibility, not merely moving methods into another extension.
- [ ] Run focused tests, `swift build -c release`, `scripts/ci-tests.sh fast`, `scripts/ci-tests.sh serial`, `dg validate`, and `git diff --check`.

## Constraints

Do not rewrite the renderer, change image-quality behavior, or weaken source/document/display fences. Preserve public AppViewModel initialization and façade APIs while migrating callers incrementally.

## Agent log

- 2026-09-14T10:37:59.419Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Source-session boundary (pass) — SourceSessionCoordinator owns preparation, stored reconciliation, metadata/capability probes, first-frame lifetime, source generations, cancellation, and shutdown.
- [x] Preview-presentation boundary (pass) — PreviewPresentationCoordinator owns planners, display/comparison generations, cache identity, async lookup, canonical writes, and lifecycle cancellation; PreviewCoordinator remains render admission owner.
- [x] RenderRequest/RenderEngine funnel and fences (pass) — Existing latest-wins publication guards are preserved and all focused/CI suites pass.
- [x] Active document and compatibility façade (pass) — AppViewModel remains the sole published active EditDocument owner; no second store or root back-reference was added.
- [x] Fake-constructible collaborators (pass) — Injected renderer/store/provider/cache seams are tested without AppViewModel, preferences, NSWorkspace, or GPU setup.
- [x] Workflow and race coverage (pass) — Added direct source/presentation boundary tests; existing first-frame, preview, comparison, cache, prefetch, thumbnail, and navigation suites remain green.
- [x] Ownership documentation and root reduction (pass) — Updated APP_ARCHITECTURE.md and removed obsolete source worker/probe/first-frame/planner/cache-task state, reducing AppViewModel by about 400 tracked lines.
- [x] Required verification (pass) — Release build, fast 1029/1029, serial 378/378, dg validate, and git diff --check passed.
Checks run:
- swift test --filter SourceSessionCoordinatorTests|EmbeddedFirstFrameTests|PreviewCoordinatorTests
- swift build -c release
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- dg validate
- git diff --check
Findings:
- dg validate emits only existing unknown-model warnings for recorded GPT-5.6 model labels.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MU12D56K5N9O8UXE
Summary: Extracted source-session and preview-presentation orchestration into independently testable coordinators while preserving AppViewModel document and façade APIs.
