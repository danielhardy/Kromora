---
id: LUMO-293
title: "Two-phase masked preview: publish base fast, refine when masks resolve"
type: feature
status: done
priority: high
agent: claude
verification_agent: pi
model: opus
verification_model: openrouter/meta/muse-spark-1.3-contributor
labels:
  - performance
  - preview
  - masks
created: 2026-09-08T23:48:29.584Z
updated: 2026-09-09T01:10:06.092Z
depends_on:
  - LUMO-291
  - LUMO-292
order: z
board: product
commits:
  - edacdd3
---

## Objective

Masked photos paint first pixels as fast as unmasked photos; mask detail refines in place when Vision resolves.

## Context

Parent: LUMO-289. Depends on LUMO-291 and LUMO-292 (no wasted pre-edit render, no per-tick thumbnails) so the base image itself is cheap. Even then, buildImage awaits resolvedLocalMasks (-> PhotoAnalysisCoordinator.mask -> Vision) before publishing anything (Sources/LumoKit/Models/RenderEngine.swift). First pixels wait on segmentation; semanticMaskPreviewCap already bounds the mask working set (Sources/LumoKit/Models/LocalMaskRendering.swift).

## Plan

- Two-phase publish on the preview path only (not export): build and publish the pre-mask graph result immediately, then resolve masks and publish the refined frame. PreviewCoordinator needs a mask-revision publication gate so a stale refinement can never overwrite a newer base (reuse the existing revision/sourceRevision/displayRevision fencing; refinements carry the same displayRevision they refine).
- Keep export, histogram, and comparison on the single-phase exact path.
- If the base publish complicates the actor path, an acceptable smaller first step: resolve masks outside the RenderEngine actor (pre-resolve in the scheduler operation before makeCIImage) so Vision suspension time does not head-of-line-block other actor work — but this alone does not get first pixels up faster, so prefer true two-phase.

## Acceptance

- Masked-photo time-to-first-pixels matches the unmasked base path within noise; refinement lands without flicker or stale-frame overwrite (rapid-edit and navigation tests).
- Export/histogram pixel-identical to today; LocalMaskRenderingTests and PreviewCutoverTests extended.

## Agent log

- 2026-09-09T01:10:06.086Z: Hardened the two-phase masked preview: layers whose semantic components would over-apply are deferred whole (subset rule on LocalAdjustmentLayer.allowsDeferredSemanticPreview, enforced in RenderEngine.resolvedLocalMasks); PreviewCoordinator tracks the warmed mask recipe so only a cold recipe pays for a base frame; first-pixel telemetry is no longer overwritten by the refinement. Export/full-resolution/histogram/thumbnails stay single-phase and exact. ci-tests.sh fast + serial clean.
