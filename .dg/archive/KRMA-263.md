---
id: KRMA-263
title: Two-phase relink with predicate pushdown
type: task
status: done
priority: low
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Moved-file relink resolves through the source-path predicate without invoking the fallback scan
      result: pass
    - criterion: Bookmark relink still works when the path differs
      result: pass
    - criterion: No behavior change for the hit path
      result: pass
  checks_run:
    - swift test --filter EditDocumentStoreTests (16 passed, 0 failures)
    - dg validate (OK; existing unknown pickup-model warning)
    - "macOS 14 deployment target verified; SwiftData #Index is unavailable, so no schema index was added"
  findings: []
  fixes: []
  verification_commits:
    - 0efe410
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T17:11:43.096Z
  session: 01MTUCTVXBEAO7NNNT
labels:
  - persistence
created: 2026-09-07T01:10:27.518Z
updated: 2026-09-10T12:53:51.702Z
depends_on:
  - KRMA-244
order: x7h
board: product
commits:
  - 0efe410
---

## Objective

Stop scanning the whole table on every unedited-photo open: push the common path-match into
SQLite and reserve the full scan for bookmark resolution.

## Context

KRMA-257 removed the blob decode from the relink scan (`propertiesToFetch`), but
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

## Agent log

- 2026-09-09T17:11:43.096Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Moved-file relink resolves through the source-path predicate without invoking the fallback scan (pass)
- [x] Bookmark relink still works when the path differs (pass)
- [x] No behavior change for the hit path (pass)
Checks run:
- swift test --filter EditDocumentStoreTests (16 passed, 0 failures)
- dg validate (OK; existing unknown pickup-model warning)
- macOS 14 deployment target verified; SwiftData #Index is unavailable, so no schema index was added
Findings:
- None
Fixes:
- None
Verification commits:
- 0efe410
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTUCTVXBEAO7NNNT
Summary: Implemented two-phase relink: exact canonical sourcePath lookup with fetchLimit 1, bookmark-only fallback scan, and regression coverage. #Index is unavailable for the macOS 14 deployment target, so the predicate remains the materialization-avoidance mechanism.
