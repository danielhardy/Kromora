---
id: KRMA-457
title: Vignette midpoint reset is off by one after a fractional edit
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: swift test --filter EffectsInspectorTests passes, including testBindingsRoundTripAndIndividualResetsPreserveOtherEffects
      result: pass
      notes: All 7 EffectsInspectorTests passed.
    - criterion: Root-cause the vignette midpoint rounding/reset discrepancy and fix the actual defect rather than masking incorrect behavior
      result: pass
      notes: "The defect was the test expectation: KRMA-445 rounds 40.6 to 41 at the VignetteAdjustments value boundary, and resetVignette(.amount) correctly preserves the rounded midpoint. Updated the assertion to 41 and documented the invariant."
  checks_run:
    - swift test --filter EffectsInspectorTests (7/7 passed)
    - git diff --check (passed)
    - dg validate (passed with pre-existing unknown-model warnings only)
  findings:
    - AppViewModel vignetteBinding, vignetteValue, and resetVignette logic are correct; no production-code change was needed.
  fixes:
    - Updated Tests/KromoraKitTests/EffectsInspectorTests.swift to expect the rounded midpoint value 41 after resetting vignette Amount.
  verification_commits:
    - 6c3f777
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-19T02:00:59.984Z
  session: 01MU7QNKYMOVTWSR42
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-18T23:28:13.089Z
updated: 2026-09-19T02:00:59.987Z
parent: KRMA-449
order: z8
board: product
commits:
  - 6c3f777
---

## Objective

Fix `EffectsInspectorTests.testBindingsRoundTripAndIndividualResetsPreserveOtherEffects`, which fails
with `41.0` vs an expected `40.0` after `viewModel.vignetteBinding(for: .midpoint).wrappedValue = 40.6`
is set and later reset. The rounding/reset path in `AppViewModel`'s vignette effects logic looks to be
off by one somewhere between the binding write and `vignetteValue(for:)`.

## Context

Found while verifying KRMA-449 (Photos promise/bitmap drop import). KRMA-449's own diff never touched
this code; the bug was simply unreachable because `EffectsInspectorView.swift` and
`EffectsInspectorTests.swift` did not compile before this verification pass restored the build (a
pre-existing, unrelated argument-order break — see KRMA-449's completion comment). Once compiling, this
test fails deterministically and was never part of KRMA-449's own acceptance criteria, so it is filed
here rather than fixed inline.

## Acceptance criteria

- [ ] `swift test --filter EffectsInspectorTests` passes, including
      `testBindingsRoundTripAndIndividualResetsPreserveOtherEffects`.
- [ ] Root-caused: identify whether the bug is in `AppViewModel`'s vignette midpoint rounding, its reset
      logic, or the test's own expectation, and fix the actual defect rather than adjusting the test to
      match incorrect behavior.

## Implementation notes

Start from `Tests/KromoraKitTests/EffectsInspectorTests.swift:119` and the `vignetteBinding`/
`vignetteValue`/`resetVignette` implementations in `AppViewModel`/`AppViewModel+Effects.swift`.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-19T02:00:59.984Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] swift test --filter EffectsInspectorTests passes, including testBindingsRoundTripAndIndividualResetsPreserveOtherEffects (pass) — All 7 EffectsInspectorTests passed.
- [x] Root-cause the vignette midpoint rounding/reset discrepancy and fix the actual defect rather than masking incorrect behavior (pass) — The defect was the test expectation: KRMA-445 rounds 40.6 to 41 at the VignetteAdjustments value boundary, and resetVignette(.amount) correctly preserves the rounded midpoint. Updated the assertion to 41 and documented the invariant.
Checks run:
- swift test --filter EffectsInspectorTests (7/7 passed)
- git diff --check (passed)
- dg validate (passed with pre-existing unknown-model warnings only)
Findings:
- AppViewModel vignetteBinding, vignetteValue, and resetVignette logic are correct; no production-code change was needed.
Fixes:
- Updated Tests/KromoraKitTests/EffectsInspectorTests.swift to expect the rounded midpoint value 41 after resetting vignette Amount.
Verification commits:
- 6c3f777
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MU7QNKYMOVTWSR42
Summary: Corrected the stale vignette midpoint reset expectation. The binding stores 40.6 as 41 by design, and resetVignette(.amount) preserves that rounded midpoint; AppViewModel rounding and reset logic were already correct.
