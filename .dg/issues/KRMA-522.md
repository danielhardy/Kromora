---
id: KRMA-522
title: Move preview disk-cache rasterization into the render boundary and bound cache I/O
type: task
status: ready
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - performance
  - rendering
created: 2026-09-21T20:33:03.509Z
updated: 2026-09-21T21:41:04.818Z
estimate: 8
order: z
board: product
---

## Objective

Keep Core Image rasterization inside the render boundary, coalesce settled-frame cache writes, and prevent every preview write or deletion from scanning/deleting the entire cache.

## Context and evidence

PreviewPresentationCoordinator captures CIImage into a detached task and calls PreviewDiskCache.canonicalRaster. That creates a new CIContext per call, renders full extent, then downsamples on the CPU, violating the documented RenderEngine/Core Image boundary and discarding Core Image caches. Each settled frame creates an untracked detached task. PreviewDiskCache.write calls enforceCap after every write and AppViewModel initialization enforces it synchronously on the main actor. Deleting one library asset calls invalidateAll and removes every preview.

There are also ad-hoc CIContext constructions in AppleEnhancementReference, LookLUTConverter, and RecipeExtractor.

## Scope

- Add a RenderEngining/RenderEngine method that produces the canonical preview raster at the required long edge using the engine-owned context and returns CGImage/Data.
- Give PreviewDiskCache a serial/coalescing writer keyed by cache key, cancellation, and an in-memory size/LRU index loaded once in background.
- Enforce cache caps incrementally rather than enumerating the directory after every write.
- Invalidate by portable asset identity/key prefix, preserving unrelated previews.
- Route documented ad-hoc contexts through RenderEngineResources or a shared per-owner context; retain only explicit test utilities.

## Acceptance criteria

- [ ] No CIContext construction remains outside RenderEngineResources/RenderEngine except documented tests.
- [ ] Settled-frame writes are coalesced and cancellable; cache writes do not enumerate the directory per write.
- [ ] Deleting one photo leaves other assets' previews cached.
- [ ] Canonical preview pixels and dimensions remain compatible with existing consumers.
- [ ] Memory peak and settled-frame write cost improve in the existing preview benchmark.
- [ ] Render, preview, deletion, and cache tests pass.

## Dependencies and coordination

Independent of the library chain. Coordinate with CQ-09 because both touch render/kernel boundaries and with CQ-15 because RenderEngine remains one actor during this work.

## Likely files and checks

PreviewPresentationCoordinator, PreviewDiskCache.swift, RenderEngine/RenderEngineResources, PreviewSurface, AppViewModel deletion, AppleEnhancementReference, LookLUTConverter, RecipeExtractor, and preview cost tests.
