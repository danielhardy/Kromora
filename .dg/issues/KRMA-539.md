---
id: KRMA-539
title: Fix MaskingWorkspaceTests source-switch and mask persistence failures
type: task
status: ready
priority: high
agent: codex
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - fast-lane
  - regression
  - masking
created: 2026-09-22T17:35:55.872Z
updated: 2026-09-22T17:36:26.482Z
estimate: 3
order: zt
board: product
---

## Objective

Restore MaskingWorkspaceTests coverage for source switching, active-photo state, and persisted mask reopening.

## Evidence

The fast lane failed while waiting for the second photo, persisted masks, and the second source to publish. The failures affected active-photo mask-tab restoration and semantic-mask reuse, including missing persisted targets and source readiness.

## Acceptance criteria

- [ ] The focused MaskingWorkspaceTests suite passes without timeout.
- [ ] Switching photos preserves the active photo and restores its mask document.
- [ ] Persisted semantic masks reopen with their target and source state.
- [ ] The fast lane no longer reports this suite.
