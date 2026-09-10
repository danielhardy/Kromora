---
id: KRMA-269
title: Parallelize independent detailed-analysis stages
type: task
status: done
priority: low
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Cold-.detailed per-stage timings recorded in the ticket
      result: pass
    - criterion: Either concurrent stages land with measured speedup and unchanged failure semantics, or ticket closes with numbers justifying sequential
      result: pass
  checks_run:
    - "benchmark testDetailedAnalysisBenchmark (release, 5 iters): PASS - cold detailedAnalysis median 74.044ms end-to-end; stages subject 20.042ms, foregroundInstance 31.951ms, background 0.016ms, face 13.142ms, person 1.023ms; reproduces reported sub-second result (57.897ms)"
    - "swift test --filter PhotoAnalysisCoordinatorTests: PASS - 7/7, 0 failures"
    - "production-diff review of 649a782 + coordinator defaultStages: PASS - test-only benchmark instrumentation (+81 lines); .detailed registry unchanged, still sequential"
  findings:
    - "No issues: measure-first outcome correct, cold .detailed total comfortably sub-second, concurrency not justified; no correctness, maintainability, security, or performance problems found."
  fixes: []
  verification_commits: []
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-09T17:33:17.606Z
labels:
  - masking
  - performance
created: 2026-09-07T01:14:47.482Z
updated: 2026-09-10T12:53:52.176Z
order: a0
board: product
branch: main
---

## Objective

Find out whether the five `.detailed` analysis stages can run concurrently instead of
sequentially, and do it only if measurement says it matters.

## Context

`PhotoAnalysisCoordinator.defaultStages[.detailed]` runs subject → foregroundInstance(0) →
background → face → person as sequential awaits (each a Vision request on a 768px image,
one-time per photo thanks to `PhotoAnalysisCache`). The person gate needs face/foreground
signals cached first, which constrains ordering: subject, foreground-instance, and face are
independent of each other, but person must come after the signals land (background derives
from foreground, so it slots after the instance stage too).

## Work (measure-first)

- Time a cold `.detailed` analysis on a representative photo, per stage. If the total is
  comfortably sub-second, close this ticket with the numbers — the complexity is not worth it.
- If it matters: run subject + foregroundInstance(0) + face concurrently (task group),
  then background + person after their inputs land. Preserve the swallowed-stage semantics
  (a failed stage must not fail siblings or the analysis) and the in-flight dedup in
  `coordinator.mask`.
- Caveat to verify: Vision/ANE may serialize internally, in which case concurrency buys
  nothing but contention — the measurement decides.

## Acceptance criteria

- [ ] Cold-`.detailed` per-stage timings recorded in the ticket.
- [ ] Either concurrent stages land with a measured speedup and unchanged failure semantics
      (existing provider/coordinator tests pass unmodified in spirit), or the ticket closes
      with numbers justifying sequential.


### Comment — codex @ 2026-09-09T17:23:35.338Z

Measure-first result (2026-09-09, Release, LUMO_PHOTO_ANALYSIS_BENCHMARK=1, 5 iterations): cold detailed analysis median 57.897 ms end-to-end. Per-stage medians: subject 16.374 ms; foregroundInstance(0) 21.605 ms; background 0.007 ms; face 12.041 ms; person 0.853 ms. The representative 1024x768 PNG is normalized to the production 768px analysis image. The total is comfortably sub-second, so concurrency is not justified; Vision/ANE contention risk and added orchestration complexity outweigh any plausible benefit at this scale. No production changes made. Focused coordinator suite: 7/7 passed, including in-flight deduplication, cancellation, cache, and timing behavior. Benchmark command: LUMO_PHOTO_ANALYSIS_BENCHMARK=1 LUMO_PHOTO_ANALYSIS_ITERATIONS=5 swift test -c release --filter PhotoAnalysisPerformanceTests.testDetailedAnalysisBenchmark

## Agent log

- 2026-09-09T17:31:43.359Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: openrouter/meta/muse-spark-1.3-contributor
Pickup session: 01MTUDAS03KYZ0FJ69
Summary: test

- 2026-09-09T17:33:08.825Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: unknown
Summary: x

- 2026-09-09T17:33:17.606Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Cold-.detailed per-stage timings recorded in the ticket (pass)
- [x] Either concurrent stages land with measured speedup and unchanged failure semantics, or ticket closes with numbers justifying sequential (pass)
Checks run:
- benchmark testDetailedAnalysisBenchmark (release, 5 iters): PASS - cold detailedAnalysis median 74.044ms end-to-end; stages subject 20.042ms, foregroundInstance 31.951ms, background 0.016ms, face 13.142ms, person 1.023ms; reproduces reported sub-second result (57.897ms)
- swift test --filter PhotoAnalysisCoordinatorTests: PASS - 7/7, 0 failures
- production-diff review of 649a782 + coordinator defaultStages: PASS - test-only benchmark instrumentation (+81 lines); .detailed registry unchanged, still sequential
Findings:
- No issues: measure-first outcome correct, cold .detailed total comfortably sub-second, concurrency not justified; no correctness, maintainability, security, or performance problems found.
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: unknown
Summary: Verification pass: reproduced sub-second cold-.detailed measurement (74ms end-to-end, per-stage breakdown consistent with reported 57.9ms); no production changes (test-only instrumentation); coordinator suite 7/7 green. Sequential pipeline correctly retained.
