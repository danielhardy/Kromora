---
id: KRMA-639
title: Auto low-key intent target pinning regresses to neutral median instead of baseline
type: bug
status: ready
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - auto
created: 2026-09-26T17:49:53.301Z
updated: 2026-09-27T02:29:03.006Z
parent: KRMA-592
blockers: []
order: zy
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
