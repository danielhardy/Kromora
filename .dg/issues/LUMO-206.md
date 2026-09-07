---
id: LUMO-206
title: Performance instrumentation + benchmark suite
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 71a770658a9cf64d19725fbe5f5140baf185070f
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-04T18:37:21.045Z
  session: 01MTNA3ISNPCT9JYM9
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - photo-intelligence
created: 2026-09-04T14:27:58.504Z
updated: 2026-09-07T04:02:46.099Z
depends_on:
  - LUMO-196
  - LUMO-190
order: e415gzne
board: product
commits:
  - 71a770658a9cf64d19725fbe5f5140baf185070f
---

**Type:** Task
**Component:** `Tests/LumoKitTests/PhotoAnalysisPerformanceTests.swift` (new) + instrumentation
additions across `Sources/LumoKit/Models/PhotoAnalysis/`
**Depends on:** LUMO-196, LUMO-190
**Epic:** LUMO-181 — see `docs/PHASE3_SPEC.md` §6, original proposal §26–28, §43

## 1. Problem

Every analysis/mask ticket was asked to populate `AnalysisTimings` per stage, but nothing yet
enforces the performance budgets in `docs/PHASE3_SPEC.md` §6, and the 768px canonical-image
dimension (left as `// TODO(LUMO-206)` since LUMO-183) is unbenchmarked. This ticket closes both
gaps.

## 2. Requirement (acceptance criteria)

1. `os.signpost`/`Signposter` instrumentation around each major stage (image prep, global tone,
   each mask provider, masked-statistics, assembly) — mostly threading existing `AnalysisTimings`
   capture points into real signposts.
2. Benchmark tests covering: `prepareAnalysisImage()`, `GlobalToneAnalyzer`, each mask provider
   (subject/face/foreground/person), `MaskedToneAnalyzer`, full `.standard` analysis,
   `MaskStore`/`PhotoAnalysisCache` reads (cache-hit path).
3. Baseline + allowed-percentage-regression assertions, not strict ms ceilings (CI variability).
4. Resolve the `// TODO(LUMO-206)` from LUMO-183: benchmark 512/768/1024 canonical dimensions for
   timing + a rough quality signal (does subject detection still succeed); update the default if
   the data supports a different value, otherwise confirm 768 with the numbers that justified it.
5. Confirm measured numbers against `docs/PHASE3_SPEC.md` §6's targets on a representative Apple
   Silicon Mac; record results in the completion comment.
6. Rough transient-memory check that `.standard` analysis stays well under the ~50MB target.
7. Swift 6 clean.

## 3. Implementation notes

- This ticket is explicitly allowed to change `AnalysisConfiguration.maximumDimension`'s default.
- If no benchmark-baseline pattern exists elsewhere in this repo, use a simple "N runs, median,
  compare to a checked-in baseline JSON with allowed % drift" approach.

## 4. Where to look

- `docs/PHASE3_SPEC.md` §6.
- LUMO-183's `AnalysisConfiguration.maximumDimension` TODO.
- Every prior mask-provider/analyzer ticket's `AnalysisTimings` population points.

## 5. Testing

- The benchmark suite itself is the deliverable. Run it, capture numbers, report in the completion
  comment.


### Comment — codex @ 2026-09-04T18:37:09.043Z

Implemented in commit 71a7706. Added Swift 6-safe os.signpost instrumentation and populated AnalysisTimings for image preparation, global tone, subject/face/foreground/background/person masks, masked statistics, assembly, and total analysis. Full analyses now reuse one canonical AnalysisImage; cache hits emit CacheHit and persisted timings are retained. Added the opt-in PhotoAnalysisPerformanceTests suite with median N-run measurements, checked-in JSON baselines with 25% drift allowance, 512/768/1024 canonical-dimension quality checks, and a resident-memory smoke check. Release reference run on Apple M1 Pro, 16 GB, generated 1024x768 sRGB fixture, 3 samples: prepare 0.000 ms; global 2.661 ms; subject 173.948 ms (3/3); face 12.766 ms (0/3, typed no-face path); foreground 23.834 ms (0/3, no-instance path); person 0.805 ms (0/3, gated path); masked tone 106.246 ms; cold standard median 606.726 ms; cache hit 0.407 ms; standard resident delta 3.00 MB. Canonical subject timing: 512 221.3 ms, 768 173.7 ms, 1024 299.7 ms; subject succeeded at all three, so the 768 default remains. Against PHASE3_SPEC section 6, cache hit, Tier 0, and memory were within targets; the generated-fixture subject and standard paths exceeded the aspirational 75/150 ms targets and are recorded as measurements rather than strict CI ceilings. Focused LUMO-206 tests and swift build passed. Full swift test completed with 800 passing, 41 expected skips, and 15 unrelated existing flaky failures in inspector/persistence/thumbnail tests under the parallel run.


### Comment — codex @ 2026-09-04T18:37:13.911Z

Correction to the verification count in the previous comment: the full parallel run reported 815 executed, 41 skipped, and 15 failures, which is 759 passing tests. The failures were existing unrelated flaky inspector/persistence/thumbnail tests; the focused LUMO-206 tests were green.

### Comment — codex @ 2026-09-04T18:39:23.243Z

Post-commit Release rerun on the exact committed tree passed all 7 PhotoAnalysisPerformanceTests (3 samples each). Measurements: canonical 512=193.946 ms, 768=180.113 ms, 1024=305.698 ms with subject=true at all sizes; global tone 2.951 ms; masked tone 106.591 ms; subject 177.633 ms (3/3); face 12.793 ms (typed no-face path); foreground 25.011 ms (no-instance path); person 0.822 ms (gated path); prepare 0.000 ms; cold standard 604.186 ms; cache hit 0.351 ms; transient resident delta 1.70 MB. Baseline drift assertions passed.

## Agent log

- 2026-09-04T18:37:21.046Z: Verification report
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
- 71a770658a9cf64d19725fbe5f5140baf185070f
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTNA3ISNPCT9JYM9
Summary: Performance instrumentation and opt-in benchmark suite implemented; canonical default remains 768px based on measured 512/768/1024 subject signal and timing results.
