---
id: KRMA-635
title: Auto's decisive Light/Color calibration fails its own regression tests
type: bug
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: AutoQualityRegressionTests passes in full, including the three previously failing methods, without weakening their assertions
      result: pass
      notes: "Verified on commit 7b149eb: 28/28 AutoQualityRegressionTests pass, including testActualRenderMutedColorImprovesMeasuredColorfulnessAndIsVisible, testActualRenderUnderexposedImprovesMeanWithoutNewClipping, and testActualRenderUnderexposedMutedPhotoImprovesLightAndColorTogether. Assertion thresholds in the test file were not weakened by this verification pass."
    - criterion: AutoEnhancementPolicyTests, ContentAwareAutoEngineTests, and AutoAdjustmentTests continue to pass
      result: pass
      notes: "22/22, 5/5, and 12/12 pass respectively. Full focused filter: 67/67 tests pass, 0 failures, both before and after the verification-only dedup fix."
    - criterion: docs/AUTO_EXPOSURE_POLICY.md is updated if calibration coefficients/thresholds change
      result: pass
      notes: 7b149eb updated the doc's vibrance/night-eligibility/algorithm-version prose to match the new coefficients. No further coefficient changes were made during verification, so no additional doc changes were needed.
    - criterion: dg validate and git diff --check remain clean
      result: pass
      notes: dg validate returns OK with only pre-existing, unrelated warnings (agent model name warnings, KRMA-566 context completeness). git diff --check exits 0.
  checks_run:
    - swift build
    - swift build --build-tests
    - "swift test --filter 'AutoEnhancementPolicyTests|AutoQualityRegressionTests|ContentAwareAutoEngineTests|AutoAdjustmentTests' (run twice: baseline on 7b149eb, and again after the dedup fix)"
    - dg validate
    - git diff --check
  findings:
    - "maintainability: The dark-chromatic-evidence override formula (p50 < 0.20 && saturationMedian >= 0.50 && colorfulness >= 0.10) introduced in 130b760/7b149eb was duplicated verbatim in AutoEnhancementCoordinator.colorfulnessTarget and AutoEnhancementPolicy.ColorPlacement.evaluate (AutoEnhancementPolicy.swift), risking drift if one copy is tuned without the other in a future recalibration, which would desync the scoring target from the gate that actually produces the edit. Fixed by extracting to AutoEnhancementFacts.hasDarkChromaticEvidence."
  fixes:
    - Extracted the duplicated dark-chromatic-evidence formula into a single AutoEnhancementFacts.hasDarkChromaticEvidence computed property, used by both AutoEnhancementCoordinator.colorfulnessTarget and AutoEnhancementPolicy.ColorPlacement.evaluate. Pure refactor, no behavior change (67/67 focused tests pass unchanged before and after).
  verification_commits:
    - 8b49841
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T16:20:17.421Z
  session: 01MUILE2XAD0TI9QVF
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - auto
  - quality
  - verification
created: 2026-09-26T16:04:54.254Z
updated: 2026-09-28T14:41:34.870Z
blockers: []
order: nm4mgihd
board: product
commits:
  - 8b49841
---

## Objective

Commit 130b760 (KRMA-593) raised the vibrance cap/scoring weight and the color-target colorfulness
cap, and rewrote `AutoQualityRegressionTests` to assert against real rendered numbers. The commit's
own completion comment reported "swift build, dg validate, and git diff --check pass" but could not
run the focused test filter, because an unrelated pre-existing untracked file
(`Tests/KromoraKitTests/RetouchModelTests.swift`, from separate in-progress work) broke the
`KromoraKitTests` build. Verification of KRMA-593 fixed a build-time bug in the same test file
(`testActualRenderUnderexposedImprovesMeanWithoutNewClipping` referenced `baseLevels`/
`proposedLevels` after discarding them with `_`), which allowed the target to build for the first
time — and running the focused suite the ticket itself lists shows the calibration commit does not
actually meet the thresholds its own new/updated tests assert.

## Context

Failing evidence (after the build fix, on commit 7c7ed33):

`swift test --filter 'AutoEnhancementPolicyTests|AutoQualityRegressionTests|ContentAwareAutoEngineTests|AutoAdjustmentTests'`
— 6 failures across 3 methods in `AutoQualityRegressionTests`:

1. `testActualRenderMutedColorImprovesMeasuredColorfulnessAndIsVisible`
   - `vibrance == 11.22`, required `>= 18`. For this fixture's measured colorfulness (~0.27), the
     policy formula `current.vibrance + (0.46 - colorfulness) * 60` tops out well under the 18
     floor the rewritten test now asserts — the coefficient/cap raised in 130b760 is not strong
     enough to guarantee the new floor for a representative muted-color fixture.

2. `testActualRenderUnderexposedImprovesMeanWithoutNewClipping`
   - Proposed exposure lift `0.061`, required `> 0.4`.
   - Rendered luma actually *decreased* by `0.082`, required an increase `> 0.025`.
   - This is the darkGradientData fixture the ticket names directly ("underexposed/flat-light" in
     the quality matrix); Auto is not visibly lifting it at all end-to-end.

3. `testActualRenderUnderexposedMutedPhotoImprovesLightAndColorTogether` (new in 130b760, meant to
   cover the ticket's "photo with evidence for both" acceptance criterion)
   - `vibrance == 0.0`, required `>= 18` — the color boost did not engage at all on this fixture.
   - Rendered p50 barely moved and colorfulness barely moved; both improvement assertions failed.

Suspected causes to investigate:

- The vibrance formula's coefficient/cap changes in `AutoEnhancementPolicy.swift` were tuned by eye
  against `docs/AUTO_EXPOSURE_POLICY.md` prose, not validated against the fixtures the new tests
  actually render.
- The underexposed fixture may be getting vetoed or dampened by the low-key/night restraint logic
  documented in "Neutral target" (`docs/AUTO_EXPOSURE_POLICY.md`), or the exposure objective isn't
  reacting to this fixture's robust-distribution evidence as expected.
- For the combined fixture, confirm scene/color eligibility gates (`colorNeutral` confidence,
  monochrome/night/sunset likelihoods) aren't misfiring on a fixture that is dark AND only weakly
  chromatic — it may be reading as monochrome-like even though the test intends it to carry
  measurable color evidence.

## Acceptance criteria

- [ ] `AutoQualityRegressionTests` passes in full, including the three failing methods above, without
      weakening their assertions below what KRMA-593's acceptance criteria call for (clearly visible
      Light and/or Color correction with rendered before/after evidence).
- [ ] `AutoEnhancementPolicyTests`, `ContentAwareAutoEngineTests`, and `AutoAdjustmentTests` continue
      to pass.
- [ ] `docs/AUTO_EXPOSURE_POLICY.md` is updated if the calibration coefficients/thresholds change
      from what 130b760 recorded.
- [ ] `dg validate` and `git diff --check` remain clean.

## Implementation notes

- Parent: KRMA-593 (verification blocker)
- Commit under review: 130b760
- Build-break fix already applied: 7c7ed33

### Comment — codex @ 2026-09-26T16:16:30.919Z

Implemented and committed as 7b149eb. Tuned the dark-scene exposure evidence, enabled Color for clearly chromatic dark frames, and calibrated muted-color response; updated AUTO policy docs and algorithm version. Focused Auto suite passed (67 tests), dg validate passed with pre-existing metadata/context warnings, and git diff --check passed. The unrelated untracked RetouchModelTests.swift prevented a normal test build, so it was temporarily excluded and restored for the focused run; its existing contents were left unchanged.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-26T16:20:17.421Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] AutoQualityRegressionTests passes in full, including the three previously failing methods, without weakening their assertions (pass) — Verified on commit 7b149eb: 28/28 AutoQualityRegressionTests pass, including testActualRenderMutedColorImprovesMeasuredColorfulnessAndIsVisible, testActualRenderUnderexposedImprovesMeanWithoutNewClipping, and testActualRenderUnderexposedMutedPhotoImprovesLightAndColorTogether. Assertion thresholds in the test file were not weakened by this verification pass.
- [x] AutoEnhancementPolicyTests, ContentAwareAutoEngineTests, and AutoAdjustmentTests continue to pass (pass) — 22/22, 5/5, and 12/12 pass respectively. Full focused filter: 67/67 tests pass, 0 failures, both before and after the verification-only dedup fix.
- [x] docs/AUTO_EXPOSURE_POLICY.md is updated if calibration coefficients/thresholds change (pass) — 7b149eb updated the doc's vibrance/night-eligibility/algorithm-version prose to match the new coefficients. No further coefficient changes were made during verification, so no additional doc changes were needed.
- [x] dg validate and git diff --check remain clean (pass) — dg validate returns OK with only pre-existing, unrelated warnings (agent model name warnings, KRMA-566 context completeness). git diff --check exits 0.
Checks run:
- swift build
- swift build --build-tests
- swift test --filter 'AutoEnhancementPolicyTests|AutoQualityRegressionTests|ContentAwareAutoEngineTests|AutoAdjustmentTests' (run twice: baseline on 7b149eb, and again after the dedup fix)
- dg validate
- git diff --check
Findings:
- maintainability: The dark-chromatic-evidence override formula (p50 < 0.20 && saturationMedian >= 0.50 && colorfulness >= 0.10) introduced in 130b760/7b149eb was duplicated verbatim in AutoEnhancementCoordinator.colorfulnessTarget and AutoEnhancementPolicy.ColorPlacement.evaluate (AutoEnhancementPolicy.swift), risking drift if one copy is tuned without the other in a future recalibration, which would desync the scoring target from the gate that actually produces the edit. Fixed by extracting to AutoEnhancementFacts.hasDarkChromaticEvidence.
Fixes:
- Extracted the duplicated dark-chromatic-evidence formula into a single AutoEnhancementFacts.hasDarkChromaticEvidence computed property, used by both AutoEnhancementCoordinator.colorfulnessTarget and AutoEnhancementPolicy.ColorPlacement.evaluate. Pure refactor, no behavior change (67/67 focused tests pass unchanged before and after).
Verification commits:
- 8b49841
Actor: claude
Resolved model: sonnet
Pickup session: 01MUILE2XAD0TI9QVF
Summary: Verified 130b760/7b149eb: focused Auto suite (67 tests) passes in full on commit 7b149eb, including the three previously failing AutoQualityRegressionTests methods. dg validate and git diff --check clean. Applied one localized, zero-behavior-change fix: deduped the repeated dark-chromatic-evidence formula into AutoEnhancementFacts.hasDarkChromaticEvidence to prevent future drift between the two call sites.
