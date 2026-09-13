---
id: KRMA-408
title: "Phase 3.3: ImageWorkScheduler package I/O lanes and editor-priority yielding"
type: feature
status: ready
priority: high
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
updated: 2026-09-13T04:43:58.278Z
depends_on:
  - KRMA-407
order: zzzzq
board: product
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
