---
id: KRMA-990
title: "Library grid: bound row-model work at full-library scale"
type: task
status: backlog
priority: medium
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
parent: KRMA-951
created: 2026-10-13T23:31:30.531Z
updated: 2026-10-13T23:31:30.531Z
blockers: []
order: zzzzzzv
board: product
---

## Objective

Keep Library grid scrolling and re-entry work bounded for full-library collections.

## Context

KRMA-951 coarsens scroll updates and gives rows stable identity, while keeping the existing data paging model. `LibraryGridView.body` currently calls `GridRow.rows(...)`, which eagerly constructs row models for every current thumbnail entry on each body update. `LazyVStack` virtualizes hosted views, but it does not bound this row-model construction. At large collection sizes, scrolling through many row crossings can repeat full-collection work. A full-library virtualized scroller was explicitly out of scope for KRMA-951.

## Acceptance criteria

- [ ] Row-model creation and scroll-time work are bounded to the visible and prefetch windows as collection size grows.
- [ ] A deterministic synthetic test with at least 10,000 generated items verifies the row-model work bound across a scripted scroll.
- [ ] Stable asset identity, scroll continuity, selection, keyboard navigation, shift-click, drag, thumbnail demand, and existing paging behavior remain intact.
- [ ] Existing Library grid tests pass and `swift build` remains warning-free.

## Implementation notes

Keep package query/window ownership unchanged unless the bounded-work design requires a separately reviewed change.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
