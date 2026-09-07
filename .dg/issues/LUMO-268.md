---
id: LUMO-268
title: Cap preview-quality mask working resolution
type: task
status: ready
priority: medium
labels:
  - masking
  - performance
created: 2026-09-07T01:14:46.878Z
updated: 2026-09-07T04:03:07.483Z
order: t
board: product
---

## Objective

Determine whether `.preview`-quality semantic masks can resolve at a capped working
resolution instead of the full render extent, letting Core Image upscale the smooth mask to
display. This is the only lever that avoids 60M-element work on zoomed-in previews entirely
rather than merely accelerating it.

## Context

The interactive preview correctly renders at planned display resolution (~2MP typical), so the
common case is already bounded. The cliff is 1:1 zoom on a 60MP photo: the resolver upscales
the 768×512 seed to the full extent in Swift (tens of seconds in debug, seconds in release),
and the result can never be cached (240MB vs 64MB budget). But a person mask is almost
everywhere low-frequency — its information content is the 768×512 seed — and GPU upscaling of
a smooth alpha mask is visually free.

## Work (measure-first)

- Prototype: clamp `targetSize` for `.preview`-quality semantic resolves to a working cap
  (candidate: 4MP / 2560px long edge) in `CoordinatorLocalMaskResolver` or
  `resolvedLocalMasks`, leaving `.render`/export untouched at full resolution.
- Validate visually, not just numerically: feathered edges, hair-level person boundaries at
  1:1, and hard-edged definitions (density 1, no feather, inverted) must show no visible
  regression vs full-res masks. If hard edges regress, scope the cap to feathered/soft
  definitions only.
- Measure: wall time for a 1:1 preview render with a person layer before/after, debug and
  release.

## Acceptance criteria

- [ ] Decision recorded with measurements: either the cap lands with the chosen threshold
      and scope, or the ticket documents why full-res preview masks stay (with numbers).
- [ ] If it lands: side-by-side render comparison test (capped vs full-res) within stated
      tolerance on feathered and hard-edge fixtures.
- [ ] Export/`.render` path provably untouched (existing render tests).
