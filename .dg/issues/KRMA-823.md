---
id: KRMA-823
title: Verify derived Look staging file is writable under App Sandbox
type: task
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-10-05T14:36:57.941Z
updated: 2026-10-05T14:36:58.828Z
blockers: []
order: y3sf5omi
board: product
---

## Objective

Verify derived Look staging file is writable under App Sandbox

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
Context: KRMA-819 stages a hidden sibling file (.<name>.<uuid>.tmp) in the destination directory. NSSavePanel under the sandbox with files.user-selected.read-write grants access to the chosen file, not necessarily to creating siblings in its directory. Verify in the production sandboxed app (scripts/app-store-build.sh) that saving a derived Look to a folder outside the library folder succeeds. If it fails, stage via FileManager.replaceItemAt/NSItemReplacementDirectory instead. Acceptance: sandboxed save to a new and an existing destination both succeed.
