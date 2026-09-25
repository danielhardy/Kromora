---
id: KRMA-567
title: "Masking: select a mask by clicking its pin on the photo"
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
created: 2026-09-25T00:33:18.547Z
updated: 2026-09-25T00:33:19.167Z
depends_on:
  - KRMA-563
blockers: []
order: y
board: product
---

## Objective

Let a photographer choose "the sky" by pointing at the sky instead of reading the Masks list. Show a small pin on the canvas for each mask and select the mask by clicking its pin, as Lightroom does. This is an interaction change and needs product sign-off on pin placement and visibility before implementation.

## Acceptance criteria

- Each mask shows one pin at a stable, meaningful location (for example the gradient center, radial center, brush centroid, or smart-mask coverage centroid), transformed correctly through crop, zoom, and pan.
- Clicking a pin selects that mask (same effect as clicking its row); the selected mask's pin is visually distinct. Pins never intercept painting or gradient-handle drags.
- Pins can be hidden (for example follow the overlay toggle, or appear only on hover of the canvas); agreed behavior is documented.
- Pins are presentation-only: no document, history, or render-request changes.
- VoiceOver can reach and activate pins or an equivalent; tests cover pin placement math and selection; reviewed in the running app.

## Context

- Builds on KRMA-563 (masking workspace rework): Sources/KromoraKit/Views/MaskingWorkspace.swift (MaskingWorkspace, MaskLayerRow, MaskPartRow, MaskCanvasOverlay), Sources/KromoraKit/Models/MaskInteractionState.swift, Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift.
- Overlay presentation is display-only and must never enter EditDocument, history, a render request, or export (docs/ENGINEERING_GUIDE.md, Persistence and masks).
- Swift 6 language mode with zero opt-outs; macOS 14 deployment target; no third-party dependencies (CLAUDE.md).
- Canvas geometry goes through `CanvasMaskTransform`; pointer input through `MaskPointerSurface` (hit testing only when a drawing tool is active).
