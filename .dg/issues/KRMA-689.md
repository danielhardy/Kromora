---
id: KRMA-689
title: Investigate remaining white strokes along image edges
type: bug
status: review
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - bug
  - rendering
created: 2026-09-28T20:49:18.685Z
updated: 2026-09-28T21:14:54.833Z
blockers:
  - id: evt_mulqxbsh_ne6p7s
    type: human
    reason: The remaining edge-stroke report cannot be reproduced or localized because its screenshot/source image is inaccessible and the affected view and conditions are unknown.
    action: Attach a readable screenshot and, if possible, the source image; specify whether it occurs in preview, thumbnail, comparison, crop, or export and note zoom/display conditions.
    created_at: 2026-09-28T21:14:54.833Z
order: a0
board: product
blocked_reason: The remaining edge-stroke report cannot be reproduced or localized because its screenshot/source image is inaccessible and the affected view and conditions are unknown.
blocked_action: Attach a readable screenshot and, if possible, the source image; specify whether it occurs in preview, thumbnail, comparison, crop, or export and note zoom/display conditions.
blocked_from_status: ready
---

## Objective

Eliminate any remaining cases where a white stroke appears along the side or top edge of a displayed image. Image boundaries should show only the photo content, without an unintended outline or band.

## User report

The user reports that images sometimes end up with a white stroke on the side or top and that this should not happen. The attached screenshot could not be read because macOS denied access to its temporary capture path, so the exact image, view, and editing state are unavailable.

## Related work

KRMA-686 (done) reproduced and fixed a Core Image preview presentation fallback artifact caused by fractional-scale filtering at finite image extents. This follow-up tracks the newly reported side/top strokes and should first establish whether they reproduce after that fix, under a different view/path, or with different image/display conditions. Avoid duplicating the KRMA-686 fix without evidence of a distinct or still-present cause.

## Acceptance criteria

- [ ] Reproduce the reported side/top stroke after KRMA-686, or establish a deterministic fixture and record the affected image characteristics, view, and conditions.
- [ ] Determine whether the artifact is in rendered pixels or only appears in a particular presentation, and identify the responsible stage/path.
- [ ] Remove the cause so no unintended white stroke/band appears along image edges in the affected path; check export if it shares or reproduces that path.
- [ ] Preserve intended framing, crop, orientation, edge pixels, alpha behavior, and legitimate editor UI.
- [ ] Add regression coverage for the identified triggering condition and record verification commands and results.

## Investigation notes

Compare the affected image across preview, thumbnails, comparison/crop modes, and export as appropriate. Inspect pixel data and edge handling, including filtering, transforms, compositing, and view decoration. Reuse an accessible screenshot or source image if available during implementation; the original temporary screenshot path was inaccessible to this session.


### Comment — codex @ 2026-09-28T21:14:51.102Z

Investigated the retained Metal and Core Image preview paths after KRMA-686. The existing deterministic fallback perimeter regression still passes; Test Suite 'Selected tests' started at 2026-09-28 15:14:50.534.
Test Suite 'KromoraKitTests.xctest' started at 2026-09-28 15:14:50.534.
Test Suite 'PreviewSurfaceTests' started at 2026-09-28 15:14:50.534.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAFailedReplacementKeepsTheLastValidFrame]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAFailedReplacementKeepsTheLastValidFrame]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testARetainedROIFrameDoesNotRefuseTheCompletePhoto]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testARetainedROIFrameDoesNotRefuseTheCompletePhoto]' passed (0.025 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAStalePresentationCompletionCannotCommitOverANewerFrame]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAStalePresentationCompletionCannotCommitOverANewerFrame]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAttachingAViewRequestsAFramePublishedBeforeTheViewWasCreated]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAttachingAViewRequestsAFramePublishedBeforeTheViewWasCreated]' passed (0.027 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testBundledMetalSourcesAreResolvable]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testBundledMetalSourcesAreResolvable]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testClearResetsTheWorkingSpace]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testClearResetsTheWorkingSpace]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCompletedEngineTexturePresentsVisualTopAtFramebufferRowZero]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCompletedEngineTexturePresentsVisualTopAtFramebufferRowZero]' passed (0.022 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testConfirmationOnceTest]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testConfirmationOnceTest]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCoordinatorBuildsAPresentationPipelineFromBundledMetallib]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCoordinatorBuildsAPresentationPipelineFromBundledMetallib]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCroppedCompleteFrameFillsFitCanvas]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCroppedCompleteFrameFillsFitCanvas]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCropStraightenFitsTheRotatedPhotoAABBWithoutChangingTheRenderedSourceExtent]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCropStraightenFitsTheRotatedPhotoAABBWithoutChangingTheRenderedSourceExtent]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDisplayChangeTest]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDisplayChangeTest]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDoubleClickDoesNotStartAPan]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDoubleClickDoesNotStartAPan]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDoubleClickMouseDownTogglesCanvasAfterLeavingCropTool]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDoubleClickMouseDownTogglesCanvasAfterLeavingCropTool]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDownscaledInteractiveROIUsesPlannerLayoutOnFitCanvas]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDownscaledInteractiveROIUsesPlannerLayoutOnFitCanvas]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testEffectiveAppearanceResolvesTheSameLetterboxForMetalAndCoreImage]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testEffectiveAppearanceResolvesTheSameLetterboxForMetalAndCoreImage]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testFillCoversTheViewportWithAPortraitStandIn]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testFillCoversTheViewportWithAPortraitStandIn]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testGeometryGoldenTest]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testGeometryGoldenTest]' passed (0.012 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testHeadlessSurfaceConfirmsACompletedPresentationImmediately]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testHeadlessSurfaceConfirmsACompletedPresentationImmediately]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testInvalidCandidateCannotBlankTheLastConfirmedFrame]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testInvalidCandidateCannotBlankTheLastConfirmedFrame]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testLatestPublicationRemainsAvailableAcrossSkippedReplacement]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testLatestPublicationRemainsAvailableAcrossSkippedReplacement]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMetalFramebufferRowZeroIsVisualTop]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMetalFramebufferRowZeroIsVisualTop]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseDragPreservesPointerDirectionOnBothAxes]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseDragPreservesPointerDirectionOnBothAxes]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseDragPublishesPanBeforeMouseUp]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseDragPublishesPanBeforeMouseUp]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseUpDoesNotInvertTheAccumulatedPan]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseUpDoesNotInvertTheAccumulatedPan]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testNavigationCannotReplaceAValidSharperFrameWithALowerDetailFrame]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testNavigationCannotReplaceAValidSharperFrameWithALowerDetailFrame]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testNoCIEvalOnRepaintTest]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testNoCIEvalOnRepaintTest]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPartialROIFollowsLivePanOnRetainedCompleteFrameWithoutGaps]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPartialROIFollowsLivePanOnRetainedCompleteFrameWithoutGaps]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPartialROIFrameStaysAtPublishedNavigationUntilReplacementArrives]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPartialROIFrameStaysAtPublishedNavigationUntilReplacementArrives]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPortraitStandInDoesNotStretchOntoLandscapePresentationExtent]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPortraitStandInDoesNotStretchOntoLandscapePresentationExtent]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentationFallbackDoesNotBlendCanvasIntoPhotoPerimeter]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentationFallbackDoesNotBlendCanvasIntoPhotoPerimeter]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentationImageRemainsBoundedAbove100PercentAndKeepsTheSourceVisible]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentationImageRemainsBoundedAbove100PercentAndKeepsTheSourceVisible]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentStoresTheWorkingSpaceForThePresentedImage]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentStoresTheWorkingSpaceForThePresentedImage]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPreviewSurfaceLayoutUsesProposedSizeWithoutIntrinsicMeasurement]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPreviewSurfaceLayoutUsesProposedSizeWithoutIntrinsicMeasurement]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testProxyFirstFrameFillsFitCanvas]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testProxyFirstFrameFillsFitCanvas]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPublicationRequestsRedrawOnAnExistingMetalView]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPublicationRequestsRedrawOnAnExistingMetalView]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testRetainedTextureCropStraightenRotatesThePhotoInsteadOfZoomingItsTexture]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testRetainedTextureCropStraightenRotatesThePhotoInsteadOfZoomingItsTexture]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testSkippedDrawableStaysPendingUntilARealPresentation]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testSkippedDrawableStaysPendingUntilARealPresentation]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testSkippedDrawRetriesAreBoundedAndQuietAfterConsecutiveSkips]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testSkippedDrawRetriesAreBoundedAndQuietAfterConsecutiveSkips]' passed (0.106 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testUncoveredROIStaysAtVirtualOriginOnFit]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testUncoveredROIStaysAtVirtualOriginOnFit]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testVisibilityRestoreRearmsSkippedDrawRetries]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testVisibilityRestoreRearmsSkippedDrawRetries]' passed (0.064 seconds).
Test Suite 'PreviewSurfaceTests' passed at 2026-09-28 15:14:50.865.
	 Executed 41 tests, with 0 failures (0 unexpected) in 0.329 (0.331) seconds
Test Suite 'KromoraKitTests.xctest' passed at 2026-09-28 15:14:50.865.
	 Executed 41 tests, with 0 failures (0 unexpected) in 0.329 (0.331) seconds
Test Suite 'Selected tests' passed at 2026-09-28 15:14:50.865.
	 Executed 41 tests, with 0 failures (0 unexpected) in 0.329 (0.332) seconds passes all 41 tests. No accessible source image or screenshot was available to reproduce the remaining report or distinguish preview, thumbnail, comparison, crop, and export paths. A synthetic fractional-crop comparison was inconclusive, so I made no product changes. Please provide a readable capture and reproduction details to localize the remaining case.
