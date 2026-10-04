---
id: KRMA-814
title: Add a keyboard shortcut for applying Auto edits
type: task
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
created: 2026-10-04T02:34:50.644Z
updated: 2026-10-04T02:35:02.509Z
blockers: []
order: zzzzzzzq
board: product
---

## Objective

Expose the existing Auto edit operation as a keyboard command so users can apply automatic adjustments without leaving the keyboard workflow.

## Acceptance criteria

- Add a keyboard command that invokes the existing Auto edit behavior for the active photo; do not introduce new adjustment semantics.
- Choose and document a discoverable shortcut (consider `A` or `Shift+A`) after checking for conflicts and following macOS keyboard conventions.
- Include the command and shortcut in the app’s existing keyboard shortcut reference so users can discover it.
- Add or update focused coverage for command routing and shortcut discoverability.
