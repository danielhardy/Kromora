---
id: KRMA-723
title: ThumbnailSwitchLifecycleTests delayed-completion test fails deterministically
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: ThumbnailSwitchLifecycleTests delayed-completion test no longer fails deterministically
      result: pass
      notes: Fixed by f11a129 (KRMA-712), which clears the edited-thumbnail revision marker on edits and fences late completions.
  checks_run:
    - "swift test --filter ThumbnailSwitchLifecycleTests: 17 tests, 0 failures"
  findings: []
  fixes: []
  verification_commits:
    - f11a129
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T21:49:56.414Z
  session: 01MUN7LIPZ5RBFCOA6
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-29T19:24:08.058Z
updated: 2026-09-29T21:49:56.416Z
blockers: []
order: a0
board: product
commits:
  - f11a129
---

## Objective

ThumbnailSwitchLifecycleTests delayed-completion test fails deterministically

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-29T21:49:17.409Z

Verified the reported deterministic failure is resolved by KRMA-712 (commit f11a129), which clears the edited-thumbnail revision marker immediately on document edits and fences late completions. Validation on the current tree: ThumbnailSwitchLifecycleTests passed 17/17; testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument passed three additional consecutive runs. No additional source changes were required for KRMA-723.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T21:49:56.414Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] ThumbnailSwitchLifecycleTests delayed-completion test no longer fails deterministically (pass) — Fixed by f11a129 (KRMA-712), which clears the edited-thumbnail revision marker on edits and fences late completions.
Checks run:
- swift test --filter ThumbnailSwitchLifecycleTests: 17 tests, 0 failures
Findings:
- None
Fixes:
- None
Verification commits:
- f11a129
Actor: claude
Resolved model: sonnet
Pickup session: 01MUN7LIPZ5RBFCOA6
Summary: Verified: the deterministic failure was fixed by KRMA-712 (f11a129); ThumbnailSwitchLifecycleTests pass 17/17.
