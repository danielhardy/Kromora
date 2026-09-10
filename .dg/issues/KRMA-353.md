---
id: KRMA-353
title: Rotate local-adjustment mask geometry along with image rotation
type: task
status: ready
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-10T14:49:59.785Z
updated: 2026-09-10T16:05:02.221Z
parent: KRMA-332
order: v
board: product
---

## Objective

Rotate local-adjustment mask geometry along with image rotation, matching the crop-rotation fix
made during KRMA-332 verification.

## Context

KRMA-332 (non-destructive image rotation) added a quarter-turn `ImageRotation` to `EditDocument`
and applied it consistently to render/export geometry. Verification found and fixed one gap:
a **committed crop**'s `normalizedRect` — defined in the oriented source's coordinate space — was
not remapped when rotation changed, so it silently framed the wrong region after a rotate. That
was fixed by `CropAdjustments.rotated(byClockwiseQuarterTurns:)`, applied in
`AppViewModel.rotateImage`/`resetRotation` (see KRMA-332 commit history).

The same class of problem likely applies to `EditDocument.localAdjustments`
(`LocalAdjustmentLayer` masks — gradient/radial/region geometry, etc.): if their geometry is
anchored to the oriented-image coordinate space the same way crop is, rotating the image will
leave mask shapes pointing at the wrong region without any user-visible feedback. This was out of
scope for a localized verification fix (the local-adjustment data model is more complex than a
single rect, and remapping each mask kind correctly needs its own design/test pass), so it's
filed here as a follow-up rather than folded into KRMA-332.

## Acceptance criteria

- [ ] Determine whether each `LocalAdjustmentLayer` mask kind's geometry is expressed in
      oriented-image coordinates (same convention as crop) or is otherwise rotation-invariant.
- [ ] If not rotation-invariant, remap mask geometry on rotate/reset-rotation the same way
      `CropAdjustments.rotated(byClockwiseQuarterTurns:)` does for crop.
- [ ] Add regression coverage: commit a mask, rotate, and assert the mask still selects the same
      visual content (mirroring `ImageRotationTests.testRotatingAnImageWithACommittedCropKeepsTheSameFramedContent`).

## Implementation notes

Start from `Sources/KromoraKit/Models/CropAdjustments.swift`'s new `rotated(byClockwiseQuarterTurns:)`
for the coordinate-transform pattern, and `AppViewModel.rotateImage`/`resetRotation` for where to
apply it. Local adjustment geometry lives in `LocalAdjustmentLayer` — check each mask kind's shape
representation before assuming the crop-rect formula applies directly.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
