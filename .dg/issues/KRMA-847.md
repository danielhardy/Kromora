---
id: KRMA-847
title: "Fix Soften edges breaking smart masks: replace O(r²) feather blur with separable running sum"
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
created: 2026-10-10T13:02:23.644Z
updated: 2026-10-10T13:02:39.692Z
blockers: []
order: zq
board: product
---

## Objective

Adjusting a smart mask's "Soften edges" slider (for example on a Person mask after exposure edits) could leave the mask broken: it stopped applying to the photo and its overlay disappeared.

## Root cause

`MaskOperations.feather` was a naive box blur that re-summed the whole (2r+1)² window for every pixel, O(pixels × r²). The radius scales with mask size and the slider, so at large targets it ran effectively forever and was not cancellable; slider ticks stacked more of it.

## Work done

Replaced it with a separable running-sum box blur in `Sources/KromoraKit/Models/PhotoAnalysis/MaskOperations.swift`. It averages over the same edge-clipped window with the same in-bounds count, so output matches, but cost is O(pixels) regardless of radius. It checks `Task.checkCancellation()` every 64 rows in both passes so a dragged slider can abandon stale work. Accumulation is in Double.

## Acceptance criteria

- Dragging Soften edges on a smart mask after other edits keeps the mask applied and its overlay visible.
- Existing mask tests (MaskRefinementTests, RegionMaskTests, LocalMaskRenderingTests, MaskResamplingPerformanceTests) pass.
- Not yet done: a unit test pinning feather output against a reference implementation for an edge-clipped window, and a cancellation test. Verifier may add these as a localized safe fix.
