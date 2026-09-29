---
id: KRMA-700
title: Keep zoomed image previews sharp during edit slider drags
type: bug
status: review
priority: medium
verification_report:
  verdict: blocker
  acceptance_criteria:
    - criterion: Reproduce the quality drop while dragging adjustment controls at multiple zoom levels and record the render path and conditions.
      result: pass
      notes: "Confirmed via code inspection of RenderRequest.renderScale/.interactive and RenderScale.targetSize: with the pre-fix code, the interactive frame budget (1.5 MP) was applied against the full planner-chosen targetSize (which approaches native resolution at high zoom per ResolutionPlanner.detailScales), so a deep-zoom drag downscaled the whole decode even though the visible ROI was a small fraction of the source."
    - criterion: Identify why interactive renders lose detail during a drag and why the full clarity returns on release (for example, a preview render scale, resolution, or cache path change).
      result: pass
      notes: RenderScale.interactive applied a fixed ~1.5 MP pixel budget to the full requested targetSize regardless of how small the actual visible ROI was, so zoomed interactive frames were downscaled far below the settled/.preview path, which uses the uncapped targetSize. Root cause and fix are in Sources/KromoraKit/Models/RenderScale.swift and RenderRequest.swift (commit 488241b).
    - criterion: Keep the zoomed preview acceptably sharp throughout adjustment drags, including at higher zoom levels, while preserving responsive feedback.
      result: fail
      notes: "The fix's mechanism (scale the interactive pixel budget up by 1/budgetAreaFraction, where budgetAreaFraction is the visible ROI's share of native area) is mathematically sound for the new regression test and does sharpen zoomed interactive frames. However it directly conflicts with a pre-existing, still-present invariant enforced by Tests/KromoraKitTests/CropROITests.swift:139 (testInteractiveZoomFragmentLayoutStaysInPlannerSpace), which asserts interactive quality must always decode at or below the fixed 1.5 MP budget regardless of the requested planner size. That test now fails: native 3000x2000, ROI 1200x800 (16% of native area), planner target 2400x1600 now decodes at the full 2400x1600 instead of the previously-required 1500px cap. This is a genuine, uncaught regression against an existing documented invariant (interactive decode must stay bounded so a rapid drag cannot monopolize the GPU past the next display tick), not a stale/obsolete test - it was not touched by the fix commit. The two behaviors are irreconcilable as written and one of them needs a product decision."
    - criterion: Ensure the final preview after release remains correct and does not show stale or lower-resolution output.
      result: pass
      notes: The .preview/settled path is untouched by this change (RenderRequest.renderScale only adds budgetAreaFraction under .interactive); RenderRequestTests.testInteractivePixelBudgetTracksVisibleROIAcrossZoomLevels confirms the settled factor still equals plan.scale at every tested zoom level.
    - criterion: Add regression coverage for interactive and settled preview quality at more than one zoom level; record verification commands and results.
      result: pass
      notes: RenderRequestTests.testInteractivePixelBudgetTracksVisibleROIAcrossZoomLevels covers 2x/4x/8x zoom for both interactive and settled quality and passes. However this new coverage was added without running the full required fast CI lane, which is how the CropROITests regression was missed.
  checks_run:
    - swift build (pass)
    - swift test --filter RenderRequestTests (pass, 7/7)
    - "scripts/ci-tests.sh fast (FAIL: CropROITests.testInteractiveZoomFragmentLayoutStaysInPlannerSpace - XCTAssertEqualWithAccuracy failed: (2400.0) is not equal to (1500.0) +/- (0.5) - the 1.5 MP interactive budget must actually decode below the planner size)"
    - dg validate (pass, pre-existing unrelated model-name warnings only)
  findings:
    - "correctness/blocker: RenderScale.targetSize's new budgetAreaFraction scaling (Sources/KromoraKit/Models/RenderScale.swift:38-54, introduced by 488241b for KRMA-700) removes the interactive quality tier's absolute pixel ceiling whenever the visible ROI is a small fraction of the source, which is exactly the deep-zoom case this ticket targets. This breaks Tests/KromoraKitTests/CropROITests.swift:139 (testInteractiveZoomFragmentLayoutStaysInPlannerSpace), a pre-existing test asserting interactive decode must stay at or below 1.5 MP regardless of requested target size. Filed as child ticket KRMA-701 (urgent) to reconcile: either the ROI-scaled budget is the intended new policy and the old test needs updating with a recorded product decision, or the fix needs an absolute ceiling (e.g. cap the ROI-scaled budget at some bounded multiple of 1.5 MP) so a rapid slider drag at deep zoom cannot make interactive RAW decode arbitrarily large."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T01:34:00.850Z
  session: 01MULZTZK8IKJNXZBV
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - bug
  - rendering
created: 2026-09-28T23:36:50.934Z
updated: 2026-09-29T01:34:00.955Z
depends_on:
  - KRMA-701
blockers: []
order: v
board: product
---

## Objective

Keep the zoomed photo preview clear while edit adjustments are being dragged, without making slider interaction unresponsive.

## User report

In Edit mode, zoom into a picture and drag an adjustment slider (light, color, effects, and similar controls). The image becomes blurry or pixelated during the drag, then becomes clear again when the mouse button is released. The stronger the zoom, the more noticeable the blur/pixelation.

## Acceptance criteria

- [ ] Reproduce the quality drop while dragging adjustment controls at multiple zoom levels and record the render path and conditions.
- [ ] Identify why interactive renders lose detail during a drag and why the full clarity returns on release (for example, a preview render scale, resolution, or cache path change).
- [ ] Keep the zoomed preview acceptably sharp throughout adjustment drags, including at higher zoom levels, while preserving responsive feedback.
- [ ] Ensure the final preview after release remains correct and does not show stale or lower-resolution output.
- [ ] Add regression coverage for interactive and settled preview quality at more than one zoom level; record verification commands and results.

## Investigation notes

Compare the preview render scale and source resolution during slider changes and after commit/mouse-up. Exercise adjustments from the light, color, and effects groups, and distinguish a deliberate performance-quality tradeoff from an unintended resolution drop.

## Agent log

- 2026-09-29T01:34:00.954Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Reproduce the quality drop while dragging adjustment controls at multiple zoom levels and record the render path and conditions. (pass) — Confirmed via code inspection of RenderRequest.renderScale/.interactive and RenderScale.targetSize: with the pre-fix code, the interactive frame budget (1.5 MP) was applied against the full planner-chosen targetSize (which approaches native resolution at high zoom per ResolutionPlanner.detailScales), so a deep-zoom drag downscaled the whole decode even though the visible ROI was a small fraction of the source.
- [x] Identify why interactive renders lose detail during a drag and why the full clarity returns on release (for example, a preview render scale, resolution, or cache path change). (pass) — RenderScale.interactive applied a fixed ~1.5 MP pixel budget to the full requested targetSize regardless of how small the actual visible ROI was, so zoomed interactive frames were downscaled far below the settled/.preview path, which uses the uncapped targetSize. Root cause and fix are in Sources/KromoraKit/Models/RenderScale.swift and RenderRequest.swift (commit 488241b).
- [ ] Keep the zoomed preview acceptably sharp throughout adjustment drags, including at higher zoom levels, while preserving responsive feedback. (fail) — The fix's mechanism (scale the interactive pixel budget up by 1/budgetAreaFraction, where budgetAreaFraction is the visible ROI's share of native area) is mathematically sound for the new regression test and does sharpen zoomed interactive frames. However it directly conflicts with a pre-existing, still-present invariant enforced by Tests/KromoraKitTests/CropROITests.swift:139 (testInteractiveZoomFragmentLayoutStaysInPlannerSpace), which asserts interactive quality must always decode at or below the fixed 1.5 MP budget regardless of the requested planner size. That test now fails: native 3000x2000, ROI 1200x800 (16% of native area), planner target 2400x1600 now decodes at the full 2400x1600 instead of the previously-required 1500px cap. This is a genuine, uncaught regression against an existing documented invariant (interactive decode must stay bounded so a rapid drag cannot monopolize the GPU past the next display tick), not a stale/obsolete test - it was not touched by the fix commit. The two behaviors are irreconcilable as written and one of them needs a product decision.
- [x] Ensure the final preview after release remains correct and does not show stale or lower-resolution output. (pass) — The .preview/settled path is untouched by this change (RenderRequest.renderScale only adds budgetAreaFraction under .interactive); RenderRequestTests.testInteractivePixelBudgetTracksVisibleROIAcrossZoomLevels confirms the settled factor still equals plan.scale at every tested zoom level.
- [x] Add regression coverage for interactive and settled preview quality at more than one zoom level; record verification commands and results. (pass) — RenderRequestTests.testInteractivePixelBudgetTracksVisibleROIAcrossZoomLevels covers 2x/4x/8x zoom for both interactive and settled quality and passes. However this new coverage was added without running the full required fast CI lane, which is how the CropROITests regression was missed.
Checks run:
- swift build (pass)
- swift test --filter RenderRequestTests (pass, 7/7)
- scripts/ci-tests.sh fast (FAIL: CropROITests.testInteractiveZoomFragmentLayoutStaysInPlannerSpace - XCTAssertEqualWithAccuracy failed: (2400.0) is not equal to (1500.0) +/- (0.5) - the 1.5 MP interactive budget must actually decode below the planner size)
- dg validate (pass, pre-existing unrelated model-name warnings only)
Findings:
- correctness/blocker: RenderScale.targetSize's new budgetAreaFraction scaling (Sources/KromoraKit/Models/RenderScale.swift:38-54, introduced by 488241b for KRMA-700) removes the interactive quality tier's absolute pixel ceiling whenever the visible ROI is a small fraction of the source, which is exactly the deep-zoom case this ticket targets. This breaks Tests/KromoraKitTests/CropROITests.swift:139 (testInteractiveZoomFragmentLayoutStaysInPlannerSpace), a pre-existing test asserting interactive decode must stay at or below 1.5 MP regardless of requested target size. Filed as child ticket KRMA-701 (urgent) to reconcile: either the ROI-scaled budget is the intended new policy and the old test needs updating with a recorded product decision, or the fix needs an absolute ceiling (e.g. cap the ROI-scaled budget at some bounded multiple of 1.5 MP) so a rapid slider drag at deep zoom cannot make interactive RAW decode arbitrarily large.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULZTZK8IKJNXZBV
Summary: KRMA-700's fix (commit 488241b) correctly sharpens zoomed interactive previews, but it removes the interactive quality tier's absolute 1.5 MP decode ceiling whenever the visible ROI is small, which regresses the pre-existing invariant test CropROITests.testInteractiveZoomFragmentLayoutStaysInPlannerSpace and fails the required scripts/ci-tests.sh fast lane. Filed urgent child KRMA-701 to reconcile the two requirements before this can pass verification.
