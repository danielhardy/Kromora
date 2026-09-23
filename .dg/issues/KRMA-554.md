---
id: KRMA-554
title: Histogram does not follow the displayed Space-comparison request
type: task
status: backlog
priority: high
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - verification
created: 2026-09-23T15:00:15.772Z
updated: 2026-09-23T15:00:15.772Z
order: zh
board: product
parent: KRMA-548
---

## Objective

Make the Info histogram follow the displayed Space-comparison request, so
`DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest` passes and the
deterministic fast lane goes green.

## Context

Parent: KRMA-548 (counterpoint-verification residual; the only failure in a fresh 1172-test
fast-lane run, reproduced 3x: implementer fast run, verifier isolated run, verifier full lane).

Reproduction: `swift test --filter
'DevelopInspectorTests.testHistogramFollowsTheDisplayedComparisonRequest'` fails twice: the
`waitUntil("the comparison histogram")` times out (histogramRequests never reaches 3) and the
final assert shows the last tally still describes the edited document
(`adjustments: [.vibrance(amount: 0.8)]`) instead of the comparison baseline
(`adjustments: []`).

What already works: `showOriginal(true)` returns true, a preview request carrying the
comparison-baseline document is issued, and its `previewCompleted` event fires. The tally for
that displayed frame is never enqueued.

Suspect path (`Sources/KromoraKit/ViewModels/AppViewModel.swift`): `showOriginal` ->
`schedulePreview` -> `submitSettledPreview` -> `presentSettledRaster` ->
`previewSurface.present(onPresented:)` -> `didPresentVisibleFrame` guard (assetID,
sourceRevision, displayRevision, `request.document == displayRequest.document`) ->
`updateHistogram(for:presentedImage:)` enqueue. Also note
`FakeRenderEngine.histogram(presentedImage:)` records `lastPreviewRecord`, so any stray
preview issued between comparison completion and the histogram job would also corrupt the
assertion — check both halves.

Documented intent is that the histogram describes the pixels on screen (`displayRequest`:
"the histogram is supposed to describe the pixels on screen, and it stopped doing so
precisely because it derived its image separately"). If transient-comparison-no-tally is
instead the intended product behavior, change the test explicitly — but that contradicts the
test's pre-existing name and the accessor comment, so decide deliberately and say so.

## Acceptance criteria

- [ ] `DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest` passes
  deterministically, isolated and inside `scripts/ci-tests.sh fast`.
- [ ] No regressions in the neighboring histogram tests (debounce coalescing, revision-guard
  staleness, Develop-tab-no-tally, provisional-frame gating).
- [ ] Any product-behavior change is called out separately from test-only adjustments.

## Implementation notes

Keep the fix narrow: this gates KRMA-548. Do not weaken production package validation, do not
reformat unrelated files, and do not absorb the untracked PackagePath/NumericClamping work
sitting in the tree (see the KRMA-548 verification hygiene ticket).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
