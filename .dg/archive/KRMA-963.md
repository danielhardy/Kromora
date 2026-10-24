---
id: KRMA-963
title: Pool or reuse GPU processing textures instead of allocating one per render
type: task
status: done
priority: low
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - nice-to-have
  - performance
  - gpu
created: 2026-10-13T14:48:13.266Z
updated: 2026-10-15T12:44:29.275Z
parent: KRMA-922
blockers: []
order: zzzzzzh
board: product
context:
  files: []
  docs:
    - .context/2026-10-14-release-readiness-review.md
  issues:
    - KRMA-994
  commands: []
---

## Objective

Stop allocating a new processing texture for every render; reuse by size/format.

## Context

Review `.context/2026-10-13-release-readiness-review.md` "Nice to have: GPU allocation". `Sources/KromoraKit/Models/RenderEngineResources.swift`
~L320 creates a processing texture per render. Per-render allocation costs time and memory churn at
slider-drag rates, and the engine already has bounded caches and memory-pressure eviction, which a pool
must respect (read the eviction code in the same file and `docs/ENGINEERING_GUIDE.md` render/resource
boundaries).

## Acceptance criteria

- [ ] A small `ProcessingTexturePool` keyed by (width, height, pixelFormat, usage) hands out a texture
      and takes it back when the render completes (including on cancel/throw, via `defer`), with a
      hard cap on retained textures and total bytes (reuse the engine's existing byte-budget constants).
- [ ] Textures are never shared by two in-flight renders (the preview engine and the export engine
      are separate instances; pools must not be shared across them).
- [ ] The pool drops everything on memory pressure (hook into the existing eviction path) and on
      engine shutdown.
- [ ] Tests (serial lane, real engine): back-to-back renders of the same size reuse one texture (expose
      an allocation counter via an internal seam); a different size allocates a new one; cancelled
      render returns its texture; memory-pressure notification empties the pool.
- [ ] Rendered pixels are identical before/after (existing render parity tests pass).
- [ ] No display-bound benchmark is run; if you want a number, use a window-independent test.
- [ ] `swift build` is warning-free and Swift 6 mode stays clean (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`, no `#available` branches).
- [ ] `scripts/ci-tests.sh fast` exits 0 (if only `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` fails, re-run it alone with `swift test --filter`, note it in the review comment, and do not change it here; it is tracked separately).
- [ ] `scripts/ci-tests.sh serial` exits 0.

## 2026-10-14 review — do not pool until ownership is proven

Finding 11 in `.context/2026-10-14-release-readiness-review.md`. Processing textures are allocated per completed render (`RenderEngineResources.swift` around line 320). A pool may help if allocation shows up in a profile. Reuse has to wait until GPU completion and every retained presentation reference is finished. Pooling without that protocol can corrupt pixels. This issue was moved from `ready` back to `backlog` for that reason. Epic KRMA-994 tracks the finding. This issue stays a child of KRMA-922.

## Additional acceptance criteria

- [ ] Before any pool lands, name the completion and presentation owners that can still read a texture after `render` returns. A window-independent test must show a texture is not handed out again while one of those owners holds it.
- [ ] If you cannot show that fence, stop and leave the per-render allocation in place. Say so in the review comment. Do not ship a pool that fails the fence.
- [ ] Do not run a display-bound capture to justify the pool.


### Comment — cursor @ 2026-10-14T16:11:01.240Z

Moved from ready back to backlog. The 2026-10-14 review says a texture pool can corrupt pixels if it reuses storage before GPU completion and outstanding presentation references are finished. Implement the pool only with that fence, and only if allocation shows up in a profile.


### Comment — claude @ 2026-10-14T23:56:44.557Z

No pool shipped; the per-render allocation in RenderEngineResources.makeProcessingTexture stays. The ticket requires proving a fence before any pool lands, and I can't. Completed textures leave the engine (RenderEngine.swift:560, :2133) and PreviewSurface retains them in at least six places: presentationTexture, transitionTexture, lastValidPresentationTexture, retainedCompleteTexture, pendingPresentationMaterialization, and the histogram readback path. Nothing in the engine is told when those owners release a texture or when GPU completion happens, so a pool could hand out storage that is still being read, which corrupts pixels. No profile shows allocation cost either. A pool would first need an explicit lease/release protocol from the presentation owners. That is a separate design task. No code changed and no tests or benchmarks were run.


### Comment — claude @ 2026-10-15T12:44:28.744Z

Closing as won't-do for now. No profile shows allocation cost, and a pool needs an explicit lease/release protocol from the presentation owners first. Design work is tracked in KRMA-1029.
