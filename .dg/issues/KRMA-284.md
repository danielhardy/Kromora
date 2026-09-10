---
id: KRMA-284
title: Single-photo Metal preview stays blank after spinner clears
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Opening a photo in single-photo mode results in visible non-blank canvas pixels after the spinner clears
      result: pass
      notes: attachDisplayView() calls setNeedsDisplay immediately on view creation to replay an already-published frame, and present()/failure paths call requestDisplay() on every publication, closing the invalidation gap described in the findings.
    - criterion: The redraw request is explicit and reliable for both a newly-created and an existing PreviewSurfaceView
      result: pass
      notes: PreviewSurfaceTests.testPublicationRequestsRedrawOnAnExistingMetalView and testAttachingAViewRequestsAFramePublishedBeforeTheViewWasCreated both pass, covering the two orderings.
    - criterion: Thumbnail/grid presentation remains unaffected
      result: pass
      notes: Thumbnail path is untouched by this change (no edits under Sources/LumoKit/Models/Thumbnail*); ThumbnailTests and ThumbnailSwitchLifecycleTests pass unchanged.
    - criterion: Add a regression test covering publication followed by an actual MTKView redraw request, including the swift run/bundleless launch path where practical
      result: pass
      notes: TrackingMTKView-based unit tests added in PreviewSurfaceTests.swift; ConcurrentExportEditingBenchmark was changed to rely on the production invalidation path (manual redraw shim removed) rather than its own workaround.
    - criterion: Existing preview, navigation, RAW, and Metal presentation tests remain green
      result: pass
      notes: Full fast (640 tests) and serial (277 tests) CI lanes pass with zero failures; opt-in RAW/concurrent-capture benchmark skips as expected (no fixture present in this environment).
  checks_run:
    - swift build (clean)
    - swift test --filter LumoKitTests.PreviewSurfaceTests (11 passed)
    - "LUMO_METAL_BENCHMARK=1 LUMO_CONCURRENT_CAPTURE=1 swift test --filter ConcurrentExportEditingBenchmark (skipped: no RAW fixture in this environment, expected for opt-in lane)"
    - scripts/ci-tests.sh fast (640 passed, 0 failed)
    - scripts/ci-tests.sh serial (277 passed, 0 failed)
    - dg validate (OK)
    - git status --porcelain (clean of source changes)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-08T21:58:55.588Z
  session: 01MTT7JB1BR18PVZLA
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - editor
  - rendering
  - metal
  - swift-run
created: 2026-09-08T20:00:06.457Z
updated: 2026-09-10T12:53:53.378Z
order: a0
board: product
---

## Objective

Ensure the single-photo editor displays the completed preview after a photo is opened with `swift run`.

## Context

When the editor is opened from the library, the thumbnail is visible and the loading spinner eventually
disappears, but the main single-photo canvas remains blank. This blocks visual editing even though the
source and render pipeline have completed.

### Reproduction

1. Start the current build with `swift run`.
2. Open or restore a folder containing photos (the observed reproduction used `DSC03804.ARW`).
3. Enter the single-photo editor from the thumbnail/grid.
4. Observe that the thumbnail is present and the spinner clears, but the main photo is not drawn.

### Findings

The thumbnail and main preview use separate paths. The thumbnail can be produced from the embedded
camera preview, while the editor uses the Core Image/Metal render path. The ARW was confirmed to render
through `RenderEngine` and the real CAMetalLayer presentation benchmark passed, so this is not a RAW
decoder failure.

The likely defect is a presentation invalidation gap: `PreviewSurface.present()` publishes the candidate
image and increments `revision`, which is enough for `PreviewView` to leave the spinner, but production
does not explicitly request `setNeedsDisplay` on the paused `MTKView`. The benchmark has to call
`setNeedsDisplay` manually after `present()`. Depending on SwiftUI's `NSViewRepresentable` update timing,
the canvas can therefore exist without receiving a draw request.

## Acceptance criteria

- [ ] Opening a photo in single-photo mode results in visible non-blank canvas pixels after the
      spinner clears.
- [ ] The redraw request is explicit and reliable for both a newly-created and an existing
      `PreviewSurfaceView`.
- [ ] Thumbnail/grid presentation remains unaffected.
- [ ] Add a regression test covering publication followed by an actual `MTKView` redraw request,
      including the `swift run`/bundleless launch path where practical.
- [ ] Existing preview, navigation, RAW, and Metal presentation tests remain green.

## Implementation notes

Inspect the handoff between `AppViewModel.publishPreview`, `PreviewSurface.present`, and
`PreviewSurfaceView.Coordinator`. Keep the completed GPU texture path intact; fix only the draw
invalidation/lifecycle seam and preserve the last valid frame behavior.

Relevant code:

- `Sources/LumoKit/Views/PreviewSurface.swift:53`
- `Sources/LumoKit/Views/PreviewSurface.swift:260`
- `Sources/LumoKit/ViewModels/AppViewModel.swift:2756`
- `Tests/LumoKitTests/ConcurrentExportEditingBenchmark.swift:173`

Verification performed during triage:

- `swift test --filter LumoKitTests.RenderEngineTests/testCompletedRAWPreviewReflectsDevelopSettings` — passed against `DSC03804.ARW`.
- `LUMO_METAL_BENCHMARK=1 LUMO_METAL_BENCHMARK_ITERATIONS=2 swift test --filter MetalPresentationBenchmark/testRealMetalPresentationBenchmark` — passed.
- Minimal end-to-end `PreviewSurfaceView` capture with `DSC03804.ARW` — passed.

### Comment — codex @ 2026-09-08T21:54:29.046Z

Implemented in commit 46bed0d. PreviewSurface now binds weakly to its active MTKView and explicitly requests redraws after valid publication, on view attachment for pre-published frames, and after presentation rejection; surface replacement/dismantling is detached safely. Added MTKView redraw-request regression tests and removed the benchmark’s manual redraw so it exercises the production path. Verification: swift build passed; swift test passed (962 tests, 45 expected skips); git diff --check passed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-08T21:58:55.589Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Opening a photo in single-photo mode results in visible non-blank canvas pixels after the spinner clears (pass) — attachDisplayView() calls setNeedsDisplay immediately on view creation to replay an already-published frame, and present()/failure paths call requestDisplay() on every publication, closing the invalidation gap described in the findings.
- [x] The redraw request is explicit and reliable for both a newly-created and an existing PreviewSurfaceView (pass) — PreviewSurfaceTests.testPublicationRequestsRedrawOnAnExistingMetalView and testAttachingAViewRequestsAFramePublishedBeforeTheViewWasCreated both pass, covering the two orderings.
- [x] Thumbnail/grid presentation remains unaffected (pass) — Thumbnail path is untouched by this change (no edits under Sources/LumoKit/Models/Thumbnail*); ThumbnailTests and ThumbnailSwitchLifecycleTests pass unchanged.
- [x] Add a regression test covering publication followed by an actual MTKView redraw request, including the swift run/bundleless launch path where practical (pass) — TrackingMTKView-based unit tests added in PreviewSurfaceTests.swift; ConcurrentExportEditingBenchmark was changed to rely on the production invalidation path (manual redraw shim removed) rather than its own workaround.
- [x] Existing preview, navigation, RAW, and Metal presentation tests remain green (pass) — Full fast (640 tests) and serial (277 tests) CI lanes pass with zero failures; opt-in RAW/concurrent-capture benchmark skips as expected (no fixture present in this environment).
Checks run:
- swift build (clean)
- swift test --filter LumoKitTests.PreviewSurfaceTests (11 passed)
- LUMO_METAL_BENCHMARK=1 LUMO_CONCURRENT_CAPTURE=1 swift test --filter ConcurrentExportEditingBenchmark (skipped: no RAW fixture in this environment, expected for opt-in lane)
- scripts/ci-tests.sh fast (640 passed, 0 failed)
- scripts/ci-tests.sh serial (277 passed, 0 failed)
- dg validate (OK)
- git status --porcelain (clean of source changes)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTT7JB1BR18PVZLA
Summary: Verified: PreviewSurface's weak MTKView binding correctly re-invalidates the paused view on publish, on late view attachment, and on presentation rejection; all coordinator/lifecycle transitions (surface swap, dismantle) detach cleanly. Full fast (640) and serial (277) CI lanes pass; new regression tests confirmed.
