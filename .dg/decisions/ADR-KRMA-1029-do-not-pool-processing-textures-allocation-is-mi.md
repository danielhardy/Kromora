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
| interactive 1600x1067 rgba8 | 0.0034 ms | 0.0043 ms |
| preview 2560x1707 rgba16f | 0.0036 ms | 0.0039 ms |
| preview 3840x2560 rgba16f | 0.0060 ms | 0.0095 ms |

A slider-drag frame at 60 Hz is 16.7 ms, so allocation is under 0.05% of the budget. Caveat: this times the API call, not first-use page-in on the GPU. If an Instruments Metal System Trace later shows first-touch cost on large previews, revisit. No such profile exists today, and a pool would need to beat a few microseconds while adding a correctness hazard (stale pixels, torn reads).

## Owners that can read a texture after `render` returns

The engine hands out a `CIImage` wrapping the texture (`RenderEngine.swift` ~:560, completed only after `commitAndWaitForCompletion`) and, for processing prefixes, retains it in `processingPrefixCache` (~:2140). Readers:

1. `PreviewSurface.presentationTexture` - acquired in `presentationTextureMaterializationCompleted`, released on surface reset or replacement.
2. `transitionTexture` - the previous presentation copied at the start of a crossfade; released when the crossfade ends.
3. `lastValidPresentationTexture` - fallback when a newer frame is refused; replaced on the next valid frame, cleared on reset.
4. `retainedCompleteTexture` - last complete (settled) frame kept across interactive frames.
5. `pendingPresentationMaterialization` - texture awaiting its materialization completion callback; cleared on completion or revision change.
6. Histogram readback path - samples `presentationTexture` into `histogramRetryReadbackBuffers` via a command buffer that may outlive the surface revision.
7. `processingPrefixCache` entries (`MaterializedImage`) inside the engine; evicted by LRU, `invalidateAll`, `evictAll`, memory pressure.
8. Any `CIImage` downstream (thumbnails, Core Image graphs built on a prefix) - retains the texture through the CIImage.

None of these tell the engine when they let go, and the engine does not expose GPU completion of consumers' own command buffers (only its own render).

## Protocol, if ever needed

- `TextureLease` is a `final class` (Sendable by holding only a `Sendable` pool reference and the texture's identity) wrapping the `MTLTexture`; the `CIImage` and every owner above hold the lease, never the bare texture. `deinit` (nonisolated) posts the texture ID to a lock-free return channel (an `AsyncStream.Continuation`, which is Sendable); the pool actor drains the channel before each allocation. No `@unchecked Sendable` needed.
- A texture is reusable only when (a) its lease is deallocated, and (b) the last command buffer that read or wrote it has completed. Consumers that submit their own command buffers (histogram, presentation) must register those via `lease.addCompletionFence(commandBuffer)`, which bumps an outstanding count decremented in `addCompletedHandler`; release waits on count == 0.
- Cancel/throw: the lease is created after `makeProcessingTexture` and dropped on any early return, so the deinit path covers it. A cancelled render whose command buffer is still in flight keeps its fence and is not reusable until the handler fires.
- Memory pressure and shutdown: `evictAll` drops the free list only; leased textures are untouched and return to nowhere (the pool is marked closed, returns are discarded). Preview and export engines each own a separate pool; textures never cross engines.

## Test (window-independent)

A deterministic fake: a pool over a counting texture factory, acquire N leases, retain some in stand-in owners, drop others, attach fences with controllable completion, and assert (1) a texture ID is never returned by `acquire` while its lease is alive or its fence outstanding, (2) cancel and throw paths release, (3) closed pool discards returns. A real-Metal variant writes a sentinel through a retained lease, churns acquisitions, and verifies the sentinel is unchanged.

## Follow-ups

None filed. Revisit only with a Metal System Trace showing allocation or first-touch cost in a slider-drag hot path.
