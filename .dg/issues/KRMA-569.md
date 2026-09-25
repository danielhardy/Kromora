---
id: KRMA-569
title: "Masking: collapse unchanged adjustment groups and summarize changes"
type: feature
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - masking
  - ui-ux
created: 2026-09-25T00:33:20.547Z
updated: 2026-09-25T00:33:21.173Z
depends_on:
  - KRMA-563
blockers: []
order: zh
board: product
---

## Objective

Replace the wall of 13 local sliders with something scannable. Keep the Light, Color, and Effects groups collapsed unless they contain changes, and show what changed on each group header (for example "Light · Exposure −0.7"), so the photographer sees what a mask does at a glance.

## Acceptance criteria

- Each group (Light, Color, Effects, as in `LocalAdjustmentControl.inspectorGroups`) is a disclosure; a group with any non-neutral value starts expanded, others start collapsed, per selected mask. Manual expand/collapse is respected while that mask stays selected.
- Collapsed group headers summarize changed controls with the same readouts the rows use; a group reset is available from the header.
- Amount stays visible outside the groups.
- No change to how values are stored, rendered, or undone.
- Tests cover the expansion rule and the summary text; reviewed in the running app for consistency with the Edit inspectors (InspectorDisclosure).

## Context

- Builds on KRMA-563 (masking workspace rework): Sources/KromoraKit/Views/MaskingWorkspace.swift (MaskingWorkspace, MaskLayerRow, MaskPartRow, MaskCanvasOverlay), Sources/KromoraKit/Models/MaskInteractionState.swift, Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift.
- Overlay presentation is display-only and must never enter EditDocument, history, a render request, or export (docs/ENGINEERING_GUIDE.md, Persistence and masks).
- Swift 6 language mode with zero opt-outs; macOS 14 deployment target; no third-party dependencies (CLAUDE.md).
- Grouping lives in `LocalAdjustmentControl.inspectorGroups` (MaskingWorkspace.swift) with a coverage test in MaskingWorkspaceTests.
