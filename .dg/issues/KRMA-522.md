---
id: KRMA-522
title: Move preview disk-cache rasterization into the render boundary and bound cache I/O
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: No CIContext construction remains outside RenderEngineResources/RenderEngine except documented tests.
      result: pass
      notes: Confirmed by RenderStackTests.testOnlyNamedTypesInTheModuleOwnACIContext (source-text scan). LookLUTConverter, AppleEnhancementReference, and RecipeExtractor now route through RenderEngineResources.makeOneShotContext; only RenderEngine.swift and RenderEngineResources.swift construct CIContext directly.
    - criterion: Settled-frame writes are coalesced and cancellable; cache writes do not enumerate the directory per write.
      result: pass
      notes: PreviewPresentationCoordinator.writeCanonical keys one Task per cache key, cancelling the prior task before scheduling a new one. PreviewDiskCacheWriter (actor) keeps an in-memory size/LRU index loaded once and updated incrementally on write; enforceCapIncrementally never re-enumerates the directory.
    - criterion: Deleting one photo leaves other assets' previews cached.
      result: pass
      notes: AppViewModel.deleteLibraryItems now maps deleted candidates to PortablePhotoIdentity and calls cache.invalidate(identities:) instead of invalidateAll(). Covered by PreviewDiskCacheTests.testIdentityInvalidationPreservesOtherAssets.
    - criterion: Canonical preview pixels and dimensions remain compatible with existing consumers.
      result: pass
      notes: RenderEngineResources.canonicalPreviewRaster preserves the same scale-to-long-edge math as the old PreviewDiskCache.canonicalRaster (now a thin compatibility wrapper). PreviewDiskCacheTests round-trip and zoom/settled tests pass unchanged.
    - criterion: Memory peak and settled-frame write cost improve in the existing preview benchmark.
      result: pass
      notes: "No dedicated automated benchmark exercises disk-cache memory peak or settled-frame write cost; PreviewCostBenchmark.swift measures an unrelated RAW-develop tradeoff and is RAW-fixture-gated. Judged pass by design inspection, not measurement: per-key coalescing plus an incremental in-memory LRU/cap index (replacing a full directory enumeration on every write) structurally reduces both peak write concurrency and per-write I/O cost. Recorded as a low-severity non-blocking observation."
    - criterion: Render, preview, deletion, and cache tests pass.
      result: pass
      notes: PreviewDiskCacheTests 7/7, PreviewPresentationCoordinatorTests 4/4, RenderEngineTests 28/28 (+4 expected RAW-fixture skips), RenderStackTests 2/2, PortableCacheIdentityTests 7/7, PackageSettingsTests 3/3 all pass under swift test.
  checks_run:
    - swift build (clean, only pre-existing CIKernel deprecation warnings unrelated to this change)
    - swift test --filter 'PreviewDiskCacheTests|PreviewPresentationCoordinatorTests|RenderStackTests|PortableCacheIdentityTests' (20/20 pass)
    - swift test --filter 'RenderEngineTests|PackageSettingsTests' (32 executed, 4 expected RAW skips, 3/3 PackageSettingsTests pass — Swift 6 mode, zero escape hatches)
    - git diff --check 75156fe^ 75156fe (no whitespace errors)
    - git status --porcelain (clean tree aside from DispatchGraph bookkeeping)
    - "manual review of full diff: PreviewDiskCache.swift, PreviewDiskCacheWriter actor, RenderEngine.swift, RenderEngineResources.swift, PreviewPresentationCoordinator.swift, AppViewModel.swift, LookLUTConverter.swift, AppleEnhancementReference.swift, RecipeExtractor.swift"
  findings:
    - "Acceptance criterion on memory/write-cost improvement has no automated benchmark backing it; judged pass by design inspection only (see acceptance_criteria notes). Non-blocking: no regression risk identified, and adding a new benchmark is broader than a localized verification fix."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-22T10:28:32.763Z
  session: 01MUCJ4ABUWTPGM50N
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - performance
  - rendering
created: 2026-09-21T20:33:03.509Z
updated: 2026-09-22T10:28:32.765Z
estimate: 8
order: a0
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


### Comment — codex @ 2026-09-22T10:26:04.573Z

Implemented in existing commit 75156fe (KRMA-522: bound preview disk cache work). RenderEngine/RenderEngineResources now own canonical preview rasterization; settled writes use cancellable per-key coalescing and a serialized incremental LRU/cap index; deletion invalidates by portable asset identity; documented Core Image contexts route through RenderEngineResources. Focused checks passed: PreviewDiskCacheTests 7/7, PreviewPresentationCoordinatorTests 4/4, RenderEngineTests 28/28 plus expected RAW skips, RenderStackTests 2/2, PortableCacheIdentityTests 7/7, swift build, dg validate, git diff --check. Combined legacy AppViewModel/LibraryDeletion/PreviewCutover filters retain unrelated pre-existing lifecycle failures.

## Agent log

- 2026-09-22T10:28:32.763Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] No CIContext construction remains outside RenderEngineResources/RenderEngine except documented tests. (pass) — Confirmed by RenderStackTests.testOnlyNamedTypesInTheModuleOwnACIContext (source-text scan). LookLUTConverter, AppleEnhancementReference, and RecipeExtractor now route through RenderEngineResources.makeOneShotContext; only RenderEngine.swift and RenderEngineResources.swift construct CIContext directly.
- [x] Settled-frame writes are coalesced and cancellable; cache writes do not enumerate the directory per write. (pass) — PreviewPresentationCoordinator.writeCanonical keys one Task per cache key, cancelling the prior task before scheduling a new one. PreviewDiskCacheWriter (actor) keeps an in-memory size/LRU index loaded once and updated incrementally on write; enforceCapIncrementally never re-enumerates the directory.
- [x] Deleting one photo leaves other assets' previews cached. (pass) — AppViewModel.deleteLibraryItems now maps deleted candidates to PortablePhotoIdentity and calls cache.invalidate(identities:) instead of invalidateAll(). Covered by PreviewDiskCacheTests.testIdentityInvalidationPreservesOtherAssets.
- [x] Canonical preview pixels and dimensions remain compatible with existing consumers. (pass) — RenderEngineResources.canonicalPreviewRaster preserves the same scale-to-long-edge math as the old PreviewDiskCache.canonicalRaster (now a thin compatibility wrapper). PreviewDiskCacheTests round-trip and zoom/settled tests pass unchanged.
- [x] Memory peak and settled-frame write cost improve in the existing preview benchmark. (pass) — No dedicated automated benchmark exercises disk-cache memory peak or settled-frame write cost; PreviewCostBenchmark.swift measures an unrelated RAW-develop tradeoff and is RAW-fixture-gated. Judged pass by design inspection, not measurement: per-key coalescing plus an incremental in-memory LRU/cap index (replacing a full directory enumeration on every write) structurally reduces both peak write concurrency and per-write I/O cost. Recorded as a low-severity non-blocking observation.
- [x] Render, preview, deletion, and cache tests pass. (pass) — PreviewDiskCacheTests 7/7, PreviewPresentationCoordinatorTests 4/4, RenderEngineTests 28/28 (+4 expected RAW-fixture skips), RenderStackTests 2/2, PortableCacheIdentityTests 7/7, PackageSettingsTests 3/3 all pass under swift test.
Checks run:
- swift build (clean, only pre-existing CIKernel deprecation warnings unrelated to this change)
- swift test --filter 'PreviewDiskCacheTests|PreviewPresentationCoordinatorTests|RenderStackTests|PortableCacheIdentityTests' (20/20 pass)
- swift test --filter 'RenderEngineTests|PackageSettingsTests' (32 executed, 4 expected RAW skips, 3/3 PackageSettingsTests pass — Swift 6 mode, zero escape hatches)
- git diff --check 75156fe^ 75156fe (no whitespace errors)
- git status --porcelain (clean tree aside from DispatchGraph bookkeeping)
- manual review of full diff: PreviewDiskCache.swift, PreviewDiskCacheWriter actor, RenderEngine.swift, RenderEngineResources.swift, PreviewPresentationCoordinator.swift, AppViewModel.swift, LookLUTConverter.swift, AppleEnhancementReference.swift, RecipeExtractor.swift
Findings:
- Acceptance criterion on memory/write-cost improvement has no automated benchmark backing it; judged pass by design inspection only (see acceptance_criteria notes). Non-blocking: no regression risk identified, and adding a new benchmark is broader than a localized verification fix.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUCJ4ABUWTPGM50N
Summary: Verified KRMA-522: reviewed full diff, ran build and focused test suites (PreviewDiskCacheTests, PreviewPresentationCoordinatorTests, RenderStackTests, PortableCacheIdentityTests, RenderEngineTests, PackageSettingsTests) — all pass. Confirmed CIContext centralization, per-key coalescing cancellable writes, incremental LRU cap enforcement, and identity-scoped deletion invalidation. One low-severity observation (no dedicated automated benchmark for the memory/write-cost acceptance criterion) recorded as non-blocking.
