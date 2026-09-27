---
id: KRMA-667
title: Heal membrane pull/push pyramid computes numerator and weight chains redundantly
type: task
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-27T19:40:17.340Z
updated: 2026-09-27T19:40:17.340Z
parent: KRMA-659
blockers: []
order: zzzzzh
board: product
---

## Objective

Avoid computing the Heal membrane's numerator and confidence pyramids as two independent
blur/downsample chains from the same starting image.

## Context

`RetouchRenderer.healedFill` (Sources/KromoraKit/Models/RetouchRenderer.swift, KRMA-659/353d5a4)
seeds both `numeratorLevels` and `weightLevels` from the exact same `difference` image
(`var numeratorLevels = [difference]; var weightLevels = [difference]`), then downsamples each
array independently through `downsample(_:to:)`. Since `difference` already carries the weighted
RGB numerator in its color channels and the confidence weight in alpha, and `downsample` applies
an identical Gaussian blur + 2x reduction to whichever image it is given, the two arrays end up
computing the *same* blur/downsample chain twice per pyramid level (once for the array whose only
consumed channel is `.rgb`, once for the array whose only consumed channel is `.a`). This is a
performance-only finding from KRMA-659 verification, not a correctness defect — the retouchPush
kernel (fixed in the same verification pass to blend `propagated`/`localMean` instead of summing
them) still reads exactly one channel from each array, so the duplicate computation is otherwise
harmless.

## Acceptance criteria

- [ ] `healedFill` maintains one pyramid chain (downsampling a single four-channel image) instead
      of two parallel chains built from the same starting image, so each Heal spot's per-level
      Gaussian blur + downsample runs once instead of twice.
- [ ] Heal/Clone pixel output is unchanged for existing regression coverage, including
      `testHealMembraneExcludesPixelsInsideTheHole` and
      `testHealOverFlatExteriorDoesNotOvershootDestinationTone`.

## Implementation notes

Candidate approach: keep a single `levels: [CIImage]` array seeded with `difference` and
downsampled once per level; have the coarsest/refine `retouchPush` calls read both `.rgb`
(numerator) and `.a` (confidence) from the same sampler argument instead of two separate
arguments, or pass the same image twice into the existing two-sampler signature without
duplicating the upstream Core Image graph nodes.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
