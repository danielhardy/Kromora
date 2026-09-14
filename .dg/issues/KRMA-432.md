---
id: KRMA-432
title: Extract source-session and preview orchestration from AppViewModel
type: task
status: ready
priority: high
agent: codex
model: gpt-5.6-luna
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
updated: 2026-09-14T03:54:23.734Z
depends_on:
  - KRMA-382
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
