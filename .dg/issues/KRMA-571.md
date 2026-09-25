---
id: KRMA-571
title: "Masking: show a thumbnail of each mask in the Masks list"
type: feature
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - masking
  - ui-ux
created: 2026-09-25T00:33:22.559Z
updated: 2026-09-25T00:33:23.208Z
depends_on:
  - KRMA-563
blockers: []
order: zv
board: product
---

## Objective

Make masks recognisable at a glance rather than by name: show a tiny black-and-white silhouette of each mask's effective coverage in its Masks-list row (and optionally for parts of multi-part masks).

## Acceptance criteria

- Each mask row shows a small thumbnail of its effective coverage over the cropped frame, updated after edits settle (not per pointer sample).
- Thumbnails are generated off the main actor through the existing mask overlay render path at a tiny target size, cached per mask definition, and never block the preview or overlay renders.
- Presentation-only: no document, history, or export changes; disabled masks read as disabled.
- Tests cover thumbnail invalidation on mask edits and no work for unchanged masks; performance checked on a many-mask document; reviewed in the running app.

## Context

- Builds on KRMA-563 (masking workspace rework): Sources/KromoraKit/Views/MaskingWorkspace.swift (MaskingWorkspace, MaskLayerRow, MaskPartRow, MaskCanvasOverlay), Sources/KromoraKit/Models/MaskInteractionState.swift, Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift.
- Overlay presentation is display-only and must never enter EditDocument, history, a render request, or export (docs/ENGINEERING_GUIDE.md, Persistence and masks).
- Swift 6 language mode with zero opt-outs; macOS 14 deployment target; no third-party dependencies (CLAUDE.md).
- Overlay images come from RenderEngine.makeMaskOverlayImage via MaskingWorkflowCoordinator.renderMaskOverlay (grayscale inspection already produces a silhouette).
