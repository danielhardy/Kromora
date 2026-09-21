---
id: KRMA-389
title: "Phase 0: establish library scale baseline and thumbnail packing decision"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Deterministic, cancellable synthetic libraries cover 1,000, 10,000, and 100,000 assets without repository fixtures
      result: pass
      notes: Existing committed SyntheticLibraryGenerator supports seeded metadata/edit summaries/thumbnail demand, cooperative cancellation, partial-root cleanup, and optional all-scale generation.
    - criterion: Folder-backed baseline records required metrics, p95/p99.9 definitions, environment, and sample counts
      result: pass
      notes: Existing committed LibraryFolderBaselinePerformanceTests and docs/LIBRARY_PACKAGE_BASELINE.md record warm launch, first page, filtering, scrolling, memory, decoded thumbnails, and interactive preview submission with nearest-rank p95/p99.9 methodology and environment/sample metadata.
    - criterion: Packed-thumbnail prototype measures a recommendation and covers stale, missing, duplicate, lookup, and compaction cases
      result: pass
      notes: PackedThumbnailPrototypeTests covers missing/deleted keys, duplicate replacement, stale offsets, bounded indexed reads, compaction reclamation, and live-entry integrity; the all-scale benchmark measured current per-file versus packed-by-shard at 1k/10k/100k and the documentation recommends packed storage with low-priority compaction.
    - criterion: Artifacts remain isolated from product behavior and are runnable in the optional benchmark lane
      result: pass
      notes: Prototype code is test-target-only; optional CI classification includes PackedThumbnailPerformanceTests and no shipping source or library-data path was changed.
    - criterion: Required verification passes
      result: pass
      notes: "swift test --no-parallel: 1,353 passed/52 expected skips; focused prototype tests: 8 passed; all-scale packed benchmark: passed; scripts/ci-tests.sh fast: 933 passed; scripts/ci-tests.sh verify: passed; dg validate: OK with pre-existing unknown-model warnings; git diff --check: passed."
  checks_run:
    - swift test --no-parallel
    - swift test --no-parallel --filter SyntheticLibraryGeneratorTests|PackedThumbnailPrototypeTests
    - KROMORA_PACKED_THUMBNAIL_BENCHMARK=1 swift test --no-parallel --filter PackedThumbnailPerformanceTests/testPackedByShardComparisonAtAllSupportedScales
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh verify
    - dg validate
    - git diff --check
  findings:
    - At 100,000 assets, the fresh run reduced thumbnail files from 100,000 to 257, cold scan from 388.59 ms to 221.38 ms, and flagged-subset regeneration from 13.70 s to 3.14 s; packed lookup measured 66.83 microseconds versus 64.16 microseconds per-file.
    - Packed compaction measured 8.08 s at 100,000 assets versus 0.49 s for the per-file comparator, so the documented recommendation keeps compaction cancellable, serialized, and low priority.
  fixes: []
  verification_commits:
    - 10ef3b0
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-12T21:24:31.354Z
  session: 01MTYVY605LEIR02NG
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - library
  - architecture
  - performance
  - benchmark
created: 2026-09-12T19:19:10.270Z
updated: 2026-09-12T21:24:31.356Z
depends_on:
  - KRMA-394
  - KRMA-395
  - KRMA-396
order: a0
board: product
commits:
  - 10ef3b0
---

## Objective

Produce the reusable scale-test harness and committed pre-package baseline required before any
identity or persistence rewrite. This phase is a throwaway/spike lane; it must not change product
behavior or migrate current library data.

## Scope

- Generate deterministic synthetic libraries at 1,000, 10,000, and 100,000 assets with plausible
  metadata, edit summaries, and thumbnail demand.
- Capture the current folder-backed library baseline for warm launch, first-page delivery, filtering,
  scrolling, memory, decoded-thumbnail count, and interactive preview submission latency.
- Prototype packed thumbnails by shard and compare cold scan, file count, lookup cost, regeneration,
  and compaction behavior with the current one-file-per-asset shape.
- Record the decision and baseline numbers in the testing/performance documentation so later phases
  cannot move the goalposts.

## Acceptance criteria

- [ ] The generator is deterministic, cancellable, and produces all three scale sizes without
  committing photo or thumbnail fixtures to the repository.
- [ ] Baseline measurements include the hard invariants and the p95/p99.9 latency definitions from
  `docs/LIBRARY_PACKAGE_PLAN.md` §8.1–8.2, with environment and sample counts recorded.
- [ ] The thumbnail prototype has a measured recommendation (packed or rejected) and covers stale,
  missing, duplicate, lookup, and compaction cases.
- [ ] The committed artifacts are runnable in CI/optional benchmark lanes and do not import package
  APIs or alter current deletion, edit persistence, or import behavior.
- [ ] `swift test`, the applicable benchmark lane, `dg validate`, and `git diff --check` pass.

## Verification lane

Performance/benchmark lane, with deterministic unit tests for generation and packed-thumbnail
offset/index behavior. Review the committed baseline before Phase 1 starts.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-12T21:24:31.354Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Deterministic, cancellable synthetic libraries cover 1,000, 10,000, and 100,000 assets without repository fixtures (pass) — Existing committed SyntheticLibraryGenerator supports seeded metadata/edit summaries/thumbnail demand, cooperative cancellation, partial-root cleanup, and optional all-scale generation.
- [x] Folder-backed baseline records required metrics, p95/p99.9 definitions, environment, and sample counts (pass) — Existing committed LibraryFolderBaselinePerformanceTests and docs/LIBRARY_PACKAGE_BASELINE.md record warm launch, first page, filtering, scrolling, memory, decoded thumbnails, and interactive preview submission with nearest-rank p95/p99.9 methodology and environment/sample metadata.
- [x] Packed-thumbnail prototype measures a recommendation and covers stale, missing, duplicate, lookup, and compaction cases (pass) — PackedThumbnailPrototypeTests covers missing/deleted keys, duplicate replacement, stale offsets, bounded indexed reads, compaction reclamation, and live-entry integrity; the all-scale benchmark measured current per-file versus packed-by-shard at 1k/10k/100k and the documentation recommends packed storage with low-priority compaction.
- [x] Artifacts remain isolated from product behavior and are runnable in the optional benchmark lane (pass) — Prototype code is test-target-only; optional CI classification includes PackedThumbnailPerformanceTests and no shipping source or library-data path was changed.
- [x] Required verification passes (pass) — swift test --no-parallel: 1,353 passed/52 expected skips; focused prototype tests: 8 passed; all-scale packed benchmark: passed; scripts/ci-tests.sh fast: 933 passed; scripts/ci-tests.sh verify: passed; dg validate: OK with pre-existing unknown-model warnings; git diff --check: passed.
Checks run:
- swift test --no-parallel
- swift test --no-parallel --filter SyntheticLibraryGeneratorTests|PackedThumbnailPrototypeTests
- KROMORA_PACKED_THUMBNAIL_BENCHMARK=1 swift test --no-parallel --filter PackedThumbnailPerformanceTests/testPackedByShardComparisonAtAllSupportedScales
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh verify
- dg validate
- git diff --check
Findings:
- At 100,000 assets, the fresh run reduced thumbnail files from 100,000 to 257, cold scan from 388.59 ms to 221.38 ms, and flagged-subset regeneration from 13.70 s to 3.14 s; packed lookup measured 66.83 microseconds versus 64.16 microseconds per-file.
- Packed compaction measured 8.08 s at 100,000 assets versus 0.49 s for the per-file comparator, so the documented recommendation keeps compaction cancellable, serialized, and low priority.
Fixes:
- None
Verification commits:
- 10ef3b0
Actor: codex
Resolved model: unknown
Pickup session: 01MTYVY605LEIR02NG
Summary: Implemented the isolated packed-thumbnail-by-shard prototype, deterministic edge-case coverage, all-scale benchmark, and measured package-format recommendation; generator and folder-backed baseline are included from the completed Phase 0 dependencies.
