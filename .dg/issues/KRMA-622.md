---
id: KRMA-622
title: Add scheduled package backups and crash-edit recovery
type: feature
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - professional-polish
  - evaluation-2026-09
created: 2026-09-26T13:56:45.677Z
updated: 2026-09-26T13:56:46.019Z
blockers: []
order: zw
board: product
---

## Objective

Protect irreplaceable edits from package loss, failed upgrades, and interrupted writes.

## Context

Portable package backup/restore and termination-flush persistence exist; this ticket closes automation and abandoned-snapshot recovery gaps.

Derived from §12 Stability, data safety, and trust in `.context/2026-09-22-professional-polish-evaluation.md`. The evaluation is a gap analysis rather than a sequencing decision, so this remains a backlog candidate until product scope is selected.

## Acceptance criteria

- [ ] Create scheduled package snapshots with retention controls and backup-before-upgrade behavior.
- [ ] Allow a chosen off-volume backup target and provide a dry-run restore summary before applying it.
- [ ] Recover abandoned edit journals on relaunch and let users review restored edits per photo.
- [ ] Exercise interruption and restore behavior without modifying imported originals.

## Implementation notes

Preserve the existing non-destructive edit document, shared render graph, macOS 14 minimum, Swift 6 safety, portable package ownership, and zero third-party dependencies. Add focused regression coverage and update relevant product documentation as the feature is implemented.
