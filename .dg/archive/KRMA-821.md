---
id: KRMA-821
title: Color Mixer chip UI and honest channel Hue/Saturation tracks
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Color Mixer uses chip strip plus focused HSL panel instead of nested disclosures
      result: pass
    - criterion: Grading units use bronze thumbs, outside reset, and 4pt arc tracks
      result: pass
    - criterion: Mixer saturation track is gray to fully saturated selected channel color
      result: pass
    - criterion: Mixer hue track shows local ramp matching render mapping
      result: pass
    - criterion: Hue endpoints widened to ±60° with pixelEpoch bump and golden update
      result: pass
  checks_run:
    - swift build (pass)
    - swift test --filter ColorMixer|ColorInspector|NeutralOriginSlider|MetalKernelParityTests.testHSL (pass)
  findings: []
  fixes: []
  verification_commits: []
  actor: cursor
  resolved_model: unknown
  completed_at: 2026-10-05T13:06:01.394Z
creation_provenance:
  runner: cursor
  model: unknown
  actor: cursor
labels:
  - editor
  - inspector
  - color
  - ui
created: 2026-10-05T13:05:41.868Z
updated: 2026-10-05T13:06:01.398Z
blockers: []
order: z
board: product
footprint:
  source: observed
  paths: []
---

## Objective

Two Color inspector improvements after KRMA-820:

1. **Color Mixer / HSL** — Replace eight nested channel disclosures with a hue chip strip and a focused Hue/Saturation/Luminance panel for the selected neighborhood.
2. **Honest mixer sliders** — Saturation tracks gray → channel swatch; Hue tracks a local ramp around the selected chip (not a full rainbow). Widen mixer hue endpoints from ±30° to ±60° so full slider travel matches visible shifts.

Also polish Color Grading units: bronze thumbs (`KromoraTheme.primaryAccent`), per-zone reset outside the arcs, 4pt arc stroke aligned with horizontal sliders.

## Context

Follow-up to user review of KRMA-820 grading layout and feedback that mixer Hue looked weak/misleading (full rainbow track implied larger shifts than the kernel applied).

## Acceptance criteria

- [x] Color Mixer uses chip strip plus focused HSL panel instead of nested disclosures
- [x] Grading units use bronze thumbs, outside reset, and 4pt arc tracks
- [x] Mixer saturation track is gray to fully saturated selected channel color
- [x] Mixer hue track shows local ±`ColorMixerChannel.hueEndpointDegrees` ramp matching render mapping
- [x] Hue endpoints widened to ±60° with `pixelEpoch` bump and hsl-mixer golden update

## Implementation notes

- `SliderTrackStyle.localizedHue` and `.channelSaturation(hue:)` in `NeutralOriginSlider.swift`
- `ColorMixerChannel.hueEndpointDegrees` shared by UI tracks and `mixerKernelVector`
- `UPDATE_METAL_GOLDENS=1` helper in `MetalKernelParityTests` for golden refresh

### Comment — cursor @ 2026-10-05T13:05:58.759Z

Completed Color Mixer chip UI, channel-aware Hue/Saturation tracks, ±60° hue endpoints (pixelEpoch 35), and Color Grading bronze-thumb/reset/arc polish. swift build and focused ColorMixer/ColorInspector/NeutralOriginSlider/HSL golden tests passed.

## Agent log

- 2026-10-05: Implemented chip strip, channel panel, grading thumb/reset/arc polish, channel-aware tracks, hue endpoint widening (pixelEpoch 35). Tests passed locally.

- 2026-10-05T13:06:01.394Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Color Mixer uses chip strip plus focused HSL panel instead of nested disclosures (pass)
- [x] Grading units use bronze thumbs, outside reset, and 4pt arc tracks (pass)
- [x] Mixer saturation track is gray to fully saturated selected channel color (pass)
- [x] Mixer hue track shows local ramp matching render mapping (pass)
- [x] Hue endpoints widened to ±60° with pixelEpoch bump and golden update (pass)
Checks run:
- swift build (pass)
- swift test --filter ColorMixer|ColorInspector|NeutralOriginSlider|MetalKernelParityTests.testHSL (pass)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: cursor
Resolved model: unknown
Summary: Color Mixer chip UI, honest channel tracks, ±60° hue endpoints, grading polish.
