---
id: KRMA-829
title: Avoid quadratic presented-ratio repair in large libraries
type: task
status: done
priority: high
agent: claude
verification_agent: codex
human_review_required: false
verification_model: gpt-6.1-sol
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Resolve missing asset summaries in linear or near-linear time per shard; avoid repeated full-shard scans while holding the writer mutation lock.
      result: pass
      notes: Reviewed implementation a1ae73b2c440ad23b356177d332ab964e0ef2270. Missing entries are filtered once, resolved directly, and merged with dictionary lookups in one pass; no per-asset first(where:) shard scan remains. Nested JSON scanning and shard validation are linear. The 4,001-entry dense-shard regression passed in 1.965 s.
    - criterion: Preserve repair's concurrent edit, rating, flag, tombstone, and cancellation semantics, with focused coverage for a dense shard and a mutation racing repair.
      result: pass
      notes: Expanded dense coverage verifies rating/flag preservation and an unrepaired tombstone. The racing edit/catalog test verifies document geometry and rating/flag survive either writer ordering. Cancellation before transaction publication leaves membership unchanged; existing committed-shard cancellation/resume and session publication tests pass. Added containment regression verifies shard-level symlink rejection and lazy record-read rejection of asset-level escapes.
    - criterion: Complete the documented 1k/10k/100k three-sample scale probe and publish its JSON result. Confirm 100k production mutation/reload stays bounded and record reads remain zero; compare timing with the dated evidence in docs/LIBRARY_SCALE_REGRESSION.md.
      result: pass
      notes: "Independent documented three-sample run completed in 483.740 s, exit 0, without the prior 12-minute stall. Published docs/evidence/library-scale-krma-829-verification.json. At 100k: launch p95 16012.04 ms, post-mutation browsing reload p95 403.64 ms, browsing record reads 0, all 32 revisions committed, maximum concurrent package writers 1. Launch/post-mutation reload differ +0.5%/-0.7% from implementation evidence; post-mutation reload is above the dated KRMA-519 323.02 ms capture on a different macOS version. Important measurement limit: the pre-existing timer starts after updateLibraryState, so completion proves mutations finish and state is visible but the metric does not quantify full write/lock latency. Documentation now states this explicitly; non-blocking backlog child KRMA-831 tracks instrumentation improvement."
  checks_run:
    - Read CLAUDE.md, .dg/AGENTS.md, compiled pickup context, canonical issue, implementation diff, scale documentation, and published implementation JSON. Independently reviewed correctness, maintainability, security, performance, mutation locking, cancellation, JSON preservation, and containment at actual I/O boundaries. No context.commands were declared.
    - "KROMORA_LIBRARY_SCALE_BENCHMARK=1 KROMORA_LIBRARY_SCALE_SAMPLES=3 KROMORA_LIBRARY_SCALE_OUTPUT=/tmp/krma-829-verification-scale.json swift test --no-parallel --filter LibraryScaleRegressionPerformanceTests/testPackageBackedLargeLibraryRegressionBenchmark: exit 0; one test passed in 483.740 s. Inspected complete log and validated all three scales, three samples per metric, zero browsing record reads, and concurrency gates in emitted JSON."
    - "swift test --no-parallel --filter 'Portable|PackageEditProjectionTests|PackagePathTests|LibraryQueryControllerTests|LibraryBrowsingProjectionTests|LibraryWindowedBrowsingTests|PackageSettingsTests': exit 0; 143 tests passed, zero failures, in 89.050 s. Includes repair, session startup/publication, browsing, unknown JSON field preservation, backup/restore, transaction, validation, path, tombstone, and identity regressions."
    - "scripts/ci-tests.sh warning-gate: exit 0; application and tests built with -warnings-as-errors and no diagnostics."
    - "git diff --check and git diff --cached --check: exit 0."
    - All started background commands finished; final output and exit status inspected. No display-bound benchmarks were started.
  findings:
    - "Non-blocking, pre-existing benchmark limitation: production-mutation-reload excludes updateLibraryState and its writer-lock wait, and mutation/repair overlap depends on scheduling. Created backlog child KRMA-831, labeled verification with parent KRMA-829, to measure full mutation latency and controlled overlap. No unresolved implementation, security, or correctness blocker found."
  fixes:
    - Localized test-only additions strengthen dense-shard rating/flag/tombstone preservation, concurrent edit/catalog mutation, cancellation rollback, and shard/lazy-record symlink containment coverage; no product behavior or API/schema changes.
    - Clarified benchmark timing scope and comparison limits in docs/LIBRARY_SCALE_REGRESSION.md; published independent three-sample verification JSON. Preserved pre-existing DispatchGraph working-tree changes.
  verification_commits:
    - dd1238a91bda6c1b4a8bf6bed3025048a7d9275c
  actor: codex
  resolved_model: gpt-6.1-sol
  completed_at: 2026-10-08T15:36:59.105Z
  session: 01MUZOU3OWOVDVE1G9
creation_provenance:
  runner: codex
  model: gpt-6-sol
  actor: codex
labels:
  - verification
created: 2026-10-07T18:35:11.281Z
updated: 2026-10-08T15:36:59.109Z
parent: KRMA-828
blockers: []
order: t
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-08T15:25:02.745Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - dd1238a91bda6c1b4a8bf6bed3025048a7d9275c
---

## Objective

Keep presented-aspect-ratio repair bounded for large package libraries so background repair does not hold the package writer lock across a very large shard and stall ordinary library-state edits.

## Context

Discovered during counterpoint verification of KRMA-828. The documented three-sample `LibraryScaleRegressionPerformanceTests/testPackageBackedLargeLibraryRegressionBenchmark` run reached the 100,000-asset path but produced no report after 12 minutes and had to be stopped (command exit 1). Two process samples during the stall showed the main thread waiting in `PortableLibrarySession.updateLibraryState(for:rating:flag:)` on the writer mutation lock while background `repairPresentedAspectRatioShard` held that lock. `PortablePackageEditSidecar.swift` line 626 calls `scannedShard.entries.first(where:)` for every missing asset ID, making a dense shard quadratic in entry count. The test fixture intentionally has no asset records, so repair has many missing ratios. This path is broader than the square-grid implementation.

## Acceptance criteria

- [ ] Resolve missing asset summaries in linear or near-linear time per shard; avoid repeated full-shard scans while holding the writer mutation lock.
- [ ] Preserve repair's concurrent edit, rating, flag, tombstone, and cancellation semantics, with focused coverage for a dense shard and a mutation racing repair.
- [ ] Complete the documented 1k/10k/100k three-sample scale probe and publish its JSON result. Confirm 100k production mutation/reload stays bounded and record reads remain zero; compare timing with the dated evidence in `docs/LIBRARY_SCALE_REGRESSION.md`.

## Implementation notes

Relevant code: `Sources/KromoraKit/Models/PortablePackageEditSidecar.swift` (`repairPresentedAspectRatioShard`), `Sources/KromoraKit/Models/PortableLibrarySession.swift` (background repair and writer lock), and `Tests/KromoraKitTests/LibraryScaleRegressionPerformanceTests.swift`. The interrupted verification produced `/tmp/krma-828-scale.log` and two process samples in `/tmp/krma-828-scale-sample*.txt` on the verifier's machine.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-08T15:36:59.105Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Resolve missing asset summaries in linear or near-linear time per shard; avoid repeated full-shard scans while holding the writer mutation lock. (pass) — Reviewed implementation a1ae73b2c440ad23b356177d332ab964e0ef2270. Missing entries are filtered once, resolved directly, and merged with dictionary lookups in one pass; no per-asset first(where:) shard scan remains. Nested JSON scanning and shard validation are linear. The 4,001-entry dense-shard regression passed in 1.965 s.
- [x] Preserve repair's concurrent edit, rating, flag, tombstone, and cancellation semantics, with focused coverage for a dense shard and a mutation racing repair. (pass) — Expanded dense coverage verifies rating/flag preservation and an unrepaired tombstone. The racing edit/catalog test verifies document geometry and rating/flag survive either writer ordering. Cancellation before transaction publication leaves membership unchanged; existing committed-shard cancellation/resume and session publication tests pass. Added containment regression verifies shard-level symlink rejection and lazy record-read rejection of asset-level escapes.
- [x] Complete the documented 1k/10k/100k three-sample scale probe and publish its JSON result. Confirm 100k production mutation/reload stays bounded and record reads remain zero; compare timing with the dated evidence in docs/LIBRARY_SCALE_REGRESSION.md. (pass) — Independent documented three-sample run completed in 483.740 s, exit 0, without the prior 12-minute stall. Published docs/evidence/library-scale-krma-829-verification.json. At 100k: launch p95 16012.04 ms, post-mutation browsing reload p95 403.64 ms, browsing record reads 0, all 32 revisions committed, maximum concurrent package writers 1. Launch/post-mutation reload differ +0.5%/-0.7% from implementation evidence; post-mutation reload is above the dated KRMA-519 323.02 ms capture on a different macOS version. Important measurement limit: the pre-existing timer starts after updateLibraryState, so completion proves mutations finish and state is visible but the metric does not quantify full write/lock latency. Documentation now states this explicitly; non-blocking backlog child KRMA-831 tracks instrumentation improvement.
Checks run:
- Read CLAUDE.md, .dg/AGENTS.md, compiled pickup context, canonical issue, implementation diff, scale documentation, and published implementation JSON. Independently reviewed correctness, maintainability, security, performance, mutation locking, cancellation, JSON preservation, and containment at actual I/O boundaries. No context.commands were declared.
- KROMORA_LIBRARY_SCALE_BENCHMARK=1 KROMORA_LIBRARY_SCALE_SAMPLES=3 KROMORA_LIBRARY_SCALE_OUTPUT=/tmp/krma-829-verification-scale.json swift test --no-parallel --filter LibraryScaleRegressionPerformanceTests/testPackageBackedLargeLibraryRegressionBenchmark: exit 0; one test passed in 483.740 s. Inspected complete log and validated all three scales, three samples per metric, zero browsing record reads, and concurrency gates in emitted JSON.
- swift test --no-parallel --filter 'Portable|PackageEditProjectionTests|PackagePathTests|LibraryQueryControllerTests|LibraryBrowsingProjectionTests|LibraryWindowedBrowsingTests|PackageSettingsTests': exit 0; 143 tests passed, zero failures, in 89.050 s. Includes repair, session startup/publication, browsing, unknown JSON field preservation, backup/restore, transaction, validation, path, tombstone, and identity regressions.
- scripts/ci-tests.sh warning-gate: exit 0; application and tests built with -warnings-as-errors and no diagnostics.
- git diff --check and git diff --cached --check: exit 0.
- All started background commands finished; final output and exit status inspected. No display-bound benchmarks were started.
Findings:
- Non-blocking, pre-existing benchmark limitation: production-mutation-reload excludes updateLibraryState and its writer-lock wait, and mutation/repair overlap depends on scheduling. Created backlog child KRMA-831, labeled verification with parent KRMA-829, to measure full mutation latency and controlled overlap. No unresolved implementation, security, or correctness blocker found.
Fixes:
- Localized test-only additions strengthen dense-shard rating/flag/tombstone preservation, concurrent edit/catalog mutation, cancellation rollback, and shard/lazy-record symlink containment coverage; no product behavior or API/schema changes.
- Clarified benchmark timing scope and comparison limits in docs/LIBRARY_SCALE_REGRESSION.md; published independent three-sample verification JSON. Preserved pre-existing DispatchGraph working-tree changes.
Verification commits:
- dd1238a91bda6c1b4a8bf6bed3025048a7d9275c
Actor: codex
Resolved model: gpt-6.1-sol
Pickup session: 01MUZOU3OWOVDVE1G9
Summary: Counterpoint verification passed: 143 regression tests, zero-warning build, and independent 1k/10k/100k three-sample probe (483.74 s). Added localized coverage and published JSON. Non-blocking benchmark instrumentation follow-up KRMA-831 is in backlog.
