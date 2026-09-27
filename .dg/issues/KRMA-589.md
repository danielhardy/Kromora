---
id: KRMA-589
title: Align Photo Analysis mask demo after cropping
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: With a non-identity crop, the mask in the Photo Analysis mini demo overlays the same visible subject pixels as the corresponding full masking section.
      result: pass
      notes: AnalysisMaskOverlayLayout now derives sourceFrame/cropFrame from the shared CanvasMaskTransform, the same contract MaskingWorkspace uses; regression test asserts an interior subject point maps to the identical fractional position as CanvasMaskTransform.viewportPoint.
    - criterion: Cropping does not make the demo overlay stretch, shift, or expose mask pixels from outside the displayed crop.
      result: pass
      notes: AnalysisMaskOverlay renders the full-source mask at sourceFrame, offsets it against cropFrame, and clips to cropFrame width/height, so only the cropped region is visible and aspect ratio is preserved by CanvasMaskTransform's fit math.
    - criterion: Identity-crop behavior remains aligned and the demo continues to fit the photo and mask at matching aspect ratios.
      result: pass
      notes: testAnalysisMaskOverlayIdentityCropMatchesFittedPhotoFrame asserts sourceFrame == cropFrame and the fitted aspect ratio for .neutral crop.
    - criterion: Add focused regression coverage for mask-to-preview alignment with a non-origin, non-full-frame crop.
      result: pass
      notes: testAnalysisMaskOverlayLayoutMapsNonOriginCropAndFitsItsAspectRatio (extended in e16624f with an interior subject-point mapping assertion) and testAnalysisMaskOverlayIdentityCropMatchesFittedPhotoFrame.
    - criterion: swift build, focused analysis/masking tests, and git diff --check pass.
      result: pass
      notes: swift build succeeded; swift test --filter AnalysisDebugPanelTests (3/3) and --filter MaskingWorkspaceTests (44/44) passed after temporarily relocating the pre-existing untracked Tests/KromoraKitTests/RetouchModelTests.swift (unrelated WIP file that fails to compile against current EditDocument, blocking the whole test target) and restoring it unchanged afterward; git diff --check reported no whitespace issues.
  checks_run:
    - swift build
    - swift test --filter AnalysisDebugPanelTests
    - swift test --filter MaskingWorkspaceTests
    - git diff --check
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T17:05:22.038Z
  session: 01MUIN22G87ZTQXBU5
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - photo-analysis
  - masking
created: 2026-09-26T01:11:47.369Z
updated: 2026-09-26T17:05:22.040Z
blockers: []
order: z
board: product
---

## Objective

Keep the mask overlay aligned with the displayed photo in the Photo Analysis mini demo after a non-destructive crop is applied. The full masking section already aligns the same mask correctly.

## Reproduction

1. Open a photo and apply a non-identity crop.
2. Open Photo Analysis and show the mini mask demo.
3. Compare the mask overlay to the subject in the photo, then compare it with the corresponding overlay in the full masking section.

The mini demo overlay is offset or scaled incorrectly after cropping; the full masking section remains aligned.

## Context

`PhotoAnalysisInspectSection.maskOverlays` in `Sources/KromoraKit/Views/AnalysisDebugPanel.swift` stacks `MaskGridView` over `PreviewSurfaceView`. Analysis mask pixels use normalized analysis-image coordinates. The full masking canvas in `Sources/KromoraKit/Views/MaskingWorkspace.swift` builds a `CanvasMaskTransform` using the committed crop and canvas navigation. Investigate how to apply consistent source-to-presented crop mapping in the Photo Analysis mini demo, while retaining correct fit behavior and aspect ratio.

Relevant code and tests:

- `Sources/KromoraKit/Views/AnalysisDebugPanel.swift`
- `Sources/KromoraKit/Views/MaskingWorkspace.swift`
- `Sources/KromoraKit/Models/CanvasNavigation.swift` (`CanvasMaskTransform`)
- `Tests/KromoraKitTests/AnalysisDebugPanelTests.swift`
- `Tests/KromoraKitTests/MaskingWorkspaceTests.swift`

## Acceptance criteria

- [ ] With a non-identity crop, the mask in the Photo Analysis mini demo overlays the same visible subject pixels as the corresponding full masking section.
- [ ] Cropping does not make the demo overlay stretch, shift, or expose mask pixels from outside the displayed crop.
- [ ] Identity-crop behavior remains aligned and the demo continues to fit the photo and mask at matching aspect ratios.
- [ ] Add focused regression coverage for mask-to-preview alignment with a non-origin, non-full-frame crop.
- [ ] `swift build`, focused analysis/masking tests, and `git diff --check` pass.

## Implementation notes

Use the same source, crop, and presentation coordinate contract as the full masking canvas where practical. Keep the mini demo read-only and preserve the analysis mask values; this is a presentation alignment issue.


### Comment — codex @ 2026-09-26T16:59:33.586Z

Implemented the crop-aligned mini-demo mapping using the shared CanvasMaskTransform contract, and strengthened the non-origin crop regression with an interior subject-point mapping assertion. Verification: swift build and git diff --check pass. swift test --filter AnalysisDebugPanelTests could not compile the test target because the pre-existing untracked RetouchModelTests.swift references EditDocument.retouch, which is absent from the model. Commit: e16624f.

## Agent log

- 2026-09-26T17:05:22.038Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] With a non-identity crop, the mask in the Photo Analysis mini demo overlays the same visible subject pixels as the corresponding full masking section. (pass) — AnalysisMaskOverlayLayout now derives sourceFrame/cropFrame from the shared CanvasMaskTransform, the same contract MaskingWorkspace uses; regression test asserts an interior subject point maps to the identical fractional position as CanvasMaskTransform.viewportPoint.
- [x] Cropping does not make the demo overlay stretch, shift, or expose mask pixels from outside the displayed crop. (pass) — AnalysisMaskOverlay renders the full-source mask at sourceFrame, offsets it against cropFrame, and clips to cropFrame width/height, so only the cropped region is visible and aspect ratio is preserved by CanvasMaskTransform's fit math.
- [x] Identity-crop behavior remains aligned and the demo continues to fit the photo and mask at matching aspect ratios. (pass) — testAnalysisMaskOverlayIdentityCropMatchesFittedPhotoFrame asserts sourceFrame == cropFrame and the fitted aspect ratio for .neutral crop.
- [x] Add focused regression coverage for mask-to-preview alignment with a non-origin, non-full-frame crop. (pass) — testAnalysisMaskOverlayLayoutMapsNonOriginCropAndFitsItsAspectRatio (extended in e16624f with an interior subject-point mapping assertion) and testAnalysisMaskOverlayIdentityCropMatchesFittedPhotoFrame.
- [x] swift build, focused analysis/masking tests, and git diff --check pass. (pass) — swift build succeeded; swift test --filter AnalysisDebugPanelTests (3/3) and --filter MaskingWorkspaceTests (44/44) passed after temporarily relocating the pre-existing untracked Tests/KromoraKitTests/RetouchModelTests.swift (unrelated WIP file that fails to compile against current EditDocument, blocking the whole test target) and restoring it unchanged afterward; git diff --check reported no whitespace issues.
Checks run:
- swift build
- swift test --filter AnalysisDebugPanelTests
- swift test --filter MaskingWorkspaceTests
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUIN22G87ZTQXBU5
Summary: Verified crop-aligned Photo Analysis mask demo: build and focused AnalysisDebugPanelTests/MaskingWorkspaceTests pass, mapping matches CanvasMaskTransform contract used by the full masking canvas, no findings.
