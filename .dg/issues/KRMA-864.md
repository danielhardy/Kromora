---
id: KRMA-864
title: Crop mode toolbar renders as one tall orange pill instead of Save/Cancel/Undo
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
created: 2026-10-10T18:45:39.783Z
updated: 2026-10-10T18:45:40.163Z
blockers: []
order: zzzz
board: product
---

## Objective

In Crop mode the window toolbar shows one tall orange capsule at the top right (about 46 x 115 pt, reaching into the content area) with a single undo-style glyph, instead of the Save / Cancel / Undo glass buttons in a row.

## Analysis (from a screenshot and the code; not reproduced locally)

`CropToolbarControls` (Sources/KromoraKit/Views/ContentView.swift) returned three bare `Button`s inside `GlassEffectContainer`, all tagged `glassEffectUnion(id: "crop")`, placed in a `ToolbarItem(.primaryAction)`. With no stack of its own, the children can be laid out vertically; unioned glass then draws one tall capsule (the prominent Save tint is the orange) and hides the other buttons. The structure dates from KRMA-489 and has not changed, so the trigger is probably a recent toolchain or OS update (Xcode 27.0 beta 27A5252f on macOS 27.2), not a code change.

## Work done

The three buttons are now wrapped in an explicit `HStack(spacing: 10)` inside `CropToolbarControls`; buttons, help text, accessibility labels and the union id are unchanged. Build and MenuCommandTests/CropInspectorTests pass.

## Acceptance criteria

- Entering Crop shows Save, Cancel and Undo side by side in one glass group, vertically centred in the toolbar, with no pill extending into the canvas.
- Not yet confirmed visually: the reporter should rebuild and check. If it still renders as a tall pill, capture the view hierarchy (Xcode view debugger or `read_page` equivalent) and consider replacing the container with a `ControlGroup`, as the transfer pill does.
