---
id: LUMO-306
title: Render interactive drag frames at 8-bit, settle at 16F
type: task
status: ready
priority: medium
labels:
  - perf
  - phase:10
  - preview
created: 2026-09-09T02:38:45.105Z
updated: 2026-09-09T04:03:59.425Z
estimate: 3
order: zh
board: product
---

## Objective

Render interactive (slider-drag) frames at 8-bit texture precision; promote to 16F only on settle.

## Context

**Why:** ~2x texture bandwidth/allocation saving inside the 16.7ms interactive budget (`frameBudgetMilliseconds` in `RenderScale.interactive`). Halves the pressure that forces `interactiveMaxPixelSize` down on large files.

**Current code:**
- `Sources/LumoKit/Models/RenderEngine.swift` — `makePreviewTexture()` (~line 1130): descriptor `.rgba16Float, .private, [.shaderRead,.shaderWrite,.renderTarget]` for both `.interactive` and `.preview`; `commitAndWaitForCompletion`.
- `Sources/LumoKit/Models/RenderScale.swift` — `.interactive(maxSize, budget: 1_500_000 * safeBudget/16.7)` vs `.preview(maxSize)`; quality `.interactive` vs `.preview`.
- `Sources/LumoKit/ViewModels/PreviewCoordinator.swift` — interactive/settle two-phase publish; settle always follows, so transient 8-bit banding self-corrects.
- Export/full path uses separate `.full` float handling — do not touch.

## Scope / Steps

1. Parameterize the preview texture pixel format by quality: `.interactive` → `rgba8Unorm` (or `bgra8Unorm` to match drawable), `.preview`/`.full`/`.thumbnail` unchanged.
2. Verify the 8-bit path through `CIContext(mtlCommandQueue:)` render-to-texture + `PreviewSurface` presentation (working-space tags, no double conversion).
3. Keep the interactive pixel-budget math valid: either keep the same budget (free headroom) or document the new effective budget. Do not silently change `ResolutionPlanner` levels in this ticket.
4. Confirm no banding persists past settle (settle is still 16F → final conversion).

## Acceptance criteria

- [ ] `InteractiveDescriptorTest`: interactive-quality request produces an 8-bit texture descriptor (`rgba8Unorm`/`bgra8Unorm`); preview-quality request produces `rgba16Float` (assert pixelFormat per quality).
- [ ] `SettleQualityTest`: settled output on the sky-gradient stress fixture vs the 16F reference has max per-pixel delta <= test-recorded threshold.
- [ ] `BandwidthStructureTest`: interactive texture byte count (`bytesPerRow * height`) is half the 16F equivalent (assert ratio; `presentationEncodingMS` may be recorded informationally but never gates).
- [ ] `ExportUnchangedTest`: export output bytes identical before/after.
## Verification

- `swift build` clean (zero diagnostics).
- New/updated XCTest(s) named below green.
- `scripts/ci-tests.sh fast` green.
- Benchmark (informational, never gating): `presentationEncodingMS` / interactive fps during an exposure drag, Release build, same machine/dataset, before/after in the agent log (use the LUMO-057 harness if it exists).
- No human steps: done = all automated checks above pass.
## Out of scope

- Changing budget constants or planner levels.
- Drawable format changes.

## Constraints

- macOS 14 minimum; Metal/CoreImage only.
- Swift 6: texture stays actor-confined in `RenderEngine`.
