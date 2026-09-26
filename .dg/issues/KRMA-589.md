---
id: KRMA-589
title: Align Photo Analysis mask demo after cropping
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - photo-analysis
  - masking
created: 2026-09-26T01:11:47.369Z
updated: 2026-09-26T01:12:01.022Z
blockers: []
order: zzzz
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
