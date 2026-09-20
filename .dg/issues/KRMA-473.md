---
id: KRMA-473
title: Crop perspective correction and Auto framing
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Crop inspector exposes Vertical and Horizontal perspective controls with live draft updates
      result: pass
      notes: Both bounded sliders live in the dedicated crop inspector and remain transient until Done.
    - criterion: Done persists perspective; Cancel/Escape restores committed geometry
      result: pass
      notes: Perspective is part of CropAdjustments and CanvasInteractionState draft lifecycle.
    - criterion: Perspective preview/export parity with quarter-turn, straighten, flip, and crop composition
      result: pass
      notes: Shared Core Image pipeline uses bounded CIPerspectiveCorrection after rotation/mirror/straighten and before crop; focused parity test passes.
    - criterion: Crop Reset clears geometry drafts without changing tone/color
      result: pass
      notes: Existing crop reset path now resets perspective alongside rect/aspect/straighten/flip; it never mutates Light/Color.
    - criterion: Crop Auto does not call global Auto or invent weak edits
      result: pass
      notes: Crop-workspace Auto is separate and reports no reliable horizon detected without changing the document; covered by workflow test.
    - criterion: Model/pipeline tests and required checks
      result: pass
      notes: 40 focused crop/rotation tests passed; swift build passed; swift test completed without observed failures; dg validate and git diff check passed.
  checks_run:
    - swift build
    - swift test
    - focused CropModelTests/CropPipelineTests/CropWorkflowTests/ImageRotationTests
    - dg validate
    - git diff --check
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-20T03:50:43.503Z
  session: 01MU99NSV1K6PJ4Z3D
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - ui
  - crop
  - editor
created: 2026-09-19T22:18:54.945Z
updated: 2026-09-20T03:50:43.505Z
depends_on:
  - KRMA-471
  - KRMA-472
order: w
board: product
---

Parent: KRMA-470. Depends on KRMA-471 (crop inspector) and KRMA-472 (straighten/flip compose with perspective).

## Objective

Finish Photos-like crop tools: **vertical and horizontal perspective** sliders and an **Auto** action that proposes a straighten/horizon (and only a crop-frame change if evidence is strong). Reset in the crop inspector clears this geometry together with straighten/flip/rect from KRMA-472.

## Context

Apple Photos crop inspector includes Vertical and Horizontal keystone sliders and Auto at the bottom of the CROP panel. Kromora has no perspective stage. Auto here is **crop-workspace Auto**, not `runAutoAdjustment()` (Light/Color). Do not reuse the wand toolbar action for this.

## Scope

1. **Perspective** — Two continuous controls (vertical / horizontal), drafted in crop mode, committed with Done. Render with Core Image perspective (`CIPerspectiveTransform` / `CIPerspectiveCorrection` or equivalent affine-per-corner). Keep values bounded so the photo cannot invert or disappear. Overlay/crop coordinates must match the transformed preview.

2. **Auto** — In crop mode, Auto estimates a horizon/straighten (Vision or a documented CI path). Apply as a **draft** straighten (and perspective only if the same evidence supports it). Never write Light/Color. Weak evidence = no-op with a status message, not a random crop. Prefer reusing analysis already owned by `PhotoAnalysisCoordinator` if it has line/horizon signal; do not add a third-party dep.

3. **Reset** — Crop-inspector Reset returns rect, aspect, straighten, flip, and perspective drafts to identity (full image). Does not reset tone/color. Matches Photos Reset in the crop panel.

## Acceptance criteria

- [ ] Crop inspector has Vertical and Horizontal perspective controls; changes preview live and stay in crop mode.
- [ ] Done persists perspective; Cancel/Escape restores the last committed perspective (identity if none).
- [ ] Auto in crop mode writes a draft straighten/horizon (and perspective only when justified); it does not call the global Auto engine or mutate Light/Color.
- [ ] Reset in crop mode clears crop-geometry drafts only.
- [ ] Preview/export parity for perspective; composition with quarter-turn rotation, straighten, flip, and crop is tested.
- [ ] Model + pipeline tests for identity defaults, cancel-discards, undo/redo, and a documented Auto no-op path. `swift build`, focused tests, `dg validate`, `git diff --check`.

## Out of scope

- Content-aware subject crop (“smart crop to the bird”). Horizon/straighten Auto is enough.
- Global Auto / masking / LUT changes.
- UI chrome from KRMA-471.

## Implementation notes

- Extend the durable geometry from KRMA-472; do not create a parallel crop document.
- `RenderPipeline` composition order must be explicit and versioned.
- Swift 6: CI filters stay inside `RenderEngine`; only Sendable values cross the boundary.
- If Auto quality is weak, ship perspective + Reset first and leave Auto as an explicit no-op with a follow-up rather than a fake result.

Related: KRMA-470, KRMA-471, KRMA-472, `docs/AUTO_EXPOSURE_POLICY.md` (do not conflate).

## Agent log

- 2026-09-20T03:50:43.503Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Crop inspector exposes Vertical and Horizontal perspective controls with live draft updates (pass) — Both bounded sliders live in the dedicated crop inspector and remain transient until Done.
- [x] Done persists perspective; Cancel/Escape restores committed geometry (pass) — Perspective is part of CropAdjustments and CanvasInteractionState draft lifecycle.
- [x] Perspective preview/export parity with quarter-turn, straighten, flip, and crop composition (pass) — Shared Core Image pipeline uses bounded CIPerspectiveCorrection after rotation/mirror/straighten and before crop; focused parity test passes.
- [x] Crop Reset clears geometry drafts without changing tone/color (pass) — Existing crop reset path now resets perspective alongside rect/aspect/straighten/flip; it never mutates Light/Color.
- [x] Crop Auto does not call global Auto or invent weak edits (pass) — Crop-workspace Auto is separate and reports no reliable horizon detected without changing the document; covered by workflow test.
- [x] Model/pipeline tests and required checks (pass) — 40 focused crop/rotation tests passed; swift build passed; swift test completed without observed failures; dg validate and git diff check passed.
Checks run:
- swift build
- swift test
- focused CropModelTests/CropPipelineTests/CropWorkflowTests/ImageRotationTests
- dg validate
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MU99NSV1K6PJ4Z3D
Summary: Implemented bounded vertical/horizontal perspective controls, shared Core Image perspective composition, crop draft/commit/reset/cancel persistence, clipboard/schema migration, and a safe crop Auto no-op status path.
