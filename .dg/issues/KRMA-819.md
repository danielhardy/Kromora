---
id: KRMA-819
title: Preserve existing derived Look when replacement fails
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A failed or interrupted replacement leaves the existing destination file intact.
      result: pass
      notes: Regression test covers failure; staging cleaned up.
    - criterion: A successful replacement publishes a complete .cube file at the selected destination.
      result: pass
      notes: rename(2) of fully copied staging file.
    - criterion: Compatible with macOS 26+ and no-dependency policy.
      result: pass
  checks_run:
    - swift test --filter DeriveCoordinatorTests (13 passed)
    - git diff --check (clean)
  findings:
    - "Non-blocking: hidden sibling staging file may be denied under App Sandbox when only the chosen file is granted; tracked in KRMA-823."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-05T14:37:03.746Z
  session: 01MUVCRX5MB3COO0ET
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - appstore
created: 2026-10-04T16:26:15.413Z
updated: 2026-10-05T14:37:03.750Z
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-05T14:36:20.103Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Make replacing a saved derived Look preserve the current destination until the complete replacement
is ready to publish.

## Context

DeriveCoordinator.performSave removes an existing destination before copying the generated .cube
scratch file into place. If the copy fails or is interrupted, the user's previous Look is already
gone. This is separate from the selected-output security-scope ownership tracked by KRMA-818.

## Acceptance criteria

- [ ] A failed or interrupted replacement leaves the existing destination file intact.
- [ ] A successful replacement publishes a complete .cube file at the selected destination.
- [ ] The implementation remains compatible with macOS 26+ and the existing no-dependency policy.

## Implementation notes

Use a staging file in the destination directory, then atomically publish it after the copy/write
finishes. Keep the output-scope work in KRMA-818.

### Comment — codex @ 2026-10-05T14:36:17.278Z

Implemented destination-directory staging and atomic rename for derived Look saves; added a failure regression test proving the old destination survives and staging is cleaned up. Verification: DeriveCoordinatorTests (13 passed), deterministic fast lane (1,535 tests, exit 0), git diff --check. Commit 59f9039f.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-05T14:37:03.746Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A failed or interrupted replacement leaves the existing destination file intact. (pass) — Regression test covers failure; staging cleaned up.
- [x] A successful replacement publishes a complete .cube file at the selected destination. (pass) — rename(2) of fully copied staging file.
- [x] Compatible with macOS 26+ and no-dependency policy. (pass)
Checks run:
- swift test --filter DeriveCoordinatorTests (13 passed)
- git diff --check (clean)
Findings:
- Non-blocking: hidden sibling staging file may be denied under App Sandbox when only the chosen file is granted; tracked in KRMA-823.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUVCRX5MB3COO0ET
Summary: Verified: atomic staged replace preserves existing destination on failure; 13 DeriveCoordinatorTests pass; follow-up KRMA-823 for sandbox check.
