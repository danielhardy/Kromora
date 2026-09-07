---
id: LUMO-249
title: Remove obsolete whole-catalog-rewrite benchmark
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Both obsolete benchmark files are removed
      result: pass
    - criterion: docs/CODE_REVIEW.md records the finding as resolved with a pointer to epic LUMO-244
      result: pass
    - criterion: swift test passes with the benchmark test removed
      result: pass
  checks_run:
    - git diff --check
    - swift test -- 914 executed, 41 skipped, 0 failures
    - dg validate -- passed with existing unknown pickup-model warning
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-06T23:51:44.529Z
  session: 01MTQGRBGDSHI2I25B
labels:
  - persistence
created: 2026-09-06T04:06:27.772Z
updated: 2026-09-07T04:02:50.569Z
depends_on:
  - LUMO-244
  - LUMO-246
order: o6wty9oo
board: product
---

## Objective

Remove the obsolete whole-catalog-rewrite benchmark now that persistence is row-level.

## Context

`Tests/LumoKitTests/EditPersistenceBenchmarkTests.swift` and
`docs/EDIT_PERSISTENCE_BENCHMARK_2026-09-01.md` exist to measure the cost of rewriting the whole
JSON catalog per edit. Once Child 2 lands row-level SwiftData persistence, that premise is moot.

## Work

- Delete `Tests/LumoKitTests/EditPersistenceBenchmarkTests.swift`.
- Delete `docs/EDIT_PERSISTENCE_BENCHMARK_2026-09-01.md`.
- Add a one-line note to `docs/CODE_REVIEW.md` closing out that finding as resolved by this epic.

## Acceptance criteria

- [ ] Both files removed.
- [ ] `docs/CODE_REVIEW.md` records the finding as resolved, with a pointer to this epic.
- [ ] `swift test` still passes with the benchmark test removed.

## Depends on

Child 2.

## Agent log

- 2026-09-06T23:51:44.531Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Both obsolete benchmark files are removed (pass)
- [x] docs/CODE_REVIEW.md records the finding as resolved with a pointer to epic LUMO-244 (pass)
- [x] swift test passes with the benchmark test removed (pass)
Checks run:
- git diff --check
- swift test -- 914 executed, 41 skipped, 0 failures
- dg validate -- passed with existing unknown pickup-model warning
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTQGRBGDSHI2I25B
Summary: Removed the obsolete whole-catalog-rewrite benchmark report and documented the finding as resolved by epic LUMO-244. The benchmark test was already absent from the claimed checkout.
