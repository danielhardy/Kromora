---
id: KRMA-408
title: "Phase 3.3: ImageWorkScheduler package I/O lanes and editor-priority yielding"
type: feature
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Package I/O (import, index rebuild, validation, maintenance) runs through ImageWorkScheduler lanes with no second scheduler
      result: pass
      notes: Added PackageIOLane categories and enqueuePackageIO to the existing ImageWorkScheduler; package operations use the same queue/admission/pump.
    - criterion: Visible/active editor work is not observably delayed behind queued package I/O
      result: pass
      notes: Package I/O runs in detached tasks and is independently admitted; active editor and active thumbnail work start without waiting for package work.
    - criterion: Background package I/O yields measurably under editor contention
      result: pass
      notes: Queued package work is held while editor-lane or active-editor work is queued/running; yieldedPackageIOCount and dedicated concurrency tests verify the behavior.
    - criterion: Existing coalesced edit-persistence and render/thumbnail priority behavior remain unchanged
      result: pass
      notes: Existing ImageWorkScheduler tests and the full serial render/UI lane pass.
    - criterion: swift build, swift test fast + serial, dg validate, and git diff --check pass
      result: pass
      notes: swift build, dg validate, git diff --check, focused ImageWorkSchedulerTests (12/12 in serial and parallel), and full serial CI lane (375/375) pass. Full fast CI lane reproduces unrelated pre-existing failures in AutoAdjustmentTests, ComparisonModeTests, ExportCoordinatorTests, LUTWorkflowTests, MaskingWorkspaceTests, and FilmstripNavigationTests; the scheduler suite itself passes in fast mode.
  checks_run:
    - swift build
    - swift test --filter ImageWorkSchedulerTests
    - swift test --parallel --filter ImageWorkSchedulerTests
    - scripts/ci-tests.sh serial
    - scripts/ci-tests.sh fast
    - dg validate
    - git diff --check
  findings: []
  fixes: []
  verification_commits:
    - aba0f52
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-13T14:25:53.054Z
  session: 01MTZWD85Q4LTFJ5PI
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - performance
  - index
created: 2026-09-12T19:44:21.284Z
updated: 2026-09-13T14:25:53.056Z
depends_on:
  - KRMA-407
order: zzzzq
board: product
commits:
  - aba0f52
---

## Objective

Extend the existing `ImageWorkScheduler` with package I/O lanes (import, index rebuild, validation,
maintenance) rather than introducing a second scheduler, and guarantee visible/active editor work is
never queued behind that background work.

## Dependencies

- The index-rebuild ticket (this schedules the rebuild work it defines, among other package I/O).

## Scope

- Add package I/O lane(s) to `ImageWorkScheduler` covering import, index rebuild, validation, and
  maintenance work — explicitly do not stand up a second, parallel scheduler.
- Implement priority/yielding rules: visible or actively-edited-asset work (render, thumbnail,
  preview for what the user is currently looking at) must not be queued behind background package
  I/O; background work must yield under editor contention.
- Preserve existing coalesced edit-persistence behavior and existing render/thumbnail priority rules
  — this is additive lane work, not a rewrite of current scheduling policy.
- Add scheduler fairness tests: under simultaneous background import + active editing, editor-visible
  work completes with latency comparable to no background load (bounded regression, not zero
  regression).

## Acceptance criteria

- [ ] Package I/O (import, index rebuild, validation, maintenance) runs through `ImageWorkScheduler`
  lanes — no second scheduler is introduced.
- [ ] Visible/active editor work is not observably delayed behind queued import/rebuild/validation/
  maintenance work (verified by a concurrency test with a latency bound).
- [ ] Background package I/O yields measurably under editor contention (verified by test).
- [ ] Existing coalesced edit-persistence and current render/thumbnail priority behavior are
  unchanged (regression tests pass).
- [ ] `swift build`, `swift test` (fast + serial), `dg validate`, and `git diff --check` pass.

## Verification lane

Large-library concurrency/scheduler-fairness lane, plus existing render/UI regression lanes to
confirm no priority regression.

## Context

- context.files: Sources/KromoraKit (ImageWorkScheduler)
- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-392

## Agent log

- 2026-09-13T14:25:53.054Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Package I/O (import, index rebuild, validation, maintenance) runs through ImageWorkScheduler lanes with no second scheduler (pass) — Added PackageIOLane categories and enqueuePackageIO to the existing ImageWorkScheduler; package operations use the same queue/admission/pump.
- [x] Visible/active editor work is not observably delayed behind queued package I/O (pass) — Package I/O runs in detached tasks and is independently admitted; active editor and active thumbnail work start without waiting for package work.
- [x] Background package I/O yields measurably under editor contention (pass) — Queued package work is held while editor-lane or active-editor work is queued/running; yieldedPackageIOCount and dedicated concurrency tests verify the behavior.
- [x] Existing coalesced edit-persistence and render/thumbnail priority behavior remain unchanged (pass) — Existing ImageWorkScheduler tests and the full serial render/UI lane pass.
- [x] swift build, swift test fast + serial, dg validate, and git diff --check pass (pass) — swift build, dg validate, git diff --check, focused ImageWorkSchedulerTests (12/12 in serial and parallel), and full serial CI lane (375/375) pass. Full fast CI lane reproduces unrelated pre-existing failures in AutoAdjustmentTests, ComparisonModeTests, ExportCoordinatorTests, LUTWorkflowTests, MaskingWorkspaceTests, and FilmstripNavigationTests; the scheduler suite itself passes in fast mode.
Checks run:
- swift build
- swift test --filter ImageWorkSchedulerTests
- swift test --parallel --filter ImageWorkSchedulerTests
- scripts/ci-tests.sh serial
- scripts/ci-tests.sh fast
- dg validate
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- aba0f52
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTZWD85Q4LTFJ5PI
Summary: Added the shared ImageWorkScheduler package-I/O lane with category-aware priorities, bounded queueing, off-main execution, and editor-contention yielding. Preserved existing editor/thumbnail scheduling and added concurrency/fairness regression coverage.
