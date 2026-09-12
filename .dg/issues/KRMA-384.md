---
id: KRMA-384
title: Track the portable library package implementation plan
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - library
  - architecture
  - documentation
created: 2026-09-12T15:25:59.782Z
updated: 2026-09-12T15:25:59.782Z
order: zzq
board: product
---

## Objective

Track and eventually implement the portable, self-contained library package described in
`docs/LIBRARY_PACKAGE_PLAN.md`.

## Context

The plan is a documentation-only proposal for a future identity, package-format, indexing, and
runtime architecture. No current source change implements it, and it must not be bundled with the
unrelated KRMA-371 Library deletion workflow. Keep the plan as the design input for a separately
sequenced implementation effort.

## Acceptance criteria

- [ ] Review and approve the package format, identity, migration, and performance assumptions.
- [ ] Break the plan into implementation issues with explicit dependencies and verification lanes.
- [ ] Implement the approved phases without changing current deletion behavior or silently
  discarding existing library data.
- [ ] Update or retire the plan as each phase lands.

## Implementation notes

- Source plan: `docs/LIBRARY_PACKAGE_PLAN.md`.
- iCloud sync and current-user-data migration are explicitly out of scope in the plan and require
  separate decisions before implementation.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
