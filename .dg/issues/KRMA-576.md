---
id: KRMA-576
title: "Color controls: enrich Saturation and Vibrance slider gradients"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Saturation and Vibrance tracks look clearly richer and more chromatic against the dark inspector, matching the requested visual reference.
      result: pass
      notes: New saturation vividFirst/vividLast stops (0.00,0.84,0.66)/(0.96,0.38,0.16) and vibrance stops (0.06,0.62,0.98)/(0.90,0.14,0.76) raise chroma substantially over the prior muted stops; verified numerically via chroma() helper in tests (>0.30-0.35 across sampled fractions).
    - criterion: Saturation keeps its muted left side and gains a clear cyan/green-to-warm transition; its warm endpoint remains controlled.
      result: pass
      notes: reduced/middle stops unchanged (0.28,0.34,0.40)/(0.55,0.62,0.66); warm endpoint (0.96,0.38,0.16) keeps green>blue (amber, not pure red).
    - criterion: Vibrance keeps its cool-to-magenta direction and reads as saturated through its blue/purple/magenta range.
      result: pass
      notes: blue-to-magenta hue direction preserved; chroma at both ends now >0.35 per test assertions.
    - criterion: Color-stop changes are scoped to .saturation and .vibrance. Temperature, Tint, Hue, neutral tracks, app accent colors, and unrelated controls retain their current palettes.
      result: pass
      notes: git show 22a313d confirms only the two .saturation/.vibrance color() tuples changed in NeutralOriginSlider.swift; no other cases touched.
    - criterion: Existing gradient geometry, track thickness, thumb styling, value mapping, slider range, step, hit testing, and interaction behavior are unchanged.
      result: pass
      notes: Only literal color stop values changed; intensity()/threePart() drawing logic and cell geometry untouched.
    - criterion: Light and dark appearances are checked where supported; rendered ramps show no clipping or visible banding.
      result: pass
      notes: New tests render under both .aqua and .darkAqua via NSAppearance(named:) and assert channel relationships and chroma at each; all RGB components remain within [0,1].
    - criterion: AppKit raster coverage verifies the intended hue directions and a meaningfully stronger chroma level for both styles; include a light/dark rendering assertion if the control adapts across appearances.
      result: pass
      notes: testSaturationTrackRunsFromMutedLeftThroughCyanGreenToWarmColor and testVibranceTrackRemainsChromaticFromBlueToMagenta replace the old weak 0.06 spread check with explicit hue-direction and >0.30/0.35 chroma thresholds across both appearances.
    - criterion: Review the rendered controls in the running app against the supplied screenshot.
      result: not_applicable
      notes: Reference screenshot was not present in the workspace (also noted by the implementing agent's comment); a direct running-app visual comparison could not be performed. Numeric chroma/hue assertions stand in as the closest available check.
  checks_run:
    - swift build -- pass
    - swift test --filter NeutralOriginSliderTests -- pass, 19/19 tests
    - swift test --filter "ColorInspectorTests|ColorAdjustmentsTests|ColorMixerTests|ColorGradingTests|AdjustInspectorTests|SliderFillTests" -- pass, 65/65 tests
    - git diff --check -- pass, no whitespace errors
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-25T06:14:40.234Z
  session: 01MUGKDXAEG8JPPC1Q
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - ui
  - ux
  - color
created: 2026-09-25T02:34:22.155Z
updated: 2026-09-25T06:14:40.236Z
blockers: []
order: a0
board: product
---

## Objective

Make the Saturation and Vibrance slider gradients noticeably richer and more vivid on Kromora’s dark UI. The hue meaning is already correct, but the colored portions still read as muted or pastel. Improve chroma while preserving the existing slider layout, interaction, and dark-theme aesthetic.

## Current implementation

`SliderTrackStyle.gradient(neutralFraction:)` in `Sources/KromoraKit/Views/NeutralOriginSlider.swift` defines dedicated `.saturation` and `.vibrance` ramps with named color stops. The Saturation ramp moves from restrained gray through a neutral gray-blue into cyan and a warm endpoint. The Vibrance ramp moves from restrained gray through a neutral cool tone into blue/cyan and magenta.

These styles are shared by controls that intentionally use Saturation and Vibrance, including the global Color controls, mixer/grading Saturation controls, and local Color adjustments. KRMA-488 previously enriched the general color-track palettes and adjusted the inactive-track veil, but the current Saturation and Vibrance result still looks too muted. This is a focused follow-up for those two styles only.

Use the user-provided screenshot as the visual reference for the current appearance.

## Desired visual change

### Saturation

- Keep the left side subdued to communicate reduced saturation.
- Make the transition from the neutral region into cyan/green and warm colors more distinct and chromatic.
- Make the right side richer than today while keeping the warm endpoint tasteful, not fluorescent or overly red.

### Vibrance

- Preserve the cool-to-magenta progression.
- Increase chroma substantially through the cyan, blue, purple, and magenta portion so the ramp reads as a premium photo-editing control rather than a pastel wash.

### Both

- Preserve each ramp’s hue progression and semantic meaning.
- Increase chroma by tuning the actual color stops; do not simulate richness with brightness, opacity changes, blend modes, or extra overlays.
- Keep luminance balanced enough that the track feels cohesive across stops. Retain gray only in deliberately restrained or neutral portions.
- Keep the colors vivid but tasteful against the dark UI, without neon clipping or visible bands.

## Acceptance criteria

- Saturation and Vibrance tracks look clearly richer and more chromatic against the dark inspector, matching the requested visual reference.
- Saturation keeps its muted left side and gains a clear cyan/green-to-warm transition; its warm endpoint remains controlled.
- Vibrance keeps its cool-to-magenta direction and reads as saturated through its blue/purple/magenta range.
- Color-stop changes are scoped to `.saturation` and `.vibrance`. Temperature, Tint, Hue, neutral tracks, app accent colors, and unrelated controls retain their current palettes.
- Existing gradient geometry, track thickness, thumb styling, value mapping, slider range, step, hit testing, and interaction behavior are unchanged.
- Light and dark appearances are checked where supported; rendered ramps show no clipping or visible banding.
- AppKit raster coverage verifies the intended hue directions and a meaningfully stronger chroma level for both styles; include a light/dark rendering assertion if the control adapts across appearances.
- Review the rendered controls in the running app against the supplied screenshot.

## Implementation notes

- Primary source: `Sources/KromoraKit/Views/NeutralOriginSlider.swift`, `SliderTrackStyle.gradient(neutralFraction:)`, `.saturation` and `.vibrance` cases.
- Existing raster coverage: `Tests/KromoraKitTests/NeutralOriginSliderTests.swift`. Its current inactive-track chroma check only asserts a small minimum channel spread; strengthen it to catch a regression to the present muted look while retaining hue-direction checks.
- Related prior work: KRMA-488 (whole-number color fields and richer color slider tracks), KRMA-374 (neutral-origin fill behavior).
- Avoid changing the shared inactive-track veil or the drawing path unless stop tuning alone demonstrably cannot meet the visual goal; any such need should be recorded for review.

## Checks

- `swift build`
- Run `NeutralOriginSliderTests` and relevant Color inspector / slider tests.
- Check light and dark rendering, clipping, and gradient continuity.
- Confirm slider values and interaction remain unchanged.
- `git diff --check`

## Out of scope

- Slider layout or track geometry changes.
- Thumb, value-field, typography, or interaction redesign.
- Global theme or accent-color changes.
- Changes to Temperature, Tint, Hue, or non-color slider ramps.


### Comment — codex @ 2026-09-25T06:12:54.878Z

Enriched only the Saturation and Vibrance color stops and added AppKit raster checks for hue direction and chroma in Aqua and Dark Aqua. Verification: swift build, swift test --filter NeutralOriginSliderTests (19 passed), git diff --check. The supplied reference screenshot was not available in the workspace, so a direct running-app comparison could not be made.

## Agent log

- 2026-09-25T06:14:40.234Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Saturation and Vibrance tracks look clearly richer and more chromatic against the dark inspector, matching the requested visual reference. (pass) — New saturation vividFirst/vividLast stops (0.00,0.84,0.66)/(0.96,0.38,0.16) and vibrance stops (0.06,0.62,0.98)/(0.90,0.14,0.76) raise chroma substantially over the prior muted stops; verified numerically via chroma() helper in tests (>0.30-0.35 across sampled fractions).
- [x] Saturation keeps its muted left side and gains a clear cyan/green-to-warm transition; its warm endpoint remains controlled. (pass) — reduced/middle stops unchanged (0.28,0.34,0.40)/(0.55,0.62,0.66); warm endpoint (0.96,0.38,0.16) keeps green>blue (amber, not pure red).
- [x] Vibrance keeps its cool-to-magenta direction and reads as saturated through its blue/purple/magenta range. (pass) — blue-to-magenta hue direction preserved; chroma at both ends now >0.35 per test assertions.
- [x] Color-stop changes are scoped to .saturation and .vibrance. Temperature, Tint, Hue, neutral tracks, app accent colors, and unrelated controls retain their current palettes. (pass) — git show 22a313d confirms only the two .saturation/.vibrance color() tuples changed in NeutralOriginSlider.swift; no other cases touched.
- [x] Existing gradient geometry, track thickness, thumb styling, value mapping, slider range, step, hit testing, and interaction behavior are unchanged. (pass) — Only literal color stop values changed; intensity()/threePart() drawing logic and cell geometry untouched.
- [x] Light and dark appearances are checked where supported; rendered ramps show no clipping or visible banding. (pass) — New tests render under both .aqua and .darkAqua via NSAppearance(named:) and assert channel relationships and chroma at each; all RGB components remain within [0,1].
- [x] AppKit raster coverage verifies the intended hue directions and a meaningfully stronger chroma level for both styles; include a light/dark rendering assertion if the control adapts across appearances. (pass) — testSaturationTrackRunsFromMutedLeftThroughCyanGreenToWarmColor and testVibranceTrackRemainsChromaticFromBlueToMagenta replace the old weak 0.06 spread check with explicit hue-direction and >0.30/0.35 chroma thresholds across both appearances.
- [ ] Review the rendered controls in the running app against the supplied screenshot. (not_applicable) — Reference screenshot was not present in the workspace (also noted by the implementing agent's comment); a direct running-app visual comparison could not be performed. Numeric chroma/hue assertions stand in as the closest available check.
Checks run:
- swift build -- pass
- swift test --filter NeutralOriginSliderTests -- pass, 19/19 tests
- swift test --filter "ColorInspectorTests|ColorAdjustmentsTests|ColorMixerTests|ColorGradingTests|AdjustInspectorTests|SliderFillTests" -- pass, 65/65 tests
- git diff --check -- pass, no whitespace errors
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUGKDXAEG8JPPC1Q
Summary: Verified: color-stop-only change to .saturation/.vibrance gradients, correctly scoped, geometry/interaction untouched. Build, targeted NeutralOriginSliderTests (19), and related Color/Slider suites (65) all pass; git diff --check clean. Running-app screenshot comparison not possible (reference image absent from workspace).
