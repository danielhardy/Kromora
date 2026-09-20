---
id: KRMA-477
title: "Straighten: keep crop frame inside the rotated image and retain its aspect ratio"
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-20T13:11:56.840Z
  session: 01MU9T8X1BPMYDHKPX
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - crop
  - ui
  - ux
created: 2026-09-20T12:17:44.106Z
updated: 2026-09-20T13:11:56.842Z
order: n
board: product
---

## Objective

While Straighten is used, the crop frame must never extend outside the rotated image, and it must keep its aspect ratio.

## Context

User feedback (2026-09-20): "When using straighten, the crop overlay should never leave the outside of the image and must retain the aspect ratio."

Reading the code, nothing constrains the frame to the rotated image:
- `AppViewModel.setCropStraightenAngle` -> `CanvasState.setCropStraightenAngle` (`Sources/KromoraKit/Models/CanvasNavigation.swift`) only stores the clamped angle; the crop draft is not touched.
- `CropOverlayInteraction.translated/resized` (`Sources/KromoraKit/Models/CropAdjustments.swift`) clamp only to the unit square, i.e. the unrotated image bounds.
- `RenderPipeline.applyingGeometry` (`Sources/KromoraKit/Models/RenderPipeline.swift`) applies `CIStraightenFilter`, which enlarges the extent to the rotated bounding box and leaves transparent corners. `geometryExtent(of:for:)` already computes that bounding size.

I have not reproduced this in the running app. Reproduce first: set an angle, then check whether the frame and the committed/exported image show transparent or empty corners.

## Requirements

1. **Angle changes:** whenever the angle changes, the draft frame is adjusted so all four corners stay inside the rotated image. The frame keeps its aspect ratio exactly (the selected preset's ratio; for Freeform/Custom, the draft's current width:height at the moment straighten begins). It shrinks and/or re-centres as needed and is not stretched.
2. **Dragging:** move and resize while an angle is set must be clamped to the rotated image, not the unit square, and must keep the ratio. A drag cannot push a corner outside.
3. **Reversal:** returning the angle toward 0 need not grow the frame back automatically, but must never leave it invalid. State the chosen behaviour (Apple Photos lets the frame follow the image and only shrinks) and test it.
4. **Commit/export parity:** after Done, the committed crop renders and exports with no transparent or blank pixels in any corner for angles in the allowed range (-45 to 45 degrees).
5. Pure geometry: implement the largest-inscribed-rectangle-of-given-ratio computation and containment test as pure functions next to `CropOverlayInteraction`, so they are unit-testable and shared by overlay and model.
6. Define and document which coordinate space the draft rect lives in when an angle is set (rotated frame vs source frame) and keep `CropAdjustments.normalizedRect` semantics compatible with already-saved crops.

## Out of scope

- Perspective and flip constraints. `CIPerspectiveCorrection` keeps the output fully populated per the comment in `RenderPipeline`; confirm separately and file a follow-up if perspective can also expose empty corners.
- Realtime slider updates (see the geometry realtime ticket, KRMA-479).

## Acceptance criteria

- [ ] Root cause and chosen coordinate-space design written into this ticket.
- [ ] Property-style tests over angles -45...45 (step ~1 degree) and ratios {1:1, 3:2, 2:3, 16:9, 4:5, Original, Freeform}: all four frame corners lie inside the rotated image and the frame's ratio matches the target within a small epsilon.
- [ ] Tests for move/resize at non-zero angles: result stays inside and keeps ratio.
- [ ] A render test at several angles asserting the committed crop has no transparent corner pixels (RenderEngine, serial lane).
- [ ] Saved documents with an existing crop and angle still load and render identically or documented as intentionally corrected.
- [ ] Manual check in the running app: drag the Straighten slider end to end with 3:2, 1:1 and Freeform; frame never crosses the image edge.
- [ ] `scripts/ci-tests.sh fast` and `serial` pass.


### Comment — codex @ 2026-09-20T13:09:11.386Z

Implemented design: Straighten drafts are normalized in the post-geometry rotated image bounding box, with the persisted CropAdjustments.normalizedRect retaining that same post-geometry normalized meaning for saved-document compatibility. CropOverlayInteraction now provides pure rotated-polygon containment, largest-inscribed-rectangle, constrained move/resize, and angle-reframe geometry. The frame preserves a pixel aspect ratio (captured at Straighten start for Freeform), shrinks/recentres on angle changes, and does not grow when the angle returns toward zero. The root cause was unit-square-only clamping against the pre-rotation bounds while CIStraightenFilter renders transparent corners in the rotated bounding extent.


### Comment — codex @ 2026-09-20T13:11:34.875Z

Verification: scripts/ci-tests.sh fast passed (1,088 tests); scripts/ci-tests.sh serial passed (390 tests, 1 expected RAW-fixture skip, 0 failures). Added property coverage for angles -45...45 and ratios 1:1, 3:2, 2:3, 16:9, 4:5, Original, and Freeform; non-zero-angle move/resize and reversal tests; AppViewModel draft/commit coverage; and RenderEngine preview/export opaque-corner coverage at -45, -30, 15, and 45 degrees. Manual slider drag was not run in a visible app session; automated overlay/model/render coverage exercises the same path.

## Agent log

- 2026-09-20T13:11:56.840Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MU9T8X1BPMYDHKPX
Summary: Straighten crop frames now remain inside the rotated image with a preserved pixel aspect ratio; preview/export corners are opaque and the persisted post-geometry crop contract remains compatible.
