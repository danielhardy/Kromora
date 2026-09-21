---
id: KRMA-396
title: "Phase 0.3: packed-thumbnail-by-shard prototype and decision"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Packed-by-shard prototype compares current per-file thumbnails at 1,000, 10,000, and 100,000 assets across cold scan, file count, lookup, regeneration, and compaction
      result: pass
      notes: Opt-in benchmark exercised all three scales and emitted the committed comparison table in docs/LIBRARY_PACKAGE_BASELINE.md.
    - criterion: Stale, missing, duplicate, lookup, and compaction cases have deterministic correctness tests
      result: pass
      notes: PackedThumbnailPrototypeTests covers missing/deleted keys, duplicate replacement, injected stale offsets, bounded lookup reads, compaction reclamation, and no dangling offsets.
    - criterion: Written packed/rejected recommendation with measured deciding metrics is committed to documentation
      result: pass
      notes: Documentation recommends packed-by-shard at the 100,000-asset target, with low-priority compaction, and records one-sample Debug measurements for all scales.
    - criterion: Prototype is isolated from shipping code and does not alter current thumbnail generation, deletion, or import behavior
      result: pass
      notes: Implementation exists only under Tests/KromoraKitTests/Support; benchmark wiring is test-lane-only and scripts/ci-tests.sh optional classification was updated.
    - criterion: swift build, swift test, benchmark lane, dg validate, and git diff --check pass
      result: pass
      notes: swift build passed; full swift test passed with 1,353 tests, 52 expected skips, and 0 failures; fast lane passed 933 tests; optional lane passed 49 tests with 48 expected skips and the all-scale benchmark enabled; dg validate and git diff --check passed.
  checks_run:
    - swift build
    - swift test
    - swift test --filter PackedThumbnailPrototypeTests
    - KROMORA_PACKED_THUMBNAIL_BENCHMARK=1 swift test --no-parallel --filter PackedThumbnailPerformanceTests/testPackedByShardComparisonAtAllSupportedScales
    - KROMORA_PACKED_THUMBNAIL_BENCHMARK=1 scripts/ci-tests.sh optional
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh verify
    - dg validate
    - git diff --check
  findings:
    - At 100,000 assets packed storage reduced files from 100,000 to 257, cold scan from 387.16 ms to 228.88 ms, and flagged-subset regeneration from 14.08 s to 3.11 s; lookup was 64.20 microseconds per-file versus 71.18 microseconds packed.
    - Packed compaction is materially more expensive (8.08 s at 100,000 assets versus 0.46 s for per-file deletion/scan), so the documentation requires it to remain cancellable, serialized, and low priority.
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-12T21:16:32.485Z
  session: 01MTYV9T16GBVMMNXG
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - performance
  - benchmark
created: 2026-09-12T19:44:10.865Z
updated: 2026-09-12T21:16:32.487Z
depends_on:
  - KRMA-394
order: zz
board: product
---

## Objective

Prototype packed (shard-based) thumbnail storage against the current one-file-per-asset layout and
produce a measured, written recommendation (packed or rejected) that later phases (KRMA-391/392) can
follow without re-litigating the question.

## Dependencies

- The synthetic-library generator ticket (reuses it to produce thumbnail-demand data at scale).

## Scope

- Build a standalone prototype (test-lane code, not shipped product code) of packed thumbnails
  stored by shard — i.e. many thumbnails concatenated into a small number of files with an
  offset/index, versus the current per-asset thumbnail file.
- Compare, at 1,000 / 10,000 / 100,000 synthetic assets: cold scan time, on-disk file count, lookup
  cost (single-thumbnail fetch latency), regeneration cost (rebuilding a subset), and compaction
  behavior (reclaiming space after stale/deleted entries) between packed and current layouts.
- Cover the edge cases explicitly: stale entries, missing entries, duplicate entries, lookup of a
  non-existent key, and compaction correctness (no data loss, no dangling offsets) for the packed
  format.
- Write the recommendation and the measured numbers into the testing/performance documentation
  (same location as the baseline ticket) so KRMA-391/392 can cite it directly.
- Prototype code must not be imported by or wired into any shipping code path, and must not alter
  current thumbnail generation, deletion, or import behavior.

## Acceptance criteria

- [ ] The prototype exercises packed-by-shard storage with a measured comparison against current
  per-file thumbnails across all listed metrics and all three scale sizes.
- [ ] Stale, missing, duplicate, lookup, and compaction cases have deterministic unit tests with
  correctness assertions (not just timing).
- [ ] A written recommendation (packed or rejected, with the deciding metric(s)) is committed to
  documentation, citable by later phases.
- [ ] The prototype is isolated from shipping code — no changes to current thumbnail generation,
  deletion, or import behavior.
- [ ] `swift build`, `swift test`, the benchmark lane, `dg validate`, and `git diff --check` pass.

## Verification lane

Performance/benchmark lane for scale comparisons; deterministic unit tests for offset/index
correctness (stale/missing/duplicate/lookup/compaction). Review the recommendation before KRMA-389
is considered complete.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/AUTO_PERFORMANCE.md, docs/TESTING.md
- context.issues: KRMA-389

## Agent log

- 2026-09-12T21:16:32.485Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Packed-by-shard prototype compares current per-file thumbnails at 1,000, 10,000, and 100,000 assets across cold scan, file count, lookup, regeneration, and compaction (pass) — Opt-in benchmark exercised all three scales and emitted the committed comparison table in docs/LIBRARY_PACKAGE_BASELINE.md.
- [x] Stale, missing, duplicate, lookup, and compaction cases have deterministic correctness tests (pass) — PackedThumbnailPrototypeTests covers missing/deleted keys, duplicate replacement, injected stale offsets, bounded lookup reads, compaction reclamation, and no dangling offsets.
- [x] Written packed/rejected recommendation with measured deciding metrics is committed to documentation (pass) — Documentation recommends packed-by-shard at the 100,000-asset target, with low-priority compaction, and records one-sample Debug measurements for all scales.
- [x] Prototype is isolated from shipping code and does not alter current thumbnail generation, deletion, or import behavior (pass) — Implementation exists only under Tests/KromoraKitTests/Support; benchmark wiring is test-lane-only and scripts/ci-tests.sh optional classification was updated.
- [x] swift build, swift test, benchmark lane, dg validate, and git diff --check pass (pass) — swift build passed; full swift test passed with 1,353 tests, 52 expected skips, and 0 failures; fast lane passed 933 tests; optional lane passed 49 tests with 48 expected skips and the all-scale benchmark enabled; dg validate and git diff --check passed.
Checks run:
- swift build
- swift test
- swift test --filter PackedThumbnailPrototypeTests
- KROMORA_PACKED_THUMBNAIL_BENCHMARK=1 swift test --no-parallel --filter PackedThumbnailPerformanceTests/testPackedByShardComparisonAtAllSupportedScales
- KROMORA_PACKED_THUMBNAIL_BENCHMARK=1 scripts/ci-tests.sh optional
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh verify
- dg validate
- git diff --check
Findings:
- At 100,000 assets packed storage reduced files from 100,000 to 257, cold scan from 387.16 ms to 228.88 ms, and flagged-subset regeneration from 14.08 s to 3.11 s; lookup was 64.20 microseconds per-file versus 71.18 microseconds packed.
- Packed compaction is materially more expensive (8.08 s at 100,000 assets versus 0.46 s for per-file deletion/scan), so the documentation requires it to remain cancellable, serialized, and low priority.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTYV9T16GBVMMNXG
Summary: Implemented isolated packed-thumbnail-by-shard prototype, deterministic edge-case tests, all-scale benchmark, and documented packed recommendation.
