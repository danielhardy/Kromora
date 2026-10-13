---
id: KRMA-968
title: Isolate DeriveCoordinator scratch output from parallel tests
type: task
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
  - tests
  - flaky
created: 2026-10-13T17:17:43.714Z
updated: 2026-10-13T17:17:43.714Z
blockers: []
order: zzzx
board: product
parent: KRMA-927
---

## Objective

Make `DeriveCoordinatorTests.testStaleSuccessAfterDismissDoesNotPublish` deterministic under the parallel fast lane.

## Context

Independent verification of KRMA-927 ran `scripts/ci-tests.sh fast`; the only failing test was this case. Its assertion reported many unrelated `KromoraDerive-*` scratch directories as stale output. The test passes by itself (`swift test --filter 'DeriveCoordinatorTests/testStaleSuccessAfterDismissDoesNotPublish'`, exit 0), which points to cross-test scratch-directory visibility under parallel execution.

## Acceptance criteria

- [ ] The test only inspects scratch output owned by its invocation, or otherwise safely distinguishes concurrent test output.
- [ ] The focused test passes.
- [ ] `scripts/ci-tests.sh fast` passes, including repeated parallel runs sufficient to exercise the original collision.

## Implementation notes

Keep the fix within test ownership/isolation unless investigation shows a production cleanup defect. Avoid deleting scratch directories owned by concurrent operations.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
