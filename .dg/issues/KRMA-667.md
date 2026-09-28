---
id: KRMA-667
title: Heal membrane pull/push pyramid computes numerator and weight chains redundantly
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: healedFill maintains one pyramid chain (downsampling a single four-channel image) instead of two parallel chains built from the same starting image
      result: pass
      notes: "Commit 4a85eaf replaces numeratorLevels/weightLevels with a single levels: [CIImage] array seeded once with difference and downsampled once per level (RetouchRenderer.swift:112-121). The retouchPush kernel already reads .rgb from its numerator argument and .a from its confidence argument (KromoraCIKernels.ci.metal:437-444), so passing the same shared level image twice into those two sampler slots is semantically identical to the old two-array scheme while eliminating the duplicate blur/downsample pass."
    - criterion: Heal/Clone pixel output is unchanged for existing regression coverage, including testHealMembraneExcludesPixelsInsideTheHole and testHealOverFlatExteriorDoesNotOvershootDestinationTone
      result: pass
      notes: Both named tests pass, plus testManuallySourcedHealAndCloneProduceDifferentLocalFills, testRetouchSpotChangesRenderedPixelsAndNeutralRetouchIsIdentity, and testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry (all Heal/Clone/Retouch coverage in RenderPipelineTests). Full required serial (435 tests) and fast (1300 tests) CI lanes also pass with 0 failures.
  checks_run:
    - swift build
    - swift test --filter RenderPipelineTests/(testRetouchSpotChangesRenderedPixelsAndNeutralRetouchIsIdentity|testManuallySourcedHealAndCloneProduceDifferentLocalFills|testHealMembraneExcludesPixelsInsideTheHole|testHealOverFlatExteriorDoesNotOvershootDestinationTone|testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry) -> 5/5 passed
    - scripts/ci-tests.sh serial -> 435 tests, 1 skipped, 0 failures
    - scripts/ci-tests.sh fast -> 1300 tests, 0 failures
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T21:36:47.774Z
  session: 01MUKC04YPRXN329YL
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-27T19:40:17.340Z
updated: 2026-09-28T14:41:35.030Z
parent: KRMA-659
blockers: []
order: o3yofupa
board: product
---

## Objective

Avoid computing the Heal membrane's numerator and confidence pyramids as two independent
blur/downsample chains from the same starting image.

## Context

`RetouchRenderer.healedFill` (Sources/KromoraKit/Models/RetouchRenderer.swift, KRMA-659/353d5a4)
seeds both `numeratorLevels` and `weightLevels` from the exact same `difference` image
(`var numeratorLevels = [difference]; var weightLevels = [difference]`), then downsamples each
array independently through `downsample(_:to:)`. Since `difference` already carries the weighted
RGB numerator in its color channels and the confidence weight in alpha, and `downsample` applies
an identical Gaussian blur + 2x reduction to whichever image it is given, the two arrays end up
computing the *same* blur/downsample chain twice per pyramid level (once for the array whose only
consumed channel is `.rgb`, once for the array whose only consumed channel is `.a`). This is a
performance-only finding from KRMA-659 verification, not a correctness defect — the retouchPush
kernel (fixed in the same verification pass to blend `propagated`/`localMean` instead of summing
them) still reads exactly one channel from each array, so the duplicate computation is otherwise
harmless.

## Acceptance criteria

- [ ] `healedFill` maintains one pyramid chain (downsampling a single four-channel image) instead
      of two parallel chains built from the same starting image, so each Heal spot's per-level
      Gaussian blur + downsample runs once instead of twice.
- [ ] Heal/Clone pixel output is unchanged for existing regression coverage, including
      `testHealMembraneExcludesPixelsInsideTheHole` and
      `testHealOverFlatExteriorDoesNotOvershootDestinationTone`.

## Implementation notes

Candidate approach: keep a single `levels: [CIImage]` array seeded with `difference` and
downsampled once per level; have the coarsest/refine `retouchPush` calls read both `.rgb`
(numerator) and `.a` (confidence) from the same sampler argument instead of two separate
arguments, or pass the same image twice into the existing two-sampler signature without
duplicating the upstream Core Image graph nodes.

### Comment — codex @ 2026-09-27T21:29:18.977Z

Implemented a single shared Heal membrane pyramid chain; each level is downsampled once and the existing pull/push kernel reads RGB numerator and alpha confidence from that shared image. Verified with focused RenderPipelineTests: testHealMembraneExcludesPixelsInsideTheHole and testHealOverFlatExteriorDoesNotOvershootDestinationTone (both passed). Commit: 4a85eaf.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T21:36:47.774Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] healedFill maintains one pyramid chain (downsampling a single four-channel image) instead of two parallel chains built from the same starting image (pass) — Commit 4a85eaf replaces numeratorLevels/weightLevels with a single levels: [CIImage] array seeded once with difference and downsampled once per level (RetouchRenderer.swift:112-121). The retouchPush kernel already reads .rgb from its numerator argument and .a from its confidence argument (KromoraCIKernels.ci.metal:437-444), so passing the same shared level image twice into those two sampler slots is semantically identical to the old two-array scheme while eliminating the duplicate blur/downsample pass.
- [x] Heal/Clone pixel output is unchanged for existing regression coverage, including testHealMembraneExcludesPixelsInsideTheHole and testHealOverFlatExteriorDoesNotOvershootDestinationTone (pass) — Both named tests pass, plus testManuallySourcedHealAndCloneProduceDifferentLocalFills, testRetouchSpotChangesRenderedPixelsAndNeutralRetouchIsIdentity, and testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry (all Heal/Clone/Retouch coverage in RenderPipelineTests). Full required serial (435 tests) and fast (1300 tests) CI lanes also pass with 0 failures.
Checks run:
- swift build
- swift test --filter RenderPipelineTests/(testRetouchSpotChangesRenderedPixelsAndNeutralRetouchIsIdentity|testManuallySourcedHealAndCloneProduceDifferentLocalFills|testHealMembraneExcludesPixelsInsideTheHole|testHealOverFlatExteriorDoesNotOvershootDestinationTone|testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry) -> 5/5 passed
- scripts/ci-tests.sh serial -> 435 tests, 1 skipped, 0 failures
- scripts/ci-tests.sh fast -> 1300 tests, 0 failures
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUKC04YPRXN329YL
Summary: Verified: shared Heal membrane pyramid chain eliminates duplicate blur/downsample pass; kernel already read .rgb/.a from separate args so output is unchanged. Full fast+serial CI lanes pass.
