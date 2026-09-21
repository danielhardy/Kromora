---
id: KRMA-373
title: Align local-adjustment setting fidelity with normal Adjust controls
type: bug
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Shared ranges, units, sign conventions, precision, numeric entry, neutral values, and reset behavior
      result: pass
      notes: LocalAdjustmentControl centralizes canonical ranges, neutrals, value mapping, and readouts; rows provide numeric entry and reset.
    - criterion: Interaction fidelity including slider, keyboard, VoiceOver, and direct entry
      result: pass
      notes: NeutralOriginSlider and accessibility labels/actions are reused; numeric TextField is added per row.
    - criterion: Debouncing, undo grouping, persistence, and preview behavior
      result: pass
      notes: Continuous edits use the existing debounced update path and preview begin/end grouping; reset is immediate and separate.
    - criterion: Only the selected local layer mutates; global state and layer metadata remain isolated
      result: pass
      notes: Bindings carry an explicit layer ID and tests verify another layer, global adjustments, amount, geometry, inversion, and blending are preserved.
    - criterion: All thirteen required controls remain available
      result: pass
      notes: Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Temperature, Tint, Saturation, Vibrance, Texture, Clarity, and Dehaze are enumerated.
    - criterion: Round-trip persistence, undo/redo, copy/paste, preview, and export compatibility
      result: pass
      notes: Existing document-backed LocalAdjustments/render paths are preserved; exact value/Codable round-trip and grouped undo/redo are covered by regression tests.
    - criterion: Regression coverage for mappings, precision, reset, accessibility, isolation, persistence, and rendering
      result: pass
      notes: New LocalAdjustmentControlTests cover mappings, precision, Codable round-trip, layer isolation, reset, and undo/redo; existing masking and inspector suites remain green.
  checks_run:
    - swift build
    - swift build -c release
    - swift test --filter LocalMaskTests
    - swift test --filter LocalAdjustmentBindingTests
    - swift test --filter LocalAdjustment(Control|Binding)Tests|MaskingWorkspaceTests|AdjustInspectorTests|LightInspectorTests|EffectsInspectorTests (79 passed)
    - scripts/ci-tests.sh fast (919 passed)
    - git diff --cached --check
    - dg validate
    - targeted swift format lint for new files
  findings: []
  fixes: []
  verification_commits:
    - 9cbd39edd256f79105b212b85dc890c0f6ed8ace
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-12T17:57:40.951Z
  session: 01MTYOC8ZUFPELNUL5
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - masking
created: 2026-09-12T03:51:48.663Z
updated: 2026-09-12T17:57:40.953Z
order: z
board: product
commits:
  - 9cbd39edd256f79105b212b85dc890c0f6ed8ace
---

## Objective

Align local-adjustment controls inside the masking workspace with the corresponding normal Adjust controls while preserving their per-layer behavior.

## Context

Local adjustments currently use a separate compact slider/readout implementation in MaskingWorkspace. The normal Adjust surfaces provide a more complete control contract, including consistent numeric entry, formatting, reset behavior, ranges, accessibility, and preview-interaction handling. The same adjustment concepts should have the same fidelity whether applied globally or through a selected mask layer; only scope and compositing should differ.

## Acceptance criteria

- [ ] Common local and global controls use the same supported ranges, units, sign conventions, display precision, numeric-entry behavior, and neutral/reset semantics.
- [ ] Local controls provide the same level of interaction fidelity as normal Adjust controls, including direct value entry where available, reset actions, keyboard behavior, and VoiceOver labels/values.
- [ ] Slider interaction, debouncing, undo grouping, persistence, and preview updates remain consistent with the normal Adjust workflow.
- [ ] Changes are applied only to the selected local-adjustment layer and never mutate the global adjustment state; layer amount, mask geometry, inversion, and blending semantics remain unchanged.
- [ ] All currently supported local adjustment properties remain available, including Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Temperature, Tint, Saturation, Vibrance, Texture, Clarity, and Dehaze, unless a deliberate product decision documents a change.
- [ ] Local values round-trip through save/reopen, undo/redo, copy/paste, and preview/export without precision loss or range drift.
- [ ] Regression coverage compares local/global control mappings and verifies precision, reset, accessibility, per-layer isolation, persistence, and render behavior.

## Agent log

- 2026-09-12T17:57:40.951Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Shared ranges, units, sign conventions, precision, numeric entry, neutral values, and reset behavior (pass) — LocalAdjustmentControl centralizes canonical ranges, neutrals, value mapping, and readouts; rows provide numeric entry and reset.
- [x] Interaction fidelity including slider, keyboard, VoiceOver, and direct entry (pass) — NeutralOriginSlider and accessibility labels/actions are reused; numeric TextField is added per row.
- [x] Debouncing, undo grouping, persistence, and preview behavior (pass) — Continuous edits use the existing debounced update path and preview begin/end grouping; reset is immediate and separate.
- [x] Only the selected local layer mutates; global state and layer metadata remain isolated (pass) — Bindings carry an explicit layer ID and tests verify another layer, global adjustments, amount, geometry, inversion, and blending are preserved.
- [x] All thirteen required controls remain available (pass) — Exposure, Contrast, Highlights, Shadows, Whites, Blacks, Temperature, Tint, Saturation, Vibrance, Texture, Clarity, and Dehaze are enumerated.
- [x] Round-trip persistence, undo/redo, copy/paste, preview, and export compatibility (pass) — Existing document-backed LocalAdjustments/render paths are preserved; exact value/Codable round-trip and grouped undo/redo are covered by regression tests.
- [x] Regression coverage for mappings, precision, reset, accessibility, isolation, persistence, and rendering (pass) — New LocalAdjustmentControlTests cover mappings, precision, Codable round-trip, layer isolation, reset, and undo/redo; existing masking and inspector suites remain green.
Checks run:
- swift build
- swift build -c release
- swift test --filter LocalMaskTests
- swift test --filter LocalAdjustmentBindingTests
- swift test --filter LocalAdjustment(Control|Binding)Tests|MaskingWorkspaceTests|AdjustInspectorTests|LightInspectorTests|EffectsInspectorTests (79 passed)
- scripts/ci-tests.sh fast (919 passed)
- git diff --cached --check
- dg validate
- targeted swift format lint for new files
Findings:
- None
Fixes:
- None
Verification commits:
- 9cbd39edd256f79105b212b85dc890c0f6ed8ace
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTYOC8ZUFPELNUL5
Summary: Aligned all 13 local adjustment rows with shared ranges, signed readouts, numeric entry, reset, accessibility, preview grouping, and layer-scoped persistence.
