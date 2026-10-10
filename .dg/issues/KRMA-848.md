---
id: KRMA-848
title: Stop restarting mask overlay resolve on every adjustment slider tick
type: bug
status: backlog
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:24.529Z
updated: 2026-10-10T13:02:39.889Z
blockers: []
order: zv
board: product
---

## Objective

Dragging an adjustment slider (Exposure, etc.) while a mask was selected restarted the mask overlay resolve on every tick and flashed "Analyzing mask…" in the status bar, even though mask coverage had not changed.

## Root cause

`MaskCanvasOverlay.OverlayTaskID` (used as the `.task(id:)` key) contained the full `[LocalAdjustmentLayer]`, including each layer's `adjustments`. Any look change cancelled and restarted overlay resolution. Mask-resolution logs showed about 20 loading/cancelled pairs in 1.5 s during an exposure drag.

## Work done

In `Sources/KromoraKit/Views/MaskingWorkspace.swift` the task id now uses `layers.map(\.overlayIdentity)`, a private `LocalAdjustmentLayer` projection that neutralises `adjustments`, `name` and `autoProvenance`. Membership, components/geometry, inversion, amount, selection, size and style still invalidate the task. The overlay is rendered with `includeIdentity: true`, so adjustments never affect it.

## Acceptance criteria

- Dragging Exposure with a smart mask selected no longer produces loading/cancelled bursts or a flashing status-bar spinner.
- Editing mask geometry, soften/strength, inversion, amount or selection still refreshes the overlay.
- Masking panel and overlay tests pass.
