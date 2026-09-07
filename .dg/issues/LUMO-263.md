---
id: LUMO-263
title: Two-phase relink with predicate pushdown
type: task
status: ready
priority: low
labels:
  - persistence
created: 2026-09-07T01:10:27.518Z
updated: 2026-09-07T04:14:23.439Z
depends_on:
  - LUMO-244
order: x3
board: product
---

## Objective

Stop scanning the whole table on every unedited-photo open: push the common path-match into
SQLite and reserve the full scan for bookmark resolution.

## Context

LUMO-257 removed the blob decode from the relink scan (`propertiesToFetch`), but
`fetchRecordsForRelinking` still materializes one row per saved photo on every miss — the
exact O(catalog) shape the epic's own benchmark motivation argues against, now growing one
row per edit instead of bytes per edit.

The overwhelmingly common relink is a moved file whose canonical path matches
`record.sourcePath` exactly — expressible as a `#Predicate`, no row materialization needed.

## Work

- Two-phase lookup on the miss path: (1) `FetchDescriptor` with
  `#Predicate { $0.sourcePath == canonical }`, fetchLimit 1; (2) only on miss, the current
  `propertiesToFetch` scan for bookmark matching.
- Add a `#Index` on `sourcePath` (verify availability under the macOS 14 deployment target;
  if unavailable, note that the predicate alone still avoids materialization).
- Keep the bookmark fallback semantics byte-identical; `matches(_:url:)` stays the arbiter for
  phase 2.

## Acceptance criteria

- [ ] Moved-file relink resolves via the indexed path predicate (assert with a test that fails
      if the phase-1 fetch is removed — e.g. counting phase-2 invocations through a seam, or
      equivalent).
- [ ] Bookmark relink still works when the path differs (existing
      `testMovedFileRelinksByBookmarkAndRekeysTheRecord` passes unchanged in spirit).
- [ ] No behavior change for the hit path.
