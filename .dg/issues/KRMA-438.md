---
id: KRMA-438
title: Add filmstrip/grid consumer and RAW-path regression coverage for crop-aware thumbnail sizing
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add or extend a filmstrip/grid-level integration test that commits a small and an aspect-ratio-changing crop and asserts the settled thumbnail published to the filmstrip/library-grid surface is not softer than the original at the same displayed size.
      result: pass
      notes: ThumbnailSwitchLifecycleTests.testFilmstripAndGridPublishCropAwareSettledThumbnails uses the real RenderEngine, drives the AppViewModel/ImageCollection publication boundary, and asserts both crop cases retain the requested pixel budget and the original long edge.
    - criterion: Add a representative RAW/embedded-preview source case (or document why none is available) to the crop-aware thumbnail sizing coverage added in KRMA-434.
      result: pass
      notes: "RenderEngineTests.testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing exercises CIRAWFilter, ImageDecoder orientation, Thumbnails embedded-preview generation, and the real settle path; it XCTSkips with an explicit, actionable message when KROMORA_RAW_FIXTURE_DIR is unset (verified: skips cleanly here)."
    - criterion: Confirm (via existing benchmarks or a new focused check) that full-native-resolution thumbnail decodes triggered by extreme small crops on large RAW sources remain bounded by the existing edited-thumbnail coalescing/throttling and do not regress interactive responsiveness.
      result: pass
      notes: ThumbnailSwitchLifecycleTests.testExtremeCropUsesNativeDetailWithoutAnUnboundedThumbnailBurst drives a debounced burst of shrinking crops on a synthetic large-RAW asset (6000x4000 metadata via extension-based RAW routing + FakeRenderEngine gating), asserting exactly one trailing thumbnail request, that it clamps to factor 1.0 native detail, and that interactive preview requests continue uninterrupted while thumbnail work is gated.
  checks_run:
    - swift build
    - swift test --filter ThumbnailSwitchLifecycleTests (16/16 pass)
    - swift test --filter RenderEngineTests/testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing (skips cleanly, no fixture)
    - swift test --filter ThumbnailSwitchLifecycleTests/testExtremeCropUsesNativeDetailWithoutAnUnboundedThumbnailBurst x3 (stable, no flake)
    - scripts/ci-tests.sh fast (1054/1054 pass)
    - scripts/ci-tests.sh serial (382/382 pass, 1 skip = RAW fixture test, expected)
    - git diff --check on the verified commit (clean)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-14T14:10:48.477Z
  session: 01MU1BI7OEQQZ4KOZ2
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - thumbnail
  - crop
  - testing
created: 2026-09-14T11:12:40.928Z
updated: 2026-09-14T14:10:48.479Z
depends_on:
  - KRMA-434
order: a0
board: product
---

Parent: KRMA-434 (verification finding, non-blocking)

## Objective

Add filmstrip/grid consumer and RAW-path regression coverage for crop-aware thumbnail sizing.

## Context

KRMA-434 fixed `RenderRequest.renderScale`'s `.thumbnail` case
(`Sources/KromoraKit/Models/RenderRequest.swift`) to expand the planned source box by the committed
crop fractions, so a cropped thumbnail is decoded with enough source detail instead of being
enlarged from an under-sized full-image raster. `RenderScale.factor` already caps the resulting
scale at 1.0, so this never upscales past native pixels. The fix is centralized in one shared
computation used by every `.thumbnail`-quality `RenderRequest`, including the filmstrip and
library/grid callers that go through `AppViewModel.requestEditedThumbnail`
(`Sources/KromoraKit/ViewModels/AppViewModel.swift:2948`), so it applies uniformly by
construction — verified by reading, not by a dedicated test.

The added regression coverage (`RenderEngineTests.testCroppedThumbnailRetainsTheOriginalDisplayedPixelBudget`,
`ResolutionPlannerTests.testThumbnailScalePlansDetailForTheCroppedOutput`,
`ResolutionPlannerTests.testThumbnailScalePreservesChangingCropAspectRatio`) exercises the renderer
and the `RenderRequest.renderScale` computation directly, with a small crop and an
aspect-ratio-changing crop. It does not exercise the filmstrip/grid consumer surfaces
(`ThumbnailSwitchLifecycleTests`-style integration tests) with a committed crop, and does not cover
a RAW/embedded-preview source, both of which KRMA-434's acceptance criteria called for. This is a
test-coverage gap, not a known behavior defect: the full suite (1,033 fast + 379 serial) passes, and
the fix is architecturally shared rather than duplicated per surface.

Separately worth confirming as part of this coverage: for a crop with a very small fraction (e.g.
5% of the source), `thumbnailSourceMaxSize` computes a source box that can exceed the native
extent, so `RenderScale.factor` clamps to 1.0 and the thumbnail decode runs at full native
resolution. That is the intended fix (a small crop must not be enlarged from an under-sized
raster), but it is worth a benchmark/regression check confirming this does not make thumbnail
settlement for extreme crops of very large RAW sources meaningfully more expensive than the
existing edited-thumbnail coalescing/throttling (KRMA-292) assumes.

## Acceptance criteria

- [ ] Add or extend a filmstrip/grid-level integration test (alongside `ThumbnailSwitchLifecycleTests`
      or similar) that commits a small and an aspect-ratio-changing crop and asserts the settled
      thumbnail published to the filmstrip/library-grid surface is not softer than the original at
      the same displayed size.
- [ ] Add a representative RAW/embedded-preview source case (or document why none is available) to
      the crop-aware thumbnail sizing coverage added in KRMA-434.
- [ ] Confirm (via existing benchmarks or a new focused check) that full-native-resolution thumbnail
      decodes triggered by extreme small crops on large RAW sources remain bounded by the existing
      edited-thumbnail coalescing/throttling and do not regress interactive responsiveness.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-14T14:07:40.602Z

Implemented in commit 13d7c98: added real-engine filmstrip/grid publication coverage for small and aspect-ratio-changing crops; added optional real RAW plus embedded-preview coverage with an explicit fixture skip; and added a deterministic extreme-crop native-detail/coalescing/responsiveness regression. Verification: scripts/ci-tests.sh verify; scripts/ci-tests.sh fast (1,054/1,054); scripts/ci-tests.sh serial (382/382); focused RAW test compiles and skips here because no local RAW fixture; git diff --check.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-14T14:10:48.478Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add or extend a filmstrip/grid-level integration test that commits a small and an aspect-ratio-changing crop and asserts the settled thumbnail published to the filmstrip/library-grid surface is not softer than the original at the same displayed size. (pass) — ThumbnailSwitchLifecycleTests.testFilmstripAndGridPublishCropAwareSettledThumbnails uses the real RenderEngine, drives the AppViewModel/ImageCollection publication boundary, and asserts both crop cases retain the requested pixel budget and the original long edge.
- [x] Add a representative RAW/embedded-preview source case (or document why none is available) to the crop-aware thumbnail sizing coverage added in KRMA-434. (pass) — RenderEngineTests.testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing exercises CIRAWFilter, ImageDecoder orientation, Thumbnails embedded-preview generation, and the real settle path; it XCTSkips with an explicit, actionable message when KROMORA_RAW_FIXTURE_DIR is unset (verified: skips cleanly here).
- [x] Confirm (via existing benchmarks or a new focused check) that full-native-resolution thumbnail decodes triggered by extreme small crops on large RAW sources remain bounded by the existing edited-thumbnail coalescing/throttling and do not regress interactive responsiveness. (pass) — ThumbnailSwitchLifecycleTests.testExtremeCropUsesNativeDetailWithoutAnUnboundedThumbnailBurst drives a debounced burst of shrinking crops on a synthetic large-RAW asset (6000x4000 metadata via extension-based RAW routing + FakeRenderEngine gating), asserting exactly one trailing thumbnail request, that it clamps to factor 1.0 native detail, and that interactive preview requests continue uninterrupted while thumbnail work is gated.
Checks run:
- swift build
- swift test --filter ThumbnailSwitchLifecycleTests (16/16 pass)
- swift test --filter RenderEngineTests/testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing (skips cleanly, no fixture)
- swift test --filter ThumbnailSwitchLifecycleTests/testExtremeCropUsesNativeDetailWithoutAnUnboundedThumbnailBurst x3 (stable, no flake)
- scripts/ci-tests.sh fast (1054/1054 pass)
- scripts/ci-tests.sh serial (382/382 pass, 1 skip = RAW fixture test, expected)
- git diff --check on the verified commit (clean)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU1BI7OEQQZ4KOZ2
Summary: Independent verification: filmstrip/grid, RAW/embedded-preview (documented skip), and extreme-crop throttling coverage all added and passing; fast 1054/1054, serial 382/382, no regressions, no blocking findings.
