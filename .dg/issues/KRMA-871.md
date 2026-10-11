---
id: KRMA-871
title: "Masks panel: mask-kind buttons should be neutral, not copper"
type: task
status: backlog
priority: low
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-11T01:10:25.691Z
updated: 2026-10-11T01:10:26.083Z
blockers: []
order: zzzzzh
board: product
---

## Objective

The mask-kind buttons in the Masks panel (Subject, Person, Face, Foreground, Background, Brush, Linear Gradient, Radial Gradient, Luminance Range, Color Range, Depth Range) rendered with copper labels and icons. They are one-shot choices, not a selected state, so they should look like ordinary buttons and leave the copper accent for what is on.

## Cause

`ContentView` applies `.tint(KromoraTheme.primaryAccent)` to the whole window, and `.buttonStyle(.bordered)` picks the tint up for its label. The chooser in `MaskingWorkspace.emptyMaskChooser` set no tint of its own.

## Work done

`.tint(nil)` on the chooser buttons (Sources/KromoraKit/Views/MaskingWorkspace.swift), the same approach as the Crop Rotate buttons (KRMA-866). The Flip toggles already use `.tint(nil)` when off and render neutral inside the same window, which is the evidence it overrides the inherited tint. An offscreen render cannot show the difference (an inactive window draws bordered buttons neutral regardless), so this has not been seen in the running app.

## Acceptance criteria

- The empty Masks panel shows the eleven kind buttons with default (non-copper) labels and icons.
- Masking panel tests pass (61 related tests do).

## Follow-up for the owner

Sixteen other `.buttonStyle(.bordered)` call sites inherit the same copper (Library grid and culling bar, Look and Color inspectors, Crop, onboarding, preview). Decide whether bordered buttons should be neutral app-wide (one shared style or a tint reset at the window level) rather than fixing them one at a time.
