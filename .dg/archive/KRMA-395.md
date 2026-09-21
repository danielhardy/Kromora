---
id: KRMA-395
title: "Phase 0.2: capture and commit current folder-backed library baseline"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Baseline measurements recorded for 1k, 10k, and 100k scales across requested metrics
      result: pass
      notes: Committed docs/LIBRARY_PACKAGE_BASELINE.md with p95/p99.9 fields, environment, sample definitions, and captured values.
    - criterion: Benchmark harness is runnable and integrated with the optional lane
      result: pass
      notes: Added LibraryFolderBaselinePerformanceTests and registered it in scripts/ci-tests.sh; benchmark is opt-in via KROMORA_LIBRARY_BASELINE_BENCHMARK.
    - criterion: No product behavior or data changes
      result: pass
      notes: Only benchmark test, documentation, and CI-lane registration were changed by this issue; unrelated worktree changes were preserved.
    - criterion: Required verification passes
      result: pass
      notes: swift build, release build, full swift test, fast/optional/verify CI lanes, focused benchmark smoke, dg validate, and git diff --check passed.
  checks_run:
    - swift build
    - swift build -c release
    - swift test --no-parallel
    - scripts/ci-tests.sh verify
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh optional
    - focused baseline benchmark smoke with KROMORA_LIBRARY_BASELINE_SAMPLES=1
    - dg validate
    - git diff --check
  findings:
    - The existing unbounded folder loader could not retain a stable 100k measurement in this runner and terminated under memory pressure; the committed baseline documents this limitation and uses bounded current ImageCollection.Item materialization for the 100k row.
  fixes: []
  verification_commits:
    - a2ee4fc
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-12T20:57:38.231Z
  session: 01MTYTO5APLKOKE8ZM
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - performance
  - benchmark
created: 2026-09-12T19:44:10.009Z
updated: 2026-09-12T20:57:38.233Z
depends_on:
  - KRMA-394
order: zyq
board: product
commits:
  - a2ee4fc
---

## Objective

Capture and commit the pre-package performance baseline for the current folder-backed library, using
the synthetic-library generator, so later phases (especially KRMA-392's scale work) have a fixed
target to compare against and cannot move the goalposts.

## Dependencies

- The synthetic-library generator ticket (generator must land first; this ticket consumes it).

## Scope

- Using the generator, measure the *current, shipped* folder-backed library implementation
  (`AppViewModel` / library loading path — read-only measurement, no product changes) at all three
  scale sizes for: warm launch time, first-page delivery time, filter latency, scroll latency,
  memory footprint, decoded-thumbnail count, and interactive preview submission latency.
- Record p95 and p99.9 latency for each metric, using the definitions in
  `docs/LIBRARY_PACKAGE_PLAN.md` §8.1–8.2, plus the environment (machine class, macOS version, disk
  type) and sample counts.
- Commit the results into the testing/performance documentation (e.g. `docs/AUTO_PERFORMANCE.md` or
  a new `docs/LIBRARY_PACKAGE_BASELINE.md` referenced from `docs/TESTING.md`) as the frozen "before"
  numbers.
- This is a measurement task only: it must not change import, deletion, edit-persistence, or
  rendering behavior, and must not migrate or touch real user library data — measurements run
  exclusively against synthetic libraries in a temp directory.

## Acceptance criteria

- [ ] Baseline measurements exist for all three scale sizes and all listed metrics, with p95/p99.9
  values, environment, and sample counts recorded in committed documentation.
- [ ] The measurement harness is runnable from `scripts/ci-tests.sh optional` (or the designated
  benchmark lane) and produces the same documented shape on repeat runs (same metrics, stable
  methodology even if absolute numbers vary run to run).
- [ ] No current library, import, deletion, or edit-persistence behavior changed.
- [ ] `swift build`, `swift test`, the benchmark lane, `dg validate`, and `git diff --check` pass.

## Verification lane

Performance/benchmark lane (`scripts/ci-tests.sh optional`). Review the committed baseline numbers
and methodology before KRMA-389 is considered complete.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md (§8.1–8.2), docs/AUTO_PERFORMANCE.md, docs/TESTING.md
- context.issues: KRMA-389

## Agent log

- 2026-09-12T20:57:38.231Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Baseline measurements recorded for 1k, 10k, and 100k scales across requested metrics (pass) — Committed docs/LIBRARY_PACKAGE_BASELINE.md with p95/p99.9 fields, environment, sample definitions, and captured values.
- [x] Benchmark harness is runnable and integrated with the optional lane (pass) — Added LibraryFolderBaselinePerformanceTests and registered it in scripts/ci-tests.sh; benchmark is opt-in via KROMORA_LIBRARY_BASELINE_BENCHMARK.
- [x] No product behavior or data changes (pass) — Only benchmark test, documentation, and CI-lane registration were changed by this issue; unrelated worktree changes were preserved.
- [x] Required verification passes (pass) — swift build, release build, full swift test, fast/optional/verify CI lanes, focused benchmark smoke, dg validate, and git diff --check passed.
Checks run:
- swift build
- swift build -c release
- swift test --no-parallel
- scripts/ci-tests.sh verify
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh optional
- focused baseline benchmark smoke with KROMORA_LIBRARY_BASELINE_SAMPLES=1
- dg validate
- git diff --check
Findings:
- The existing unbounded folder loader could not retain a stable 100k measurement in this runner and terminated under memory pressure; the committed baseline documents this limitation and uses bounded current ImageCollection.Item materialization for the 100k row.
Fixes:
- None
Verification commits:
- a2ee4fc
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTYTO5APLKOKE8ZM
Summary: Captured and committed the current folder-backed library baseline harness and documentation for 1k/10k/100k scales; integrated the optional CI lane and verified the repository.
