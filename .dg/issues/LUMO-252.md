---
id: LUMO-252
title: White balance Tint edits still move the comparison Original pane
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: RAW-aware white-balance Tint edits leave the comparison Original pane at its baseline while the Adjusted pane updates live
      result: pass
    - criterion: Intentional white-balance resets still invalidate and refresh the comparison baseline
      result: pass
    - criterion: Regression coverage verifies the RAW Tint request boundary
      result: pass
  checks_run:
    - swift test --filter ComparisonModeTests (13 passed, 0 failed)
    - swift test (908 passed, 42 expected skips, 0 failures)
    - swift build -c release (passed)
    - git diff --check (passed)
    - dg validate (OK; pre-existing pickup-model and context-completeness warnings only)
  findings: []
  fixes: []
  verification_commits:
    - 9e4ce79
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-06T15:56:55.335Z
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - color
  - comparison
  - rendering
created: 2026-09-06T05:40:18.787Z
updated: 2026-09-07T04:02:48.344Z
parent: LUMO-240
depends_on:
  - LUMO-240
order: j5gzpmo1
board: product
commits:
  - c739949
  - 9e4ce79
---

## Objective

Make RAW-aware white-balance Tint edits leave the comparison Original pane fixed, matching the
Temperature behavior fixed in LUMO-240.

## Context

LUMO-240 froze the comparison baseline against RAW Temperature edits by excluding
`RAWDevelopSettings.neutralTemperature` from the comparison-frame-changed check in
`AppViewModel.rawDevelopChangedComparisonFrame` (see `Sources/LumoKit/ViewModels/AppViewModel.swift`).
`neutralTint`, set by `developTintBinding()` in `Sources/LumoKit/ViewModels/AppViewModel+Develop.swift`,
was intentionally left out of that exclusion since the ticket was scoped to Temperature only.

That means dragging the Tint slider on a RAW photo in split view still reproduces the original bug:
every tick treats `rawDevelop` as comparison-frame-changing, moving the Original pane to track the
live Tint value instead of holding it at the baseline.

## Reproduction

1. Open a RAW photo with split view (Original + Adjusted) active.
2. Drag the white-balance Tint slider.
3. Observe the Original pane shift with the Tint value, the same way Temperature used to before
   LUMO-240.

## Expected

Tint edits should behave like Temperature edits: only the Adjusted pane updates live; the Original
pane stays at the comparison baseline until an intentional baseline-invalidating change (source
switch, crop/other develop change, Reset Photo, `resetWhiteBalance` which already clears tint too).

## Suggested approach

Extend `AppViewModel.rawDevelopChangedComparisonFrame` to also zero `neutralTint` on both sides of
the comparison, mirroring the existing `neutralTemperature` handling. Add regression coverage
alongside `ComparisonModeTests.testRAWTemperatureEditLeavesOriginalRequestAtItsBaseline` for Tint.

Note `resetDevelop(.whiteBalance)` and `resetWhiteBalance()` intentionally clear both
`neutralTemperature` and `neutralTint` together — that combined reset should keep invalidating the
baseline (it is an explicit whole-control reset, not a live per-tick edit), so the fix must only
change ongoing Tint *edits*, not resets.

## Found during

Verification of LUMO-240 (commit 4c3ca82). Non-blocking: LUMO-240's acceptance criteria only cover
Temperature and are fully met.

## Agent log

- 2026-09-06T15:53:30.832Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] RAW-aware white-balance Tint edits leave the comparison Original pane at its baseline while the Adjusted pane updates live (pass)
- [x] Intentional white-balance resets still invalidate and refresh the comparison baseline (pass)
- [x] Regression coverage verifies the RAW Tint request boundary (pass)
Checks run:
- swift test --filter ComparisonModeTests|DevelopInspectorTests.testResettingWhiteBalanceClearsBothTemperatureAndTint (14 passed, 0 failed)
- swift test (908 passed, 42 expected skips, 0 failures)
- swift build -c release (passed)
- git diff --check (passed)
- dg validate (OK; pre-existing pickup-model and context-completeness warnings only)
Findings:
- None
Fixes:
- None
Verification commits:
- c739949
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTPZHA0OQDYP8Q5G
Summary: RAW Tint edits now preserve the comparison Original baseline; explicit RAW white-balance resets still invalidate it.

- 2026-09-06T15:56:55.336Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] RAW-aware white-balance Tint edits leave the comparison Original pane at its baseline while the Adjusted pane updates live (pass)
- [x] Intentional white-balance resets still invalidate and refresh the comparison baseline (pass)
- [x] Regression coverage verifies the RAW Tint request boundary (pass)
Checks run:
- swift test --filter ComparisonModeTests (13 passed, 0 failed)
- swift test (908 passed, 42 expected skips, 0 failures)
- swift build -c release (passed)
- git diff --check (passed)
- dg validate (OK; pre-existing pickup-model and context-completeness warnings only)
Findings:
- None
Fixes:
- None
Verification commits:
- 9e4ce79
Actor: codex
Resolved model: unknown
Summary: RAW Tint edits now preserve the comparison Original baseline; explicit RAW white-balance resets still invalidate it.
