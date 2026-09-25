---
id: KRMA-570
title: "Masking: move the canvas tools into a floating strip on the photo"
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
created: 2026-09-25T00:33:21.552Z
updated: 2026-09-25T00:33:22.181Z
depends_on:
  - KRMA-563
blockers: []
order: zq
board: product
---

## Objective

Keep the photographer's eyes on the photo: move Brush, Erase, Linear, and Radial from the inspector into a small floating tool strip near the image (Pixelmator/Photos style), and retire "Select" as a visible tool since Esc already returns to it. The inspector then holds only masks and adjustments. This is an interaction change and needs product sign-off on placement before implementation.

## Acceptance criteria

- A floating strip appears over the canvas only while the Masking inspector is active, shows the four drawing tools with their shortcuts (B, E, L, R), highlights the active tool, and clicking the active tool again returns to no tool (same as Esc).
- Brush settings (size, feather, flow, strength) are reachable from the strip when Brush or Erase is active; Option-scroll and [ ] keep working.
- The strip never covers handles it cannot be moved away from; placement is agreed and documented, and it respects crop mode and comparison view.
- The inspector no longer shows the tool picker; the one-line tool guidance moves to the strip or a transient hint.
- VoiceOver and keyboard parity with today's tool picker; tests cover tool state transitions; reviewed in the running app.

## Context

- Builds on KRMA-563 (masking workspace rework): Sources/KromoraKit/Views/MaskingWorkspace.swift (MaskingWorkspace, MaskLayerRow, MaskPartRow, MaskCanvasOverlay), Sources/KromoraKit/Models/MaskInteractionState.swift, Sources/KromoraKit/ViewModels/MaskingWorkflowCoordinator.swift.
- Overlay presentation is display-only and must never enter EditDocument, history, a render request, or export (docs/ENGINEERING_GUIDE.md, Persistence and masks).
- Swift 6 language mode with zero opt-outs; macOS 14 deployment target; no third-party dependencies (CLAUDE.md).
- Tool state: `MaskInteractionState.Tool`; shortcuts in Sources/KromoraKit/Views/KeyboardShortcuts.swift; canvas host in Sources/KromoraKit/Views/PreviewView.swift.
