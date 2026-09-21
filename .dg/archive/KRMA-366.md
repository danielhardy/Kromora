---
id: KRMA-366
title: Primary canvas preview does not reflect local mask while edited thumbnail does
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Visible local mask adjustment in primary canvas at fit and non-nil ROI
      result: pass
    - criterion: Mask coverage remains in oriented full-source coordinates for ROI previews
      result: pass
    - criterion: Primary preview and edited thumbnail masked pixels agree
      result: pass
    - criterion: Preview/export masked rendering remains consistent
      result: pass
    - criterion: Cancellation, cache, and two-phase semantic behavior preserved
      result: pass
    - criterion: Regression coverage uses strong semantic foreground adjustment and source-space ROI
      result: pass
  checks_run:
    - swift test --filter LocalMaskRenderingTests/testSemanticMaskROIKeepsFullSourceCoverageAndMatchesThumbnail
    - swift test --parallel --filter KromoraKitTests.(LocalMaskRenderingTests|PreviewCoordinatorTests|PreviewSurfaceTests) — 73 tests passed
    - swift test --parallel — 1322 tests completed without reported failures
    - swift build -c release — passed
    - git diff --check — passed
    - dg validate — passed with pre-existing unknown-model warnings
  findings: []
  fixes:
    - Resolve local masks against fullFrameExtent and crop the resolved mask graph to upstream.extent before blending
  verification_commits:
    - 9b043c1
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-12T17:43:31.222Z
  session: 01MTYO3A5B2SUV904I
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - preview
  - masking
  - editor
  - rendering
created: 2026-09-11T23:35:23.407Z
updated: 2026-09-12T17:43:31.224Z
order: y
board: product
commits:
  - 9b043c1
---

## Objective

Make the primary editor canvas show the same local-mask result as the edited thumbnail and export for the active photo.

## Observed behavior

- In the attached screenshot, the large primary preview does not visibly reflect the active Foreground mask and its strong local Exposure adjustment.
- The smaller edited thumbnail in the bottom filmstrip does reflect the mask adjustment.
- The problem appears isolated to primary-area presentation or the primary preview request path; the durable mask and thumbnail render are present.

## Reproduction

1. Open a photo in Edit mode.
2. Open the persistent Masking workspace.
3. Create or select a semantic Foreground mask.
4. Give the layer a clearly visible local adjustment, such as Exposure +3.
5. Compare the large canvas with the edited filmstrip thumbnail.
6. Repeat while zoomed or panned so the primary preview request uses a non-nil source ROI.

## Investigation findings

- The filmstrip edited-thumbnail path submits a full-frame RenderRequest with quality thumbnail and no sourceROI in AppViewModel.requestEditedThumbnail, so local masks are rasterized against the complete source extent.
- The primary canvas path submits viewport-sized preview or interactive requests from schedulePreview and scheduleInteractivePreview. Once zoomed or panned, these requests carry a non-nil sourceROI.
- RenderEngine.buildImage crops the developed image to that ROI before calling resolvedLocalMasks. The mask definitions remain normalized in full oriented-source coordinates, but the LocalMaskRenderer receives upstream.extent, which is now the cropped ROI extent, with the default identity transform. This can project a full-source mask onto the ROI-local rectangle instead of preserving its source-space offset, causing the primary canvas to apply the wrong coverage or appear not to apply the adjustment while the full-frame thumbnail remains correct.
- Existing local-mask tests cover full-frame preview versus export, semantic resolution, overlay rendering, and cache behavior. They do not assert a masked primary preview with sourceROI against a full-frame reference, nor do they compare the primary and edited-thumbnail paths.
- Focused validation passed: LocalMaskRenderingTests 33 executed with 1 expected benchmark skip; PreviewCoordinatorTests 13 executed with 1 expected benchmark skip; PreviewSurfaceTests 25 executed with 0 skips.
- No product code was changed while investigating.

## Acceptance criteria

- [ ] A visible local adjustment through a semantic, brush, linear, or radial mask appears in the primary canvas at Fit and while zoomed or panned.
- [ ] Primary preview mask coverage remains in the same oriented full-source coordinates when sourceROI is non-nil.
- [ ] The primary preview and edited thumbnail show equivalent masked pixels for the same document, within the expected preview resampling tolerance.
- [ ] Preview and export continue to agree for masked documents.
- [ ] Adding regression coverage for non-nil sourceROI and primary-versus-thumbnail parity does not weaken existing cancellation, cache, or two-phase semantic-mask behavior.
- [ ] Verification includes the attached photo shape or an equivalent real-world image with a foreground/person mask and a strong local adjustment.

## Implementation notes

Investigate the source-space versus ROI-space contract at the RenderEngine.buildImage to resolvedLocalMasks boundary and the final ROI crop/remap. Preserve the existing normalized oriented-source mask contract. Keep the fix scoped to primary preview rendering and presentation; do not replace the independent edited-thumbnail path.

## Agent log

- 2026-09-12T17:43:31.222Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Visible local mask adjustment in primary canvas at fit and non-nil ROI (pass)
- [x] Mask coverage remains in oriented full-source coordinates for ROI previews (pass)
- [x] Primary preview and edited thumbnail masked pixels agree (pass)
- [x] Preview/export masked rendering remains consistent (pass)
- [x] Cancellation, cache, and two-phase semantic behavior preserved (pass)
- [x] Regression coverage uses strong semantic foreground adjustment and source-space ROI (pass)
Checks run:
- swift test --filter LocalMaskRenderingTests/testSemanticMaskROIKeepsFullSourceCoverageAndMatchesThumbnail
- swift test --parallel --filter KromoraKitTests.(LocalMaskRenderingTests|PreviewCoordinatorTests|PreviewSurfaceTests) — 73 tests passed
- swift test --parallel — 1322 tests completed without reported failures
- swift build -c release — passed
- git diff --check — passed
- dg validate — passed with pre-existing unknown-model warnings
Findings:
- None
Fixes:
- Resolve local masks against fullFrameExtent and crop the resolved mask graph to upstream.extent before blending
Verification commits:
- 9b043c1
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTYO3A5B2SUV904I
Summary: Fixed ROI local-mask rendering by resolving masks in the complete scaled oriented-source frame and cropping coverage to the working ROI. Added semantic primary-preview/thumbnail parity regression coverage; bumped renderer and preview cache versions.
