---
id: KRMA-686
title: Remove intermittent white stroke from displayed images
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce the artifact or establish a deterministic fixture and record conditions that trigger it
      result: pass
      notes: Codex reproduced with an opaque 8x4 fixture fit into a 12x12 canvas at a fractional scale, isolating the Core Image presentation fallback path in PreviewSurfaceView.
    - criterion: Trace the artifact to the responsible stage and remove its cause rather than covering it
      result: pass
      notes: "Root cause: presentationImage() transformed the source and let the destination compositor filter across the finite CIImage extent edge, blending canvas background into edge texels; the Metal quad path clamped to the edge texel instead. Fix extends edge samples via clampedToExtent() before the transform, then crops back to the untouched transformed bounds (PreviewSurface.swift:1221-1237), rather than adding a masking/compositing workaround."
    - criterion: No unintended white pixels/outline/band at image edges; confirm export if it shares the path
      result: pass
      notes: New regression test compares fallback vs Metal perimeter pixels within tolerance 2 and passes. Export uses RenderEngine.opaqueImage(), a separate 1:1 (no fractional-scale transform) compositing path that does not exhibit this failure mode, confirmed by code inspection (RenderEngine.swift:1090-1098).
    - criterion: Preserve intended bounds, crop, orientation, edge pixels, alpha; no removed editor overlays
      result: pass
      notes: Fix crops back to the original transformed.extent and destination after edge-extending, so framing/alpha outside the image is unchanged; no overlay/control code touched.
    - criterion: Add regression coverage for the triggering condition with a deterministic fixture
      result: pass
      notes: testPresentationFallbackDoesNotBlendCanvasIntoPhotoPerimeter added to PreviewSurfaceTests.swift, comparing fallback and Metal perimeter pixels; included in the 41-test suite run.
    - criterion: Record verification commands and results; visually inspect where reproduction requires it
      result: pass
      notes: Re-ran swift build, swift test --filter PreviewSurfaceTests, and git diff --check independently below; pixel-level regression test substitutes for a manual screenshot inspection since the original screenshot was unavailable.
  checks_run:
    - swift build — pass
    - swift test --filter PreviewSurfaceTests — pass (41 tests, 0 failures)
    - git diff --check HEAD~1 -- Sources/KromoraKit/Views/PreviewSurface.swift Tests/KromoraKitTests/PreviewSurfaceTests.swift — pass
  findings: []
  fixes: []
  verification_commits:
    - 27c3878
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T15:50:42.555Z
  session: 01MULFABNBS0GLI1T6
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - bug
  - rendering
created: 2026-09-28T15:38:45.312Z
updated: 2026-09-28T15:50:42.558Z
blockers: []
order: a0
board: product
commits:
  - 27c3878
---

## Objective

Find and eliminate the intermittent, unintended white stroke that appears along images in Kromora. The displayed photograph should contain only its actual image content, without a white outline or edge band introduced by loading, rendering, compositing, scaling, or presentation.

## User report

The user reports: “sometimes images have a white stroke ... they should not.” The attached screenshot could not be read in this environment (macOS returned `Operation not permitted` for the temporary screenshot path), so its specific image, view, and reproduction steps are not available in this ticket yet.

## Expected behavior

Images display and export without an added white stroke at their perimeter. Image framing, crop, orientation, transparency where supported, and legitimate editor UI (such as selection or comparison indicators) continue to behave as designed.

## Acceptance criteria

- [ ] Reproduce the artifact or establish a deterministic fixture and record the conditions that trigger it, including the affected image/view and relevant display or export path.
- [ ] Trace the artifact to the responsible stage (for example source preparation, Core Image/Metal rendering, compositing, thumbnail generation, scaling, or view presentation) and remove its cause rather than covering it with another layer.
- [ ] No unintended white pixels, outline, or band are introduced at image edges in the affected display path; confirm full-resolution export as well if it shares the affected path or also reproduces the issue.
- [ ] Preserve the image's intended bounds, crop, orientation, edge pixels, and supported alpha behavior; do not remove intentional editor controls or overlays as a workaround.
- [ ] Add regression coverage that exercises the triggering condition with a deterministic image/fixture and detects a perimeter stroke. Include the relevant preview, thumbnail, comparison, or export boundary identified during investigation.
- [ ] Record the verification commands and results, and visually inspect the affected output when the reproduction requires visual confirmation.

## Investigation notes

Start by checking whether the white stroke is present in rendered pixel data or only appears in a particular view. Compare the same source through the applicable preview, thumbnail, comparison, and export paths; inspect image extent/crop, color-space conversion, interpolation, alpha compositing, and any edge padding or border drawing along the path that reproduces it. Narrow the scope once the screenshot or a reproducible source is available.

## Context and reproduction

- Reported frequency: intermittent (“sometimes”).
- Reported symptom: white stroke along images; no stroke is desired.
- Source image, editing state, and exact screen/export location: not yet known.
- Screenshot: referenced by the user, but unavailable to this session because the temporary file could not be read. Request/reuse an accessible copy only if needed to reproduce or judge the fix.

## Suggested checks

- `swift build`
- Focused regression test(s) for the identified render/presentation boundary.
- Relevant CI lane(s) for changed render or UI behavior.
- `git diff --check`


### Comment — codex @ 2026-09-28T15:48:56.547Z

Reproduced the perimeter artifact in the Core Image presentation fallback using an opaque 8×4 fixture fit into a 12×12 canvas: fractional scaling blended the canvas into the transformed image edge, while the Metal path clamped to its edge texel. The fallback now extends edge samples for filtering and clips back to the original transformed bounds, preserving framing and alpha outside the image. Added perimeter regression coverage comparing fallback and Metal output. Verified: swift test --filter PreviewSurfaceTests (41 passed), swift build (passed), git diff --check (passed). Full-resolution export uses a separate RenderEngine path and does not share this presentation compositor. Commit: 27c3878.

## Agent log

- 2026-09-28T15:50:42.556Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce the artifact or establish a deterministic fixture and record conditions that trigger it (pass) — Codex reproduced with an opaque 8x4 fixture fit into a 12x12 canvas at a fractional scale, isolating the Core Image presentation fallback path in PreviewSurfaceView.
- [x] Trace the artifact to the responsible stage and remove its cause rather than covering it (pass) — Root cause: presentationImage() transformed the source and let the destination compositor filter across the finite CIImage extent edge, blending canvas background into edge texels; the Metal quad path clamped to the edge texel instead. Fix extends edge samples via clampedToExtent() before the transform, then crops back to the untouched transformed bounds (PreviewSurface.swift:1221-1237), rather than adding a masking/compositing workaround.
- [x] No unintended white pixels/outline/band at image edges; confirm export if it shares the path (pass) — New regression test compares fallback vs Metal perimeter pixels within tolerance 2 and passes. Export uses RenderEngine.opaqueImage(), a separate 1:1 (no fractional-scale transform) compositing path that does not exhibit this failure mode, confirmed by code inspection (RenderEngine.swift:1090-1098).
- [x] Preserve intended bounds, crop, orientation, edge pixels, alpha; no removed editor overlays (pass) — Fix crops back to the original transformed.extent and destination after edge-extending, so framing/alpha outside the image is unchanged; no overlay/control code touched.
- [x] Add regression coverage for the triggering condition with a deterministic fixture (pass) — testPresentationFallbackDoesNotBlendCanvasIntoPhotoPerimeter added to PreviewSurfaceTests.swift, comparing fallback and Metal perimeter pixels; included in the 41-test suite run.
- [x] Record verification commands and results; visually inspect where reproduction requires it (pass) — Re-ran swift build, swift test --filter PreviewSurfaceTests, and git diff --check independently below; pixel-level regression test substitutes for a manual screenshot inspection since the original screenshot was unavailable.
Checks run:
- swift build — pass
- swift test --filter PreviewSurfaceTests — pass (41 tests, 0 failures)
- git diff --check HEAD~1 -- Sources/KromoraKit/Views/PreviewSurface.swift Tests/KromoraKitTests/PreviewSurfaceTests.swift — pass
Findings:
- None
Fixes:
- None
Verification commits:
- 27c3878
Actor: claude
Resolved model: sonnet
Pickup session: 01MULFABNBS0GLI1T6
Summary: Independently verified the Core Image presentation-fallback perimeter fix: rebuilt, reran the full PreviewSurfaceTests suite (41/41 passing including the new regression test), reviewed the export and thumbnail paths for the same failure mode (unaffected), and confirmed git diff --check is clean.
