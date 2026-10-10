---
id: KRMA-865
title: Crop inspector Landscape button has no icon (rectangle.landscape is not an SF Symbol)
type: bug
status: backlog
priority: low
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T18:46:48.709Z
updated: 2026-10-10T18:46:49.091Z
blockers: []
order: zzzzh
board: product
---

## Objective

The Landscape orientation button in the Crop inspector (shown for aspect presets that support orientation) has no icon.

## Root cause

`CropInspectorView.landscapeOrientationSystemImage` returned `"rectangle.landscape"`, which is not an SF Symbol. `rectangle.portrait` exists; the landscape rectangle is plain `rectangle`. Verified with `NSImage(systemSymbolName:)` on this macOS 27.2 Mac. A missing symbol draws nothing, so the button rendered blank.

## Work done

- `landscapeOrientationSymbol` is now `"rectangle"` and `portraitOrientationSymbol` stays `"rectangle.portrait"`, exposed as static constants on `CropInspectorView`.
- Added `CropInspectorTests.testOrientationButtonsUseSymbolsThatExist`.
- Audit: every other string literal in Sources that looks like an SF Symbol name resolves; the remaining non-resolving matches are file names and identifiers. Symbols built dynamically (for example `tab.iconName`, `kind.iconName`) were not enumerated.

## Acceptance criteria

- Crop inspector shows an icon on both orientation buttons.
- CropInspectorTests pass.
- Not yet confirmed visually in the running app.
