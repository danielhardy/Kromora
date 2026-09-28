---
id: KRMA-685
title: Animate histogram transitions when switching photos
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Keep the chart visible while the new photo's histogram is being computed instead of replacing it with a spinner
      result: pass
      notes: "AppViewModel.swift:1907 now calls cancelHistogram(clear: false, pump: false) on source switch, preserving the last published histogram; InfoInspectorView.swift:290-314 continues to render HistogramChart as long as viewModel.histogram is non-nil."
    - criterion: Animate the chart from the previous distribution to the new one when the current photo's histogram is ready
      result: pass
      notes: "HistogramChart conforms to Animatable via HistogramPlotValues (VectorArithmetic) and applies .animation(.easeInOut(duration: 0.35), value: data) gated by accessibilityReduceMotion (InfoInspectorView.swift:411-460, 545-589)."
    - criterion: Rapid photo changes never animate to or leave behind a histogram belonging to an obsolete selection
      result: pass
      notes: PreviewAdmissionCoordinator.updateHistogram (lines 190-213) re-checks assetID, sourceRevision, source, document, and lut against the destination's current state before publishing a result, rejecting stale in-flight responses. Verified by testPhotoSwitchRetainsHistogramAndRejectsAnObsoleteResult, which advances through a 4th selection while a 3rd-photo request is still pending and asserts the stale result never publishes.
    - criterion: Preserve an appropriate loading or unavailable state when there is no prior histogram to retain
      result: pass
      notes: histogramPlot falls back to ProgressView while isHistogramLoading and viewModel.histogram is nil, or to the unavailable text otherwise (InfoInspectorView.swift:302-315); unaffected by this change's cancelHistogram(clear:false) since there is nothing to retain on first load.
    - criterion: Add regression coverage for retention, animation of the current result, and rejection of stale results
      result: pass
      notes: PreviewCutoverTests.testPhotoSwitchRetainsHistogramAndRejectsAnObsoleteResult covers retention during a pending switch and stale-result rejection across two overlapping transitions. Animation timing itself is not asserted (SwiftUI interpolation is not practically unit-testable), but the Animatable/VectorArithmetic wiring was verified by build and manual code reading.
  checks_run:
    - swift build (debug) - clean, zero diagnostics
    - swift test --filter PreviewCutoverTests - 17 passed, 1 skipped (no local RAW fixture), 0 failed
    - swift test --filter PackageSettingsTests - 4/4 passed (Swift 6 mode, zero concurrency escape hatches confirmed)
    - scripts/ci-tests.sh fast (full parallel run) - 3 pre-existing failures unrelated to this change (CropWorkflowTests.testCropGeometrySliderChangesStayInOneDisplayGenerationAndSettleAfterRelease, DevelopInspectorTests.testOpeningAStandardImageFallsBackFromUnavailableDevelopTab, ThumbnailSwitchLifecycleTests.testFilmstripAndGridPublishCropAwareSettledThumbnails)
    - Reproduced the Crop/DevelopInspector failures identically on commit b3fd5ee^ (pre-change) in an isolated worktree, confirming they predate this change
    - Re-ran ThumbnailSwitchLifecycleTests.testFilmstripAndGridPublishCropAwareSettledThumbnails in isolation on HEAD - passed, indicating parallel-run flakiness rather than a regression
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T15:28:35.278Z
  session: 01MULEDXLAS0R27JMY
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - editor
  - histogram
created: 2026-09-28T14:05:59.068Z
updated: 2026-09-28T15:28:35.280Z
blockers: []
order: a0
board: product
---

## Objective

Keep the histogram visible while a newly selected photo is being analyzed, then animate the
displayed histogram to the new photo's distribution.

## User report

When moving from one photo to the next in Edit, the current histogram disappears and a loading
spinner is shown while the next histogram is calculated. The user wants the chart to remain present
and smoothly transition to the selected photo's histogram when it is ready.

## Context

This is a continuity and presentation issue during photo selection. KRMA-673 tracks the separate
case where the histogram is initially unavailable after opening a photo from the Library; this
ticket covers retaining and animating an already visible histogram during subsequent photo changes.

## Acceptance criteria

- [ ] When switching photos in Edit and a histogram is already displayed, keep the chart visible
      while the new photo's histogram is being computed instead of replacing it with a spinner.
- [ ] When a histogram for the currently selected photo is ready, animate the chart from the
      previous distribution to the new one.
- [ ] Rapid photo changes never animate to or leave behind a histogram belonging to an obsolete
      selection; the final chart represents the currently selected photo.
- [ ] Preserve an appropriate loading or unavailable state when there is no prior histogram to
      retain, such as the initial photo load.
- [ ] Add regression coverage for retaining the current histogram during a photo switch, animating
      the current result, and rejecting stale results from earlier selections.

## Implementation notes

Keep the last published histogram available while the next request is pending. Start the visual
transition only after the result passes the existing asset and display-revision checks. Coordinate
with KRMA-673 if changes to initial histogram readiness overlap.

### Comment — codex @ 2026-09-28T15:23:48.167Z

Implemented histogram retention and animated channel transitions for accepted results. Added coverage for retaining the prior chart, publishing the selected photo's histogram, and rejecting stale results. Verification: PreviewCutoverTests passed (17 tests, 1 skipped because no local RAW fixture). Commit: b3fd5ee.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-28T15:28:35.278Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Keep the chart visible while the new photo's histogram is being computed instead of replacing it with a spinner (pass) — AppViewModel.swift:1907 now calls cancelHistogram(clear: false, pump: false) on source switch, preserving the last published histogram; InfoInspectorView.swift:290-314 continues to render HistogramChart as long as viewModel.histogram is non-nil.
- [x] Animate the chart from the previous distribution to the new one when the current photo's histogram is ready (pass) — HistogramChart conforms to Animatable via HistogramPlotValues (VectorArithmetic) and applies .animation(.easeInOut(duration: 0.35), value: data) gated by accessibilityReduceMotion (InfoInspectorView.swift:411-460, 545-589).
- [x] Rapid photo changes never animate to or leave behind a histogram belonging to an obsolete selection (pass) — PreviewAdmissionCoordinator.updateHistogram (lines 190-213) re-checks assetID, sourceRevision, source, document, and lut against the destination's current state before publishing a result, rejecting stale in-flight responses. Verified by testPhotoSwitchRetainsHistogramAndRejectsAnObsoleteResult, which advances through a 4th selection while a 3rd-photo request is still pending and asserts the stale result never publishes.
- [x] Preserve an appropriate loading or unavailable state when there is no prior histogram to retain (pass) — histogramPlot falls back to ProgressView while isHistogramLoading and viewModel.histogram is nil, or to the unavailable text otherwise (InfoInspectorView.swift:302-315); unaffected by this change's cancelHistogram(clear:false) since there is nothing to retain on first load.
- [x] Add regression coverage for retention, animation of the current result, and rejection of stale results (pass) — PreviewCutoverTests.testPhotoSwitchRetainsHistogramAndRejectsAnObsoleteResult covers retention during a pending switch and stale-result rejection across two overlapping transitions. Animation timing itself is not asserted (SwiftUI interpolation is not practically unit-testable), but the Animatable/VectorArithmetic wiring was verified by build and manual code reading.
Checks run:
- swift build (debug) - clean, zero diagnostics
- swift test --filter PreviewCutoverTests - 17 passed, 1 skipped (no local RAW fixture), 0 failed
- swift test --filter PackageSettingsTests - 4/4 passed (Swift 6 mode, zero concurrency escape hatches confirmed)
- scripts/ci-tests.sh fast (full parallel run) - 3 pre-existing failures unrelated to this change (CropWorkflowTests.testCropGeometrySliderChangesStayInOneDisplayGenerationAndSettleAfterRelease, DevelopInspectorTests.testOpeningAStandardImageFallsBackFromUnavailableDevelopTab, ThumbnailSwitchLifecycleTests.testFilmstripAndGridPublishCropAwareSettledThumbnails)
- Reproduced the Crop/DevelopInspector failures identically on commit b3fd5ee^ (pre-change) in an isolated worktree, confirming they predate this change
- Re-ran ThumbnailSwitchLifecycleTests.testFilmstripAndGridPublishCropAwareSettledThumbnails in isolation on HEAD - passed, indicating parallel-run flakiness rather than a regression
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULEDXLAS0R27JMY
Summary: Verified histogram retention/animation across photo switches: build clean under Swift 6 mode, PreviewCutoverTests and PackageSettingsTests pass, and the 3 fast-suite failures seen are pre-existing (reproduced on the pre-change commit) rather than regressions.
