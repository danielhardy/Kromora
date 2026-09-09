---
id: LUMO-267
title: Fuse validation and coverage into mask generation
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Full-resolve path performs at most one post-generation pass over the values (the coverage accumulation, if not folded into generation).
      result: pass
      notes: MaskOperations.scaleValuesAndCoverage (used by resized/refine, the full-resolution path exercised by MaskRefinementService.refine) clips and accumulates coverage and isBinary inline in the single post-vImage buffer walk. MaskOperations.feather likewise folds coverage/isBinary into its one generation loop. No stray .reduce/.allSatisfy remains on these paths; NormalizedMask(trustingSize:...) accepts precomputed coverage/isBinary and skips recomputation.
    - criterion: I/O boundaries (store loads, provider buffers) still go through the validating initializer, covered by existing tests, plus a test that the unchecked path traps on a count mismatch in debug.
      result: pass
      notes: "MaskStore.pixels(for:) and NormalizedMask(from decoder:) still call the validating NormalizedMask(size:values:) init. VisionSemanticMaskProvider's rectangularMask uses the trusted path with isBinary: true, which is provably correct since values are only ever set to exactly 0 or 1. RegionMaskTests.testTrustedMaskPreconditionRejectsCountMismatch spawns a subprocess (xcrun xctest) to verify the trusted initializer's precondition traps on a count mismatch in DEBUG; verified it reproduces the trap."
    - criterion: Measured improvement recorded alongside LUMO-265's numbers.
      result: pass
      notes: "Comment on the issue records opt-in 1920x1280 benchmark: Debug scalar 898.556 ms vs fused PlanarF 342.455 ms (2.62x); Release scalar 16.841 ms vs fused PlanarF 5.329 ms (3.16x)."
  checks_run:
    - swift build (clean)
    - swift test --filter 'RegionMaskTests|MaskRefinementTests|VisionSemanticMaskProviderTests' (23 passed, 0 failed)
    - scripts/ci-tests.sh fast (revealed 1 pre-existing unrelated failure, see findings)
    - "Bisected LUTWorkflowTests failure across the branch tail in a throwaway worktree (scripts/agent-worktree.sh): passes at 88e6008, 382d71b (LUMO-267 commit 1), 0fed205 (LUMO-267 commit 2, under verification), 7818f95, 2d4d7b6; fails at current HEAD bca796a — confirms LUMO-267 is not the cause"
    - Manual review of RegionMask.swift, MaskOperations.swift, VisionSemanticMaskProvider.swift, MaskStore.swift, MaskRefinement.swift for correctness of the fused coverage/isBinary accumulation and preservation of the validating I/O boundary
    - git status --porcelain (clean aside from pre-existing untracked .dg bookkeeping)
  findings:
    - "LUMO-318 (backlog child, verification label, parent LUMO-267): swift test fails deterministically on LUTWorkflowTests.testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest (XCTAssertGreaterThan: 3 is not > 3). Bisected in a throwaway worktree: passes at 88e6008, 382d71b (LUMO-267 commit 1), 0fed205 (LUMO-267 commit 2, the commit under verification), 7818f95, 2d4d7b6; fails at current HEAD bca796a. Introduced by LUMO-308 or LUMO-315, not LUMO-267 — not fixed here, out of scope."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-09T13:47:21.097Z
  session: 01MTU5D6R1L6840D5F
labels:
  - masking
  - performance
created: 2026-09-07T01:14:46.343Z
updated: 2026-09-09T13:47:21.099Z
order: a0
board: product
---

## Objective

Stop walking every full-resolution mask three extra times after generating it.
`NormalizedMask.init` runs `allSatisfy(isFinite)` plus a clamping `map`, and `coverage` runs a
`reduce` — three full passes over up to 60M values per resolve, on top of the compute pass.
Measured: the coverage pass alone costs ~0.14s per 2.5M values in debug (~3.5s at 60MP).

## Context

For internally generated masks the validation is provable dead weight: bilinear interpolation
of finite `[0, 1]` inputs with weights in `[0, 1]` is finite and stays in `[0, 1]`. We pay
for a guarantee the producer already provides. (External inputs — decoded files, provider
buffers — must keep full validation; the sidecar/legacy loads in `MaskStore` stay as-is.)

## Work

- Add an unchecked (or trust-but-verify-in-debug) construction path for masks produced by our
  own resampling, e.g. `NormalizedMask(trustingSize:values:)` with a `precondition` on count,
  used by `refine` and `resized`. Keep the validating initializer for all I/O boundaries.
- Compute `coverage` inline in the generation loop (running sum) instead of a separate
  `reduce`, threading it through to the returned `RegionMask` where the call sites currently
  recompute it.
- Pairs naturally with LUMO-265 (vImage): if vImage lands first, coverage-summing needs a
  home — either a vImage histogram/mean pass or a single Swift accumulation over the scaled
  buffer (one pass, not three).

## Acceptance criteria

- [ ] Full-resolve path performs at most one post-generation pass over the values (the
      coverage accumulation, if not folded into generation).
- [ ] I/O boundaries (store loads, provider buffers) still go through the validating
      initializer — covered by existing tests, plus a test that the unchecked path traps on a
      count mismatch in debug.
- [ ] Measured improvement recorded alongside LUMO-265's numbers.


### Comment — codex @ 2026-09-09T13:41:28.568Z

Implemented in commit 0fed205: added the trusted NormalizedMask construction path with a count precondition, fused coverage and binary metadata accumulation into the single post-vImage walk used by resized/refine, and kept validating construction for decoded/store/provider-buffer I/O. Added regression coverage for validating payloads and the DEBUG count-mismatch trap. Verification: focused RegionMaskTests, MaskRefinementTests, and VisionSemanticMaskProviderTests — 22 passed; swift build — passed; dg validate — OK (pre-existing unknown pickup-runner warning); git diff --check — passed. Opt-in 1920x1280 benchmark after fusion: Debug scalar 898.556 ms vs fused PlanarF 342.455 ms (2.62x); Release scalar 16.841 ms vs fused PlanarF 5.329 ms (3.16x). LUMO-265 baseline remains recorded separately.

## Agent log

- 2026-09-09T13:47:21.097Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Full-resolve path performs at most one post-generation pass over the values (the coverage accumulation, if not folded into generation). (pass) — MaskOperations.scaleValuesAndCoverage (used by resized/refine, the full-resolution path exercised by MaskRefinementService.refine) clips and accumulates coverage and isBinary inline in the single post-vImage buffer walk. MaskOperations.feather likewise folds coverage/isBinary into its one generation loop. No stray .reduce/.allSatisfy remains on these paths; NormalizedMask(trustingSize:...) accepts precomputed coverage/isBinary and skips recomputation.
- [x] I/O boundaries (store loads, provider buffers) still go through the validating initializer, covered by existing tests, plus a test that the unchecked path traps on a count mismatch in debug. (pass) — MaskStore.pixels(for:) and NormalizedMask(from decoder:) still call the validating NormalizedMask(size:values:) init. VisionSemanticMaskProvider's rectangularMask uses the trusted path with isBinary: true, which is provably correct since values are only ever set to exactly 0 or 1. RegionMaskTests.testTrustedMaskPreconditionRejectsCountMismatch spawns a subprocess (xcrun xctest) to verify the trusted initializer's precondition traps on a count mismatch in DEBUG; verified it reproduces the trap.
- [x] Measured improvement recorded alongside LUMO-265's numbers. (pass) — Comment on the issue records opt-in 1920x1280 benchmark: Debug scalar 898.556 ms vs fused PlanarF 342.455 ms (2.62x); Release scalar 16.841 ms vs fused PlanarF 5.329 ms (3.16x).
Checks run:
- swift build (clean)
- swift test --filter 'RegionMaskTests|MaskRefinementTests|VisionSemanticMaskProviderTests' (23 passed, 0 failed)
- scripts/ci-tests.sh fast (revealed 1 pre-existing unrelated failure, see findings)
- Bisected LUTWorkflowTests failure across the branch tail in a throwaway worktree (scripts/agent-worktree.sh): passes at 88e6008, 382d71b (LUMO-267 commit 1), 0fed205 (LUMO-267 commit 2, under verification), 7818f95, 2d4d7b6; fails at current HEAD bca796a — confirms LUMO-267 is not the cause
- Manual review of RegionMask.swift, MaskOperations.swift, VisionSemanticMaskProvider.swift, MaskStore.swift, MaskRefinement.swift for correctness of the fused coverage/isBinary accumulation and preservation of the validating I/O boundary
- git status --porcelain (clean aside from pre-existing untracked .dg bookkeeping)
Findings:
- LUMO-318 (backlog child, verification label, parent LUMO-267): swift test fails deterministically on LUTWorkflowTests.testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest (XCTAssertGreaterThan: 3 is not > 3). Bisected in a throwaway worktree: passes at 88e6008, 382d71b (LUMO-267 commit 1), 0fed205 (LUMO-267 commit 2, the commit under verification), 7818f95, 2d4d7b6; fails at current HEAD bca796a. Introduced by LUMO-308 or LUMO-315, not LUMO-267 — not fixed here, out of scope.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTU5D6R1L6840D5F
Summary: Verified: fused coverage/isBinary accumulation is correct and covers the full-resolve path (resized/refine/feather); validating init still gates all I/O boundaries; DEBUG precondition trap test confirmed. Found one unrelated pre-existing test regression (LUTWorkflowTests) introduced by LUMO-308/LUMO-315, bisected away from LUMO-267, filed as LUMO-318.
