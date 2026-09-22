---
id: KRMA-539
title: Fix MaskingWorkspaceTests source-switch and mask persistence failures
type: task
status: review
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
updated: 2026-09-22T19:52:30.749Z
estimate: 3
order: y
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

### Comment — codex @ 2026-09-22T19:28:33.379Z

Recovered implementation changes into WIP commit 20cf4cb after the prior direct claimed-to-done transition. No ticket-specific commit attribution or independent verification is accepted; this issue is intentionally back in review for fresh verification.

### Comment — codex @ 2026-09-22T19:52:30.748Z

Verification was attempted twice but the Claude runner exited before submitting a report after its background release-build/masking-test tasks were killed at runner end-of-turn. No pass is recorded; returning to review for a verifier invocation that keeps checks foreground and waits for completion.

## Agent log

- 2026-09-22T18:47:44.169Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The focused MaskingWorkspaceTests suite passes without timeout. (pass) — MaskingWorkspaceTests passed 36/36 serially and in five repeated parallel runs.
- [x] Switching photos preserves the active photo and restores its mask document. (pass) — The active-photo/tab restoration regression passed; source-session loads now await the persistence barrier before reading stored edits.
- [x] Persisted semantic masks reopen with their target and source state. (pass) — The semantic-mask reuse/reopen regression passed, including persisted Subject target and source-switch isolation.
- [x] The fast lane no longer reports this suite. (pass) — The fast lane reached the masking suite without a MaskingWorkspaceTests failure; remaining fast-lane failures were unrelated suites already tracked separately.
Checks run:
- swift test --no-parallel --filter KromoraKitTests.MaskingWorkspaceTests (36 passed)
- swift test --parallel --filter KromoraKitTests.MaskingWorkspaceTests (5 repeated runs, 36 passed each)
- swift test --no-parallel --filter KromoraKitTests.SourceSessionCoordinatorTests (4 passed)
- swift test --no-parallel --filter KromoraKitTests.EditPersistenceIntegrationTests (11 passed)
- swift build -c release
- dg validate --json
- git diff --check
Findings:
- None
Fixes:
- Source switching now waits for queued edit persistence to finish before stored-document reads begin.
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUD0OSEAKUDM9UFV
Summary: Added a source-load persistence barrier so photo switches wait for the prior edit snapshot to become durable before reading the next photo's document. Mask tab state and per-photo mask documents now survive navigation, and persisted semantic-mask recipes reopen with their target/source identity.
