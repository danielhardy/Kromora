---
id: LUMO-311
title: Remove zero-fill memset on prefix materialization
type: task
status: ready
priority: low
labels:
  - perf
  - phase:10
  - render
created: 2026-09-09T02:38:50.875Z
updated: 2026-09-09T04:04:28.420Z
estimate: 2
order: zx
board: product
---

## Objective

Remove the full-buffer zero-fill (`memset`) on every processing-prefix materialization.

## Context

**Why:** Small, certain, per-settle saving. `~15MB memset` at 2MP RGBA half-float on every prefix materialization is pure overhead — `CIContext.render(toBitmap:)` overwrites the whole buffer unconditionally.

**Current code:**
- `Sources/LumoKit/Models/RenderEngine.swift` — `materializedImage()`: `Data(repeating: 0, count: cpuBytes)` immediately followed by `context.render(preLUT, toBitmap: &cpu, rowBytes:bounds:...)`.
- Budget context lives in `Sources/LumoKit/Models/RenderScale.swift` + `RenderCacheConfiguration` (prefix 4 / 256MB).

## Scope / Steps

1. Replace zero-filled allocation with uninitialized allocation or a pooled-buffer reuse (`Data(count:)` still zeroes — use `UnsafeMutableRawPointer.allocate` + `render(toBitmap:)` + `Data(bytesNoCopy:...deallocator:)` or a small pool keyed by byte size).
2. Prove safety: every byte is written by the render before any read (rowBytes/bounds cover the full allocation; no partial-render path reads unwritten tails).
3. If pooling: cap pool size (1-2 buffers), clear on memory pressure alongside existing `didReceiveMemoryWarning` eviction.

## Acceptance criteria

- [ ] `NoZeroFillStaticTest`: automated invariant — `rg 'Data\(repeating: 0|Data\(count:' Sources/LumoKit/Models/RenderEngine.swift` (scoped to the `materializedImage` hot path) returns empty; the test/script fails on match.
- [ ] `OutputIdenticalTest`: fixture-set outputs are byte/pixel-identical before/after (assert equal hashes; catches uninitialized-read artifacts deterministically).
- [ ] `PoolBoundedTest`: if pooling is used, capacity <= 2 buffers and a simulated memory warning clears the pool (assert counts); if no pooling, assert single-allocation path with uninitialized memory.
## Verification

- `swift build` clean (zero diagnostics).
- Static `rg` invariant script green + new/updated XCTest(s) above green.
- `scripts/ci-tests.sh fast` green.
- Code review is supplementary, never gating: done = all automated checks above pass.
## Out of scope

- Texture-backed prefix (separate, larger ticket — this is the cheap CPU win first).
- Changing prefix keying or budget sizes.

## Constraints

- macOS 14 minimum; Apple frameworks only.
- Swift 6: unsafe-pointer code must be strictly scoped (no escaping pointers, no `nonisolated(unsafe)` globals). If it cannot be expressed safely, close as wont-do with a note rather than forcing it.
