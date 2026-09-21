---
id: KRMA-503
title: Limit masked local-adjustment precision to two decimal places
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Every mask-local adjustment uses no more than two digits after the decimal point.
      result: pass
      notes: LocalAdjustments.clamp quantizes to 0.01 in init, didSet, and decode for all 13 values.
    - criterion: Slider and numeric-entry paths produce the same hundredth-precision value.
      result: pass
      notes: Both bind to the model, which quantizes; slider/Kelvin step is 0.01.
    - criterion: Reset, copy/paste, persistence, preview, and export do not reintroduce extra fractional precision.
      result: pass
      notes: Quantization is at the model boundary so all paths share it; covered by clipboard/document round-trip tests.
    - criterion: Existing global adjustment precision and behavior remain unchanged.
      result: pass
      notes: Global formatting untouched; a stale test that asserted the old local temperature readout was updated.
    - criterion: Focused local-mask tests and dg validate pass.
      result: pass
      notes: 22 focused tests pass; dg validate reports only pre-existing model-name warnings.
  checks_run:
    - swift test --filter LocalAdjustmentControlTests|LocalMaskTests|EditClipboardTests (22 passed)
    - scripts/ci-tests.sh fast (exit 0, after fix)
    - scripts/ci-tests.sh serial (406 passed, 1 skipped)
    - dg validate
    - git diff --check
  findings:
    - "The fast lane initially failed: TemperatureSliderMappingTests asserted the old whole-number local temperature readout (6500 K) that this change intentionally replaced with 6500.40 K."
  fixes:
    - Updated the stale assertion in TemperatureSliderMappingTests to the new hundredth-precision local readout.
  verification_commits:
    - 9f67f00
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-21T04:12:16.155Z
  session: 01MUAQ6U44GVG8VUJT
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - mask
  - local-adjustments
  - precision
created: 2026-09-21T02:40:07.976Z
updated: 2026-09-21T04:12:16.157Z
order: a0
board: product
commits:
  - 9f67f00
---

## Objective

Limit local adjustment values used with masks to no more than two digits after the decimal point.

## Context

When working with masks, local adjustment controls should use predictable hundredth-level precision. Values currently appear to expose or retain more fractional accuracy than is useful for local adjustments, making readouts and numeric entry inconsistent.

## Requirements

1. Apply a maximum precision of 0.01 to every masked local adjustment that is user-editable.
2. Keep slider values, numeric entry, keyboard stepping, reset behavior, copy/paste, persistence, and rendered local-adjustment values consistent at that precision.
3. Display local adjustment readouts with no more than two fractional digits, without exposing a value that cannot actually be represented by the control.
4. Limit this change to mask-local adjustments unless an existing shared control contract requires broader behavior; do not reduce unrelated global adjustment precision accidentally.
5. Add focused coverage for representative local adjustment types and round-trip persistence.

## Acceptance criteria

- [ ] Every mask-local adjustment uses no more than two digits after the decimal point.
- [ ] Slider and numeric-entry paths produce the same hundredth-precision value.
- [ ] Reset, copy/paste, persistence, preview, and export do not reintroduce extra fractional precision.
- [ ] Existing global adjustment precision and behavior remain unchanged.
- [ ] Focused local-mask tests and dg validate pass.

## Implementation notes

Trace the local control bindings and the persisted mask adjustment model before choosing whether to quantize at the model boundary, control binding, or both. Avoid display-only rounding if values still retain a third or later fractional digit in the document.


### Comment — codex @ 2026-09-21T04:08:40.611Z

Implemented in commit 8f04a4d. LocalAdjustments now quantizes all 13 mask-local values to nearest 0.01 at construction, mutation, and decode, keeping preview/render/export and persisted/copy-paste data consistent. Local numeric fields, slider stepping, Kelvin slider mapping, keyboard interaction, and readouts use the same hundredth precision; global adjustment precision is unchanged. Added focused coverage for every local control, global-precision isolation, clipboard/document round trips, and binding undo/reset behavior. Checks: swift test --filter 'LocalAdjustmentControlTests|LocalMaskTests|EditClipboardTests' (22 passed); dg validate OK; git diff --check clean.

## Agent log

- 2026-09-21T04:12:16.155Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Every mask-local adjustment uses no more than two digits after the decimal point. (pass) — LocalAdjustments.clamp quantizes to 0.01 in init, didSet, and decode for all 13 values.
- [x] Slider and numeric-entry paths produce the same hundredth-precision value. (pass) — Both bind to the model, which quantizes; slider/Kelvin step is 0.01.
- [x] Reset, copy/paste, persistence, preview, and export do not reintroduce extra fractional precision. (pass) — Quantization is at the model boundary so all paths share it; covered by clipboard/document round-trip tests.
- [x] Existing global adjustment precision and behavior remain unchanged. (pass) — Global formatting untouched; a stale test that asserted the old local temperature readout was updated.
- [x] Focused local-mask tests and dg validate pass. (pass) — 22 focused tests pass; dg validate reports only pre-existing model-name warnings.
Checks run:
- swift test --filter LocalAdjustmentControlTests|LocalMaskTests|EditClipboardTests (22 passed)
- scripts/ci-tests.sh fast (exit 0, after fix)
- scripts/ci-tests.sh serial (406 passed, 1 skipped)
- dg validate
- git diff --check
Findings:
- The fast lane initially failed: TemperatureSliderMappingTests asserted the old whole-number local temperature readout (6500 K) that this change intentionally replaced with 6500.40 K.
Fixes:
- Updated the stale assertion in TemperatureSliderMappingTests to the new hundredth-precision local readout.
Verification commits:
- 9f67f00
Actor: claude
Resolved model: sonnet
Pickup session: 01MUAQ6U44GVG8VUJT
Summary: Verified: local mask adjustments quantized to 0.01 at the model boundary; fixed one stale readout test.
