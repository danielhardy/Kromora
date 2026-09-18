---
id: KRMA-429
title: Make the temperature slider non-linear for practical Kelvin adjustment
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The temperature slider gives materially finer control across 2,000–10,000 K.
      result: pass
      notes: TemperatureSliderMapping is logarithmic; for the RAW 2,000-50,000 K range, 10,000 K sits at slider position 0.5 (vs 0.166 linear), confirmed by testRAWMappingUsesTheUsefulRangeForHalfTheTrack.
    - criterion: Values above 10,000 K remain reachable through the slider up to the existing 50,000 K RAW maximum.
      result: pass
      notes: Mapping domain/range unchanged (2,000-50,000 K); round-trip verified for 49999.75 and 50000 K.
    - criterion: Mapping is monotonic, continuous, reversible, and does not introduce a jump around the practical-range boundary.
      result: pass
      notes: testMappingIsMonotonicAndContinuousAtThePracticalBoundary asserts strict monotonicity and a sub-1e-6 position delta across 10,000 K; kelvinValue/sliderPosition are exact inverses (pure log/pow).
    - criterion: Underlying Kelvin values, persistence, rendering, reset/as-shot, direct entry, keyboard interaction, and accessibility value announcements remain correct.
      result: pass
      notes: Bindings still carry Kelvin end-to-end; TemperatureSlider only reparameterizes the NSSlider's internal 0...1 coordinate. AdjustInspectorTests (19), DevelopInspectorTests (34, 2 expected skips) all pass, including reset/as-shot and debounce coverage.
    - criterion: Apply consistently to every 2,000-50,000 K RAW slider; evaluate standard-image 2,000-11,000 K sharing.
      result: pass
      notes: Applied to RAW white balance (DevelopInspectorView), standard Adjust/Color temperature (AdjustInspectorView, ColorInspectorView), and local-adjustment temperature (MaskingWorkspace). testStandardImageRangeSharesTheMappingWithoutChangingItsUpperBound confirms the 11,000 K ceiling is preserved while reusing the same mapping type.
    - criterion: Color-setting readouts rounded to whole numbers; internal precision retained.
      result: pass
      notes: ColorSettingFormatting.temperature/tint round display only; underlying Double bindings keep full precision (verified via testColorReadoutsRoundTemperatureAndTintWithoutChangingTheValues).
    - criterion: Add focused mapping, formatting, and interaction regression coverage at 2,000/6,500/10,000/50,000 K.
      result: pass
      notes: TemperatureSliderMappingTests exercises exactly these representative values plus formatting.
  checks_run:
    - swift build
    - swift test --filter TemperatureSliderMappingTests (5 passed)
    - swift test --filter 'AdjustInspectorTests|DevelopInspectorTests|LocalAdjustmentControlTests' (56 passed, 2 expected skips)
    - swift test --filter PackageSettingsTests (3 passed; zero Swift 6 concurrency escape hatches)
    - scripts/ci-tests.sh fast (1038 tests, 0 failures)
    - git diff --check 8af79cd~1 8af79cd (no whitespace errors)
    - manual derivation of slider-position sensitivity (dK/ds) for the RAW mapping to confirm finer control is concentrated at 2,000-10,000 K rather than the upper range
  findings:
    - "maintainability (low): the TemperatureSlider-vs-NeutralOriginSlider branch (Group { if control == .temperature {...} else {...} }) is duplicated near-identically across AdjustInspectorView, ColorInspectorView, DevelopInspectorView, and MaskingWorkspace. Cosmetic only — each call site's surrounding parameters differ slightly, so a shared helper would need a small param struct. Not worth a standalone ticket at this size; left as a review note, no fix applied."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-14T11:59:02.907Z
  session: 01MU16LKK7WB234B05
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ui
  - white-balance
created: 2026-09-14T02:17:51.506Z
updated: 2026-09-14T11:59:02.909Z
order: a0
board: product
---

## Objective
Make temperature adjustment easier to control across the useful photographic range without removing the existing high-end RAW capability.

## Problem
The temperature slider spans 2,000–50,000 K for RAW white balance, but the vast majority of useful work happens between roughly 2,000 and 10,000 K. With a linear mapping, that practical range occupies too little of the track, making precise everyday adjustments difficult while still requiring access to the full 50,000 K range.

## Proposed direction
Use a non-linear slider-space mapping for temperature so the 2,000–10,000 K region receives substantially more physical track length, while the upper range remains reachable and reversible. Keep the underlying persisted/rendered value in Kelvin; only the UI position-to-value mapping should change. Consider a monotonic piecewise or logarithmic mapping, with a smooth transition and a clearly defined neutral/as-shot point.

## Display precision
Color-setting readouts do not need decimal precision; display them rounded to the nearest whole number wherever decimals do not convey useful information. Preserve any underlying precision required for editing, persistence, rendering, or control semantics.

## Acceptance criteria
- [ ] The temperature slider gives materially finer control across 2,000–10,000 K.
- [ ] Values above 10,000 K remain reachable through the slider up to the existing 50,000 K RAW maximum.
- [ ] Mapping is monotonic, continuous, reversible, and does not introduce a jump around the practical-range boundary.
- [ ] Underlying Kelvin values, persistence, rendering, reset/as-shot behavior, direct entry, keyboard interaction, and accessibility value announcements remain correct.
- [ ] Apply the behavior consistently to every temperature slider that uses the 2,000–50,000 K RAW range; evaluate whether the standard-image 2,000–11,000 K control should share the mapping without changing its range.
- [ ] Color-setting readouts that currently show unnecessary decimals are rounded to the nearest whole number, while internal values and interactions retain required precision.
- [ ] Add focused mapping, formatting, and interaction regression coverage, including representative temperature values near 2,000 K, 6,500 K, 10,000 K, and 50,000 K.


### Comment — codex @ 2026-09-14T11:49:45.317Z

Implemented in commit 8af79cd. Added a shared logarithmic TemperatureSliderMapping and TemperatureSlider wrapper so RAW 2,000–50,000 K, standard-image 2,000–11,000 K, and local temperature controls get non-linear track travel while bindings remain in photographer-facing/persisted Kelvin. Standard adjustment reflection, direct entry, keyboard/native slider interaction, reset/as-shot behavior, accessibility readouts, and debounced rendering paths remain intact. Color temperature/tint readouts now round to whole units. Checks: swift test --filter TemperatureSliderMappingTests (5 passed), swift test --filter AdjustInspectorTests (19 passed), swift test --filter DevelopInspectorTests (34 passed, 2 expected skips), swift test --filter LocalAdjustmentControlTests (3 passed), scripts/ci-tests.sh fast (1,038 tests reached with no failure markers), swift build, swift build -c release, dg validate (OK with existing model warnings), git diff --check. New files pass targeted swift-format lint; the repository-wide format script still reports pre-existing violations in unrelated portions of touched legacy view files.

## Agent log

- 2026-09-14T11:59:02.907Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The temperature slider gives materially finer control across 2,000–10,000 K. (pass) — TemperatureSliderMapping is logarithmic; for the RAW 2,000-50,000 K range, 10,000 K sits at slider position 0.5 (vs 0.166 linear), confirmed by testRAWMappingUsesTheUsefulRangeForHalfTheTrack.
- [x] Values above 10,000 K remain reachable through the slider up to the existing 50,000 K RAW maximum. (pass) — Mapping domain/range unchanged (2,000-50,000 K); round-trip verified for 49999.75 and 50000 K.
- [x] Mapping is monotonic, continuous, reversible, and does not introduce a jump around the practical-range boundary. (pass) — testMappingIsMonotonicAndContinuousAtThePracticalBoundary asserts strict monotonicity and a sub-1e-6 position delta across 10,000 K; kelvinValue/sliderPosition are exact inverses (pure log/pow).
- [x] Underlying Kelvin values, persistence, rendering, reset/as-shot, direct entry, keyboard interaction, and accessibility value announcements remain correct. (pass) — Bindings still carry Kelvin end-to-end; TemperatureSlider only reparameterizes the NSSlider's internal 0...1 coordinate. AdjustInspectorTests (19), DevelopInspectorTests (34, 2 expected skips) all pass, including reset/as-shot and debounce coverage.
- [x] Apply consistently to every 2,000-50,000 K RAW slider; evaluate standard-image 2,000-11,000 K sharing. (pass) — Applied to RAW white balance (DevelopInspectorView), standard Adjust/Color temperature (AdjustInspectorView, ColorInspectorView), and local-adjustment temperature (MaskingWorkspace). testStandardImageRangeSharesTheMappingWithoutChangingItsUpperBound confirms the 11,000 K ceiling is preserved while reusing the same mapping type.
- [x] Color-setting readouts rounded to whole numbers; internal precision retained. (pass) — ColorSettingFormatting.temperature/tint round display only; underlying Double bindings keep full precision (verified via testColorReadoutsRoundTemperatureAndTintWithoutChangingTheValues).
- [x] Add focused mapping, formatting, and interaction regression coverage at 2,000/6,500/10,000/50,000 K. (pass) — TemperatureSliderMappingTests exercises exactly these representative values plus formatting.
Checks run:
- swift build
- swift test --filter TemperatureSliderMappingTests (5 passed)
- swift test --filter 'AdjustInspectorTests|DevelopInspectorTests|LocalAdjustmentControlTests' (56 passed, 2 expected skips)
- swift test --filter PackageSettingsTests (3 passed; zero Swift 6 concurrency escape hatches)
- scripts/ci-tests.sh fast (1038 tests, 0 failures)
- git diff --check 8af79cd~1 8af79cd (no whitespace errors)
- manual derivation of slider-position sensitivity (dK/ds) for the RAW mapping to confirm finer control is concentrated at 2,000-10,000 K rather than the upper range
Findings:
- maintainability (low): the TemperatureSlider-vs-NeutralOriginSlider branch (Group { if control == .temperature {...} else {...} }) is duplicated near-identically across AdjustInspectorView, ColorInspectorView, DevelopInspectorView, and MaskingWorkspace. Cosmetic only — each call site's surrounding parameters differ slightly, so a shared helper would need a small param struct. Not worth a standalone ticket at this size; left as a review note, no fix applied.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU16LKK7WB234B05
Summary: Verified: logarithmic temperature mapping is correct and consistent across RAW, standard-image, and local sliders; all acceptance criteria pass; full fast suite (1038 tests) and targeted suites green; no fixes needed.
