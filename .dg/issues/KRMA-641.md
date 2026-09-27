---
id: KRMA-641
title: Flaky LibraryGridTests.testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding under full fast lane
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Root-cause the flake in testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding (or the demand-driven grid materialization path it exercises) and make the test deterministic under scripts/ci-tests.sh fast when run repeatedly (e.g. 10+ consecutive full fast lane runs with no failures).
      result: pass
      notes: "Ran scripts/ci-tests.sh fast (full 1247-test deterministic-parallel lane) 10 consecutive times; all 10 exited 0 with no failures in testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding or elsewhere. Reviewed commit 7b53015: it switches the test from loadFromFolder (which auto-selects item 0 and prefetches adjacent filmstrip thumbnails, racing with the materialized-cell-only assertion) to loadPortableAssets (no auto-selection), and replaces a Task.yield() busy-wait with a Task.sleep(10ms) poll, removing the CPU-starvation race under full-suite --parallel execution. The change is test-only, narrowly scoped, and matches the documented root cause."
  checks_run:
    - swift build
    - swift build --build-tests
    - scripts/ci-tests.sh fast x10 consecutive (all exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-27T03:14:32.813Z
  session: 01MUJ87129Z2UUEDU4
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-26T21:20:58.902Z
updated: 2026-09-27T03:14:32.815Z
parent: KRMA-637
blockers: []
order: a0
board: product
---

## Objective

Flaky LibraryGridTests.testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding under full fast lane

## Context

Found while independently verifying KRMA-637 (AutoEnhancementCoordinatorTests fix). Running
`scripts/ci-tests.sh fast` on a clean HEAD (90811f0, no product-source changes) failed once with:

```
LibraryGridTests.swift:260: error: ... a virtualized grid must not decode every discovered cell before it appears
LibraryGridTests.swift:274: error: ... requesting one materialized cell must not admit the rest of the folder
```

both in `testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding`. This is unrelated to KRMA-637's
scope (Auto Light/Color low-key intent). Re-running the same `fast` lane immediately after passed with
exit 0, and running `swift test --filter LibraryGridTests` in isolation passed all 13 tests. This points
to a timing-sensitive interaction under `--parallel` full-suite execution (demand/materialization ordering
racing against other concurrently-running tests), not a deterministic regression.

## Acceptance criteria

- [ ] Root-cause the flake in `testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding` (or the demand-driven
      grid materialization path it exercises) and make the test deterministic under `scripts/ci-tests.sh fast`
      when run repeatedly (e.g. 10+ consecutive full `fast` lane runs with no failures).

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-27T02:54:56.509Z

Made the demand-driven grid test deterministic by loading unselected assets directly, removing the folder fixture's adjacent-thumbnail prefetch, and yielding during the thumbnail wait. Commit: 7b53015. Verification attempt: the focused test build is blocked by unrelated untracked RetouchModelTests.swift compile errors (EditDocument has no retouch member); fast-lane repetition could not run.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-27T03:14:32.813Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Root-cause the flake in testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding (or the demand-driven grid materialization path it exercises) and make the test deterministic under scripts/ci-tests.sh fast when run repeatedly (e.g. 10+ consecutive full fast lane runs with no failures). (pass) — Ran scripts/ci-tests.sh fast (full 1247-test deterministic-parallel lane) 10 consecutive times; all 10 exited 0 with no failures in testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding or elsewhere. Reviewed commit 7b53015: it switches the test from loadFromFolder (which auto-selects item 0 and prefetches adjacent filmstrip thumbnails, racing with the materialized-cell-only assertion) to loadPortableAssets (no auto-selection), and replaces a Task.yield() busy-wait with a Task.sleep(10ms) poll, removing the CPU-starvation race under full-suite --parallel execution. The change is test-only, narrowly scoped, and matches the documented root cause.
Checks run:
- swift build
- swift build --build-tests
- scripts/ci-tests.sh fast x10 consecutive (all exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUJ87129Z2UUEDU4
Summary: Verified: 10 consecutive full-suite scripts/ci-tests.sh fast runs (1247 tests each) all passed with exit 0. Reviewed commit 7b53015's fix (loadPortableAssets instead of loadFromFolder to avoid auto-selection prefetch race; Task.sleep poll instead of Task.yield busy-wait) as a correct, narrowly-scoped root-cause fix for the flake.
