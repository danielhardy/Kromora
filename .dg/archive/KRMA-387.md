---
id: KRMA-387
title: Crop view top-left handle cannot be dragged
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The top-left crop handle can be grabbed in Crop view.
      result: pass
      notes: Dedicated 44pt hit-target Rectangle inset inward from the corner, given zIndex(1) above the top controls bar, replaces the old 2x-scaled Circle contentShape whose hit area extended outside the GeometryReader/viewport at the top-left corner.
    - criterion: Dragging it changes the top and left crop boundaries.
      result: pass
      notes: "handleGesture still drives CropOverlayInteraction.resized via DragGesture(minimumDistance: 0) using value.translation, which is independent of the hit target's on-screen position, so relocating the hit target does not change resize math."
    - criterion: The crop preview updates during the drag and remains correctly positioned afterward.
      result: pass
      notes: Unchanged onChange/CropOverlayInteraction.resized wiring; covered by existing CropWorkflowTests and CropPipelineTests, all passing.
    - criterion: Other crop handles and aspect-ratio constraints continue to work.
      result: pass
      notes: All four handles use the same handleHitPosition/handleGesture path; existing testFixedRatioOneAxisResizesSymmetricallyFromEveryCorner and related tests pass unchanged.
  checks_run:
    - swift build
    - swift test --filter Crop (46/46 pass, 44 pre-existing + 2 new)
    - scripts/ci-tests.sh fast (915/915 pass)
    - scripts/check-swift-format.sh (pass after in-place reformat)
    - git diff --check (clean)
    - git status --porcelain review (no unexpected tracked-source changes)
  findings:
    - "low/test-coverage: handleHitPosition/handleHitTargetSize, the geometry that fixes KRMA-387, were private with no unit coverage; only manual/UI verification could catch a regression. Fix: widened both to internal (matching the CLAUDE.md precedent for RecipeExtractor.buildCube/workingSize) and added CropOverlayViewTests with two tests: corner-inset correctness and inset clamping for crop rects smaller than the 44pt hit-target size."
    - "low/maintainability: Tests/KromoraKitTests/CropTests.swift had pre-existing whole-file swift-format violations (line length, indentation) never caught because the file was never part of a changed-file diff until now. Fix: ran swift format format --in-place on CropTests.swift and CropOverlayView.swift; scripts/check-swift-format.sh now passes. No behavior change, formatting only."
  fixes:
    - Widened CropOverlayView.handleHitPosition and handleHitTargetSize from private to internal for testability
    - Added CropOverlayViewTests (2 tests) covering hit-target inset geometry and tiny-crop-rect clamping
    - Reformatted CropTests.swift and CropOverlayView.swift with swift-format to clear pre-existing/latent violations
  verification_commits:
    - 74d4cfb
    - 74d4cfb7f6df23b320566135cc8e36e3a7f4f9ea
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-12T17:36:50.748Z
  session: 01MTYNWP4SPHE0V097
labels:
  - crop
  - interaction
  - regression
created: 2026-09-12T16:42:03.003Z
updated: 2026-09-12T17:36:50.749Z
order: a0
board: product
commits:
  - 74d4cfb7f6df23b320566135cc8e36e3a7f4f9ea
  - 74d4cfb
---

## Objective

Restore the ability to grab and drag the top-left crop handle in Crop view to adjust the crop bounds.

## Reproduction

1. Open an image in Crop view.
2. Try to grab the top-left crop handle.
3. Drag it to adjust the crop.

## Observed behavior

The top-left handle cannot be grabbed or dragged, so that corner of the crop cannot be adjusted.

## Expected behavior

The top-left handle should provide a reliable hit target and drag normally to resize the crop box.

## Acceptance criteria

- [ ] The top-left crop handle can be grabbed in Crop view.
- [ ] Dragging it changes the top and left crop boundaries.
- [ ] The crop preview updates during the drag and remains correctly positioned afterward.
- [ ] Other crop handles and aspect-ratio constraints continue to work.

## Related work

Follow-up/regression against KRMA-124, “Reposition crop by dragging the crop area.”

### Comment — codex @ 2026-09-12T17:31:38.803Z

Implemented in commit 46b4c75. Added dedicated 44pt inward-positioned hit targets for all crop handles, kept the visible handles on the crop bounds, and prioritized handle hit testing over the top controls. Crop geometry and drag behavior remain unchanged. Verification: crop-related tests 44 passed, release build passed, Swift-format passed, git diff --check passed, and dg validate passed with existing pickup-model warnings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-12T17:36:50.748Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The top-left crop handle can be grabbed in Crop view. (pass) — Dedicated 44pt hit-target Rectangle inset inward from the corner, given zIndex(1) above the top controls bar, replaces the old 2x-scaled Circle contentShape whose hit area extended outside the GeometryReader/viewport at the top-left corner.
- [x] Dragging it changes the top and left crop boundaries. (pass) — handleGesture still drives CropOverlayInteraction.resized via DragGesture(minimumDistance: 0) using value.translation, which is independent of the hit target's on-screen position, so relocating the hit target does not change resize math.
- [x] The crop preview updates during the drag and remains correctly positioned afterward. (pass) — Unchanged onChange/CropOverlayInteraction.resized wiring; covered by existing CropWorkflowTests and CropPipelineTests, all passing.
- [x] Other crop handles and aspect-ratio constraints continue to work. (pass) — All four handles use the same handleHitPosition/handleGesture path; existing testFixedRatioOneAxisResizesSymmetricallyFromEveryCorner and related tests pass unchanged.
Checks run:
- swift build
- swift test --filter Crop (46/46 pass, 44 pre-existing + 2 new)
- scripts/ci-tests.sh fast (915/915 pass)
- scripts/check-swift-format.sh (pass after in-place reformat)
- git diff --check (clean)
- git status --porcelain review (no unexpected tracked-source changes)
Findings:
- low/test-coverage: handleHitPosition/handleHitTargetSize, the geometry that fixes KRMA-387, were private with no unit coverage; only manual/UI verification could catch a regression. Fix: widened both to internal (matching the CLAUDE.md precedent for RecipeExtractor.buildCube/workingSize) and added CropOverlayViewTests with two tests: corner-inset correctness and inset clamping for crop rects smaller than the 44pt hit-target size.
- low/maintainability: Tests/KromoraKitTests/CropTests.swift had pre-existing whole-file swift-format violations (line length, indentation) never caught because the file was never part of a changed-file diff until now. Fix: ran swift format format --in-place on CropTests.swift and CropOverlayView.swift; scripts/check-swift-format.sh now passes. No behavior change, formatting only.
Fixes:
- Widened CropOverlayView.handleHitPosition and handleHitTargetSize from private to internal for testability
- Added CropOverlayViewTests (2 tests) covering hit-target inset geometry and tiny-crop-rect clamping
- Reformatted CropTests.swift and CropOverlayView.swift with swift-format to clear pre-existing/latent violations
Verification commits:
- 74d4cfb
- 74d4cfb7f6df23b320566135cc8e36e3a7f4f9ea
Actor: claude
Resolved model: sonnet
Pickup session: 01MTYNWP4SPHE0V097
Summary: Verified: top-left crop handle now has a dedicated, reliably-positioned hit target. All 44 pre-existing crop tests pass; added 2 regression tests for the hit-target geometry and fixed a latent whole-file swift-format violation surfaced by touching CropTests.swift.
