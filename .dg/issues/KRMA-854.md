---
id: KRMA-854
title: Add unit tests for MaskOperations.feather (reference equivalence, edges, cancellation)
type: task
status: done
priority: low
agent: codex
verification_agent: codex
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Test-only naive reference matches feather within 1e-5 for seeded 37x23 masks at radii 1, 2, 5, oversized radius, 1xN/Nx1 masks, and all-zero/all-one masks.
      result: pass
    - criterion: A hard-edged half-plane blurs to about 0.5 at the original edge and spreads r pixels on both sides.
      result: pass
    - criterion: coverage equals the output mean; isBinary is false after a non-trivial blur and true for radius zero on a binary mask.
      result: pass
    - criterion: An immediately cancelled feather task on a large mask throws CancellationError before completing the blur.
      result: pass
    - criterion: Tests are deterministic and run in the fast lane.
      result: pass
  checks_run:
    - scripts/ci-tests.sh fast — passed (1717 tests; exit status 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-12T01:52:21.356Z
  session: 01MV4LGOLPIQSW1W0V
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:08:32.151Z
updated: 2026-10-12T01:52:21.359Z
depends_on:
  - KRMA-847
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-12T01:49:30.854Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

`MaskOperations.feather` (Sources/KromoraKit/Models/PhotoAnalysis/MaskOperations.swift) has no direct unit tests. KRMA-847 replaced its O(pixels x r^2) window scan with a separable running-sum blur and verified it only through existing mask tests. Pin its behavior so a future optimisation cannot silently change soften output.

## Context

- Contract: each output pixel is the mean of the in-bounds samples in the (2r+1) x (2r+1) window clipped to the mask edges (denominator is the actual in-bounds count, not (2r+1)^2).
- Output must populate `coverage` and `isBinary` consistently with `NormalizedMask.init(size:values:)`.
- `Task.checkCancellation()` runs every 64 rows in both passes.

## Acceptance criteria

1. A test-only naive reference implementation (the pre-KRMA-847 loop) lives in the test target and the optimised result matches it within 1e-5 per pixel for: a random 37x23 mask at radii 1, 2, 5; a radius larger than both dimensions; a 1xN and an Nx1 mask; an all-zero and an all-one mask.
2. A hard-edged half-plane mask blurred at radius r reads about 0.5 on the original edge and spreads r pixels each way (inside and outside).
3. `coverage` equals the mean of the output values and `isBinary` is false after a non-trivial blur, true for radius 0 on a binary mask.
4. A cancellation test: a task running feather on a large mask (for example 4000x3000) and cancelled immediately throws `CancellationError` well before completing.
5. Tests are deterministic (seeded generator) and run in the `fast` lane.

Related: KRMA-847.


### Comment — claude @ 2026-10-11T13:11:12.586Z

Scope trimmed (2026-10-11): RegionMaskTests already has clipped-window reference equivalence, cancellation, and coverage/isBinary checks. Remaining: 1xN and Nx1 masks, radius larger than the mask, half-plane edge test, isBinary at radius 0.


### Comment — codex @ 2026-10-12T01:49:29.154Z

Added seeded naive-reference comparisons for random, degenerate, constant, and oversized-radius masks; added half-plane edge-spread and radius-zero metadata checks; expanded cancellation coverage to 4000x3000. Verification: scripts/ci-tests.sh fast passed (1717 tests). Commit: 24f18732.

## Agent log

- 2026-10-12T01:52:21.356Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Test-only naive reference matches feather within 1e-5 for seeded 37x23 masks at radii 1, 2, 5, oversized radius, 1xN/Nx1 masks, and all-zero/all-one masks. (pass)
- [x] A hard-edged half-plane blurs to about 0.5 at the original edge and spreads r pixels on both sides. (pass)
- [x] coverage equals the output mean; isBinary is false after a non-trivial blur and true for radius zero on a binary mask. (pass)
- [x] An immediately cancelled feather task on a large mask throws CancellationError before completing the blur. (pass)
- [x] Tests are deterministic and run in the fast lane. (pass)
Checks run:
- scripts/ci-tests.sh fast — passed (1717 tests; exit status 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV4LGOLPIQSW1W0V
Summary: Independent verification passed: feather behavior tests cover deterministic reference equivalence, edge spread, metadata, and cancellation; fast lane passed.
