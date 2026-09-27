---
id: KRMA-648
title: Add edge-mask preview for sharpening Masking control
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - professional-polish
created: 2026-09-27T06:28:08.602Z
updated: 2026-09-27T06:28:08.602Z
parent: KRMA-598
blockers: []
order: zzzx
board: product
---

## Objective

Add a live edge-mask preview to the sharpening Masking control, matching the acceptance
criteria in KRMA-598 (parent).

## Context

KRMA-598 added sharpening Radius/Amount/Detail/Masking and wired Masking into
`RenderPipeline.applyDetailControls` (Sources/KromoraKit/Models/RenderPipeline.swift), which
derives a CIEdges-based matte to restrict sharpening to strong edges. The evaluation this
feature was derived from (`.context/2026-09-22-professional-polish-evaluation.md` §2.2) calls
out Lightroom's Alt-preview (hold a modifier while dragging Masking to see the black/white
mask full-screen) as a headline feature on its own -- the slider alone is not the acceptance bar.

KRMA-598 shipped the underlying masking math and persistence but explicitly deferred the
preview UI (see its implementation comment and verification report).

## Acceptance criteria

- [ ] While adjusting sharpening Masking (drag or equivalent interaction), show a live
      grayscale preview of the derived edge mask over the image.
- [ ] The preview reuses the same mask CIImage `RenderPipeline.applyDetailControls` already
      computes, rather than a second implementation, so the preview matches the applied result.
- [ ] Regression coverage for the preview's visibility/dismissal and that it does not mutate
      the edit document (preview-only, like existing crop/comparison overlays).

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum,
Swift 6 safety, and zero third-party dependencies.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
