---
id: KRMA-313
title: Bound skipped-drawable retries when canvas is occluded
type: task
status: done
priority: low
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "RetryBoundedTest: N consecutive presentedTime==0 produce at most 1 pending retry and zero retries after K consecutive skips"
      result: pass
    - criterion: "RestoreShowsLatestTest: visibility-restore event presents the latest revision"
      result: pass
    - criterion: "NoBlankOnReplaceTest: presented/retained image never nil across canvas replacement"
      result: pass
    - criterion: "TelemetryExclusionTest: skipped-drawable frames excluded from slow-render statistics"
      result: pass
  checks_run:
    - swift build (clean, zero diagnostics)
    - swift test --filter PreviewSurfaceTests (14 tests, 0 failures, incl. 2 new)
    - scripts/ci-tests.sh fast (665 tests, exit 0)
    - scripts/ci-tests.sh serial (321 tests, 0 failures, exit 0)
    - git diff --check (clean)
    - dg validate (OK; pre-existing unknown pickup-model warning only)
    - "grep audit: no deinit touching actor state; stopDisplayObservation remains the explicit teardown path"
    - "reviewed AppViewModel publishPreview/didPresentVisibleFrame gating: dropping superseded skipped confirmations is safe (stale guards would reject them; newer revision re-confirms)"
  findings:
    - "minor/test-coverage gap (fixed in 6c07b14): implementation had no coordinator-level test for the headline behavior — retry coalescing, K-skip suppression, and restore re-arm were untested; surface-level pending/telemetry/no-blank behavior was covered. Added testSkippedDrawRetriesAreBoundedAndQuietAfterConsecutiveSkips and testVisibilityRestoreRearmsSkippedDrawRetries plus an internal test seam on handleSkippedDrawable per repo precedent."
  fixes:
    - "Commit 6c07b14: widened PreviewSurfaceView.Coordinator.handleSkippedDrawable from private to internal with a why-comment; added two async coordinator tests driving the bounded-retry/backoff contract against a counting MTKView."
  verification_commits:
    - 6c07b14
  actor: pi
  resolved_model: openrouter/meta/muse-spark-1.3-contributor
  completed_at: 2026-09-09T17:51:59.867Z
  session: 01MTUDULFEWD30X15S
labels:
  - perf
  - phase:10
  - preview
  - stability
created: 2026-09-09T02:38:53.195Z
updated: 2026-09-10T12:53:55.847Z
estimate: 2
order: a0
board: product
commits:
  - 6c07b14
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


### Comment — codex @ 2026-09-09T17:38:57.382Z

Implemented and committed as b5a8d9e. Skipped drawables now remain pending until a real presentation, retries are coalesced to one next-runloop invalidation, and retries stop after three consecutive skips until a new revision or visibility change. Added occlusion/key visibility reset handling, preserved retained-image behavior, and tagged skipped telemetry out of presentation latency statistics. Verification: swift build; scripts/ci-tests.sh fast (665 tests); scripts/ci-tests.sh serial (319 tests); dg validate — all passed (dg validate retains the pre-existing unknown-model warning).

## Agent log

- 2026-09-09T17:51:59.867Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] RetryBoundedTest: N consecutive presentedTime==0 produce at most 1 pending retry and zero retries after K consecutive skips (pass)
- [x] RestoreShowsLatestTest: visibility-restore event presents the latest revision (pass)
- [x] NoBlankOnReplaceTest: presented/retained image never nil across canvas replacement (pass)
- [x] TelemetryExclusionTest: skipped-drawable frames excluded from slow-render statistics (pass)
Checks run:
- swift build (clean, zero diagnostics)
- swift test --filter PreviewSurfaceTests (14 tests, 0 failures, incl. 2 new)
- scripts/ci-tests.sh fast (665 tests, exit 0)
- scripts/ci-tests.sh serial (321 tests, 0 failures, exit 0)
- git diff --check (clean)
- dg validate (OK; pre-existing unknown pickup-model warning only)
- grep audit: no deinit touching actor state; stopDisplayObservation remains the explicit teardown path
- reviewed AppViewModel publishPreview/didPresentVisibleFrame gating: dropping superseded skipped confirmations is safe (stale guards would reject them; newer revision re-confirms)
Findings:
- minor/test-coverage gap (fixed in 6c07b14): implementation had no coordinator-level test for the headline behavior — retry coalescing, K-skip suppression, and restore re-arm were untested; surface-level pending/telemetry/no-blank behavior was covered. Added testSkippedDrawRetriesAreBoundedAndQuietAfterConsecutiveSkips and testVisibilityRestoreRearmsSkippedDrawRetries plus an internal test seam on handleSkippedDrawable per repo precedent.
Fixes:
- Commit 6c07b14: widened PreviewSurfaceView.Coordinator.handleSkippedDrawable from private to internal with a why-comment; added two async coordinator tests driving the bounded-retry/backoff contract against a counting MTKView.
Verification commits:
- 6c07b14
Actor: pi
Resolved model: openrouter/meta/muse-spark-1.3-contributor
Pickup session: 01MTUDULFEWD30X15S
Summary: Verified: skipped drawables stay pending until real presentation, retries coalesce to one paced invalidation and stop after 3 consecutive skips until a new revision or visibility change, retained image never blanks, and skipped frames are excluded from presentation latency stats. swift build clean; PreviewSurfaceTests 14/14 green (incl. 2 new coordinator tests); ci-tests fast (665) and serial (321) green; dg validate OK (pre-existing pickup-model warning only). One localized verification fix in 6c07b14: widened handleSkippedDrawable to internal and added bounded-retry/restore tests.
