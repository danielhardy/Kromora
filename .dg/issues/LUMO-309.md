---
id: LUMO-309
title: Cache thumbnails as images instead of PNG round-trip
type: task
status: ready
priority: medium
labels:
  - perf
  - phase:10
  - filmstrip
created: 2026-09-09T02:38:48.554Z
updated: 2026-09-09T04:04:20.711Z
estimate: 3
order: zs
board: product
---

## Objective

Serve filmstrip/grid thumbnails from a direct image cache instead of PNG-encoding on every miss and PNG-decoding on every hit.

## Context

**Why:** Grid scroll throughput. Every cell today pays ~1-2ms + 2 allocations of pure overhead, multiplied by hundreds of cells on folder scan. The PNG round-trip exists to avoid storing `NSImage` across a lock — but the lock already exists, so store the image behind it.

**Current code:**
- `Sources/LumoKit/Models/Thumbnails.swift` — `ThumbnailByteCache(256 entries, 32MB)`, `pngData()` on miss, `image(fromPNG:)` on every hit, `defaultMaxPixelSize=240`, `CGImageSourceCreateThumbnailAtIndex` fast path. Returns `NSImage`.
- `Sources/LumoKit/Models/ImageCollection.swift` — demand-driven admission (`requestThumbnail`/`releaseThumbnail`, LazyVGrid prefetch window), `cancelThumbnailWork`, `droppedThumbnailCount`.
- Callers expect `NSImage?` — keep that signature.

## Scope / Steps

1. Replace `ThumbnailByteCache` (PNG `Data`) with a direct image cache: store `CGImage` (or `NSImage`) behind the existing `OSAllocatedUnfairLock`, with byte-cost accounting (`bytesPerRow * height`, capped at the same 32MB / 256-count budgets).
2. Keep the `CGImageSource` fast path (embedded thumbnail, orientation-baked transform) — only the *storage* changes, not the decode.
3. Preserve `releaseThumbnail` semantics (finished thumbnails stay as cheap item cache; only in-flight work cancels) and `droppedThumbnailCount` observability.
4. Verify memory: 256×240px entries ≈ small; byte cap must still bind first.

## Acceptance criteria

- [ ] `NoCodecOnHitTest`: steady-state thumbnail hits perform zero PNG encode/decode (codec call counters == 0 via test hook; static `rg 'pngData|image\(fromPNG' <hit-path>` returns empty).
- [ ] `BudgetEnforcementTest`: overfill past 32MB/256-count evicts oldest first with totals within budget (assert counts + `totalCost <= 32MB`).
- [ ] `OrientationTest`: portrait-orientation fixtures return cached images pixel-matching the direct-decode reference within the test-recorded threshold.
- [ ] `DemandRegressionTest`: scripted demand/release scroll sequence keeps `droppedThumbnailCount` at or below the baseline committed in the test (assert numeric bound).
## Verification

- `swift build` clean (zero diagnostics).
- New/updated XCTest(s) named below green.
- `scripts/ci-tests.sh fast` green.
- No human steps: done = all automated checks above pass.
## Out of scope

- Edited-thumbnail engine path (separate partition ticket).
- Changing thumbnail size or grid layout.

## Constraints

- macOS 14 minimum; Apple frameworks only (ImageIO/AppKit).
- Swift 6: `CGImage`/`NSImage` are not `Sendable` — keep them behind the lock / on MainActor exactly as today; no new opt-outs.
