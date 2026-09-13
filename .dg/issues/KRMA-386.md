---
id: KRMA-386
title: Crop view image cannot be dragged to reposition the crop
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The image can be grabbed from the middle of the crop area.
      result: pass
      notes: cropGuides now carries a full-rect contentShape with the move gesture attached, restoring an interior hit target.
    - criterion: Dragging moves the image relative to the crop box.
      result: pass
      notes: moveGesture/CropOverlayInteraction.translated logic unchanged; covered by testDraggingCropAreaTranslatesInNormalizedBottomLeftSpace.
    - criterion: The crop preview updates during the drag and preserves the selected crop bounds.
      result: pass
      notes: onChange callback threading unchanged; preview/clamp behavior unaffected by the diff.
    - criterion: Edge and corner handle resizing continues to work independently.
      result: pass
      notes: 44x44 clear handle hit-rects are declared after cropGuides in the ZStack (with zIndex(1)), so SwiftUI's front-to-back hit testing still gives handles priority over the interior move surface in overlapping regions, even though the inset-by-14 exclusion was removed.
  checks_run:
    - swift build
    - swift test --filter 'Crop(Model|Pipeline|Workflow|OverlayView)Tests' (25/25 passed)
    - swift format lint Sources/KromoraKit/Views/CropOverlayView.swift (clean)
    - git show 1bdb550 code review of CropOverlayView.swift diff
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T18:30:39.299Z
  session: 01MTYPYY4TQ9LR9J81
labels:
  - crop
  - interaction
  - regression
created: 2026-09-12T16:42:02.553Z
updated: 2026-09-12T18:30:39.301Z
order: a0
board: product
---

## Objective

Restore the ability to drag the middle of the image in Crop view to reposition the crop area over the image.

## Reproduction

1. Open an image in Crop view.
2. Grab the middle of the image inside the crop box.
3. Drag to reposition which part of the image is included by the crop.

## Observed behavior

The image cannot be grabbed and dragged from the middle, so the crop area cannot be repositioned as intended.

## Expected behavior

Dragging the image from the middle of the crop area should reposition the image beneath the crop box without unexpectedly resizing or exiting Crop view.

## Acceptance criteria

- [ ] The image can be grabbed from the middle of the crop area.
- [ ] Dragging moves the image relative to the crop box.
- [ ] The crop preview updates during the drag and preserves the selected crop bounds.
- [ ] Edge and corner handle resizing continues to work independently.

## Related work

Follow-up/regression against KRMA-124, “Reposition crop by dragging the crop area.”

### Comment — codex @ 2026-09-12T18:28:56.555Z

Implemented in commit 1bdb550. The crop move gesture now lives on the rendered crop-frame surface, giving the middle of the crop a reliable hit target while keeping the four dedicated handle targets above it for independent resizing. Verification: targeted crop tests 25/25 passed, release build passed, crop-file swift-format lint passed, and git diff --check passed. The required fast CI lane ran 922 tests but had two unrelated PreviewDiskCacheTests timeouts.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-12T18:30:39.299Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The image can be grabbed from the middle of the crop area. (pass) — cropGuides now carries a full-rect contentShape with the move gesture attached, restoring an interior hit target.
- [x] Dragging moves the image relative to the crop box. (pass) — moveGesture/CropOverlayInteraction.translated logic unchanged; covered by testDraggingCropAreaTranslatesInNormalizedBottomLeftSpace.
- [x] The crop preview updates during the drag and preserves the selected crop bounds. (pass) — onChange callback threading unchanged; preview/clamp behavior unaffected by the diff.
- [x] Edge and corner handle resizing continues to work independently. (pass) — 44x44 clear handle hit-rects are declared after cropGuides in the ZStack (with zIndex(1)), so SwiftUI's front-to-back hit testing still gives handles priority over the interior move surface in overlapping regions, even though the inset-by-14 exclusion was removed.
Checks run:
- swift build
- swift test --filter 'Crop(Model|Pipeline|Workflow|OverlayView)Tests' (25/25 passed)
- swift format lint Sources/KromoraKit/Views/CropOverlayView.swift (clean)
- git show 1bdb550 code review of CropOverlayView.swift diff
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYPYY4TQ9LR9J81
Summary: Verified: crop interior drag restored via move gesture on cropGuides; handle hit-rects (drawn after, zIndex 1) still take priority for corner/edge resize. 25/25 crop tests pass, lint clean.
