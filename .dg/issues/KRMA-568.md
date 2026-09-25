---
id: KRMA-568
title: "Masking: offer intent-based starting points when a mask is created"
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - masking
  - ui-ux
created: 2026-09-25T00:33:19.544Z
updated: 2026-09-25T03:55:21.833Z
depends_on:
  - KRMA-563
blockers: []
order: zl
board: product
---

## Objective

Photographers usually know what they want ("brighten the subject", "darken the sky") before they know the slider values. When a mask is created, offer a few one-click starting points that set sensible local adjustments, which the photographer then fine-tunes.

## Acceptance criteria

- After creating a mask, a small, dismissible set of starting points is offered (for example Brighten, Darken, Warm, Cool, Add detail, Soften); choosing one sets the mask's local adjustments to documented values in one undoable step.
- Starting points only set `LocalAdjustments` on the new mask; they never alter the mask shape, other masks, or global adjustments.
- Choosing nothing leaves the mask neutral; the offer does not reappear for that mask.
- Values are defined in one value type with tests (range-valid for every LocalAdjustmentControl, one undo entry, correct layer scope); reviewed in the running app.

## Context

- Builds on KRMA-563 (masking workspace rework): Sources/KromoraKit/Views/MaskingWorkspace.swift (MaskingWorkspace, MaskLayerRow, MaskPartRow, MaskCanvasOverlay), Sources/KromoraKit/Models/MaskInteractionState.swift, Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift.
- Overlay presentation is display-only and must never enter EditDocument, history, a render request, or export (docs/ENGINEERING_GUIDE.md, Persistence and masks).
- Swift 6 language mode with zero opt-outs; macOS 14 deployment target; no third-party dependencies (CLAUDE.md).
- Local controls, ranges and neutrals: Sources/KromoraKit/Models/LocalAdjustmentControl.swift; bindings via AppViewModel.localAdjustmentBinding.
