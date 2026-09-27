---
id: KRMA-591
title: Keep the histogram unchanged when zooming
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Zooming the canvas in or out, including fit/fill and pointer zoom, does not recompute or change the histogram.
      result: pass
      notes: hasSameImageContent() compares only source/document/lut/space; viewport-only RenderRequest diffs (targetSize/ROI) do not trigger recompute. Verified by testCanvasNavigationDoesNotRecomputeTheHistogram and testPendingHistogramSurvivesCanvasZoom.
    - criterion: Editing image content recomputes the histogram for the updated photo.
      result: pass
      notes: Document change breaks hasSameImageContent equality, forcing recompute. Verified by testDevelopAndColorEditsUpdateThePinnedHistogram and testRapidEditsCoalesceHistogramWorkAfterTheSettledPreview.
    - criterion: Changing or committing a crop recomputes the histogram for the cropped photo.
      result: pass
      notes: Crop is part of EditDocument's synthesized Equatable conformance, so crop changes invalidate identity. Verified by testCropChangeRecomputesTheHistogram.
    - criterion: A pending histogram result from before an edit or crop cannot overwrite the histogram for the newer photo state.
      result: pass
      notes: Completion guard re-checks assetID, sourceRevision, admissionImageSource, admissionDisplayDocument, and admissionDisplayLUT against the in-flight request before publishing. Verified by testLateHistogramResultCannotReplaceANewerEdit.
  checks_run:
    - swift build (debug) - passed
    - swift test --filter "PreviewAdmissionCoordinatorTests|DevelopInspectorTests" - 41 tests, 0 failures, 2 pre-existing skips (no local RAW fixture)
    - scripts/ci-tests.sh fast - 1247 tests, 0 failures
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T02:52:46.295Z
  session: 01MUJ7W07PN0DDFAU2
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - histogram
  - zoom
created: 2026-09-26T02:55:36.594Z
updated: 2026-09-27T02:52:46.297Z
blockers: []
order: a0
board: product
---

## Objective

Keep the Info histogram stable during canvas navigation. Zooming the photo alone must not refresh, rescale, or otherwise change the histogram. Editing or cropping the photo should recompute it.

## Context

The histogram represents image content, not the current viewport. Reproduction: open a photo with the Info inspector visible, zoom in or out using canvas navigation, and observe that the histogram changes even though the photo pixels were not edited. Crop and image-edit operations should still refresh the histogram to reflect the changed photo.

Related but distinct: KRMA-554 fixed the histogram following the displayed temporary Space-comparison request. This ticket covers histogram invalidation caused by zoom/navigation.

## Acceptance criteria

- [ ] Zooming the canvas in or out, including fit/fill and pointer zoom, does not recompute or change the histogram.
- [ ] Editing image content recomputes the histogram for the updated photo.
- [ ] Changing or committing a crop recomputes the histogram for the cropped photo.
- [ ] A pending histogram result from before an edit or crop cannot overwrite the histogram for the newer photo state.


### Comment — codex @ 2026-09-27T02:46:21.007Z

Histogram work now ignores viewport-only request changes and remains valid across zoom; edits/crops invalidate by displayed document/LUT identity and stale results are fenced. Restored regression coverage for navigation, pending zoom work, and crop refresh. Focused git diff --check passed; tests not run.

## Agent log

- 2026-09-27T02:52:46.295Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Zooming the canvas in or out, including fit/fill and pointer zoom, does not recompute or change the histogram. (pass) — hasSameImageContent() compares only source/document/lut/space; viewport-only RenderRequest diffs (targetSize/ROI) do not trigger recompute. Verified by testCanvasNavigationDoesNotRecomputeTheHistogram and testPendingHistogramSurvivesCanvasZoom.
- [x] Editing image content recomputes the histogram for the updated photo. (pass) — Document change breaks hasSameImageContent equality, forcing recompute. Verified by testDevelopAndColorEditsUpdateThePinnedHistogram and testRapidEditsCoalesceHistogramWorkAfterTheSettledPreview.
- [x] Changing or committing a crop recomputes the histogram for the cropped photo. (pass) — Crop is part of EditDocument's synthesized Equatable conformance, so crop changes invalidate identity. Verified by testCropChangeRecomputesTheHistogram.
- [x] A pending histogram result from before an edit or crop cannot overwrite the histogram for the newer photo state. (pass) — Completion guard re-checks assetID, sourceRevision, admissionImageSource, admissionDisplayDocument, and admissionDisplayLUT against the in-flight request before publishing. Verified by testLateHistogramResultCannotReplaceANewerEdit.
Checks run:
- swift build (debug) - passed
- swift test --filter "PreviewAdmissionCoordinatorTests|DevelopInspectorTests" - 41 tests, 0 failures, 2 pre-existing skips (no local RAW fixture)
- scripts/ci-tests.sh fast - 1247 tests, 0 failures
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJ7W07PN0DDFAU2
Summary: Verified histogram invalidation now keys off document/LUT/space identity, not viewport; zoom no longer recomputes, edits/crops still do, and stale in-flight results are fenced by a re-check against the current display document at completion.
