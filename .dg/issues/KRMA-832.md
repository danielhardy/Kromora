---
id: KRMA-832
title: Remove obsolete mosaic aspect projection from square Library grid
type: task
status: backlog
priority: low
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6-sol
  actor: codex
labels:
  - verification
parent: KRMA-828
created: 2026-10-08T15:58:33.161Z
updated: 2026-10-08T15:58:33.161Z
blockers: []
order: zh
board: product
---

## Objective

Remove mosaic-era aspect fields and invalidation work that the square Library grid no longer consumes.

## Context

`ImageCollection.ThumbnailEntry` still carries `aspectRatio` and `aspectResolved`, and
`CollectionProjection.Cache` computes them for every entry. The grid and filmstrip only consume
entry identity/index. `metadataAffectsMosaic` still invalidates the full projection after dimension
metadata arrives. Several comments and grid tests still describe aspect-dependent cell geometry.
The square layout introduced by KRMA-828 derives geometry solely from viewport width and item index.
This is a maintenance and avoidable projection-work finding, not a visible layout blocker.

## Acceptance criteria

- [ ] Remove unused aspect fields and mosaic-specific projection invalidation without changing
      thumbnail arrival, metadata observation, filtering, selection, or paging.
- [ ] Update stale mosaic comments and replace grid geometry assertions that inspect per-photo
      aspect ratios with assertions relevant to the square layout; retain presented-ratio model
      coverage where other consumers still need it.
- [ ] Run focused grid, collection projection, metadata, and package browsing tests.

## Implementation notes

Keep the cleanup scoped to internal projection data. Do not change durable presented-ratio repair,
package schema, or thumbnail pixel generation.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
