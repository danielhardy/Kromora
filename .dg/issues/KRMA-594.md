---
id: KRMA-594
title: Add a white-balance eyedropper and preset choices
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Provide a loupe-assisted neutral sample with a documented averaging area and a clear cancel/commit interaction.
      result: pass
      notes: beginWhiteBalanceSampling/updateWhiteBalanceSample/cancelWhiteBalanceSampling in AppViewModel+Color.swift average an 11x11 display-pixel square, show a 3x loupe crop that follows the pointer, and support Cancel Sample button plus click-to-commit. Averaging area and coordinate mapping documented in docs/ENGINEERING_GUIDE.md and inline comments; the Y-axis loupe/sample math correctly follows the pre-existing y-up/y-down flip convention documented in RenderRequest.swift's presentationLayoutExtent.
    - criterion: Offer As Shot, Auto, Daylight, Cloudy, Shade, Tungsten, Fluorescent, Flash, and Custom choices where the source supports them.
      result: pass
      notes: WhiteBalancePreset enum (Models/WhiteBalancePreset.swift) covers exactly this set with Kelvin targets for the fixed presets, Auto samples the current preview (gray-world estimate), Custom is a no-op that preserves current values. Menu disabled when a RAW source lacks decoder capabilities, matching existing RAW-gating convention.
    - criterion: Keep sampled and preset values editable, undoable, and persistent for standard and RAW sources.
      result: pass
      notes: setWhiteBalance() writes to the existing rawDevelop neutralTemperature/neutralTint fields for RAW and the existing temperature/tint adjustment node for standard images, calling endUndoGrouping() first exactly like the pre-existing resetWhiteBalance(_:) path. ColorInspectorTests.testWhiteBalancePresetsUseTheEditableDocumentAndUndoHistory exercises preset apply + undo; WhiteBalancePresetTests.testWhiteBalanceValuesRoundTripInBothDocumentStoragePaths exercises Codable persistence of both storage paths.
  checks_run:
    - swift build (debug) - succeeded
    - swift test --filter WhiteBalancePresetTests|ColorInspectorTests - 13/13 passed
    - scripts/ci-tests.sh fast (deterministic/model/fake-engine, parallel) - 1258/1258 passed
    - scripts/ci-tests.sh serial (Core Image/render + AppKit/UI, serial) - 427/427 passed, 1 skipped (pre-existing opt-in skip)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T04:37:23.005Z
  session: 01MUJBGUDYAYHB9E8Q
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:24.933Z
updated: 2026-09-27T04:37:23.007Z
blockers: []
order: a0
board: product
---

## Objective

Let photographers neutralize a sampled area and choose common white-balance presets, while retaining fine Temperature and Tint adjustment.

## Context

Current controls expose Temperature and Tint but no neutral sampler or preset menu. Respect decoder-specific RAW white balance and the existing non-destructive document model.

Derived from §2.1 White balance and tone fundamentals in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Provide a loupe-assisted neutral sample with a documented averaging area and a clear cancel/commit interaction.
- [ ] Offer As Shot, Auto, Daylight, Cloudy, Shade, Tungsten, Fluorescent, Flash, and Custom choices where the source supports them.
- [ ] Keep sampled and preset values editable, undoable, and persistent for standard and RAW sources.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.


### Comment — codex @ 2026-09-27T04:26:32.530Z

Implemented the white balance preset menu and loupe-assisted neutral sampler. Presets and sampled values use the existing editable document path for standard and RAW sources; sampling averages an 11×11 display-pixel area, supports cancel, and persists through document history. Added regression coverage and documented the behavior. Verified with swift build and focused WhiteBalancePresetTests/ColorInspectorTests (5 tests passing). Commit: 846e03f.

## Agent log

- 2026-09-27T04:37:23.005Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Provide a loupe-assisted neutral sample with a documented averaging area and a clear cancel/commit interaction. (pass) — beginWhiteBalanceSampling/updateWhiteBalanceSample/cancelWhiteBalanceSampling in AppViewModel+Color.swift average an 11x11 display-pixel square, show a 3x loupe crop that follows the pointer, and support Cancel Sample button plus click-to-commit. Averaging area and coordinate mapping documented in docs/ENGINEERING_GUIDE.md and inline comments; the Y-axis loupe/sample math correctly follows the pre-existing y-up/y-down flip convention documented in RenderRequest.swift's presentationLayoutExtent.
- [x] Offer As Shot, Auto, Daylight, Cloudy, Shade, Tungsten, Fluorescent, Flash, and Custom choices where the source supports them. (pass) — WhiteBalancePreset enum (Models/WhiteBalancePreset.swift) covers exactly this set with Kelvin targets for the fixed presets, Auto samples the current preview (gray-world estimate), Custom is a no-op that preserves current values. Menu disabled when a RAW source lacks decoder capabilities, matching existing RAW-gating convention.
- [x] Keep sampled and preset values editable, undoable, and persistent for standard and RAW sources. (pass) — setWhiteBalance() writes to the existing rawDevelop neutralTemperature/neutralTint fields for RAW and the existing temperature/tint adjustment node for standard images, calling endUndoGrouping() first exactly like the pre-existing resetWhiteBalance(_:) path. ColorInspectorTests.testWhiteBalancePresetsUseTheEditableDocumentAndUndoHistory exercises preset apply + undo; WhiteBalancePresetTests.testWhiteBalanceValuesRoundTripInBothDocumentStoragePaths exercises Codable persistence of both storage paths.
Checks run:
- swift build (debug) - succeeded
- swift test --filter WhiteBalancePresetTests|ColorInspectorTests - 13/13 passed
- scripts/ci-tests.sh fast (deterministic/model/fake-engine, parallel) - 1258/1258 passed
- scripts/ci-tests.sh serial (Core Image/render + AppKit/UI, serial) - 427/427 passed, 1 skipped (pre-existing opt-in skip)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJBGUDYAYHB9E8Q
Summary: Verified white-balance presets, neutral sampler, and undo/persistence paths; full fast+serial test suites pass with zero failures, no fixes needed.
