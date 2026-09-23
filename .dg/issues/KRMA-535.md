---
id: KRMA-535
title: Reconcile documentation with the package-backed product
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: No current guidance claims the product is folder-backed or that package storage is merely future.
      result: pass
      notes: bd5855e reconciled the 7 in-scope files; verification found 3 residual present-tense stale claims outside that file set (README persistence section + roadmap paragraph, LIBRARY_PACKAGE_FORMAT trash paragraph) and fixed them in e2489bf. Post-fix stale-claim scan shows only intentional historical records (frozen baseline, disposition history, explicitly superseded statements).
    - criterion: Improvement-plan status clearly identifies done, open, superseded, and linked CQ tickets.
      result: pass
      notes: REPOSITORY_IMPROVEMENT_PLAN R1-R8 table maps each item to done/partial/open status with linked KRMA-517/518/519/520/521/535/542/547 records and conservative scoping notes; all linked issue files and ADR-001 exist.
    - criterion: Scale documentation distinguishes production UI measurements from helper/fixture measurements.
      result: pass
      notes: LIBRARY_SCALE_REGRESSION states the fixture measures the production query/window path (PortableLibrarySession open, browsingWindow page, ImageCollection adapter, mutation reload) and explicitly excludes packaged-app launch time, SwiftUI frame time, thumbnail decode/render, real-library I/O, and end-to-end UI latency. Metric names verified against LibraryScaleRegressionPerformanceTests.
    - criterion: Persistence and storage docs match the implemented package-backed source of truth.
      result: pass
      notes: "Verified against Sources: EditDocumentStore is a bounded actor-local cache (defaultCacheCapacity 128, revision-checked), zero SwiftData/EditRecord references in production code, LibraryQueryController/LibraryIndexProjection/browsingWindow exist and are used by AppViewModel. STORAGE_POLICY cache label and disposition banner corrected in e2489bf."
    - criterion: Links, headings, and examples are valid; documentation audit/relevant validation checks pass.
      result: pass
      notes: All local .md link targets across the 7 KRMA-535 files plus README, FORMAT, and disposition docs resolve; git diff --check clean; no new headings added by either commit; benchmark env-var examples match test sources.
  checks_run:
    - rg stale-claim scan (folder-backed/SwiftData-future/KRMA-384-future phrasing) across CLAUDE.md, README.md, docs/*.md before and after fix
    - local Markdown link-target existence check across all 10 touched/referenced docs
    - git diff --check (clean)
    - "source cross-check: EditDocumentStore bounded cache, EditHistory.maximumDepth=100, termination flush, zero SwiftData/EditRecord in Sources/, LibraryQueryController/browsingWindow/LibraryIndexProjection existence and AppViewModel use"
    - "dependency status check: KRMA-519/520/531 all done"
    - "test-name cross-check: production-* metric keys in LIBRARY_SCALE_REGRESSION match LibraryScaleRegressionPerformanceTests"
  findings:
    - "Non-blocking (fixed): README persistence section described SwiftData EditRecord in EditStore.store as current, contradicting the package-backed product."
    - "Non-blocking (fixed): README roadmap paragraph treated the portable package as future work under KRMA-384 (blocked) and referenced coordinator tickets as open."
    - "Non-blocking (fixed): LIBRARY_PACKAGE_FORMAT trash section presented KRMA-371 folder-backed deletion as the current workflow."
    - "Non-blocking (fixed): STORAGE_POLICY row label 'SwiftData edit projection' contradicted its own body and ENGINEERING_GUIDE; EDIT_STORE_IDENTITY_DISPOSITION (KRMA-399 record stating the app opens EditStore.v2.store) is now bannered as superseded in production by KRMA-531."
    - No blockers. No security, performance, or maintainability defects introduced by bd5855e (docs-only). Residual SwiftData/folder-backed mentions are explicitly framed as historical/retired and are intentional.
  fixes:
    - "e2489bf KRMA-535 verification: reconcile remaining stale doc claims (README.md, docs/LIBRARY_PACKAGE_FORMAT.md, docs/STORAGE_POLICY.md, docs/EDIT_STORE_IDENTITY_DISPOSITION.md)"
  verification_commits:
    - e2489bf
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-23T06:22:40.579Z
  session: 01MUDPPRRED21W8N6S
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - documentation
  - architecture
created: 2026-09-21T20:33:14.597Z
updated: 2026-09-23T06:22:40.581Z
depends_on:
  - KRMA-519
  - KRMA-520
  - KRMA-531
estimate: 3
order: zv
board: product
commits:
  - e2489bf
---

## Objective

Make repository guidance accurately describe the package-backed product, record which older improvement-plan items are complete or superseded, and document the measured production path.

## Context and evidence

CLAUDE.md still says the current product is folder-backed and portable library is future. DOCUMENTATION_AUDIT.md and LIBRARY_PACKAGE_PLAN.md repeat that outdated model. REPOSITORY_IMPROVEMENT_PLAN.md does not distinguish done/open/moot work. LIBRARY_SCALE_REGRESSION.md does not disclose that the production UI path is not measured. ENGINEERING_GUIDE.md still describes the standalone v2 persistence store.

## Scope

- Update CLAUDE.md and DOCUMENTATION_AUDIT.md to describe package-backed storage and current compatibility boundaries.
- Update LIBRARY_PACKAGE_PLAN.md and STORAGE_POLICY.md where the package is now the product source of truth.
- Point REPOSITORY_IMPROVEMENT_PLAN.md to CODE_QUALITY_CLEANUP_PLAN.md for remaining work, or retire/supersede it explicitly with status mapping.
- Update LIBRARY_SCALE_REGRESSION.md with the production-path benchmark and limitations from CQ-04.
- Update ENGINEERING_GUIDE.md persistence sections after CQ-16 to describe the package-backed cache and sidecars.
- Document decisions and migration boundaries from CQ-05, CQ-16, and any retained legacy files; do not claim behavior that tests/benchmarks do not verify.

## Acceptance criteria

- [ ] No current guidance claims the product is folder-backed or that package storage is merely future.
- [ ] Improvement-plan status clearly identifies done, open, superseded, and linked CQ tickets.
- [ ] Scale documentation distinguishes production UI measurements from helper/fixture measurements.
- [ ] Persistence and storage docs match the implemented package-backed source of truth.
- [ ] Links, headings, and examples are valid; documentation audit/relevant validation checks pass.

## Dependencies and coordination

Land the behavior-specific updates with CQ-04, CQ-05, and CQ-16 where practical; this final reconciliation depends on those tickets' decisions. Keep repo-meta-only changes small and avoid rewriting historical records.

## Likely files and checks

CLAUDE.md, docs/DOCUMENTATION_AUDIT.md, docs/LIBRARY_PACKAGE_PLAN.md, docs/REPOSITORY_IMPROVEMENT_PLAN.md, docs/LIBRARY_SCALE_REGRESSION.md, docs/ENGINEERING_GUIDE.md, docs/STORAGE_POLICY.md, and documentation validation.


### Comment — codex @ 2026-09-23T05:47:11.913Z

Reconciled product/storage guidance with the package-backed source of truth and migration boundary (KRMA-519/520/531), updated the package plan's obsolete SwiftData/folder-backed passages, and retired the old R1–R8 plan as an execution queue with status and issue mapping. The scale guide records the 1k/10k/100k production query/window benchmark and states that the generated-summary probe does not measure packaged-app launch, SwiftUI frame time, thumbnail rendering, or real-library I/O. Commit bd5855e. Checks: local Markdown link targets in seven updated docs exist; git diff --check passes; stale-claim scan clean. Historical open items are explicitly marked for re-triage.

## Agent log

- 2026-09-23T06:22:40.579Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] No current guidance claims the product is folder-backed or that package storage is merely future. (pass) — bd5855e reconciled the 7 in-scope files; verification found 3 residual present-tense stale claims outside that file set (README persistence section + roadmap paragraph, LIBRARY_PACKAGE_FORMAT trash paragraph) and fixed them in e2489bf. Post-fix stale-claim scan shows only intentional historical records (frozen baseline, disposition history, explicitly superseded statements).
- [x] Improvement-plan status clearly identifies done, open, superseded, and linked CQ tickets. (pass) — REPOSITORY_IMPROVEMENT_PLAN R1-R8 table maps each item to done/partial/open status with linked KRMA-517/518/519/520/521/535/542/547 records and conservative scoping notes; all linked issue files and ADR-001 exist.
- [x] Scale documentation distinguishes production UI measurements from helper/fixture measurements. (pass) — LIBRARY_SCALE_REGRESSION states the fixture measures the production query/window path (PortableLibrarySession open, browsingWindow page, ImageCollection adapter, mutation reload) and explicitly excludes packaged-app launch time, SwiftUI frame time, thumbnail decode/render, real-library I/O, and end-to-end UI latency. Metric names verified against LibraryScaleRegressionPerformanceTests.
- [x] Persistence and storage docs match the implemented package-backed source of truth. (pass) — Verified against Sources: EditDocumentStore is a bounded actor-local cache (defaultCacheCapacity 128, revision-checked), zero SwiftData/EditRecord references in production code, LibraryQueryController/LibraryIndexProjection/browsingWindow exist and are used by AppViewModel. STORAGE_POLICY cache label and disposition banner corrected in e2489bf.
- [x] Links, headings, and examples are valid; documentation audit/relevant validation checks pass. (pass) — All local .md link targets across the 7 KRMA-535 files plus README, FORMAT, and disposition docs resolve; git diff --check clean; no new headings added by either commit; benchmark env-var examples match test sources.
Checks run:
- rg stale-claim scan (folder-backed/SwiftData-future/KRMA-384-future phrasing) across CLAUDE.md, README.md, docs/*.md before and after fix
- local Markdown link-target existence check across all 10 touched/referenced docs
- git diff --check (clean)
- source cross-check: EditDocumentStore bounded cache, EditHistory.maximumDepth=100, termination flush, zero SwiftData/EditRecord in Sources/, LibraryQueryController/browsingWindow/LibraryIndexProjection existence and AppViewModel use
- dependency status check: KRMA-519/520/531 all done
- test-name cross-check: production-* metric keys in LIBRARY_SCALE_REGRESSION match LibraryScaleRegressionPerformanceTests
Findings:
- Non-blocking (fixed): README persistence section described SwiftData EditRecord in EditStore.store as current, contradicting the package-backed product.
- Non-blocking (fixed): README roadmap paragraph treated the portable package as future work under KRMA-384 (blocked) and referenced coordinator tickets as open.
- Non-blocking (fixed): LIBRARY_PACKAGE_FORMAT trash section presented KRMA-371 folder-backed deletion as the current workflow.
- Non-blocking (fixed): STORAGE_POLICY row label 'SwiftData edit projection' contradicted its own body and ENGINEERING_GUIDE; EDIT_STORE_IDENTITY_DISPOSITION (KRMA-399 record stating the app opens EditStore.v2.store) is now bannered as superseded in production by KRMA-531.
- No blockers. No security, performance, or maintainability defects introduced by bd5855e (docs-only). Residual SwiftData/folder-backed mentions are explicitly framed as historical/retired and are intentional.
Fixes:
- e2489bf KRMA-535 verification: reconcile remaining stale doc claims (README.md, docs/LIBRARY_PACKAGE_FORMAT.md, docs/STORAGE_POLICY.md, docs/EDIT_STORE_IDENTITY_DISPOSITION.md)
Verification commits:
- e2489bf
Actor: pi
Resolved model: unknown
Pickup session: 01MUDPPRRED21W8N6S
Summary: Pass: bd5855e reconciliation verified against source and tests; 4 residual stale-claim fixes landed in e2489bf; all acceptance criteria met.
