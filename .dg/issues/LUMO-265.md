---
id: LUMO-265
title: Resample semantic masks with vImage instead of Swift loops
type: task
status: done
priority: high
labels:
  - masking
  - performance
created: 2026-09-07T01:14:45.167Z
updated: 2026-09-08T00:39:37.122Z
order: a0
board: product
commits:
  - 7d8a102
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: refine and resized produce pixel-identical (or stated-tolerance) output vs the prior implementation on the resize/union fixtures
      result: pass
      notes: RegionMaskTests covers the asymmetric resize fixture at a documented 0.2 tolerance (vImage's high-quality kernel is not bit-for-bit bilinear) and single-pixel clamp-to-edge; MaskRefinementTests asserts refine's output equals MaskOperations.resized on the same seed.
    - criterion: Measured wall-time improvement on a >=2MP upscale recorded (debug and release); 60MP case drops to low-single-seconds in debug
      result: pass
      notes: "Commit bf0f79e records 1920x1280: debug 1025.132ms -> 3.161ms (324x), release 18.177ms -> 0.940ms (19x); linear scaling to 60MP stays low-single-digit seconds in debug."
    - criterion: Cancellation during a full-res refine still resolves within one tile/chunk, covered by a test
      result: pass
      notes: refine checks cancellation before the vImage call and again after a Task.yield before the store write (no longer tiled, since it's one vImage call); testCancellationDoesNotPersistAnIncompleteRenderMask exercises this and passes.
    - criterion: swift build, swift test pass with zero Swift 6 diagnostics and zero opt-outs
      result: pass
      notes: "Verified independently: swift build clean (only pre-existing unrelated CIKernel deprecation warnings); swift test 936 executed, 43 skipped, 0 failures."
  checks_run:
    - swift build — clean (pre-existing unrelated CIKernel deprecation warnings only)
    - swift test — 936 executed, 43 skipped, 0 failures
    - swift test --filter 'MaskRefinementTests|RegionMaskTests|MaskResamplingPerformanceTests' — all passed
    - dg validate — OK (pre-existing unrelated runner-model warning)
    - git status --porcelain — clean aside from this issue's changes
  findings:
    - "MaskRefinementService.refine's tileSize parameter survived the switch to a single vImageScale_PlanarF call: it was validated (>0) but never used to chunk work, misleadingly implying cancellation-granularity control that no longer exists. Fixed directly as a localized, no-behavior-change cleanup rather than filed as a follow-up: removed the parameter and the now-dead MaskRefinementError.invalidTileSize case, updated the two test call sites (commit 7d8a102)."
  fixes:
    - Removed the vestigial tileSize parameter and invalidTileSize error case from MaskRefinementService.refine / PhotoAnalysisCoordinator.refineMask; updated MaskRefinementTests call sites accordingly (commit 7d8a102).
  verification_commits:
    - 7d8a102
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-08T00:39:37.114Z
  session: 01MTRXPCVKHAD0N0LV
---

## Objective

Replace the hand-rolled bilinear loops in `MaskRefinementService.refine` and
`MaskOperations.resized` with Accelerate's `vImageScale_PlanarF`. Single biggest compute win
on the person-mask path, with less code, not more.

## Context

Measured in a debug build: upscaling the 768×512 analysis seed to 1920×1280 costs ~0.94s
(includes `NormalizedMask` validation passes); coverage over 2.5M values costs ~0.14s. Scaled
linearly to a 60MP source, one full-resolution resolve burns ~25s in Swift loops alone —
uncached and uncacheable (a 240MB payload can never fit the 64MB `localMaskCache` budget), so
every full-zoom preview, full-res render, and export pays it. Release builds are ~15–30×
faster on such loops, but 1–3s of single-threaded scalar resampling per render is still the
dominant cost, and Accelerate (Apple framework, zero third-party deps — repo rule satisfied)
does this SIMD and multithreaded at roughly 10–50× the throughput.

## Work

- Route both upscale sites through one shared helper (e.g. on `MaskOperations`, next to
  `resized`, keeping the existing seam tests meaningful): planar-Float scale with bilinear
 -equivalent interpolation.
- Keep the exact edge semantics the current code relies on (clamp-to-edge; the resolver's and
  refinement's `max(1, size - 1)` normalization). Any intentional behavior delta must be
  documented and covered by a test.
- Preserve cancellation points: the current `refine` checks cancellation per tile. Chunk the
  vImage work (or check between seed-fetch, scale, and store) so a superseded render still
  dies fast — vImage calls themselves are not cancellable mid-flight.
- No API changes for callers; `MaskOperations.resized` keeps its signature where feasible.

## Acceptance criteria

- [ ] `refine` and `resized` produce pixel-identical (or stated-tolerance) output vs the
      current implementation on the existing resize/union test fixtures.
- [ ] Measured wall-time improvement on a ≥2MP upscale recorded in the ticket (debug and
      release); the 60MP case must drop from tens-of-seconds to low-single-seconds in debug.
- [ ] Cancellation during a full-res refine still resolves within one tile/chunk, covered by a
      test.
- [ ] `swift build`, `swift test` pass with zero Swift 6 diagnostics and zero opt-outs.


### Comment — codex @ 2026-09-08T00:31:25.663Z

Implemented in commit bf0f79e: MaskOperations now uses one Accelerate vImageScale_PlanarF + vDSP clip PlanarF helper, MaskRefinementService routes through it with cancellation checks around scale/store, and Package.swift links Accelerate. Added resize/refinement parity, clamp-to-edge, cancellation, and opt-in paired performance coverage. Verification: swift build passed; swift test passed (936 tests, 43 skips, 0 failures); dg validate passed. Benchmarked 1920x1280 on this Apple-silicon host: Debug scalar 1025.132 ms vs PlanarF 3.161 ms (324.31x); Release scalar 18.177 ms vs PlanarF 0.940 ms (19.33x). Existing unrelated Swift/Core Image deprecation and test warnings remain.

## Agent log

- 2026-09-08T00:39:37.120Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] refine and resized produce pixel-identical (or stated-tolerance) output vs the prior implementation on the resize/union fixtures (pass) — RegionMaskTests covers the asymmetric resize fixture at a documented 0.2 tolerance (vImage's high-quality kernel is not bit-for-bit bilinear) and single-pixel clamp-to-edge; MaskRefinementTests asserts refine's output equals MaskOperations.resized on the same seed.
- [x] Measured wall-time improvement on a >=2MP upscale recorded (debug and release); 60MP case drops to low-single-seconds in debug (pass) — Commit bf0f79e records 1920x1280: debug 1025.132ms -> 3.161ms (324x), release 18.177ms -> 0.940ms (19x); linear scaling to 60MP stays low-single-digit seconds in debug.
- [x] Cancellation during a full-res refine still resolves within one tile/chunk, covered by a test (pass) — refine checks cancellation before the vImage call and again after a Task.yield before the store write (no longer tiled, since it's one vImage call); testCancellationDoesNotPersistAnIncompleteRenderMask exercises this and passes.
- [x] swift build, swift test pass with zero Swift 6 diagnostics and zero opt-outs (pass) — Verified independently: swift build clean (only pre-existing unrelated CIKernel deprecation warnings); swift test 936 executed, 43 skipped, 0 failures.
Checks run:
- swift build — clean (pre-existing unrelated CIKernel deprecation warnings only)
- swift test — 936 executed, 43 skipped, 0 failures
- swift test --filter 'MaskRefinementTests|RegionMaskTests|MaskResamplingPerformanceTests' — all passed
- dg validate — OK (pre-existing unrelated runner-model warning)
- git status --porcelain — clean aside from this issue's changes
Findings:
- MaskRefinementService.refine's tileSize parameter survived the switch to a single vImageScale_PlanarF call: it was validated (>0) but never used to chunk work, misleadingly implying cancellation-granularity control that no longer exists. Fixed directly as a localized, no-behavior-change cleanup rather than filed as a follow-up: removed the parameter and the now-dead MaskRefinementError.invalidTileSize case, updated the two test call sites (commit 7d8a102).
Fixes:
- Removed the vestigial tileSize parameter and invalidTileSize error case from MaskRefinementService.refine / PhotoAnalysisCoordinator.refineMask; updated MaskRefinementTests call sites accordingly (commit 7d8a102).
Verification commits:
- 7d8a102
Actor: claude
Resolved model: sonnet
Pickup session: 01MTRXPCVKHAD0N0LV
Summary: Verified LUMO-265: Accelerate vImage resample matches prior bilinear behavior within stated tolerance, cancellation still resolves promptly, benchmarks confirm the speedup, full suite green. Removed a vestigial tileSize parameter left over from the old tiled loop as a localized cleanup.
