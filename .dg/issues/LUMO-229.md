---
id: LUMO-229
title: "Masking workspace: implement functional mask alpha overlay (color-wash/grayscale/solo)"
type: bug
status: backlog
priority: high
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - masking
  - epic:masking
created: 2026-09-05T04:39:51.202Z
updated: 2026-09-05T04:40:10.534Z
order: zzy
board: product
---

## Objective

Make the masking workspace's overlay-inspection controls actually inspect the mask, per
`docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md` Section 5.2 and Step 8 ("solo inspection"), which
LUMO-220 references but does not implement.

## Problem

`MaskInteractionState` (`Sources/LumoKit/Models/MaskInteractionState.swift`) exposes
`overlayInspection` (color-wash/grayscale), `overlayColor`, `overlayOpacity`, and `soloLayerID`,
and `MaskingWorkspace`'s row menu has a working "Solo" button that calls `toggleSolo(layerID:)`.
None of these values ever reach a rendering of the mask's actual resolved alpha:

- `MaskCanvasOverlay.draw` (`Sources/LumoKit/Views/MaskingWorkspace.swift`) only draws vector
  *geometry guides* (a dashed rectangle for semantic masks, brush stroke paths, gradient handles)
  for the selected layer's target component. It never renders the mask's computed per-pixel
  coverage/alpha.
- `soloLayerID` is set and cleared by `toggleSolo`/`clearSolo` but is never read anywhere outside
  `MaskInteractionState` itself — clicking "Solo" in the layer row's action menu currently has zero
  observable effect.
- `overlayInspection` (color-wash vs. grayscale) only changes the color of the vector guide
  outline, not an actual alpha visualization.

The plan is explicit that these are meant to be functional: "The overlay supports color-wash and
grayscale/black-and-white inspection modes, ... never affects export or edit history" and "The
active mask may be soloed to inspect its alpha without changing the document."

## Why this wasn't fixed as part of LUMO-220 verification

This requires computing/exposing the layer's resolved soft-mask alpha as an image and compositing
it into the preview surface — touching the `RenderEngine`/`CIImage` boundary that
`Sources/LumoKit/Models/RenderPipeline.swift` and friends own (per CLAUDE.md, `CIImage`/`CIFilter`/
`CIContext` must stay inside `RenderEngine`; only values may cross the boundary). That's a genuine
rendering feature addition, not a localized, testable fix, so it doesn't belong in the counterpoint
verification pass for LUMO-220.

## Acceptance criteria

- [ ] Selecting a layer and enabling "Show overlay" renders that layer's actual resolved mask
      alpha over the canvas (not just geometry guides), in the chosen color-wash or grayscale mode,
      at the chosen opacity.
- [ ] Toggling "Solo" on a layer isolates that layer's mask alpha in the overlay (or an equivalent
      visible effect); toggling it off restores the normal per-selection overlay.
- [ ] Overlay/solo/inspection state remains presentation-only: it must not affect `EditDocument`,
      undo history, or exported/committed preview pixels.
- [ ] Geometry guides (brush path, gradient handles, semantic bounding box) continue to render
      alongside or on top of the alpha overlay for the selected component.
- [ ] Test coverage: overlay pixels reflect the resolved mask for representative brush/linear/
      radial/semantic layers; solo isolates the expected layer; overlay is absent from exported
      pixels.

## Context

- Parent: LUMO-220 (Replace selection-only mask sheet with persistent Masking workspace)
- Related: LUMO-219 (Render ordered local adjustments through resolved soft masks) — likely source
  of the `LocalMaskResolving` boundary this overlay should reuse to get alpha without duplicating
  mask-resolution logic.
- Plan: `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md` Section 5.2, Step 8.
