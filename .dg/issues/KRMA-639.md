---
id: KRMA-639
title: Auto low-key intent target pinning regresses to neutral median instead of baseline
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Decide whether AutoExposureObjective.targetMedian should let strong low-key/night intent override the structural-evidence gate, or whether the test's expected value is outdated.
      result: pass
      notes: "Policy decision already made in 90811f0: decisive scene-key intent (highKey or lowKey likelihood >= 0.95) zeroes the dark-spread structural term in robustUnderexposureEvidence unless upper structure or shadow clipping materially contradicts it, keeping evidence below the 0.05 gate for the low-key fixture."
    - criterion: Update the losing side (implementation or test) so AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent passes and reflects the intended policy.
      result: pass
      notes: "Implementation was updated (not the test): robustUnderexposureEvidence now takes an optional scene parameter and all three call sites in AutoExposureObjective/AutoEnhancementPolicy pass scene through. Independently recomputed the arithmetic by hand for the darkFacts fixture (p50=0.25, p95=0.45, p05=0.1) with lowKeyLikelihood=1: underexposure evidence ~0.0096, below the 0.05 gate, so intentWeight=1 and target=tone.p50=0.25, matching the test's expectation exactly."
    - criterion: swift test --filter AutoEnhancementCoordinatorTests passes.
      result: pass
      notes: "Ran locally: 19 tests, 0 failures, including testFrozenTargetsPreserveLowKeyIntent (0.25) and testFrozenTargetsDefaultToMiddleGrayPlacement (0.48, default scene keeps the neutral median)."
  checks_run:
    - swift test --filter AutoEnhancementCoordinatorTests (19 tests, 0 failures)
    - scripts/ci-tests.sh fast (1253 tests, exit 0, no failures)
    - Manual re-derivation of robustUnderexposureEvidence/targetMedian arithmetic against the darkFacts fixture for both the low-key and default-scene cases
    - git show 90811f0 review of AutoEnhancementPolicy.swift diff to confirm all call sites of robustUnderexposureEvidence were updated consistently
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T03:38:20.888Z
  session: 01MUJ9L4TP778KPF08
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - auto
created: 2026-09-26T17:49:53.301Z
updated: 2026-09-27T03:38:20.890Z
parent: KRMA-592
blockers: []
order: a0
board: product
---

## Objective

`AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent` fails deterministically on
`main`: `AutoEvaluationTargets.frozen` returns `globalTargetMedian == 0.48` for a fully low-key scene
(`lowKeyLikelihood == 1`) where the test expects `0.25` (the baseline median).

## Context

Found while running the fast test lane during KRMA-592 verification (unrelated to that issue's
Edit→Library inspector-dismissal animation). Root cause is in
`AutoExposureObjective.targetMedian` (`Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementPolicy.swift`):
when `robustUnderexposureEvidence(tone:)` crosses `structuralEvidenceGate` (0.05), `intentWeight` is
forced to 0 regardless of how strong `lowKeyLikelihood`/`nightLikelihood` is, so the target collapses
to `neutralMedian` (0.48) instead of tracking `tone.p50`. The darkFacts() fixture used by the test
produces underexposure evidence above that gate, so the "full low-key intent pins the target to the
baseline median" behavior the test documents no longer holds under current gating logic.

Either the gating logic needs to let a sufficiently strong scene-key signal override the structural
evidence gate, or the test's expectation is stale relative to an intentional policy change (the
inline comment above `intentWeight` suggests the neutral-full-weight behavior above the gate is
deliberate) and should be updated to match. This is an Auto-exposure policy decision, not a
mechanical fix, so it needs a human/implementation-agent judgment call rather than a verifier's
localized patch.

## Acceptance criteria

- [ ] Decide whether `AutoExposureObjective.targetMedian` should let strong low-key/night intent
      override the structural-evidence gate, or whether the test's expected value is outdated.
- [ ] Update the losing side (implementation or test) so
      `AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent` passes and reflects the
      intended policy.
- [ ] `swift test --filter AutoEnhancementCoordinatorTests` passes.

## Implementation notes

Relevant code: `AutoExposureObjective.targetMedian` and `robustUnderexposureEvidence` in
`Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementPolicy.swift:533-598`. Test:
`Tests/KromoraKitTests/AutoEnhancementCoordinatorTests.swift:202-208`.

### Comment — codex @ 2026-09-27T03:33:45.896Z

codex implementation review: The reported failure is already resolved in committed 90811f0d (Fix pre-existing test failures). The policy decision is to preserve decisive scene-key intent unless retained upper structure or shadow clipping materially contradicts it; broad dark spread alone is not evidence against low-key intent when likelihood is >= 0.95. AutoExposureObjective.targetMedian and the correction cap now pass scene into robustUnderexposureEvidence, which applies that rule. Verification: swift test --filter AutoEnhancementCoordinatorTests passed (19 tests, 0 failures), including testFrozenTargetsPreserveLowKeyIntent at 0.25 and the neutral default at 0.48. No duplicate product change was needed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T03:38:20.888Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Decide whether AutoExposureObjective.targetMedian should let strong low-key/night intent override the structural-evidence gate, or whether the test's expected value is outdated. (pass) — Policy decision already made in 90811f0: decisive scene-key intent (highKey or lowKey likelihood >= 0.95) zeroes the dark-spread structural term in robustUnderexposureEvidence unless upper structure or shadow clipping materially contradicts it, keeping evidence below the 0.05 gate for the low-key fixture.
- [x] Update the losing side (implementation or test) so AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent passes and reflects the intended policy. (pass) — Implementation was updated (not the test): robustUnderexposureEvidence now takes an optional scene parameter and all three call sites in AutoExposureObjective/AutoEnhancementPolicy pass scene through. Independently recomputed the arithmetic by hand for the darkFacts fixture (p50=0.25, p95=0.45, p05=0.1) with lowKeyLikelihood=1: underexposure evidence ~0.0096, below the 0.05 gate, so intentWeight=1 and target=tone.p50=0.25, matching the test's expectation exactly.
- [x] swift test --filter AutoEnhancementCoordinatorTests passes. (pass) — Ran locally: 19 tests, 0 failures, including testFrozenTargetsPreserveLowKeyIntent (0.25) and testFrozenTargetsDefaultToMiddleGrayPlacement (0.48, default scene keeps the neutral median).
Checks run:
- swift test --filter AutoEnhancementCoordinatorTests (19 tests, 0 failures)
- scripts/ci-tests.sh fast (1253 tests, exit 0, no failures)
- Manual re-derivation of robustUnderexposureEvidence/targetMedian arithmetic against the darkFacts fixture for both the low-key and default-scene cases
- git show 90811f0 review of AutoEnhancementPolicy.swift diff to confirm all call sites of robustUnderexposureEvidence were updated consistently
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJ9L4TP778KPF08
