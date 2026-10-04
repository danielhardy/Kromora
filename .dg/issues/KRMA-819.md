---
id: KRMA-819
title: Preserve existing derived Look when replacement fails
type: task
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - appstore
created: 2026-10-04T16:26:15.413Z
updated: 2026-10-04T16:26:15.413Z
blockers: []
order: zzzzzzzv
board: product
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

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
