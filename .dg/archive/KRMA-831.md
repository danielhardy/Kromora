---
id: KRMA-831
title: Measure writer-lock wait in the production mutation scale probe
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Measure the full updateLibraryState plus browsing reload interval, including writer-lock wait, without hiding it behind a timer started after the write.
      result: pass
      notes: The probe records production-mutation-write and production-mutation-full from before updateLibraryState through the reload; production-mutation-reload retains the historical post-write interval and is explicitly distinguished.
    - criterion: Exercise a mutation while presented-ratio repair is active using a controlled synchronization boundary rather than depending on incidental task scheduling; retain rating/flag visibility and zero browsing record-read assertions.
      result: pass
      notes: The repair hook parks inside the writer lock, the probe waits for that boundary before issuing the mutation, and every sample verifies rating/flag visibility with zero browsing record reads.
    - criterion: Publish a three-sample 1k/10k/100k JSON result and document the timing boundary, keeping historical captures accurately labeled and avoiding invalid comparisons between different intervals.
      result: pass
      notes: Committed schema-version-2 evidence contains three samples at each scale and documents the intervals. The independent run also passed at all scales; the KRMA-829 historical JSON files are unchanged.
  checks_run:
    - Reviewed CLAUDE.md, .dg/AGENTS.md, compiled pickup context, KRMA-831 implementation commit, synchronization hook, report schema, documentation, and evidence; no correctness, maintainability, security, or performance blocker found.
    - "KROMORA_LIBRARY_SCALE_BENCHMARK=1 KROMORA_LIBRARY_SCALE_SAMPLES=3 KROMORA_LIBRARY_SCALE_OUTPUT=/tmp/kromora-library-scale-krma-831-verification.json swift test --no-parallel --filter LibraryScaleRegressionPerformanceTests/testPackageBackedLargeLibraryRegressionBenchmark: exit 0; one test passed in 479.872 s. Independently inspected emitted JSON: three samples per scale, zero record reads, and 32/32 concurrency revisions with one writer."
    - Validated independent JSON schema version 2, sample count 3, scales 1000/10000/100000, mutation interval metrics, zero record reads, and concurrency gates with jq; passed.
    - Confirmed the KRMA-829 historical evidence files were not modified by the KRMA-831 implementation commit.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T15:15:03.996Z
  session: 01MV3YG66C7LA5LNTV
creation_provenance:
  runner: codex
  model: gpt-6.1-sol
  actor: codex
labels:
  - verification
created: 2026-10-08T15:28:30.395Z
updated: 2026-10-11T15:15:03.999Z
parent: KRMA-829
blockers: []
order: q
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T13:53:26.012Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Capture the full production rating/flag mutation and subsequent reload, including time waiting for background package repair to release the writer lock.

## Context

Counterpoint verification of KRMA-829 found that `measureProductionLaunch` in `Tests/KromoraKitTests/LibraryScaleRegressionPerformanceTests.swift` calls `session.updateLibraryState` before recording `mutationReloadStart`. The published `production-mutation-reload` metric therefore measures only the post-write browsing reload, excluding the writer-lock wait and package transaction. This is pre-existing instrumentation, not a regression from KRMA-829. The completed three-sample probe proves writes finish and state is visible, but its reload timing cannot quantify the stall that motivated KRMA-829.

Keep the historical evidence intact and explicitly distinguish its measured reload interval from any new full mutation interval. See `docs/LIBRARY_SCALE_REGRESSION.md` and `docs/evidence/library-scale-krma-829.json`.

## Acceptance criteria

- [ ] Measure the full `updateLibraryState` plus browsing reload interval, including writer-lock wait, without hiding it behind a timer started after the write.
- [ ] Exercise a mutation while presented-ratio repair is active using a controlled synchronization boundary rather than depending on incidental task scheduling; retain rating/flag visibility and zero browsing record-read assertions.
- [ ] Publish a three-sample 1k/10k/100k JSON result and document the timing boundary, keeping historical captures accurately labeled and avoiding invalid comparisons between different intervals.

## Implementation notes

This is a non-blocking benchmark-quality follow-up. It does not require product behavior changes. Coordinate metric naming/schema and documentation changes so existing captured evidence remains interpretable. Do not run display-bound capture harnesses for this issue.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-11T15:15:03.996Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Measure the full updateLibraryState plus browsing reload interval, including writer-lock wait, without hiding it behind a timer started after the write. (pass) — The probe records production-mutation-write and production-mutation-full from before updateLibraryState through the reload; production-mutation-reload retains the historical post-write interval and is explicitly distinguished.
- [x] Exercise a mutation while presented-ratio repair is active using a controlled synchronization boundary rather than depending on incidental task scheduling; retain rating/flag visibility and zero browsing record-read assertions. (pass) — The repair hook parks inside the writer lock, the probe waits for that boundary before issuing the mutation, and every sample verifies rating/flag visibility with zero browsing record reads.
- [x] Publish a three-sample 1k/10k/100k JSON result and document the timing boundary, keeping historical captures accurately labeled and avoiding invalid comparisons between different intervals. (pass) — Committed schema-version-2 evidence contains three samples at each scale and documents the intervals. The independent run also passed at all scales; the KRMA-829 historical JSON files are unchanged.
Checks run:
- Reviewed CLAUDE.md, .dg/AGENTS.md, compiled pickup context, KRMA-831 implementation commit, synchronization hook, report schema, documentation, and evidence; no correctness, maintainability, security, or performance blocker found.
- KROMORA_LIBRARY_SCALE_BENCHMARK=1 KROMORA_LIBRARY_SCALE_SAMPLES=3 KROMORA_LIBRARY_SCALE_OUTPUT=/tmp/kromora-library-scale-krma-831-verification.json swift test --no-parallel --filter LibraryScaleRegressionPerformanceTests/testPackageBackedLargeLibraryRegressionBenchmark: exit 0; one test passed in 479.872 s. Independently inspected emitted JSON: three samples per scale, zero record reads, and 32/32 concurrency revisions with one writer.
- Validated independent JSON schema version 2, sample count 3, scales 1000/10000/100000, mutation interval metrics, zero record reads, and concurrency gates with jq; passed.
- Confirmed the KRMA-829 historical evidence files were not modified by the KRMA-831 implementation commit.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV3YG66C7LA5LNTV
Summary: Independent verification passed: controlled writer-lock overlap and full mutation timing verified by a three-sample 1k/10k/100k probe; no findings.
