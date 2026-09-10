---
id: KRMA-332
title: Add image rotation
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Obvious control for rotating the selected image clockwise/counterclockwise in 90-degree increments
      result: pass
      notes: AppViewModel.rotateClockwise/rotateCounterClockwise + ContentView control; addingClockwiseQuarterTurns keeps only the four canonical orientations.
    - criterion: Rotation applies consistently to canvas preview and exported image, including correct output dimensions for portrait/landscape changes
      result: pass
      notes: RenderPipeline/RenderEngine thread document.rotation through developedSource, buildImage, and RenderRequest sizing; ImageRotationTests confirms preview and export extents and pixels match for a rotated+cropped document.
    - criterion: Rotation persisted as part of the edit document and restored on revisit
      result: pass
      notes: EditDocument gained a Codable `rotation` field (schema v3) with decodeIfPresent fallback to .zero for older records; testRotationStateIsCodableVisibleAndIdentityAware covers round-trip and legacy-decode.
    - criterion: Undo/redo/reset for rotation without disturbing unrelated adjustments
      result: pass
      notes: rotateImage/resetRotation go through the normal document-history path; testRotationControlsUseDocumentHistoryAndResetOnlyRotation and testRotationHistoryUndoRedoDoesNotLoseOtherEdits cover this.
    - criterion: Regression coverage for rotation state, rendering/export orientation, persistence, and interaction with crop or other spatial edits
      result: pass
      notes: Original coverage tested crop+rotation only when set together in one document, not rotate-after-an-existing-committed-crop. That sequence was broken (see findings) and is now fixed and covered by a new regression test.
  checks_run:
    - swift build
    - swift test --filter ImageRotationTests
    - swift test --filter 'CropTests|CropROITests|AppViewModelTests|CropModelTests|CropPipelineTests|CropWorkflowTests'
    - scripts/ci-tests.sh fast (full fast suite, exit 0)
    - git status --porcelain (tree clean aside from intended changes)
  findings:
    - "[high, fixed] Rotating an image with an already-committed crop silently reframed the wrong region. CropAdjustments.normalizedRect is defined in the oriented source's coordinate space; rotateImage() only cancelled an in-progress crop-tool draft before changing rotation, leaving a committed crop's normalizedRect untouched. It was then reinterpreted against the new, axis-swapped oriented extent in RenderBuildPlan/RenderPipeline, silently selecting a different region of the photo instead of rotating the crop with the image. Not covered by any existing test (rotation+crop tests only constructed both fields together, never rotated after a crop was already committed)."
  fixes:
    - "Added CropAdjustments.rotated(byClockwiseQuarterTurns:) to remap a committed crop's normalizedRect through a quarter-turn, applied in AppViewModel.rotateImage (forward turn) and resetRotation (inverse of the accumulated turns) so a committed crop stays anchored to the same visual content across rotation changes. Files: Sources/KromoraKit/Models/CropAdjustments.swift, Sources/KromoraKit/ViewModels/AppViewModel.swift."
    - "Added regression tests: unit coverage for the quarter-turn crop-rect transform (round trip, 4-turn identity), and an integration test that commits a crop, rotates, asserts the crop keeps framing the same content, then resets rotation and asserts the original crop rect is restored. File: Tests/KromoraKitTests/ImageRotationTests.swift."
  verification_commits:
    - c8e12c76ea6089ade8ff153d5da64da681f7d829
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-10T14:52:42.611Z
  session: 01MTVN2XEUAX5ADH7K
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - feature
created: 2026-09-10T04:08:12.873Z
updated: 2026-09-10T14:52:42.613Z
order: a0
board: product
commits:
  - c8e12c76ea6089ade8ff153d5da64da681f7d829
---

## Objective

Allow the user to rotate the selected image from the editor.

## Context

Images may be imported in the wrong orientation or need to be turned for the intended
composition. Rotation should be a non-destructive edit that remains consistent across the
preview and exported result.

## Acceptance criteria

- [ ] Provide an obvious control for rotating the selected image clockwise and counterclockwise
      (at minimum in 90-degree increments).
- [ ] Apply the rotation consistently to the canvas preview and exported image, including the
      correct output dimensions for portrait/landscape changes.
- [ ] Persist the rotation as part of the edit document and restore it when revisiting the image.
- [ ] Support undo/redo and reset for the rotation without disturbing unrelated adjustments.
- [ ] Add regression coverage for rotation state, rendering/export orientation, persistence, and
      interaction with crop or other spatial edits.

## Implementation notes

Consider the existing crop, render-pipeline, edit-history, and export pathways when choosing where
rotation belongs. Preserve source pixels and keep the edit non-destructive.

### Comment — codex @ 2026-09-10T14:45:08.368Z

Implemented non-destructive clockwise/counterclockwise 90-degree rotation with persisted ImageRotation state, preview/export dimension and pixel parity, crop-aware planning, undo/redo/reset, and clipboard support. Verification: swift test full suite passed (1068 tests, 47 skipped, 0 failures), plus focused rotation/crop/export/persistence tests. Commit: 6317b18.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-10T14:52:42.611Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Obvious control for rotating the selected image clockwise/counterclockwise in 90-degree increments (pass) — AppViewModel.rotateClockwise/rotateCounterClockwise + ContentView control; addingClockwiseQuarterTurns keeps only the four canonical orientations.
- [x] Rotation applies consistently to canvas preview and exported image, including correct output dimensions for portrait/landscape changes (pass) — RenderPipeline/RenderEngine thread document.rotation through developedSource, buildImage, and RenderRequest sizing; ImageRotationTests confirms preview and export extents and pixels match for a rotated+cropped document.
- [x] Rotation persisted as part of the edit document and restored on revisit (pass) — EditDocument gained a Codable `rotation` field (schema v3) with decodeIfPresent fallback to .zero for older records; testRotationStateIsCodableVisibleAndIdentityAware covers round-trip and legacy-decode.
- [x] Undo/redo/reset for rotation without disturbing unrelated adjustments (pass) — rotateImage/resetRotation go through the normal document-history path; testRotationControlsUseDocumentHistoryAndResetOnlyRotation and testRotationHistoryUndoRedoDoesNotLoseOtherEdits cover this.
- [x] Regression coverage for rotation state, rendering/export orientation, persistence, and interaction with crop or other spatial edits (pass) — Original coverage tested crop+rotation only when set together in one document, not rotate-after-an-existing-committed-crop. That sequence was broken (see findings) and is now fixed and covered by a new regression test.
Checks run:
- swift build
- swift test --filter ImageRotationTests
- swift test --filter 'CropTests|CropROITests|AppViewModelTests|CropModelTests|CropPipelineTests|CropWorkflowTests'
- scripts/ci-tests.sh fast (full fast suite, exit 0)
- git status --porcelain (tree clean aside from intended changes)
Findings:
- [high, fixed] Rotating an image with an already-committed crop silently reframed the wrong region. CropAdjustments.normalizedRect is defined in the oriented source's coordinate space; rotateImage() only cancelled an in-progress crop-tool draft before changing rotation, leaving a committed crop's normalizedRect untouched. It was then reinterpreted against the new, axis-swapped oriented extent in RenderBuildPlan/RenderPipeline, silently selecting a different region of the photo instead of rotating the crop with the image. Not covered by any existing test (rotation+crop tests only constructed both fields together, never rotated after a crop was already committed).
Fixes:
- Added CropAdjustments.rotated(byClockwiseQuarterTurns:) to remap a committed crop's normalizedRect through a quarter-turn, applied in AppViewModel.rotateImage (forward turn) and resetRotation (inverse of the accumulated turns) so a committed crop stays anchored to the same visual content across rotation changes. Files: Sources/KromoraKit/Models/CropAdjustments.swift, Sources/KromoraKit/ViewModels/AppViewModel.swift.
- Added regression tests: unit coverage for the quarter-turn crop-rect transform (round trip, 4-turn identity), and an integration test that commits a crop, rotates, asserts the crop keeps framing the same content, then resets rotation and asserts the original crop rect is restored. File: Tests/KromoraKitTests/ImageRotationTests.swift.
Verification commits:
- c8e12c76ea6089ade8ff153d5da64da681f7d829
Actor: claude
Resolved model: sonnet
Pickup session: 01MTVN2XEUAX5ADH7K
Summary: Verification passed. Found and fixed a real gap: rotating an image with an already-committed crop silently reframed the wrong region because the committed normalizedRect wasn't remapped through the rotation. Fixed with CropAdjustments.rotated(byClockwiseQuarterTurns:) applied in rotateImage/resetRotation, plus new regression tests. Full fast CI suite passes. Filed KRMA-353 (verification-labeled, non-blocking) for the analogous local-adjustment mask geometry gap.
