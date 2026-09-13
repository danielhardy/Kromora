---
id: KRMA-415
title: "Phase 4.5: low-priority maintenance — packed-thumbnail and revision compaction"
type: feature
status: ready
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - backup
  - recovery
  - performance
created: 2026-09-12T19:44:27.380Z
updated: 2026-09-13T04:44:03.811Z
depends_on:
  - KRMA-392
  - KRMA-389
order: zzzzzv
board: product
---

## Objective

Implement low-priority maintenance: immutable-revision-safe compaction and packed-thumbnail
compaction (per KRMA-389's packed-thumbnail decision), running as background scheduler work that
never turns a rebuildable artifact into an integrity failure.

## Dependencies

- KRMA-392 (scheduler lanes — compaction runs as background package I/O through the existing
  scheduler, not a new mechanism).
- KRMA-389 (the packed-thumbnail-or-rejected decision this compaction work implements against).

## Scope

- If KRMA-389 recommended packed thumbnails, implement compaction for the packed-thumbnail shards:
  reclaiming space from stale/deleted entries without data loss or dangling offsets, running as
  low-priority background maintenance.
- Implement compaction/pruning for old immutable edit revisions where a retention policy applies
  (e.g. collapsing very old superseded revisions), without ever discarding the current/latest
  revision or violating the immutable-revision guarantee for revisions still referenced.
- All maintenance work must run through `ImageWorkScheduler`'s package I/O lanes (KRMA-392) at low
  priority, yielding to editor-visible work.
- Treat every compacted/maintained artifact here as rebuildable-tier, never critical — a
  maintenance failure must be logged and retried, never surfaced as a data-loss integrity failure
  (that classification is KRMA-393's validation ticket's job).

## Acceptance criteria

- [ ] Packed-thumbnail compaction (if applicable per the KRMA-389 decision) reclaims space from
  stale/deleted entries with no data loss or dangling offsets, verified by test.
- [ ] Edit-revision compaction never discards the current revision or a still-referenced revision.
- [ ] Maintenance runs through `ImageWorkScheduler`'s package I/O lanes at low priority and yields to
  editor-visible work under contention.
- [ ] A failed or interrupted maintenance pass is retried and never reported as a critical/data-loss
  failure.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Compaction/unit lane with injected stale/deleted entries and interrupted maintenance runs, plus a
scheduler-fairness check under simultaneous editor activity.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/AUTO_PERFORMANCE.md
- context.issues: KRMA-393, KRMA-392, KRMA-389
