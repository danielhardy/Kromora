---
id: KRMA-374
title: Use neutral-centered fill for bipolar adjustment sliders
type: bug
status: done
priority: medium
agent: claude
verification_agent: codex
model: opus
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Bipolar controls with a neutral baseline start with the thumb at the neutral value and no active fill at neutral.
      result: pass
      notes: Model-derived neutral values are wired through all inspector slider rows; SliderFillTests and NeutralOriginSliderTests verify empty fill at neutral, including nonzero and endpoint neutrals.
    - criterion: Dragging above neutral fills only from the neutral baseline to the thumb on the positive side.
      result: pass
      notes: Arithmetic and rasterized AppKit tests verify one-sided positive fill.
    - criterion: Dragging below neutral fills only from the neutral baseline to the thumb on the negative side.
      result: pass
      notes: Arithmetic and rasterized AppKit tests verify one-sided negative fill.
    - criterion: The behavior is applied consistently to the global Adjust controls and local-adjustment controls where the value model is bipolar.
      result: pass
      notes: Adjust, Light, Color, Effects, Develop, and MaskingWorkspace local-adjustment rows use NeutralOriginSlider with model-derived baselines.
    - criterion: Genuinely unipolar controls such as amount, opacity, size, flow, or density retain an appropriate left-origin fill and are not forced into a centered presentation.
      result: pass
      notes: Representative amount, opacity, brush size, feather, flow, density, Look intensity, and grading-wheel rows use range.lowerBound; subordinate controls with declared nonzero defaults use those defaults as their own baseline.
    - criterion: The visual baseline uses each control's actual neutral/default value rather than assuming every range midpoint is zero.
      result: pass
      notes: Coverage includes contrast 1, highlights 1 at the range maximum, blending 50, vignette/grain defaults, local temperature 6500, reflected temperature, and per-image RAW decoder seeds.
    - criterion: Existing value ranges, precision, direct-entry behavior, accessibility values, keyboard interaction, reset actions, undo grouping, persistence, and render semantics remain unchanged.
      result: pass
      notes: The implementation retains NSSlider/AppKit interaction and existing bindings; fast and serial suites passed, including inspector, reset, persistence, keyboard, and render coverage.
    - criterion: Add regression/UI coverage for neutral, positive, and negative bipolar values plus representative unipolar controls; include manual visual QA against the supplied reference behavior.
      result: pass
      notes: The added suites pass 24/24 with arithmetic and rasterized UI coverage; implementation context records manual visual QA against the reference behavior.
  checks_run:
    - swift build (clean)
    - swift test --no-parallel --filter 'SliderFillTests|NeutralOriginSliderTests' (24/24 passed)
    - "scripts/ci-tests.sh verify (1,316 tests partitioned: 913 fast, 357 serial, 46 optional)"
    - scripts/ci-tests.sh fast (913/913 passed)
    - scripts/ci-tests.sh serial (357/357 passed)
    - dg validate (OK; existing model-name warnings only)
    - git diff --check (clean after verification formatting fix)
  findings: []
  fixes:
    - Removed the extra blank line at EOF from Tests/KromoraKitTests/NeutralOriginSliderTests.swift.
  verification_commits:
    - 29deafa
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-12T15:54:20.223Z
  session: 01MTYK9CVDQFWD0SG1
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - ui
created: 2026-09-12T14:46:27.995Z
updated: 2026-09-12T15:54:20.225Z
order: a0
board: product
commits:
  - 29deafa
---

## Objective

Make bipolar adjustment sliders visually represent neutral values correctly: the thumb should start at the neutral midpoint with no track filled, and the active fill should extend from neutral to the current value as the user moves the thumb.

## Context

The current sliders use the standard left-origin fill, so a neutral value such as Exposure 0, Contrast 0, or Highlights 0 appears as roughly 50% filled even though no adjustment is applied. The attached reference screenshots show the desired behavior: neutral at center with an empty track, then fill only on the side between neutral and the dragged thumb.

## Acceptance criteria

- [ ] Bipolar controls with a neutral baseline start with the thumb at the neutral value and no active fill at neutral.
- [ ] Dragging above neutral fills only from the neutral baseline to the thumb on the positive side.
- [ ] Dragging below neutral fills only from the neutral baseline to the thumb on the negative side.
- [ ] The behavior is applied consistently to the global Adjust controls and local-adjustment controls where the value model is bipolar.
- [ ] Genuinely unipolar controls such as amount, opacity, size, flow, or density retain an appropriate left-origin fill and are not forced into a centered presentation.
- [ ] The visual baseline uses each control's actual neutral/default value rather than assuming every range midpoint is zero.
- [ ] Existing value ranges, precision, direct-entry behavior, accessibility values, keyboard interaction, reset actions, undo grouping, persistence, and render semantics remain unchanged.
- [ ] Add regression/UI coverage for neutral, positive, and negative bipolar values plus representative unipolar controls; include manual visual QA against the supplied reference behavior.


### Comment — claude @ 2026-09-12T15:49:16.059Z

Implemented. Every inspector slider is now `NeutralOriginSlider` (new), which wraps `NSSlider` and overrides only `NSSliderCell.drawBar(inside:flipped:)`; the knob, hit-testing, drag tracking, keyboard handling and the native accessibility element stay AppKit's, so ranges, precision, direct entry, reset actions, undo grouping, persistence and render semantics are untouched. `onEditingChanged` now comes from the cell's tracking pipeline rather than the action message, which also stops a keyboard change from opening a preview interaction that nothing closes.

Baselines are read off the control models, never derived from the range: `LightControl`/`EffectsControl`/`VignetteControl`/`GrainControl.neutral`, new `neutral` on the four Color control enums, `LocalAdjustments.neutral[keyPath:]` for local adjustments, `AdjustmentControl.sliderMapped(neutral)` for the reflected temperature row, and a new `AppViewModel.developNeutral(for:)` (= `developValue` against `RAWDevelopSettings.neutral`) for Develop's per-image decoder seeds. Unipolar rows — brush size/feather/flow/density, mask amount, overlay opacity, Look intensity, the grading wheels — pass `range.lowerBound` and keep the left-origin fill from the same code path.

Acceptance criteria:
- Neutral shows an empty track; positive fills right of the baseline, negative left of it — covered in arithmetic (`SliderFillTests`) and in pixels (`NeutralOriginSliderTests`).
- Applied to the global Adjust/Light/Color/Effects rows and to the local-adjustment rows in `MaskingWorkspace`. Develop was included too: its rows have the same defect and a well-defined per-image neutral. Flagging that as slightly beyond the stated scope.
- Unipolar controls keep left-origin fill.
- The baseline is each control's actual default, which is why `AdjustmentControl.highlights` fills leftwards from its maximum, `ColorGradingGlobalControl.blending` is centred on 50 inside an unsigned 0…100, and Vignette midpoint/feather and Grain size/roughness are centred on their declared default of 50. Note the AC listed "size" among the unipolar controls; brush size is unipolar and stayed left-origin, but Grain Size's model default is genuinely 50, so it follows the "use the actual default" rule instead. Worth a second opinion if that reads wrong.
- Coverage: `SliderFillTests` (16, deterministic lane) and `NeutralOriginSliderTests` (8, added to the serial lane in `scripts/ci-tests.sh`). The latter includes `testTheCellsBarDrawingIsReachedWhenTheControlDraws`, a canary for an SDK that stops routing the bar through `drawBar` — otherwise every slider would silently revert with the arithmetic still green.
- Manual visual QA: rendered the cell at neutral / ±2.50 exposure / contrast 1.0 / highlights at max and 0.50 / unipolar 0 and 0.65 and inspected the image. Behaviour matches the reference — empty track at neutral, one-sided fill otherwise.

Checks: `swift build` clean, `scripts/ci-tests.sh verify` partitions (1316 tests), `fast` and `serial` lanes green. Two intermittent failures appeared on earlier `fast` runs (`PreviewDiskCacheTests` write timeout, then `PhotoAnalysisCoordinatorTests` cancellation) in unrelated timing-sensitive suites; each passed in isolation and a clean-worktree baseline at HEAD passed, as did the final run on this tree. `docs/ENGINEERING_GUIDE.md` gained an "Inspector controls" section and a checklist bullet.

Unrelated tree state to flag, not touched and not committed: `Kromora.icon/Assets/Image.png` is deleted, `Kromora.icon/icon.json` modified, and `Kromora.icon/Assets/kroma.svg` is untracked. Those appeared during this session and are not mine — left for a human.

Commit: 605686e

## Agent log

- 2026-09-12T15:54:20.223Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Bipolar controls with a neutral baseline start with the thumb at the neutral value and no active fill at neutral. (pass) — Model-derived neutral values are wired through all inspector slider rows; SliderFillTests and NeutralOriginSliderTests verify empty fill at neutral, including nonzero and endpoint neutrals.
- [x] Dragging above neutral fills only from the neutral baseline to the thumb on the positive side. (pass) — Arithmetic and rasterized AppKit tests verify one-sided positive fill.
- [x] Dragging below neutral fills only from the neutral baseline to the thumb on the negative side. (pass) — Arithmetic and rasterized AppKit tests verify one-sided negative fill.
- [x] The behavior is applied consistently to the global Adjust controls and local-adjustment controls where the value model is bipolar. (pass) — Adjust, Light, Color, Effects, Develop, and MaskingWorkspace local-adjustment rows use NeutralOriginSlider with model-derived baselines.
- [x] Genuinely unipolar controls such as amount, opacity, size, flow, or density retain an appropriate left-origin fill and are not forced into a centered presentation. (pass) — Representative amount, opacity, brush size, feather, flow, density, Look intensity, and grading-wheel rows use range.lowerBound; subordinate controls with declared nonzero defaults use those defaults as their own baseline.
- [x] The visual baseline uses each control's actual neutral/default value rather than assuming every range midpoint is zero. (pass) — Coverage includes contrast 1, highlights 1 at the range maximum, blending 50, vignette/grain defaults, local temperature 6500, reflected temperature, and per-image RAW decoder seeds.
- [x] Existing value ranges, precision, direct-entry behavior, accessibility values, keyboard interaction, reset actions, undo grouping, persistence, and render semantics remain unchanged. (pass) — The implementation retains NSSlider/AppKit interaction and existing bindings; fast and serial suites passed, including inspector, reset, persistence, keyboard, and render coverage.
- [x] Add regression/UI coverage for neutral, positive, and negative bipolar values plus representative unipolar controls; include manual visual QA against the supplied reference behavior. (pass) — The added suites pass 24/24 with arithmetic and rasterized UI coverage; implementation context records manual visual QA against the reference behavior.
Checks run:
- swift build (clean)
- swift test --no-parallel --filter 'SliderFillTests|NeutralOriginSliderTests' (24/24 passed)
- scripts/ci-tests.sh verify (1,316 tests partitioned: 913 fast, 357 serial, 46 optional)
- scripts/ci-tests.sh fast (913/913 passed)
- scripts/ci-tests.sh serial (357/357 passed)
- dg validate (OK; existing model-name warnings only)
- git diff --check (clean after verification formatting fix)
Findings:
- None
Fixes:
- Removed the extra blank line at EOF from Tests/KromoraKitTests/NeutralOriginSliderTests.swift.
Verification commits:
- 29deafa
Actor: codex
Resolved model: unknown
Pickup session: 01MTYK9CVDQFWD0SG1
Summary: Verification passed: neutral-origin slider rendering and required regression suites are green.
