---
id: KRMA-866
title: "Crop: drop the duplicate Save/Cancel bar from the inspector and neutralize the Rotate buttons"
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
created: 2026-10-10T19:18:44.347Z
updated: 2026-10-10T19:18:44.716Z
blockers: []
order: zzzzq
board: product
---

## Objective

Crop mode had two sets of Save/Cancel: the glass group in the window toolbar and a Cancel/Save bar at the bottom of the Crop inspector. Keep one. Also, the Rotate buttons were accent-orange while the Flip toggles were neutral, so orange read as an "on" state on buttons that have none.

## Decision

Toolbar only (chosen by the reporter). The toolbar group also carries Undo and sits with the window chrome; the inspector holds only adjustments.

## Work done

- `CropInspectorView`: removed the bottom Divider and Cancel/Save `HStack` and the `onDone` parameter; `onCancel` stays for `onExitCommand`. `InfoInspectorView`'s call site updated.
- Return and Escape are unchanged: the global key monitor in `KeyboardShortcuts.swift` calls `commitCrop()` / `cancelCrop()` while Crop is active, and the toolbar buttons keep their help text.
- `transformButton` (Rotate 90 left/right) now has `.tint(nil)`, so the one-shot actions are neutral like an idle flip toggle; only a flip that is on shows the accent.
- `MenuCommandTests` source-text assertions that required the inspector buttons now assert their absence. These are the brittle source-text tests tracked in KRMA-858.

## Acceptance criteria

- Crop shows Save/Cancel only in the toolbar; the inspector bottom bar is gone and Return/Escape still apply/cancel.
- Rotate buttons are neutral; a flip is orange only when on.
- MenuCommandTests, CropInspectorTests and InfoInspector tests pass. Not yet confirmed visually.
