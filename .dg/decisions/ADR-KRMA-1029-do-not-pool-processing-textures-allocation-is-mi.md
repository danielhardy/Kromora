---
id: ADR-KRMA-1029
title: Do not pool processing textures; allocation is microseconds
date: 2026-10-19T02:07:37.301Z
status: accepted
---

Decision (KRMA-1029): do not pool processing textures. Keep per-render allocation in `RenderEngineResources.makeProcessingTexture`. No lease/release protocol ships; the one below is recorded so it can be adopted if a profile ever shows allocation cost.

## Evidence

`TextureAllocationBenchmark` (opt-in lane, window-independent, real `RenderEngineResources`, 200 iterations per size, Apple Silicon) times `makeProcessingTexture` with private storage:

| Texture | Median | p95 |
|---|---|---|
| interactive 1600x1067 rgba8 | 0.0035 ms | 0.0051 ms |
| preview 2560x1707 rgba16f | 0.0038 ms | 0.0074 ms |
| preview 3840x2560 rgba16f | 0.0062 ms | 0.0119 ms |

A slider-drag frame at 60 Hz is 16.7 ms. The largest median is 0.0062 ms (about 0.04% of that budget); the largest p95 is 0.0119 ms (under 0.08%). Caveat: this times the API call, not first-use page-in on the GPU. If an Instruments Metal System Trace later shows first-touch cost on large previews, revisit. No such profile exists today, and a pool would need to beat a few microseconds while adding a correctness hazard (stale pixels, torn reads).

## Owners that can read a texture after `render` returns

There are two different textures in the preview path, and only the first is in scope for this decision:

- `RenderEngine.makeCIImage` wraps its completed render texture in the returned `CIImage` (`RenderEngine.swift`, `makeCIImage`). It waits for the write command buffer before returning. `materializedPrefixImage` similarly wraps a processing-prefix texture in a `CIImage` (`RenderEngine.swift`, `materializedPrefixImage`).
- `PreviewSurface.makePresentationTexture` allocates a separate BGRA display texture from that `CIImage`. `presentationTexture`, `transitionTexture`, `lastValidPresentationTexture`, `retainedCompleteTexture`, and `pendingPresentationMaterialization` refer to this display copy, not the texture returned by `RenderEngine`. The histogram retry command buffer also samples this display copy. These holders matter if the presenter texture is ever pooled; they are not owners of the processing texture considered here.

For a final render texture returned as a `CIImage`, current strong owners and release points are:

1. `PreviewCoordinator.renderSingle` holds the result in `gpuImage`; a stale or cancelled result is dropped there. A current result is passed in `PreviewCoordinator.Publication.gpuImage` to `PreviewPublicationCoordinator.publish`, and the publication value ends after the handler returns.
2. `PreviewSurface.image` is assigned by `present`. It is replaced by the next accepted image or cleared by `clear`. After a successful drawable, `lastValidImage` also aliases it; that alias is replaced by the next successful presentation or cleared by `clear`. `retainedCompleteImage` aliases a complete-coverage frame and remains while partial ROI frames are shown; it is replaced by the next complete frame or cleared by `clear`. The comparison baseline follows the same path in `originalPreviewSurface` via `PreviewAdmissionCoordinator`.
3. `PreviewPublicationCoordinator.lastPresentedVisibleImage` retains the last confirmed image for histogram and presentation fallback. It is replaced on confirmation and cleared by `resetForSource`. `PreviewAdmissionCoordinator.pendingPresentationHistogram.image` can retain that image while the presentation sample or histogram job is pending; it is cleared when that work is completed, cancelled, invalidated, or shut down. An admitted histogram job captures the image through `RenderEngine.histogram` until the job ends.
4. A settled visible image may be captured by `PreviewPresentationCoordinator.writeCanonical`'s task until `makeCanonicalPreviewRaster` finishes or the task is cancelled. The idle warmer similarly holds its result while awaiting `writeCanonicalForWarmer`. Adjacent-preview prefetch drops its result immediately after `makeCIImage` returns.
5. `processingPrefixCache` stores separate intermediate `CIImage` values produced by `materializedPrefixImage`. The LRU, `invalidateAll`, `evictAll`/memory-pressure eviction, and `invalidateSourceCache` release cache entries; a downstream `CIImage` graph can still retain a prefix texture after the cache entry is evicted. Materialization flights also hold the completed image until the cache insert/return path finishes.
6. Core Image transforms and command buffers that consume any of these images can extend the underlying texture's lifetime. In particular, `PreviewSurface.beginPresentationTextureMaterialization` encodes a read of the returned image and commits asynchronously; the consumer fence completes independently of the engine's already-completed write.

The returned image's holders do not tell the engine when they let go, and the engine does not expose completion of consumers' command buffers. A lease must therefore travel with each retained image/derived graph, while fences cover every command buffer that reads it. The display-copy holders above are a separate texture lifecycle.

## Protocol, if ever needed

- `TextureLease` is a final, checked-`Sendable` class holding only an immutable texture ID and a sendable return handle; the pool actor owns the `MTLTexture`. A `LeasedImage` value pairs the `CIImage` with the lease, and all owners/derived graphs above retain that pair rather than passing a bare image. `deinit` (nonisolated) posts the texture ID to a thread-safe return channel (`AsyncStream.Continuation`); the pool actor drains returns before reuse. No `@unchecked Sendable` is needed.
- A texture is reusable only when (a) no `LeasedImage` or derived graph retains its lease, and (b) every command buffer that read or wrote it has completed. Consumers must register those command buffers before commit; completion handlers decrement the fence count, and reuse waits for count == 0. The current histogram retry reads the separate display copy, while the first presentation materialization reads the leased processing image.
- Cancel/throw: the lease is created after `makeProcessingTexture` and dropped on any early return, so the deinit path covers it. A cancelled render whose command buffer is still in flight keeps its fence and is not reusable until the handler fires.
- Memory pressure and shutdown: `evictAll` drops the free list only; active leases remain valid. An explicit actor-isolated `close` drops free storage, marks the pool closed, and discards later returns. Engine teardown must call it from an explicit actor-isolated shutdown path rather than `deinit`. Preview and export engines each own a separate pool; textures never cross engines.

## Test (window-independent)

A deterministic fake: a pool over a counting texture factory, acquire N leases, retain some in stand-in owners, drop others, attach fences with controllable completion, and assert (1) a texture ID is never returned by `acquire` while its lease is alive or its fence outstanding, (2) cancel and throw paths release, (3) closed pool discards returns. A real-Metal variant writes a sentinel through a retained lease, churns acquisitions, and verifies the sentinel is unchanged.

## Follow-ups

None filed. Revisit only with a Metal System Trace showing allocation or first-touch cost in a slider-drag hot path.
