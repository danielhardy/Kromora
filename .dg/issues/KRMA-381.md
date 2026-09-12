---
id: KRMA-381
title: Move view-owned feature state and async models into ViewModels
type: task
status: backlog
priority: medium
labels:
  - architecture
  - ui
  - testing
created: 2026-09-12T15:24:47.343Z
updated: 2026-09-12T15:24:47.937Z
order: zy
board: product
---

## Objective

Make Views primarily declarative by relocating feature-level state, asynchronous work, and domain presentation policy out of files under Views.

## Context

AnalysisDebugPanelModel and MaskingPanelModel are ObservableObject implementations embedded in View files. They launch task groups, call PhotoAnalysisCoordinator, apply MaskPresentationPolicy, invert masks with MaskOperations, manage errors, and coordinate apply callbacks.

LookInspectorView also persists collapsed-folder state directly through UserDefaults instead of using an injected preference owner.

Relevant code:
- Sources/KromoraKit/Views/AnalysisDebugPanel.swift:6-138
- Sources/KromoraKit/Views/MaskingPanel.swift:9-219
- Sources/KromoraKit/Views/LookInspectorView.swift:81-88 and 544-573

## Acceptance criteria

- [ ] AnalysisDebugPanelModel and MaskingPanelModel move to ViewModels or an explicitly named presentation-model module.
- [ ] Their async loading, cancellation, error mapping, selection, inversion, and apply orchestration are covered by focused tests independent of SwiftUI body construction.
- [ ] Views receive observable value state and send intents; they do not own PhotoAnalysisCoordinator task groups.
- [ ] Look folder-collapse persistence is accessed through an injected settings/preferences boundary rather than UserDefaults.standard in the View.
- [ ] MaskPresentationPolicy and MaskOperations remain shared domain/application services, with no duplicated policy in the Views.
- [ ] Preserve existing cancellation behavior when panels disappear or collapse.
- [ ] Existing analysis, masking, Look, and UI-facing tests remain passing; run dg validate and git diff --check.

## Out of scope

- Changing mask-generation algorithms or provider selection.
- Redesigning the masking workspace interaction model.
- Removing legitimate SwiftUI @State used only for transient visual state.
