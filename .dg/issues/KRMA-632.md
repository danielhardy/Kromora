---
id: KRMA-632
title: Share Auto muted-color eligibility check between coordinator scoring and policy proposal
type: task
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-26T14:57:58.549Z
updated: 2026-09-26T14:57:58.549Z
blockers: []
order: zzzh
board: product
parent: KRMA-593
---

## Objective

Share Auto muted-color eligibility check between coordinator scoring and policy proposal.

## Context

KRMA-593 added two independent implementations of the same "is this frame eligible for a
muted-color boost" gate:

- `AutoEvaluationTargets.colorfulnessTarget` in
  `Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementCoordinator.swift` (drives the
  candidate-scoring reward for closing the colorfulness gap).
- `ColorPlacement.evaluate`'s muted-color branch in
  `Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementPolicy.swift` (drives whether the
  proposal actually raises vibrance).

The two gates are not identical: the policy's branch additionally requires
`spread < 0.5` (`saturationP95 - saturationMedian`), which the coordinator's gate does not
check. Today this does not cause a visible bug — when the policy declines to propose a
vibrance change, no candidate render actually gains colorfulness, so the scoring reward
term evaluates to the same (non-discriminating) value across candidates. But the two copies
can silently drift further apart as either file is tuned independently, at which point the
score could start rewarding a colorfulness improvement that the policy is not actually
allowed to produce (or vice versa).

## Acceptance criteria

- [ ] The muted-color eligibility conditions (mixed-light, monochrome/sunset/night
      likelihoods, color-neutral confidence, colorfulness, saturationP95 spread) are computed
      from a single shared helper used by both `AutoEvaluationTargets.colorfulnessTarget` and
      `ColorPlacement.evaluate`.
- [ ] Existing Auto policy/coordinator/quality-regression tests continue to pass with no
      behavior change (this is a maintainability cleanup, not a policy recalibration).

## Implementation notes

Found during KRMA-593 verification (non-blocking). See
`Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementCoordinator.swift` around
`colorfulnessTarget` and `Sources/KromoraKit/Models/PhotoAnalysis/AutoEnhancementPolicy.swift`
around `ColorPlacement.evaluate`.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
