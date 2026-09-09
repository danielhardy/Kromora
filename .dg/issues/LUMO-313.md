---
id: LUMO-313
title: Bound skipped-drawable retries when canvas is occluded
type: task
status: ready
priority: low
labels:
  - perf
  - phase:10
  - preview
  - stability
created: 2026-09-09T02:38:53.195Z
updated: 2026-09-09T04:04:35.725Z
estimate: 2
order: zt
board: product
---

## Objective

Stop the skipped-drawable retry loop from spinning extra GPU work while the canvas is occluded, screen-sharing, or being replaced by SwiftUI.

## Context

**Why:** Stability + correctness-as-performance. `presentedTime==0` (no vsync) currently triggers an immediate `setNeedsDisplay` retry with no backoff — while headless/occluded this manufactures GPU churn and pollutes render telemetry with false "slow" samples.

**Current code:**
- `Sources/LumoKit/Views/PreviewSurface.swift` — `markDrawablePresented(time==0)` → `retrySkippedDraw()` → `setNeedsDisplay`, `skippedDrawNeedsRetry` flag, `lastValidImage` retention (good — keep), fallback-present hook used by tests.
- Producer gating in `Sources/LumoKit/ViewModels/AppViewModel.swift` — `didPresentVisibleFrame` only fires on real presentation (comparison/histogram wait on it — correct, keep).
- Telemetry: `previewCoordinator.telemetry`, `presentationEncodingMS` per revision.

## Scope / Steps

1. Coalesce skipped-drawable retries: max one pending retry, paced to the next runloop/vsync (or display-link tick) instead of immediate re-draw. No unbounded `setNeedsDisplay` loop.
2. Distinguish transient skip (one frame) from sustained occlusion (N consecutive skips → stop retrying until the next new revision or visibility change).
3. Keep `lastValidImage` behavior (no blanking) and the test fallback hook.
4. Optionally tag telemetry so skipped-then-retried frames are excluded from "slow render" stats.

## Acceptance criteria

- [ ] `RetryBoundedTest`: N consecutive `presentedTime == 0` events produce at most 1 pending retry and zero retries after K consecutive skips (assert `setNeedsDisplay` call count bounded; quiet thereafter).
- [ ] `RestoreShowsLatestTest`: a visibility-restore event presents the latest revision (assert present called with latest revision ID and zero additional triggers).
- [ ] `NoBlankOnReplaceTest`: across a simulated SwiftUI canvas-replacement sequence the presented/retained image is never nil (assert nil-gap count == 0).
- [ ] `TelemetryExclusionTest`: skipped-drawable frames are excluded from slow-render statistics (assert stats query over a skip-containing session).
## Verification

- `swift build` clean (zero diagnostics).
- New/updated XCTest(s) named above green (bounded-retry, restore-presents-latest, no-nil-gap, telemetry exclusion).
- `scripts/ci-tests.sh fast` + `serial` (AppKit/UI lane) green.
- No manual minimize/occlude: done = all automated checks above pass.
## Out of scope

- Textured-quad presentation itself (separate ticket).
- Changing confirmation gating for histogram/comparison.

## Constraints

- macOS 14 minimum; AppKit/Metal only.
- Swift 6: view teardown via explicit method (see `KeyMonitor.stop()`), never `deinit` touching actor state. No opt-outs.
