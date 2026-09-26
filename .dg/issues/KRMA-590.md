---
id: KRMA-590
title: Correct reversed Tint slider color direction
type: bug
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - color
  - white-balance
created: 2026-09-26T01:15:28.546Z
updated: 2026-09-26T01:16:03.541Z
blockers: []
order: zzzz
board: product
---

## Objective

Make the Tint slider’s rendered color direction match its green-to-magenta track and user-facing labels. Moving toward green currently makes the image more magenta, and moving toward magenta makes it greener.

## Reproduction

1. Open an image and show the white-balance Tint control.
2. Move the slider toward the green end and observe the rendered image shift toward magenta.
3. Move it toward the magenta end and observe the rendered image shift toward green.

The track currently documents and displays green at the negative end and magenta at the positive end (`NeutralOriginSlider.swift`). Tint is rendered through different paths for standard images and RAW development, so check both.

## Context

Relevant implementation and regression coverage:

- `Sources/KromoraKit/Views/NeutralOriginSlider.swift` — tint track direction
- `Sources/KromoraKit/Views/ColorInspectorView.swift` — standard-image Tint control
- `Sources/KromoraKit/Views/DevelopInspectorView.swift` — RAW Tint control
- `Sources/KromoraKit/Models/RenderPipeline.swift` — standard-image `CITemperatureAndTint` path
- `Sources/KromoraKit/Models/RAWDevelopSettings.swift` — RAW decoder tint value
- `Tests/KromoraKitTests/RenderPipelineTests.swift`
- `Tests/KromoraKitTests/RAWCapabilitiesTests.swift`

## Acceptance criteria

- [ ] Moving the slider toward the green end produces a greener image; moving toward the magenta end produces a more magenta image.
- [ ] The rendered direction agrees with the track, value sign/readout, and reset neutral position.
- [ ] Standard-image and RAW Tint controls have the same user-facing direction, accounting for differences between the post-render and RAW decoder APIs.
- [ ] Add focused regression coverage that verifies rendered Tint direction for both paths where test fixtures permit; preserve the existing neutral/identity behavior.
- [ ] `swift build`, focused white-balance/render tests, and `git diff --check` pass.

## Implementation notes

Trace the sign from the slider value through `whiteBalanceBinding`/`developTintBinding` into each renderer. Correct the mapping at the appropriate boundary and consider saved edits and Auto white-balance proposals so positive/negative tint retains one consistent user-facing meaning.
