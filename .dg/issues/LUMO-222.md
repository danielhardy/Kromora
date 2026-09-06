---
id: LUMO-222
title: Add editable radial gradient masks
type: feature
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - epic:masking
  - masking
  - editor
  - rendering
created: 2026-09-04T21:48:30.922Z
updated: 2026-09-05T14:23:54.880Z
depends_on:
  - LUMO-221
order: z
board: product
commits:
  - 8cae573
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Create and edit radial ellipses with center, cardinal, corner, inner feather, and rotation handles
      result: pass
    - criterion: Persist normalized center, radii, rotation, feather, density, and inside/outside selection
      result: pass
    - criterion: Support Shift circle constraint, Option symmetric resize, inversion, keyboard nudging, cancel, and VoiceOver values
      result: pass
    - criterion: Evaluate aspect-correct analytic radial masks consistently across interactive, preview, and export resolutions without persisted rasters
      result: pass
    - criterion: Keep guides and hit targets aligned under non-square sources, crop, zoom, pan, resize, and Retina scale
      result: pass
  checks_run:
    - swift build
    - swift test --filter LocalMaskTests|MaskingWorkspaceTests|LocalMaskRenderingTests|CanvasNavigationTests (34 passed)
    - "swift test (863 tests: 23 pre-existing failures matching the baseline documented in LUMO-231, 42 skipped)"
    - git diff --check
  findings:
    - Full-suite failures are pre-existing and unrelated; tracked by LUMO-231
  fixes: []
  verification_commits:
    - 8cae573
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-05T14:23:54.876Z
  session: 01MTOGKN3RBAMUK8O5
---

## Objective

Let users draw, resize, rotate, move, feather, invert, and later re-edit an elliptical radial mask.

## Context

Radial masks need source-normalized, aspect-correct geometry and clear inner/outer falloff guides.
Without one shared geometry contract, non-square photos and zoomed/cropped canvases will make the
handles disagree with the rendered selection.

## Acceptance criteria

- [ ] Dragging creates an ellipse from an initial center; the center moves it, cardinal handles
      resize an axis, corner handles resize both axes, and a rotation handle edits angle.
- [ ] Inner and outer ellipses visualize falloff; feather can be edited from the inspector or by
      dragging the inner boundary.
- [ ] Persist normalized center, radii, rotation, feather, density, and inside/outside selection.
- [ ] Shift constrains to a circle, Option resizes symmetrically, and invert switches inside/outside
      without destroying geometry.
- [ ] The renderer evaluates an aspect-correct analytic mask consistently at interactive, preview,
      and export resolutions without a persisted raster.
- [ ] Handles retain screen-point hit sizes and align under orientation, crop, fit/fill, zoom, pan,
      window resize, Retina scale, and non-square sources.
- [ ] Keyboard nudging, VoiceOver, cancel, undo/redo, persistence, reopen, source switching, and
      deselect/reselect editing are covered.

## Implementation notes

Follow Section 4.5 and Step 5 of `docs/MASKING_AND_LOCAL_ADJUSTMENTS_PLAN.md`. Reuse the linear
gradient's overlay, gesture ownership, hit testing, accessibility, and analytic-render patterns.

Pin aspect correction and rotation with pure geometry tests before wiring pointer behavior.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-05T14:23:54.878Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Create and edit radial ellipses with center, cardinal, corner, inner feather, and rotation handles (pass)
- [x] Persist normalized center, radii, rotation, feather, density, and inside/outside selection (pass)
- [x] Support Shift circle constraint, Option symmetric resize, inversion, keyboard nudging, cancel, and VoiceOver values (pass)
- [x] Evaluate aspect-correct analytic radial masks consistently across interactive, preview, and export resolutions without persisted rasters (pass)
- [x] Keep guides and hit targets aligned under non-square sources, crop, zoom, pan, resize, and Retina scale (pass)
Checks run:
- swift build
- swift test --filter LocalMaskTests|MaskingWorkspaceTests|LocalMaskRenderingTests|CanvasNavigationTests (34 passed)
- swift test (863 tests: 23 pre-existing failures matching the baseline documented in LUMO-231, 42 skipped)
- git diff --check
Findings:
- Full-suite failures are pre-existing and unrelated; tracked by LUMO-231
Fixes:
- None
Verification commits:
- 8cae573
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTOGKN3RBAMUK8O5
Summary: Implemented editable radial gradient masks with source-pixel-correct geometry, interactive editing, and analytic rendering.
