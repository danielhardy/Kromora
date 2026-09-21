---
id: KRMA-208
title: Fix missing string interpolation in AutoLightEngine exposure rationale
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Exposure rationale displays the formatted median value
      result: pass
    - criterion: Regression coverage exercises AutoLightEngine.evaluate rationale output
      result: pass
  checks_run:
    - swift test --filter AutoLightEngineTests
    - swift test --filter AutoLightEngineTests/testExposureRationaleIncludesFormattedMedian
    - git diff --check
    - dg validate
  findings:
    - dg validate reports only the pre-existing warning that agents.pickup.runner model gpt-5.6-luna is not known for codex.
  fixes:
    - Changed the exposure rationale to interpolate format(tone.p50).
    - Added testExposureRationaleIncludesFormattedMedian with exact expected rationale text.
  verification_commits:
    - 81e34dc
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T19:11:07.542Z
  session: 01MTNBVMB1WLS3RSI9
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-04T18:51:42.916Z
updated: 2026-09-10T12:53:47.234Z
parent: KRMA-207
order: eeeeeec4
board: product
commits:
  - 81e34dc
---

## Objective

Fix missing string interpolation in AutoLightEngine exposure rationale

## Context

`Sources/LumoKit/Models/PhotoAnalysis/AutoLightEngine.swift:325` (in
`AutoLightSceneSignals.exposure`, introduced in commit `7e990f07`, predates KRMA-207) builds the
exposure evaluator's rationale string as:

```swift
reason: "Median (format(tone.p50)) EV correction, restrained by tonal-key intent."
```

`format(tone.p50)` is inside the string literal with no `\(...)` interpolation, so the private
`format(_:)` helper is never called — the rationale text literally reads `"Median
(format(tone.p50)) EV correction..."` instead of showing the actual median value. Found during
KRMA-207 counterpoint verification; out of that ticket's scope (pre-existing, unrelated to the
corpus-tuning change), so filed separately.

## Fix

Change the literal to `"Median (\(format(tone.p50))) EV correction, restrained by tonal-key
intent."` and add/adjust a test asserting the rationale explanation contains a formatted numeric
value (e.g. via `AutoLightEngine.evaluate(...).rationale.exposure.explanation`).


## Acceptance criteria

- [ ]

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-04T19:11:07.544Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Exposure rationale displays the formatted median value (pass)
- [x] Regression coverage exercises AutoLightEngine.evaluate rationale output (pass)
Checks run:
- swift test --filter AutoLightEngineTests
- swift test --filter AutoLightEngineTests/testExposureRationaleIncludesFormattedMedian
- git diff --check
- dg validate
Findings:
- dg validate reports only the pre-existing warning that agents.pickup.runner model gpt-5.6-luna is not known for codex.
Fixes:
- Changed the exposure rationale to interpolate format(tone.p50).
- Added testExposureRationaleIncludesFormattedMedian with exact expected rationale text.
Verification commits:
- 81e34dc
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTNBVMB1WLS3RSI9
Summary: Interpolated the formatted median in AutoLightEngine exposure rationale and added an exact-output regression test.
