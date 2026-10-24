---
id: KRMA-700
title: Keep zoomed image previews sharp during edit slider drags
type: bug
status: done
priority: medium
agent: claude
verification_agent: codex
model: sonnet
thinking: high
verification_model: gpt-6-luna
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce the quality drop while dragging adjustment controls at multiple zoom levels and record the render path and conditions.
      result: pass
      notes: Human verification recorded under KRMA-713 confirms the remaining blur is now acceptable. Code review confirms adjustment renders use the interactive RenderScale path with the visible ROI area fraction.
    - criterion: Identify why interactive renders lose detail during a drag and why the full clarity returns on release.
      result: pass
      notes: Interactive decode uses an ROI-aware quality budget while settled preview uses its independent uncapped preview path. The current implementation allocates 4 MP to zoomed visible regions, preserves the 1.5 MP fit budget, and caps source-wide interactive decode at 36 MP.
    - criterion: Keep the zoomed preview acceptably sharp throughout adjustment drags, including at higher zoom levels, while preserving responsive feedback.
      result: pass
      notes: The human reviewer confirmed the blur is acceptable now in KRMA-713. Budget tests cover multiple zoom levels and enforce the source-wide ceiling; PreviewCoordinator tests cover coalescing and interactive submission behavior.
    - criterion: Ensure the final preview after release remains correct and does not show stale or lower-resolution output.
      result: pass
      notes: The settled preview scale remains independent of the interactive ROI budget; RenderRequestTests cover settled quality across zoom levels, and preview publication tests pass.
    - criterion: Add regression coverage for interactive and settled preview quality at more than one zoom level; record verification commands and results.
      result: pass
      notes: RenderRequestTests and CropROITests cover interactive and settled detail across zoom levels, visible-pixel budget, layout alignment, and the absolute decode ceiling.
  checks_run:
    - swift test --filter 'CropROITests|RenderRequestTests|Render.*Tests|PreviewCutoverTests|PreviewCoordinatorTests' — passed, 221 tests executed, 10 skipped, 0 failures.
    - scripts/ci-tests.sh fast — passed, all 1,344 required_fast tests completed with exit code 0.
    - dg validate — passed; emitted only model-name warnings.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-09-29T23:01:25.523Z
  session: 01MUNA1XXXDJKH6BIC
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - bug
  - rendering
created: 2026-09-28T23:36:50.934Z
updated: 2026-09-29T23:01:25.526Z
depends_on:
  - KRMA-701
  - KRMA-713
blockers: []
order: a0
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

### Comment — claude @ 2026-09-29T14:42:13.254Z

Human note: zoomed drags still blurred. Root cause: the earlier ROI-scaled budget kept the visible region at ~1.5 MP (and 6 MP source-wide at deep zoom), about half a retina viewport, so the ROI texture was upscaled ~2x during drags. Zoomed requests (ROI < source) now budget 4 MP visible pixels under a 36 MP source-wide ceiling; fit views keep 1.5 MP; settled path unchanged. Tests: RenderRequestTests, CropROITests (new zoomed-visible-pixels + ceiling cases), Render*/PreviewCutover/PreviewCoordinator suites pass. scripts/ci-tests.sh fast has one failure, ThumbnailSwitchLifecycleTests.testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument, which also fails with RenderScale.swift reverted to HEAD (unrelated to this change). Not verified by eye in the running app.

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

## HUMAN NOTE

This still blurs significantly when making adjustments while zoomed on an image.

- 2026-09-29T14:47:05.685Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Reproduce the quality drop while dragging adjustment controls at multiple zoom levels and record the render path and conditions. (pass) — Code and regression-test inspection confirms interactive requests use RenderScale.interactive with the visible ROI area fraction. The human reviewer reports the quality drop remains after the latest change; the latest behavior was not personally verified in the running app during this verification.
- [x] Identify why interactive renders lose detail during a drag and why the full clarity returns on release (for example, a preview render scale, resolution, or cache path change). (pass) — Interactive decoding is quality-limited while the settled preview uses its independent preview path. KRMA-700 raised the zoomed visible budget to 4 MP under a 36 MP source-wide cap, but current unit tests only validate modeled pixel budgets, not the perceived sharpness of the presented frame.
- [ ] Keep the zoomed preview acceptably sharp throughout adjustment drags, including at higher zoom levels, while preserving responsive feedback. (fail) — The human review after commit cb7444f says the image still blurs significantly during zoomed adjustments. The numeric budget tests pass, but the acceptance criterion is perceptual and remains unmet.
- [x] Ensure the final preview after release remains correct and does not show stale or lower-resolution output. (pass) — The settled path is unchanged by the budget update; the focused RenderRequest and preview tests passed.
- [x] Add regression coverage for interactive and settled preview quality at more than one zoom level; record verification commands and results. (pass) — RenderRequestTests.testInteractivePixelBudgetTracksVisibleROIAcrossZoomLevels and CropROITests cover multiple zoom levels and the fit/zoomed budget policy; the focused render/preview suite passed. These are proxy/budget assertions and do not cover perceived sharpness in the running app.
Checks run:
- scripts/ci-tests.sh fast — failed: 1,338 tests reached; ThumbnailSwitchLifecycleTests.testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument failed with two stale-thumbnail assertions. The issue handoff reports the same failure also occurs with RenderScale.swift reverted; this session did not independently run that baseline.
- swift test --filter 'CropROITests|RenderRequestTests|Render.*Tests|PreviewCutoverTests|PreviewCoordinatorTests' — passed, 220 tests executed, 10 skipped, 0 failures.
- dg validate — passed; emitted only model-name warnings, including pre-existing repository warnings.
Findings:
- correctness/blocker: The human reviewer reports significant blur persists during zoomed adjustment drags after the 4 MP visible-ROI budget change in cb7444f. Current regression tests assert calculated pixel budgets but do not establish perceived sharpness or responsiveness in the running app. Urgent child KRMA-713 (verification, parent KRMA-700) tracks on-device reproduction, diagnosis, and a bounded fix.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MUMSCD6G5R3O3W6L
Summary: Significant blur remains during zoomed adjustment drags per human review; budget tests pass but do not verify perceived sharpness in the app. Urgent child KRMA-713 tracks on-device diagnosis and fix. Fast CI has one reported unrelated ThumbnailSwitchLifecycleTests failure.

## HUMAN NOTE UPDATE
This no longer blurs and is ready to be verified .

- 2026-09-29T23:01:25.523Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce the quality drop while dragging adjustment controls at multiple zoom levels and record the render path and conditions. (pass) — Human verification recorded under KRMA-713 confirms the remaining blur is now acceptable. Code review confirms adjustment renders use the interactive RenderScale path with the visible ROI area fraction.
- [x] Identify why interactive renders lose detail during a drag and why the full clarity returns on release. (pass) — Interactive decode uses an ROI-aware quality budget while settled preview uses its independent uncapped preview path. The current implementation allocates 4 MP to zoomed visible regions, preserves the 1.5 MP fit budget, and caps source-wide interactive decode at 36 MP.
- [x] Keep the zoomed preview acceptably sharp throughout adjustment drags, including at higher zoom levels, while preserving responsive feedback. (pass) — The human reviewer confirmed the blur is acceptable now in KRMA-713. Budget tests cover multiple zoom levels and enforce the source-wide ceiling; PreviewCoordinator tests cover coalescing and interactive submission behavior.
- [x] Ensure the final preview after release remains correct and does not show stale or lower-resolution output. (pass) — The settled preview scale remains independent of the interactive ROI budget; RenderRequestTests cover settled quality across zoom levels, and preview publication tests pass.
- [x] Add regression coverage for interactive and settled preview quality at more than one zoom level; record verification commands and results. (pass) — RenderRequestTests and CropROITests cover interactive and settled detail across zoom levels, visible-pixel budget, layout alignment, and the absolute decode ceiling.
Checks run:
- swift test --filter 'CropROITests|RenderRequestTests|Render.*Tests|PreviewCutoverTests|PreviewCoordinatorTests' — passed, 221 tests executed, 10 skipped, 0 failures.
- scripts/ci-tests.sh fast — passed, all 1,344 required_fast tests completed with exit code 0.
- dg validate — passed; emitted only model-name warnings.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MUNA1XXXDJKH6BIC
Summary: Verification passed: zoomed adjustment preview quality is human-confirmed acceptable; focused render/preview tests, fast CI, and dg validate passed.
