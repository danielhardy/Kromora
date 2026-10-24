---
id: KRMA-712
title: Fix testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument thumbnail-order failure
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument no longer fails
      result: pass
      notes: 32 tests, 0 failures.
  checks_run:
    - "swift test --filter EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests: 32 passed"
  findings:
    - "Note (non-blocking): invalidateWork now clears the edited-thumbnail revision on every call, including navigation away, so the Library thumbnail may briefly fit instead of fill until the replacement renders."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T20:08:51.032Z
  session: 01MUN3ZCEKQ1USB7OK
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-29T04:28:32.863Z
updated: 2026-09-29T20:08:51.034Z
parent: KRMA-710
blockers: []
order: a0
board: product
---

## Objective

Fix testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument thumbnail-order failure

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-29T20:08:01.212Z

Implemented immediate active-thumbnail invalidation on document edits. Late completions are generation-fenced, stale revision markers are cleared while the current bitmap remains visible, and the settled request renders the latest document. Verified: the reported lifecycle regression and all EditedThumbnailCoordinatorTests pass (16 tests total). Commit: f11a129.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

Found during KRMA-710 verification. ThumbnailSwitchLifecycleTests.testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument fails at lines 824 and 833: a late thumbnail publishes for an obsolete document revision (exposure 0.25 vs expected 0.75). Not touched by KRMA-710; likely related to KRMA-709 (edited thumbnail refresh).

- 2026-09-29T20:08:51.032Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument no longer fails (pass) — 32 tests, 0 failures.
Checks run:
- swift test --filter EditedThumbnailCoordinatorTests|ThumbnailSwitchLifecycleTests: 32 passed
Findings:
- Note (non-blocking): invalidateWork now clears the edited-thumbnail revision on every call, including navigation away, so the Library thumbnail may briefly fit instead of fill until the replacement renders.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUN3ZCEKQ1USB7OK
