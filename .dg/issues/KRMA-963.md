---
id: KRMA-963
title: Pool or reuse GPU processing textures instead of allocating one per render
type: task
status: backlog
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
parent: KRMA-922
created: 2026-10-13T14:48:13.266Z
updated: 2026-10-13T14:48:23.984Z
blockers: []
order: zzz
board: product
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
