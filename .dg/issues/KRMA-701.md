---
id: KRMA-701
title: Interactive RAW decode budget regression from ROI-scaled pixel cap
type: bug
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Decide and document whether interactive decode may exceed the historical 1.5 MP budget when the visible ROI is small, or whether an absolute ceiling must still apply.
      result: pass
      notes: RenderScale.targetSize now spends the 1.5 MP budget on the visible ROI (budgetAreaFraction) but caps the resulting pixel budget at a 6 MP source-wide ceiling (interactiveAbsolutePixelCeiling), both scaled proportionally by frameBudgetMilliseconds. Documented in docs/ENGINEERING_GUIDE.md and in RenderScale.swift doc comments.
    - criterion: Update CropROITests.testInteractiveZoomFragmentLayoutStaysInPlannerSpace (if ROI-scaled policy is permanent) or RenderScale.targetSize (if an absolute ceiling must be restored) so both tests encode one consistent policy.
      result: pass
      notes: Test renamed to testInteractiveZoomFragmentLayoutStaysInPlannerSpaceWithinROIShapedBudget and updated to assert the ROI-scaled decode stays within the planner box and under 1.5 MP for the visible ROI; new testInteractiveROIBudgetKeepsAbsoluteDecodeCeiling covers the 6 MP source-wide ceiling directly. RenderRequestTests updated to expect min(ROI budget, absolute ceiling).
    - criterion: scripts/ci-tests.sh fast passes end to end.
      result: pass
      notes: "Re-ran scripts/ci-tests.sh fast independently during verification: all 1334 tests executed, exit code 0, no failures, no compiler warnings."
  checks_run:
    - scripts/ci-tests.sh fast (1334/1334 tests passed, exit 0)
    - Manual re-derivation of the ROI-budget math (roiBudgetPixels vs absoluteBudgetPixels) against both new CropROITests cases and the RenderRequestTests expectation
    - Repo-wide grep for other references to the 1.5 MP / 6 MP budget constants to confirm no other test or doc still encodes the superseded absolute-only policy
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T01:42:57.675Z
  session: 01MUM0BTJFJTEB0WXC
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-29T01:29:38.345Z
updated: 2026-09-29T01:42:57.677Z
parent: KRMA-700
blockers: []
order: a0
board: product
---

## Objective

Commit 488241b (KRMA-700, "Keep zoomed interactive previews sharp") scales the interactive
pixel budget in `RenderScale.targetSize` up by `1 / budgetAreaFraction`, where
`budgetAreaFraction` is the visible ROI's share of the native source area. This directly
contradicts a pre-existing, still-present invariant test,
`CropROITests.testInteractiveZoomFragmentLayoutStaysInPlannerSpace`, which asserts that
interactive quality must always decode at or below the 1.5 MP frame budget regardless of the
requested planner size. Running the required fast CI lane (`scripts/ci-tests.sh fast`) fails
on this test after the KRMA-700 change: with native 3000x2000, ROI 1200x800 (16% of native
area), and a 2400x1600 planner target, the interactive decode now resolves to the full
2400x1600 (2400px effective native-scaled width) instead of being capped to 1500px as the
test requires.

Reconcile the two requirements: either update
`testInteractiveZoomFragmentLayoutStaysInPlannerSpace` to reflect a deliberately revised
policy (decode budget scales with visible ROI share, not the full requested box) with a
recorded product decision that the old absolute 1.5 MP-regardless-of-target-size cap is
superseded, or adjust the KRMA-700 fix so the interactive decode still respects an upper
absolute pixel/frame-time ceiling (e.g. cap the ROI-scaled budget at some multiple of 1.5 MP)
so a rapid slider drag at deep zoom cannot make interactive RAW decode arbitrarily large.

## Context

KRMA-700 raised the interactive frame budget by `1 / budgetAreaFraction` in
`Sources/KromoraKit/Models/RenderScale.swift` (`targetSize`) and
`Sources/KromoraKit/Models/RenderRequest.swift` (`renderScale`, `roiAreaFraction`). This
correctly fixes the reported blur-while-dragging-zoomed bug (verified against the new
`RenderRequestTests.testInteractivePixelBudgetTracksVisibleROIAcrossZoomLevels`), but the
same source file's existing budget invariant is enforced elsewhere by
`Tests/KromoraKitTests/CropROITests.swift:139` and was not updated or reconciled, so the
required `scripts/ci-tests.sh fast` lane now fails.

## Acceptance criteria

- [ ] Decide and document whether the interactive decode is allowed to exceed the historical
      1.5 MP budget when the visible ROI is small relative to the source, or whether an
      absolute ceiling must still apply.
- [ ] Update either `CropROITests.testInteractiveZoomFragmentLayoutStaysInPlannerSpace` (if the
      new ROI-scaled policy is the intended, permanent behavior) or `RenderScale.targetSize`
      (if an absolute ceiling must be restored) so both tests encode one consistent policy.
- [ ] `scripts/ci-tests.sh fast` passes end to end.

## Implementation notes

See KRMA-700's commit 488241b for the introduced `budgetAreaFraction` mechanism.

### Comment — codex @ 2026-09-29T01:37:59.712Z

Implemented and documented a 1.5 MP visible-ROI interactive budget with a 6 MP per-frame source-wide ceiling. Updated ROI budget expectations and added absolute-ceiling coverage. Verification: scripts/ci-tests.sh fast completed all 1,334 required fast tests; build emitted two pre-existing macOS 15 String(contentsOf:) deprecation warnings in LookLUTExportTests.swift. Commit: dfbc76b.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T01:42:57.675Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Decide and document whether interactive decode may exceed the historical 1.5 MP budget when the visible ROI is small, or whether an absolute ceiling must still apply. (pass) — RenderScale.targetSize now spends the 1.5 MP budget on the visible ROI (budgetAreaFraction) but caps the resulting pixel budget at a 6 MP source-wide ceiling (interactiveAbsolutePixelCeiling), both scaled proportionally by frameBudgetMilliseconds. Documented in docs/ENGINEERING_GUIDE.md and in RenderScale.swift doc comments.
- [x] Update CropROITests.testInteractiveZoomFragmentLayoutStaysInPlannerSpace (if ROI-scaled policy is permanent) or RenderScale.targetSize (if an absolute ceiling must be restored) so both tests encode one consistent policy. (pass) — Test renamed to testInteractiveZoomFragmentLayoutStaysInPlannerSpaceWithinROIShapedBudget and updated to assert the ROI-scaled decode stays within the planner box and under 1.5 MP for the visible ROI; new testInteractiveROIBudgetKeepsAbsoluteDecodeCeiling covers the 6 MP source-wide ceiling directly. RenderRequestTests updated to expect min(ROI budget, absolute ceiling).
- [x] scripts/ci-tests.sh fast passes end to end. (pass) — Re-ran scripts/ci-tests.sh fast independently during verification: all 1334 tests executed, exit code 0, no failures, no compiler warnings.
Checks run:
- scripts/ci-tests.sh fast (1334/1334 tests passed, exit 0)
- Manual re-derivation of the ROI-budget math (roiBudgetPixels vs absoluteBudgetPixels) against both new CropROITests cases and the RenderRequestTests expectation
- Repo-wide grep for other references to the 1.5 MP / 6 MP budget constants to confirm no other test or doc still encodes the superseded absolute-only policy
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUM0BTJFJTEB0WXC
