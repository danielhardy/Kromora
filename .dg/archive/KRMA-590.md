---
id: KRMA-590
title: Correct reversed Tint slider color direction
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Moving the slider toward the green end produces a greener image; moving toward the magenta end produces a more magenta image.
      result: pass
      notes: RenderPipeline.applyAdjustments negates tint at the CITemperatureAndTint boundary (RenderPipeline.swift:1475), verified by testTintDirectionMatchesGreenToMagentaTrack.
    - criterion: The rendered direction agrees with the track, value sign/readout, and reset neutral position.
      result: pass
      notes: Sign flip is isolated to the renderer boundary; stored document values, slider track, and neutral (0) reset are unchanged. testEndpointNeutralValuesAreExactNoOpsAndPreserveExtent and testTintDirectionMatchesGreenToMagentaTrack confirm zero-tint identity is preserved.
    - criterion: Standard-image and RAW Tint controls have the same user-facing direction.
      result: pass
      notes: RAW path passes neutralTint straight into CIRAWFilter unmodified (RAWDevelopSettings.swift:112), already matching the green-to-magenta track; only the standard-image CITemperatureAndTint path needed inversion. Also verified the fix consistently propagates to the local-mask tint control (MaskingWorkspace.swift), which shares the same applyAdjustments code path.
    - criterion: Add focused regression coverage that verifies rendered Tint direction for both paths where test fixtures permit; preserve the existing neutral/identity behavior.
      result: pass
      notes: testTintDirectionMatchesGreenToMagentaTrack (RenderPipelineTests) covers the standard-image path directly; testRawTintDirectionMatchesGreenToMagentaTrack (RAWCapabilitiesTests) covers RAW but is opt-in/skipped without KROMORA_RAW_FIXTURE_DIR, consistent with project convention.
    - criterion: swift build, focused white-balance/render tests, and git diff --check pass.
      result: pass
      notes: Ran independently; see checks_run. Test target normally fails to compile due to pre-existing untracked in-flight work (RetouchModelTests.swift referencing EditDocument.retouch) unrelated to this issue; temporarily moved those untracked files aside to compile/run the actual test target, then restored them exactly.
  checks_run:
    - swift build (pass)
    - swift test --filter "RenderPipelineTests|RAWCapabilitiesTests" (pass, 56 executed, 9 skipped for missing opt-in RAW fixture, 0 failures)
    - swift test --filter "WhiteBalance|DevelopInspector|ColorInspector" (pass, 48 executed, 2 skipped, 0 failures)
    - git diff --check (clean)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T17:12:10.598Z
  session: 01MUINA8965FM63BNL
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - color
  - white-balance
created: 2026-09-26T01:15:28.546Z
updated: 2026-09-28T14:41:37.074Z
blockers: []
order: tq3awd70
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


### Comment — codex @ 2026-09-26T17:03:17.511Z

Implemented in a911f73: invert only the standard-image CITemperatureAndTint sign at the renderer boundary, bump the render cache version, and cover standard and RAW tint directions with neutral identity. Verification: swift build and git diff --check pass. Focused swift test filters could not compile because pre-existing untracked RetouchModelTests.swift references missing EditDocument.retouch; RAW fixture direction test also requires the opt-in DNG.

## Agent log

- 2026-09-26T17:12:10.598Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Moving the slider toward the green end produces a greener image; moving toward the magenta end produces a more magenta image. (pass) — RenderPipeline.applyAdjustments negates tint at the CITemperatureAndTint boundary (RenderPipeline.swift:1475), verified by testTintDirectionMatchesGreenToMagentaTrack.
- [x] The rendered direction agrees with the track, value sign/readout, and reset neutral position. (pass) — Sign flip is isolated to the renderer boundary; stored document values, slider track, and neutral (0) reset are unchanged. testEndpointNeutralValuesAreExactNoOpsAndPreserveExtent and testTintDirectionMatchesGreenToMagentaTrack confirm zero-tint identity is preserved.
- [x] Standard-image and RAW Tint controls have the same user-facing direction. (pass) — RAW path passes neutralTint straight into CIRAWFilter unmodified (RAWDevelopSettings.swift:112), already matching the green-to-magenta track; only the standard-image CITemperatureAndTint path needed inversion. Also verified the fix consistently propagates to the local-mask tint control (MaskingWorkspace.swift), which shares the same applyAdjustments code path.
- [x] Add focused regression coverage that verifies rendered Tint direction for both paths where test fixtures permit; preserve the existing neutral/identity behavior. (pass) — testTintDirectionMatchesGreenToMagentaTrack (RenderPipelineTests) covers the standard-image path directly; testRawTintDirectionMatchesGreenToMagentaTrack (RAWCapabilitiesTests) covers RAW but is opt-in/skipped without KROMORA_RAW_FIXTURE_DIR, consistent with project convention.
- [x] swift build, focused white-balance/render tests, and git diff --check pass. (pass) — Ran independently; see checks_run. Test target normally fails to compile due to pre-existing untracked in-flight work (RetouchModelTests.swift referencing EditDocument.retouch) unrelated to this issue; temporarily moved those untracked files aside to compile/run the actual test target, then restored them exactly.
Checks run:
- swift build (pass)
- swift test --filter "RenderPipelineTests|RAWCapabilitiesTests" (pass, 56 executed, 9 skipped for missing opt-in RAW fixture, 0 failures)
- swift test --filter "WhiteBalance|DevelopInspector|ColorInspector" (pass, 48 executed, 2 skipped, 0 failures)
- git diff --check (clean)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUINA8965FM63BNL
Summary: Verified a911f73's standard-image CITemperatureAndTint sign inversion: build, focused white-balance/render tests, and git diff --check all pass; confirmed RAW path and local-mask tint path are consistent with the fixed direction. No fixes needed.
