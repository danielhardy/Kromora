---
id: KRMA-264
title: Track the SwiftData concurrency probe test
type: task
status: done
priority: low
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Concurrency-gate coverage lives in a tracked test file and passes in the deterministic lane
      result: pass
    - criterion: git status shows no stray test files
      result: pass
  checks_run:
    - swift test --filter SwiftDataConcurrencyGateTests — 1 test, 0 failures
    - swift test list — SwiftDataConcurrencyGateTests/testModelAndModelActorAreSwift6ConcurrencySafe present and not in serial/optional skip filters, so it runs in the fast deterministic lane
    - git ls-files — only SwiftDataConcurrencyGateTests.swift tracked; no probe/LUMO245 files; grep finds no stale references
    - Reviewed gate file for correctness, maintainability, security, performance, Swift 6 zero-opt-out compliance
  findings: []
  fixes: []
  verification_commits: []
  actor: pi
  resolved_model: openrouter/meta/muse-spark-1.3-contributor
  completed_at: 2026-09-09T17:20:43.881Z
  session: 01MTUD53XDK60K64DQ
labels:
  - persistence
created: 2026-09-07T01:10:27.950Z
updated: 2026-09-10T12:53:51.780Z
depends_on:
  - KRMA-245
order: a0
board: product
---

## Objective

Put the KRMA-245 spike's concurrency gate under version control before it evaporates.

## Context

`Tests/LumoKitTests/SwiftDataConcurrencyProbeTests.swift` exists in the working tree but is
untracked (`??` in `git status`) — it was never committed with the epic. Its header says it
was deliberately kept as a compile-time gate for SwiftData's `@Model`/`@ModelActor` boundary
under Swift 6 strict concurrency, but an untracked file is one `git clean` away from deleting
that guarantee, and the "clean tree" verification checks do not cover it.

## Work

- `git add` the probe test as-is (it is self-contained and passes), or fold its assertions
  into `EditDocumentStoreTests` and delete the file. Either way the guarantee must live in a
  tracked file.
- If kept separate, rename out of the ticket-scoped `LUMO245` prefix so the next reader does
  not mistake it for scratch (e.g. `SwiftDataConcurrencyGateTests`).

## Acceptance criteria

- [ ] The concurrency-gate coverage lives in a tracked test file and passes in the
      deterministic lane.
- [ ] `git status --porcelain` shows no stray test files.


### Comment — codex @ 2026-09-09T17:19:11.604Z

Verified the tracked SwiftData concurrency gate in Tests/LumoKitTests/SwiftDataConcurrencyGateTests.swift. The gate passes directly, and scripts/ci-tests.sh fast passes all 665 required deterministic tests, including SwiftDataConcurrencyGateTests. The implementation is present in commits fe9cee7 and 407e6f5; no stray SwiftData/probe test files remain.

## Agent log

- 2026-09-09T17:20:43.881Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Concurrency-gate coverage lives in a tracked test file and passes in the deterministic lane (pass)
- [x] git status shows no stray test files (pass)
Checks run:
- swift test --filter SwiftDataConcurrencyGateTests — 1 test, 0 failures
- swift test list — SwiftDataConcurrencyGateTests/testModelAndModelActorAreSwift6ConcurrencySafe present and not in serial/optional skip filters, so it runs in the fast deterministic lane
- git ls-files — only SwiftDataConcurrencyGateTests.swift tracked; no probe/LUMO245 files; grep finds no stale references
- Reviewed gate file for correctness, maintainability, security, performance, Swift 6 zero-opt-out compliance
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: openrouter/meta/muse-spark-1.3-contributor
Pickup session: 01MTUD53XDK60K64DQ
Summary: KRMA-264 verified: SwiftData concurrency gate is tracked, correctly named, passes, and runs in the deterministic fast lane; no stray files or stale references remain.
