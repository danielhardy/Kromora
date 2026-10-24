---
id: KRMA-855
title: "Test semantic mask resolver: soften/shift/strength at matte resolution before resize"
type: task
status: done
priority: low
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Resolver-level semantic resolution with non-default softness, edge shift, and strength reports the requested target size and only finite [0,1] matte values.
      result: pass
      notes: testCoordinatorResolverAppliesSemanticSettingsBeforeResizeAndBoundsPayload passed.
    - criterion: Compare soften-before-resize with resize-then-soften on a smooth matte at 2-3 softness values, documenting and enforcing tolerance.
      result: pass
      notes: The test documents a 0.05 absolute coverage tolerance for the 1 px minimum radius and integer radius rounding; softness 0.12, 0.5, and 0.9 remained within it.
    - criterion: Strength 0.5 on a binary matte yields maximum coverage 0.5; edge shift +1 saturates and -1 empties coverage.
      result: pass
      notes: testSemanticStrengthAndExtremeEdgeShiftClampResolvedCoverage passed.
    - criterion: Identity settings return the resized matte unchanged and bypass the feather allocation path.
      result: pass
      notes: The injected feather closure was not called, and resolver output equaled the resized seed.
    - criterion: The tests run in the fast lane.
      result: pass
      notes: scripts/ci-tests.sh fast exited 0.
  checks_run:
    - swift test --filter SmartMaskTests (10 passed)
    - scripts/ci-tests.sh fast (1,715 tests; exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T21:53:13.973Z
  session: 01MV4CWDT7BI8QZKXV
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:08:33.115Z
updated: 2026-10-24T13:04:47.542Z
blockers: []
order: n
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T21:49:46.163Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

KRMA-852 moved Soften / edge shift / strength in `CoordinatorLocalMaskResolver.resolve` (Sources/KromoraKit/Models/LocalMaskRendering.swift) to run on the matte at its own resolution before the single resize to the target. Nothing asserts that the reorder preserves the result or that the payload size and values remain correct.

## Context

- Softness radius is `edgeFeather * min(mask width, height) * 0.05`, rounded, minimum 1 px, so it is resolution-independent by design. Edge shift and density are per-value affine maps and commute with bilinear resize except at the [0,1] clamp.
- Known difference: the 1 px minimum radius is relatively wider at low Soften; the matte is stretched to the photo's aspect afterwards.

## Acceptance criteria

1. A resolver-level test (fake `PhotoAnalysisCoordinator` or the existing mask test doubles) resolves a semantic definition with non-default softness, shift and strength and asserts the payload `targetSize` equals the request and all values lie in [0,1].
2. A tolerance test compares the new order against resize-then-apply for a smooth matte at 2-3 softness values; document the tolerance and why (and assert it stays within it).
3. Strength 0.5 on a binary matte yields max value 0.5 after resolution; shift +1 saturates coverage; shift -1 empties it.
4. An identity definition (softness 0, shift 0, strength 1) returns the resized matte unchanged and does not allocate the blur path.
5. Runs in the `fast` lane.

Related: KRMA-852, KRMA-847.


### Comment — codex @ 2026-10-11T21:49:45.674Z

Added resolver coverage for matte-resolution adjustment order, the 0.05 tolerance across three softness values, strength/shift limits, and identity feather bypass. Verified SmartMaskTests (10 passed) and scripts/ci-tests.sh fast (1,715 tests passed). Commit: 94147bbb.

## Agent log

- 2026-10-11T21:53:13.973Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Resolver-level semantic resolution with non-default softness, edge shift, and strength reports the requested target size and only finite [0,1] matte values. (pass) — testCoordinatorResolverAppliesSemanticSettingsBeforeResizeAndBoundsPayload passed.
- [x] Compare soften-before-resize with resize-then-soften on a smooth matte at 2-3 softness values, documenting and enforcing tolerance. (pass) — The test documents a 0.05 absolute coverage tolerance for the 1 px minimum radius and integer radius rounding; softness 0.12, 0.5, and 0.9 remained within it.
- [x] Strength 0.5 on a binary matte yields maximum coverage 0.5; edge shift +1 saturates and -1 empties coverage. (pass) — testSemanticStrengthAndExtremeEdgeShiftClampResolvedCoverage passed.
- [x] Identity settings return the resized matte unchanged and bypass the feather allocation path. (pass) — The injected feather closure was not called, and resolver output equaled the resized seed.
- [x] The tests run in the fast lane. (pass) — scripts/ci-tests.sh fast exited 0.
Checks run:
- swift test --filter SmartMaskTests (10 passed)
- scripts/ci-tests.sh fast (1,715 tests; exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV4CWDT7BI8QZKXV
Summary: Verified KRMA-855 acceptance criteria; focused and fast test lanes passed with no findings or verification fixes.
