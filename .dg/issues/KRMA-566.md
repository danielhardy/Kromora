---
id: KRMA-566
title: "Masking: show a mask's overlay while hovering its row"
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
created: 2026-09-25T00:33:17.575Z
updated: 2026-09-25T00:33:18.171Z
depends_on:
  - KRMA-563
blockers: []
order: x
board: product
---

## Objective

Let a photographer answer "what does this mask cover?" by pointing at it. While the pointer is over a mask (or part) row in the Masks list, show that mask's overlay on the photo even when the overlay is turned off, the way Lightroom does. With that in place the overlay can default to off and the photo stays clean until asked.

## Acceptance criteria

- Hovering a mask row shows that mask's effective coverage using the Settings overlay appearance; hovering a part row shows that part alone. Leaving the row restores the previous overlay state within one frame, with no flicker between adjacent rows.
- Works when the overlay is off (temporary reveal) and when it is on (hovered mask takes precedence over the selected mask while hovered).
- Hover never changes selection, the document, undo history, or the preview render request.
- Decide and document whether the overlay now defaults to off (Settings > Masking can expose the default); O and the header eye keep working.
- Keyboard/VoiceOver: an equivalent way to preview a mask's coverage without a pointer (for example an accessibility action on the row).
- Tests cover hover state not touching the document/history and the overlay task choosing the hovered layer; reviewed in the running app.

## Context

- Builds on KRMA-563 (masking workspace rework): Sources/KromoraKit/Views/MaskingWorkspace.swift (MaskingWorkspace, MaskLayerRow, MaskPartRow, MaskCanvasOverlay), Sources/KromoraKit/Models/MaskInteractionState.swift, Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift.
- Overlay presentation is display-only and must never enter EditDocument, history, a render request, or export (docs/ENGINEERING_GUIDE.md, Persistence and masks).
- Swift 6 language mode with zero opt-outs; macOS 14 deployment target; no third-party dependencies (CLAUDE.md).
- The overlay task is keyed by `OverlayTaskID` in MaskCanvasOverlay; overlay renders are exempt from preview revision supersession (MaskingWorkflowCoordinator.renderMaskOverlay).
