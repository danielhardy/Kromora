---
id: KRMA-919
title: Investigate intermittent stored-edit adoption supersession failure
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
parent: KRMA-917
created: 2026-10-13T01:50:05.794Z
updated: 2026-10-13T01:50:05.794Z
blockers: []
order: zzzx
board: product
---

## Objective

Investigate an intermittent failure in the stored-edit adoption supersession regression under the parallel fast lane.

## Context

During independent verification of KRMA-917, the first `scripts/ci-tests.sh fast` run failed once in `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` at `Tests/KromoraKitTests/StoredEditAdoptionTests.swift:364`, on the assertion that the superseded photo remains a browsing placeholder after delayed materialization is released. The same test passed immediately when rerun alone, and the full fast lane passed on a subsequent run. The observation is intermittent and outside KRMA-917's dust-suggestion test change.

## Acceptance criteria

- [ ] Determine whether the failure is a product race or a test synchronization issue under parallel execution.
- [ ] Ensure a superseded photo's delayed materialization cannot publish after another photo becomes active, and make the regression deterministic under the fast lane.
- [ ] `swift test --filter 'StoredEditAdoptionTests/testSlowMaterializationCannotReopenSupersededPhoto'` passes.
- [ ] `scripts/ci-tests.sh fast` exits 0.

## Implementation notes

Keep the stored-edit adoption ownership/supersession contract intact. If the production path is correct, tighten the test's synchronization rather than adding scheduling delays to production code.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
