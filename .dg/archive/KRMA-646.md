---
id: KRMA-646
title: Add ViewModel-level tests for per-channel tone curve editing
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: LightInspectorTests exercise add/set/remove/move tone curve point with a non-master channel, confirming edits land on that channel and leave others untouched
      result: pass
      notes: testToneCurveEditingRoutesEveryOperationToSelectedChannel drives all four operations on .green and asserts master/red/blue are unchanged.
    - criterion: Coverage for resetToneCurve(_:) resetting only the given channel to identity
      result: pass
      notes: testToneCurveResetClearsOnlySelectedChannelAndIsUndoable now includes a non-identity master curve and asserts master and blue unchanged after reset and after undo.
  checks_run:
    - "swift test --filter LightInspectorTests: 24 tests, 0 failures"
  findings: []
  fixes: []
  verification_commits:
    - d5750dff
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-01T18:11:38.661Z
  session: 01MUPUOHO28O8L6YI7
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-27T05:10:45.074Z
updated: 2026-10-01T18:11:38.664Z
parent: KRMA-595
blockers: []
order: zv
board: product
commits:
  - d5750dff
---

## Objective

Add ViewModel-level tests for per-channel tone curve editing

## Context

Verification finding from KRMA-595: `AppViewModel+Light.swift` threads a `channel: ToneCurveChannel`
parameter through `setToneCurvePoint`, `addToneCurvePoint`, `removeToneCurvePoint`,
`moveToneCurvePoint`, and `resetToneCurve`, but `LightInspectorTests.swift` only exercises these
through their default (`.master`) parameter. `LightAdjustmentsTests` and `RenderPipelineTests` cover
the model and render layers for red/green/blue and parametric curves, so this is not a correctness
blocker — routing was verified by inline reading — but the ViewModel-facing API that the channel
picker in `LightInspectorView` actually calls has no direct regression coverage for non-master
channels or for `resetToneCurve(_:)` resetting only the selected channel.

## Acceptance criteria

- [ ] Add `LightInspectorTests` coverage exercising `addToneCurvePoint`/`setToneCurvePoint`/
      `removeToneCurvePoint`/`moveToneCurvePoint` with a non-master `channel`, confirming edits land
      on that channel's curve and leave the others untouched.
- [ ] Add coverage for `resetToneCurve(_:)` resetting only the given channel's curve to identity.

## Implementation notes

See `Sources/KromoraKit/ViewModels/AppViewModel+Light.swift` and
`Tests/KromoraKitTests/LightInspectorTests.swift`.

### Comment — codex @ 2026-10-01T18:10:55.843Z

Added ViewModel-level coverage for add, set, move, and remove on the green tone curve, asserting master/red/blue stay unchanged. Expanded selected-channel reset coverage to assert master and blue remain unchanged and undo restores only red. Verified with Test Suite 'Selected tests' started at 2026-10-01 12:10:48.858.
Test Suite 'KromoraKitTests.xctest' started at 2026-10-01 12:10:48.860.
Test Suite 'LightInspectorTests' started at 2026-10-01 12:10:48.860.
Test Case '-[KromoraKitTests.LightInspectorTests testAccessibilityAdjustableActionAddsTheFirstCurvePoint]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testAccessibilityAdjustableActionAddsTheFirstCurvePoint]' passed (0.372 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testAdvancedCurveControlsAreCollapsedUntilExpanded]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testAdvancedCurveControlsAreCollapsedUntilExpanded]' passed (0.415 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testComparisonBaselineRemovesLightButKeepsDevelop]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testComparisonBaselineRemovesLightButKeepsDevelop]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testCurveAddAndRemoveEachUseOneUndoStep]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testCurveAddAndRemoveEachUseOneUndoStep]' passed (0.347 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testCurveDragCoalescesEveryTickIntoOneUndoStep]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testCurveDragCoalescesEveryTickIntoOneUndoStep]' passed (0.333 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testCurveDragKeepsMonotonicControlPointsOrderedAndBounded]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testCurveDragKeepsMonotonicControlPointsOrderedAndBounded]' passed (0.324 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testCurveDragMovesBothEndpointsInBothDimensions]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testCurveDragMovesBothEndpointsInBothDimensions]' passed (0.342 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testCurveDragPublishesAnIntermediatePreviewBeforeRelease]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testCurveDragPublishesAnIntermediatePreviewBeforeRelease]' passed (0.574 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testCurveHitTestingUsesTheSameNormalizedToleranceForSelectionAndRemoval]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testCurveHitTestingUsesTheSameNormalizedToleranceForSelectionAndRemoval]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testDoubleClickEndpointResetPreservesInteriorPointsAndGroupsUndo]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testDoubleClickEndpointResetPreservesInteriorPointsAndGroupsUndo]' passed (0.392 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testEmptyCurveDragCreatesOnePointAndUndoRedoKeepTheWholeGestureTogether]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testEmptyCurveDragCreatesOnePointAndUndoRedoKeepTheWholeGestureTogether]' passed (0.381 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testIndividualAndPanelResetsAreScopedAndUndoable]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testIndividualAndPanelResetsAreScopedAndUndoable]' passed (0.380 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testInspectorRetainsViewportWidthDuringUnspecifiedScrollMeasurements]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testInspectorRetainsViewportWidthDuringUnspecifiedScrollMeasurements]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testLightBindingRoundTripsAndDoesNotTouchOtherDocumentSections]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testLightBindingRoundTripsAndDoesNotTouchOtherDocumentSections]' passed (0.392 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testLightControlsExposePhotographerRangesInPanelOrder]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testLightControlsExposePhotographerRangesInPanelOrder]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testLightSliderGestureIsOneUndoOperation]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testLightSliderGestureIsOneUndoOperation]' passed (0.343 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testNearestPointIncludesEndpointsSoAPressOnAHandleStartsADragNotAnAdd]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testNearestPointIncludesEndpointsSoAPressOnAHandleStartsADragNotAnAdd]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testNearExistingPointMovesThatPointWithoutAddingADuplicate]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testNearExistingPointMovesThatPointWithoutAddingADuplicate]' passed (0.354 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testPhotoHandoffRestoresTheLightDocumentAndHistory]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testPhotoHandoffRestoresTheLightDocumentAndHistory]' passed (0.729 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testToneCurveEditingRoutesEveryOperationToSelectedChannel]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testToneCurveEditingRoutesEveryOperationToSelectedChannel]' passed (0.325 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testToneCurveGraphPinsItsVerticalSizeInsideTheScrollingInspector]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testToneCurveGraphPinsItsVerticalSizeInsideTheScrollingInspector]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testToneCurveHandleHitTestingUsesRenderedPositionsAtInspectorSizes]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testToneCurveHandleHitTestingUsesRenderedPositionsAtInspectorSizes]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testToneCurveResetClearsOnlySelectedChannelAndIsUndoable]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testToneCurveResetClearsOnlySelectedChannelAndIsUndoable]' passed (0.327 seconds).
Test Case '-[KromoraKitTests.LightInspectorTests testToneCurveResetUsesAccessibleTrailingDisclosureAction]' started.
Test Case '-[KromoraKitTests.LightInspectorTests testToneCurveResetUsesAccessibleTrailingDisclosureAction]' passed (0.001 seconds).
Test Suite 'LightInspectorTests' passed at 2026-10-01 12:10:55.206.
	 Executed 24 tests, with 0 failures (0 unexpected) in 6.344 (6.347) seconds
Test Suite 'KromoraKitTests.xctest' passed at 2026-10-01 12:10:55.206.
	 Executed 24 tests, with 0 failures (0 unexpected) in 6.344 (6.347) seconds
Test Suite 'Selected tests' passed at 2026-10-01 12:10:55.206.
	 Executed 24 tests, with 0 failures (0 unexpected) in 6.344 (6.348) seconds (24 passed). Commit: d5750df.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-01T18:11:38.662Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] LightInspectorTests exercise add/set/remove/move tone curve point with a non-master channel, confirming edits land on that channel and leave others untouched (pass) — testToneCurveEditingRoutesEveryOperationToSelectedChannel drives all four operations on .green and asserts master/red/blue are unchanged.
- [x] Coverage for resetToneCurve(_:) resetting only the given channel to identity (pass) — testToneCurveResetClearsOnlySelectedChannelAndIsUndoable now includes a non-identity master curve and asserts master and blue unchanged after reset and after undo.
Checks run:
- swift test --filter LightInspectorTests: 24 tests, 0 failures
Findings:
- None
Fixes:
- None
Verification commits:
- d5750dff
Actor: claude
Resolved model: sonnet
Pickup session: 01MUPUOHO28O8L6YI7
Summary: Verified per-channel tone curve ViewModel tests; LightInspectorTests pass (24/24).
