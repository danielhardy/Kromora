---
id: KRMA-554
title: Histogram does not follow the displayed Space-comparison request
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest passes deterministically, isolated and inside scripts/ci-tests.sh fast
      result: pass
      notes: "Isolated run passed 4x consecutively (0.4s each). Full ./scripts/ci-tests.sh fast run: 1177 tests, exit 0, no failures."
    - criterion: No regressions in the neighboring histogram tests (debounce coalescing, revision-guard staleness, Develop-tab-no-tally, provisional-frame gating)
      result: pass
      notes: Full DevelopInspectorTests suite (34 tests, 2 local-RAW skips) passed, including testLateHistogramResultCannotReplaceANewerEdit, testRapidEditsCoalesceHistogramWorkAfterTheSettledPreview, testNoHistogramIsTalliedWhileTheDevelopTabIsShowing, testSwitchingBackToInfoRecomputesTheHistogram.
    - criterion: Any product-behavior change is called out separately from test-only adjustments
      result: pass
      notes: "Fix (commit a4b2f10) touches only Tests/KromoraKitTests/DevelopInspectorTests.swift: disables preview disk cache (previewDiskCacheCapBytes: 0) and filters preview/completion matches by requestRevision > previousDisplayRevision so a stale cached identity frame cannot satisfy the comparison-render wait. No Sources/ changes; root cause was test-side cache-hit aliasing, not the suspected AppViewModel enqueue path."
  checks_run:
    - swift test --filter DevelopInspectorTests.testHistogramFollowsTheDisplayedComparisonRequest (x4, all passed)
    - swift test --filter DevelopInspectorTests (34 tests, 2 skipped local-RAW, 0 failures)
    - scripts/ci-tests.sh fast (1177 tests, exit 0, 0 failures)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-23T16:17:18.702Z
  session: 01MUEAXSC0J592MDU8
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - verification
created: 2026-09-23T15:00:15.772Z
updated: 2026-09-23T16:17:18.704Z
parent: KRMA-548
order: zv
board: product
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

### Comment — codex @ 2026-09-23T16:04:23.489Z

Corrected the comparison histogram test to disable preview cache hits and match only a request from the new display revision. This ensures it waits for the Space comparison render instead of matching the earlier identity frame. No product behavior changed. Verified: focused test passed twice; DevelopInspectorTests passed (34 tests, 2 local RAW skips). scripts/ci-tests.sh fast still fails only ObservabilityTests expectations that omit existing LibraryIndexWarm and LibraryIndexRebuild events. Commit: a4b2f10.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-23T16:17:18.702Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest passes deterministically, isolated and inside scripts/ci-tests.sh fast (pass) — Isolated run passed 4x consecutively (0.4s each). Full ./scripts/ci-tests.sh fast run: 1177 tests, exit 0, no failures.
- [x] No regressions in the neighboring histogram tests (debounce coalescing, revision-guard staleness, Develop-tab-no-tally, provisional-frame gating) (pass) — Full DevelopInspectorTests suite (34 tests, 2 local-RAW skips) passed, including testLateHistogramResultCannotReplaceANewerEdit, testRapidEditsCoalesceHistogramWorkAfterTheSettledPreview, testNoHistogramIsTalliedWhileTheDevelopTabIsShowing, testSwitchingBackToInfoRecomputesTheHistogram.
- [x] Any product-behavior change is called out separately from test-only adjustments (pass) — Fix (commit a4b2f10) touches only Tests/KromoraKitTests/DevelopInspectorTests.swift: disables preview disk cache (previewDiskCacheCapBytes: 0) and filters preview/completion matches by requestRevision > previousDisplayRevision so a stale cached identity frame cannot satisfy the comparison-render wait. No Sources/ changes; root cause was test-side cache-hit aliasing, not the suspected AppViewModel enqueue path.
Checks run:
- swift test --filter DevelopInspectorTests.testHistogramFollowsTheDisplayedComparisonRequest (x4, all passed)
- swift test --filter DevelopInspectorTests (34 tests, 2 skipped local-RAW, 0 failures)
- scripts/ci-tests.sh fast (1177 tests, exit 0, 0 failures)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUEAXSC0J592MDU8
