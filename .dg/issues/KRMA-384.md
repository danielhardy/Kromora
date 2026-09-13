---
id: KRMA-384
title: Track the portable library package implementation plan
type: task
status: blocked
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
updated: 2026-09-12T19:23:20.577Z
order: a0
board: product
blocked_reason: The package plan requires human approval of the current EditStore data disposition and the local-only package and compatibility policy before identity or persistence implementation can begin.
blocked_action: Approve ADR-001, or specify the migration/disposition for current library data and any changes to the local-only compatibility boundary; then resume KRMA-384.
blocked_from_status: claimed
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

### Comment — codex @ 2026-09-12T19:23:16.543Z

Reviewed docs/LIBRARY_PACKAGE_PLAN.md and recorded ADR-001. Created the phased implementation issues KRMA-389 through KRMA-393 with explicit dependencies, acceptance criteria, and verification lanes. Updated the plan tracking line. No source, deletion behavior, or current library data was changed.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
