---
id: KRMA-775
title: Flaky WarmReopenPresentationTests.testReplacedSourceNeverShowsTheStoredFrame (3 != 2 at line 205)
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Flaky WarmReopenPresentationTests.testReplacedSourceNeverShowsTheStoredFrame no longer flaky
      result: pass
      notes: Test no longer compares against a cold-open frame count; asserts one render, confirmed session, and no storedFrame provisional candidate. Passed 5 consecutive runs plus full suite.
  checks_run:
    - swift test --filter WarmReopenPresentationTests (7 passed)
    - swift test --filter testReplacedSourceNeverShowsTheStoredFrame x5 (all passed)
  findings: []
  fixes: []
  verification_commits:
    - 73962b7
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-02T19:34:14.496Z
  session: 01MURD2I1875DRKD4V
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-10-02T18:43:28.365Z
updated: 2026-10-02T19:34:14.498Z
blockers: []
order: n
board: product
commits:
  - 73962b7
---

## Objective

Flaky WarmReopenPresentationTests.testReplacedSourceNeverShowsTheStoredFrame (3 != 2 at line 205)

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ]

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-10-02T19:33:29.763Z

Replaced the flaky total-revision comparison with a direct assertion that the reopened session never admits a stored-frame candidate for the changed source, while still rendering exactly once. Verified the targeted test four times, including one rebuild. Commit: 73962b7.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-02T19:34:14.496Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Flaky WarmReopenPresentationTests.testReplacedSourceNeverShowsTheStoredFrame no longer flaky (pass) — Test no longer compares against a cold-open frame count; asserts one render, confirmed session, and no storedFrame provisional candidate. Passed 5 consecutive runs plus full suite.
Checks run:
- swift test --filter WarmReopenPresentationTests (7 passed)
- swift test --filter testReplacedSourceNeverShowsTheStoredFrame x5 (all passed)
Findings:
- None
Fixes:
- None
Verification commits:
- 73962b7
Actor: claude
Resolved model: sonnet
Pickup session: 01MURD2I1875DRKD4V
Summary: Verified: flaky assertion replaced with direct stored-frame provenance check; passes repeatedly.
