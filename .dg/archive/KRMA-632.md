---
id: KRMA-632
title: Share Auto muted-color eligibility check between coordinator scoring and policy proposal
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Muted-color eligibility conditions computed from a single shared helper used by both AutoEvaluationTargets.colorfulnessTarget and ColorPlacement.evaluate
      result: pass
      notes: AutoMutedColorEligibility.allowsVibranceLift(facts:) in Sources/KromoraKit/Models/PhotoAnalysis/AutoMutedColorEligibility.swift now encodes isMixed, monochrome/sunset/night likelihoods (with dark-chromatic-evidence exception), colorNeutral confidence, colorfulness, and saturationP95-saturationMedian spread. Both AutoEnhancementCoordinator.colorfulnessTarget and AutoEnhancementPolicy.ColorPlacement.evaluate call it; the coordinator retains its scoring-only saturationP95 <= 0.85 cap and the policy retains its scene-suppression early-returns for the clipping/over-saturation branch, both of which are outside the shared gate's scope.
    - criterion: Existing Auto policy/coordinator/quality-regression tests continue to pass with no behavior change
      result: pass
      notes: swift test --filter 'Auto(EnhancementCoordinator|EnhancementPolicy|QualityRegression)' -> 69/69 passed. Full fast CI suite (scripts/ci-tests.sh fast) -> 1273/1273 passed, exit 0, including PackageSettingsTests (Swift 6 zero-diagnostics gate). Adding the spread<0.5 check to the coordinator's gate only changes the scoring target in the case where the policy already declines to propose a vibrance change, so rendered output is unaffected, matching the issue's own analysis.
  checks_run:
    - swift build
    - swift test --filter 'Auto(EnhancementCoordinator|EnhancementPolicy|QualityRegression)' (69 passed, 0 failed)
    - scripts/ci-tests.sh fast (1273 passed, 0 failed, exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T07:38:00.510Z
  session: 01MUJI5BP4QCXEFNUV
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-26T14:57:58.549Z
updated: 2026-09-28T14:41:32.752Z
parent: KRMA-593
blockers: []
order: hi5y0nrq
board: product
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

### Comment — codex @ 2026-09-27T07:33:25.983Z

Implemented shared muted-color eligibility in AutoMutedColorEligibility and applied it to both coordinator scoring and policy vibrance proposals. Retained the coordinator's scoring-only saturation cap and policy scene suppression for other color adjustments. Verification: swift test --filter 'Auto(EnhancementCoordinator|EnhancementPolicy|QualityRegression)' (69 tests passed; 0 failures). The broader swift test run was stopped during the unrelated full synthetic library relocation test. Commit: 26e3e42.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T07:38:00.510Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Muted-color eligibility conditions computed from a single shared helper used by both AutoEvaluationTargets.colorfulnessTarget and ColorPlacement.evaluate (pass) — AutoMutedColorEligibility.allowsVibranceLift(facts:) in Sources/KromoraKit/Models/PhotoAnalysis/AutoMutedColorEligibility.swift now encodes isMixed, monochrome/sunset/night likelihoods (with dark-chromatic-evidence exception), colorNeutral confidence, colorfulness, and saturationP95-saturationMedian spread. Both AutoEnhancementCoordinator.colorfulnessTarget and AutoEnhancementPolicy.ColorPlacement.evaluate call it; the coordinator retains its scoring-only saturationP95 <= 0.85 cap and the policy retains its scene-suppression early-returns for the clipping/over-saturation branch, both of which are outside the shared gate's scope.
- [x] Existing Auto policy/coordinator/quality-regression tests continue to pass with no behavior change (pass) — swift test --filter 'Auto(EnhancementCoordinator|EnhancementPolicy|QualityRegression)' -> 69/69 passed. Full fast CI suite (scripts/ci-tests.sh fast) -> 1273/1273 passed, exit 0, including PackageSettingsTests (Swift 6 zero-diagnostics gate). Adding the spread<0.5 check to the coordinator's gate only changes the scoring target in the case where the policy already declines to propose a vibrance change, so rendered output is unaffected, matching the issue's own analysis.
Checks run:
- swift build
- swift test --filter 'Auto(EnhancementCoordinator|EnhancementPolicy|QualityRegression)' (69 passed, 0 failed)
- scripts/ci-tests.sh fast (1273 passed, 0 failed, exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJI5BP4QCXEFNUV
Summary: Verified shared AutoMutedColorEligibility gate: single source of truth used by both coordinator scoring and policy proposal, no behavior change; 69 targeted tests + full fast CI suite (1273 tests) pass.
