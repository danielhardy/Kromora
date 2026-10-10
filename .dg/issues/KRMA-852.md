---
id: KRMA-852
title: Apply Soften/shift/strength at matte resolution before resizing to the target
type: task
status: backlog
priority: medium
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:02:27.995Z
updated: 2026-10-10T13:02:40.660Z
blockers: []
order: zzh
board: product
---

## Objective

Cut the CPU cost of resolving a smart mask at each new zoom size. Logs showed the 512×384 / 768×512 matte being resized to about 2400×1600 and then blurred and remapped over every pixel (about 370 ms for the face mask at strength != 1, 1.7 s with Soften edges), per distinct target size.

## Work done

`CoordinatorLocalMaskResolver.resolve` in `Sources/KromoraKit/Models/LocalMaskRendering.swift` now runs `apply` (soften, edge shift, strength) on the matte at its own resolution and then resizes once. Soften radius is a fraction of the mask's shorter side, so the result is resolution-independent; a render-quality refined matte is already at target size, where order is irrelevant. `MaskResolveTiming` now reports `applyMs` before `resizeMs`.

## Known behavior differences

- At very low Soften values the 1 px minimum radius is relatively wider.
- The matte is stretched to the photo's shape afterwards, so softness can be about 10% wider horizontally than vertically. Verify on a high-contrast edge.

## Acceptance criteria

- `applyMs` drops to a few ms for the person and face masks in the mask-resolution log; `resizeMs` is unchanged.
- Mask rendering/refinement/resampling tests pass.
- Visual check of several Soften values on a high-contrast edge shows no objectionable difference.
