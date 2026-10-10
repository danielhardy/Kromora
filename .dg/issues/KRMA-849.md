---
id: KRMA-849
title: "Fix smart mask flicker while zooming: ignore render size in semantic warmth"
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
created: 2026-10-10T13:02:25.400Z
updated: 2026-10-10T13:02:40.078Z
blockers: []
order: zx
board: product
---

## Objective

With a smart mask (for example Person) applied and fully rendered, zooming made just the mask area flicker off and on while the rest of the photo rendered steadily.

## Root cause

`PreviewCoordinator` publishes a mask-less base frame (`maskResolution: .deferSemantic`) first, then the resolved frame, unless the semantic masks are "warm". The warm identity (`SemanticWarmth`) included the render `targetSize`, so every zoom step looked cold. A Person layer is dropped whole from the base frame (`allowsDeferredSemanticPreview` is false), so each zoom published a frame without the mask followed by one with it.

## Work done

`Sources/KromoraKit/ViewModels/PreviewCoordinator.swift`: removed `targetSize` from `SemanticWarmth` and updated its doc comment. Warmth is now source, asset, mask recipe and mask quality. Vision output is cached independent of size; a new size only costs a resize of the cached matte, during which the previous frame stays on screen. Added `testZoomingAWarmSmartMaskDoesNotPublishAMasklessBaseFrame` in `PreviewCoordinatorTests`. Confirmed in a dev build with `log stream --signpost`: zoom renders no longer carry `masks=deferred`.

## Known remaining risk

Mask quality stays in the identity, so the preview→full-resolution settle after a zoom can still be two-phase. If a flicker remains at settle, a separate ticket should keep the previous mask in the base frame rather than dropping the layer.

## Acceptance criteria

- Zooming with a warm smart mask produces one resolved render per step and no `masks=deferred` render.
- Adding or editing a smart mask still publishes a base frame while Vision resolves it (existing test).
- PreviewCoordinatorTests and PreviewCutoverTests pass.
