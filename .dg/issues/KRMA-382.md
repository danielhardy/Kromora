---
id: KRMA-382
title: Decompose AppViewModel into feature-specific application coordinators
type: task
status: backlog
priority: high
labels:
  - architecture
  - maintainability
  - testing
created: 2026-09-12T15:24:48.516Z
updated: 2026-09-12T15:24:49.180Z
order: zz
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
