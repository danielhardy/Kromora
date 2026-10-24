---
id: KRMA-815
title: Bin the Info histogram from the presentation texture during live edits
type: task
status: done
priority: urgent
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Bins come from a ≤512 long-edge downsample of the presentation texture, working color space, BGRA swapped
      result: pass
      notes: encodeHistogramSample renders the texture-wrapped CIImage (not the source graph) into a ≤512 shared texture in the same command buffer, blits to a shared buffer; HistogramData(bgra8:) swaps channels.
    - criterion: Source preview CIImage not re-rendered; engine.histogram not used for frames with a texture sample
      result: pass
      notes: Admission publishes the .sample state or waits on .pending; engine fallback only on .unavailable or no sample.
    - criterion: During drag the histogram follows interactive frame; newer revision wins
      result: pass
      notes: Surface revision checked in isCurrentHistogram and sample change callbacks; stale-interactive tests pass.
    - criterion: Exact stored-frame, comparison, crop, gating, loading, failure behavior unchanged; Auto/global tone use source API
      result: pass
      notes: Exact-stored path and API untouched; retry-from-texture on failure, then existing unavailable message.
    - criterion: Fake-engine tests pass via fallback; new tests cover channel order, no second render, stale rejection
      result: pass
      notes: HistogramTests, PreviewSurfaceTests, PreviewAdmissionCoordinatorTests added/extended and pass.
  checks_run:
    - scripts/ci-tests.sh warning-gate (pass)
    - scripts/ci-tests.sh fast (1520 tests, pass)
    - swift test --filter ThumbnailSwitchLifecycleTests|AdjustInspectorTests|HistogramTests|PreviewSurfaceTests|PreviewAdmissionCoordinatorTests (113 tests, 0 failures)
    - git diff --check (clean)
    - dg validate (only unrelated pre-existing warnings)
    - swift format lint (warnings only; mostly pre-existing in touched files)
  findings:
    - "Low, non-blocking: sample CPU tally copies and swizzles a ≤512px buffer on the completion handler thread; small cost, acceptable."
    - "Low, non-blocking: swift format lint reports indentation warnings in touched files; the baseline already has many."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-04T15:06:55.113Z
  session: 01MUTYACBTEP4YFZFS
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - performance
created: 2026-10-04T12:53:49.626Z
updated: 2026-10-04T15:06:55.116Z
blockers: []
order: a0
board: product
context:
  files:
    - Sources/KromoraKit/Views/PreviewSurface.swift
    - Sources/KromoraKit/Models/RenderEngine+Histogram.swift
    - Sources/KromoraKit/Models/Histogram.swift
    - Sources/KromoraKit/Models/RenderEngine.swift
    - Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift
    - Sources/KromoraKit/ViewModels/PreviewPublicationCoordinator.swift
    - Sources/KromoraKit/ViewModels/AppViewModel.swift
    - Tests/KromoraKitTests/FakeRenderEngine.swift
    - Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift
    - Tests/KromoraKitTests/AdjustInspectorTests.swift
  docs:
    - docs/TESTING.md
    - CLAUDE.md
  issues:
    - KRMA-759
    - KRMA-760
  commands:
    - scripts/ci-tests.sh warning-gate
    - scripts/ci-tests.sh fast
    - swift test --filter ThumbnailSwitchLifecycleTests
    - swift test --filter AdjustInspectorTests
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-04T15:02:52.603Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Make the Info histogram update with the image during live edits, including on large photos with complex local masks. Count bins from the presentation texture that is already being drawn, instead of rendering the preview graph a second time.

## What is slow

The canvas and the chart do not share pixels today.

`PreviewSurface.makePresentationTexture` renders the presented `CIImage` once, on `RenderEngine.presentationContext`, into a private `bgra8Unorm` texture at the preview image's extent. The view then samples that texture. That render is the image the user sees, and on a large masked photo it lands in under a second.

The Info histogram ignores that texture. After the frame is confirmed, `PreviewAdmissionCoordinator.scheduleHistogram` calls `RenderEngine.histogram(presentedImage:)`, which runs on the engine actor's separate `CIContext`. `tallyHistogram` scales the original graph so the long edge is at most 512 and renders it to a CPU RGBA8 bitmap. "Does not rebuild the graph" only means it does not call `buildImage` again. `context.render` still evaluates whatever nodes are in the `CIImage`.

Those nodes still include local masks unless they were baked. `postLocalProcessingPrefix` materializes the post-mask graph only when the layer stack has a semantic mask (`resolvedLocalMasks` sets `cacheIdentity` only then). Brush, gradient, range, and luminance masks stay live. Each layer runs its own light, color, and clarity, then blends. The 512 px cap does not remove that work, and the presentation context's intermediates are not visible to the engine context. On a very large image with a complex mask stack this second render takes about 1–2 seconds, longer than the image itself.

Live edits make that worse. `scheduleInteractivePreview` calls `cancelHistogram(clear: false)` on every slider tick, then the next presented frame starts another full tally. The tally cannot finish inside one tick, so the chart stays on the pre-drag image until the gesture pauses.

KRMA-759 measured an ordinary warm photo switch at about 53 ms of histogram compute and correctly left the kernel alone. Those numbers do not cover this case. Do not repeat that queue-priority experiment, and do not close this ticket by citing them.

## Required behavior

- While the user drags an edit, the histogram describes the interactive frame on screen, then replaces that with the settled frame when the settled render is presented. It must not remain on the pre-drag image for the whole gesture.
- The chart describes the same pixels as the image: the graded preview, or the comparison baseline with no Look while showing the original. It is the presented preview image, not the letterboxed drawable and not a viewport crop that the current tally does not already use.
- A newer frame wins. A sample for an older surface revision must not publish over a newer photo, document, Look, or revision.
- Opening the inspector onto a frame that already has a sample publishes that sample. It must not start a second graph render.

## Implementation direction

Put the histogram sample in the same presentation command buffer as the display texture.

1. After `makePresentationTexture` encodes the full preview into its BGRA texture, encode a downsample of **that texture** into a small buffer whose long edge is at most 512. Preserve aspect ratio. Do this in the same command buffer.
2. Sample the texture. Do not call `CIContext.render` on the source `CIImage` a second time, at 512 px or otherwise. A second render of the original graph, even in the same buffer, evaluates the mask stack again and does not fix the bug.
3. The display texture is `.private`. Read back only the small image, via shared or managed storage, or a blit into a shared buffer. Do not `getBytes` a private texture.
4. The texture is BGRA. `HistogramData.init(rgba8:)` expects RGBA and computes Rec.709 luma from those channels. Swap red and blue before binning. The presentation render already uses the frame's working color space, so do not convert again.
5. On completion, publish the `HistogramData` through the existing admission checks (`HistogramIdentity`, asset id, source revision, inspector visibility, display document, Look). Tie the sample to the same surface revision `presentationTextureMaterializationCompleted` uses, and drop it when that revision is no longer current.
6. When a sample for the current frame is published, do not also enqueue `engine.histogram(presentedImage:)` for that frame.
7. `scheduleInteractivePreview` must not discard the sample for the frame that is about to appear. Submitting a newer interactive render only supersedes an older sample once the newer sample is published or the older revision is no longer current. `cancelHistogram` may still cancel an obsolete engine-context tally.
8. If `makePresentationTexture` returns nil (no Metal texture, or a test renderer that never materializes one), keep the current `engine.histogram(presentedImage:)` fallback so the chart still appears. The production path that successfully builds a texture must not use that fallback for the same frame.
9. Keep `admitExactStoredFrameHistogramIfAvailable` for an exact stored frame before a live source exists. That path already tallies a bitmap. Do not send it back through the mask graph. Once the live frame's texture sample exists, identity dedup should keep the two from doing duplicate work.

The sample is small next to the preview render, so attach it to every presentation, including while the inspector is hidden. Publish only when the existing inspector and identity gates pass. A retained sample whose identity still matches should satisfy `updateHistogram` when the inspector opens.

`HistogramData` is `Sendable`. Read bytes before hopping to the main actor. Do not move a `CIImage`, `CIContext`, or `MTLTexture` across that hop. Swift 6 language mode stays on: no `@unchecked Sendable`, `nonisolated(unsafe)`, or `@preconcurrency`.

## Preserve

- Info-histogram consumers stay on `AppViewModel.histogram`: the inspector chart, the clipped-highlight badges in `PreviewView`, and the luminance-range backdrop in `MaskingWorkspace`.
- Comparison, crop-tool, and exact-stored-frame gates in `isCurrentHistogram` and `admitExactStoredFrameHistogramIfAvailable`.
- A nil histogram still means loading, cancellation, or failure. Keep `isHistogramLoading` and `histogramErrorMessage`. A failed sample on a frame whose texture succeeded should retry from that texture, not re-render the graph. If there is nothing to bin, the existing unavailable message remains.
- `RenderEngine.histogram(source:document:lut:scale:space:maxDimension:)` is a different API. `AutoWorkflowCoordinator` and `GlobalToneAnalyzer` still call it. Do not change those callers.

## Out of scope

- Lowering `maxDimension`, raising histogram scheduler priority, or starting the current engine-context tally earlier. KRMA-759 already showed queue order is not this delay.
- Baking every non-semantic mask into `postLocalProcessingPrefix`. That would add cost to the preview path and is not required once the chart reads the texture.
- Display-bound captures. Do not run `scripts/run-kromora-capture.sh` or `LastKnownFrameReleaseBenchmark`.

## Tests

Existing fake-engine coverage must stay green. It drives the fallback, not the texture path:

- `Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift` waits on `viewModel.histogram` and `FakeRenderEngine.histogramRequests` / histogram completion events for the selected photo.
- `Tests/KromoraKitTests/AdjustInspectorTests.swift` `testTheColorTabUpdatesThePinnedHistogram` expects a histogram request whose document contains the edited exposure.

Add deterministic coverage for the new path:

- Binning swaps BGRA to RGBA and caps the long edge at 512.
- A presented frame that carries a texture sample publishes that `HistogramData` and does not enqueue `histogram(presentedImage:)`.
- Two interactive frames with different edits: the later sample wins, and an older completion cannot overwrite it. The chart updates for the interactive frame rather than only after the gesture ends.
- Opening the inspector with a retained matching sample does not enqueue an engine histogram.
- The nil-texture fallback still enqueues `histogram(presentedImage:)` once.

## Acceptance criteria

- [ ] On a production presentation that builds a texture, Info-histogram bins come from a ≤512 long-edge downsample of that texture, in the frame's working color space, with BGRA channels swapped to match `HistogramData`.
- [ ] That path does not render the source preview `CIImage` again. `engine.histogram(presentedImage:)` is not used for a frame that already has a texture sample.
- [ ] During an edit drag, the published histogram follows the interactive frame on screen and then the settled frame. A newer revision wins. The chart does not stay on the pre-drag image until the drag ends.
- [ ] Exact stored-frame admission, comparison/original, crop-tool refusal, inspector gating, loading, and failure behavior are unchanged. Auto and global-tone analysis still use the source/document histogram API.
- [ ] Fake-engine histogram identity tests still pass via the no-texture fallback, and new tests cover channel order, sample publication without a second render, and stale-revision rejection.

## Verification

Do not run the display-bound capture harness. Before handoff, run the histogram and preview suites you touch, `scripts/ci-tests.sh warning-gate`, `scripts/ci-tests.sh fast`, `swift format lint` on changed Swift files, `git diff --check`, and `dg validate`.

Commit on the current branch with a subject that starts `KRMA-815:`. Do not push. Do not stash, reset, or revert unrelated working-tree changes. Hand off to `review` with a short comment. Do not mark the issue done.


### Comment — codex @ 2026-10-04T15:02:52.110Z

Implemented bounded BGRA histogram readback from the presentation texture in the same command buffer, with revision-safe admission, retry from retained textures, and engine fallback for unavailable texture samples. Added channel-order, sample-size, stale-interactive, retained-sample, and fallback coverage. Verification passed: warning-gate, fast (1,520 tests), HistogramTests (12), PreviewSurfaceTests (46), PreviewAdmissionCoordinatorTests (17), focused warm-reopen, dg validate, and diff check. Commit: 624a01b4.

## Agent log

- 2026-10-04T15:06:55.113Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Bins come from a ≤512 long-edge downsample of the presentation texture, working color space, BGRA swapped (pass) — encodeHistogramSample renders the texture-wrapped CIImage (not the source graph) into a ≤512 shared texture in the same command buffer, blits to a shared buffer; HistogramData(bgra8:) swaps channels.
- [x] Source preview CIImage not re-rendered; engine.histogram not used for frames with a texture sample (pass) — Admission publishes the .sample state or waits on .pending; engine fallback only on .unavailable or no sample.
- [x] During drag the histogram follows interactive frame; newer revision wins (pass) — Surface revision checked in isCurrentHistogram and sample change callbacks; stale-interactive tests pass.
- [x] Exact stored-frame, comparison, crop, gating, loading, failure behavior unchanged; Auto/global tone use source API (pass) — Exact-stored path and API untouched; retry-from-texture on failure, then existing unavailable message.
- [x] Fake-engine tests pass via fallback; new tests cover channel order, no second render, stale rejection (pass) — HistogramTests, PreviewSurfaceTests, PreviewAdmissionCoordinatorTests added/extended and pass.
Checks run:
- scripts/ci-tests.sh warning-gate (pass)
- scripts/ci-tests.sh fast (1520 tests, pass)
- swift test --filter ThumbnailSwitchLifecycleTests|AdjustInspectorTests|HistogramTests|PreviewSurfaceTests|PreviewAdmissionCoordinatorTests (113 tests, 0 failures)
- git diff --check (clean)
- dg validate (only unrelated pre-existing warnings)
- swift format lint (warnings only; mostly pre-existing in touched files)
Findings:
- Low, non-blocking: sample CPU tally copies and swizzles a ≤512px buffer on the completion handler thread; small cost, acceptable.
- Low, non-blocking: swift format lint reports indentation warnings in touched files; the baseline already has many.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUTYACBTEP4YFZFS
Summary: Verified texture-based Info histogram sampling; fast lane, warning gate and 113 targeted tests pass.
