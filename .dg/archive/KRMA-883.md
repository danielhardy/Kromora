---
id: KRMA-883
title: "Library filter toolbar: summarize and clear all active filters"
type: task
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: When any Library query filter is active, the toolbar summary exposes active metadata facets, flag/rating filter, and search text accessibly and readably.
      result: pass
      notes: The query summary covers camera, lens, and location facets, flag, rating, and search text in stable order. Toolbar text has a full accessibility label; clear action is explicitly labeled.
    - criterion: One toolbar action resets the complete LibraryQuery filter state while preserving chosen sort and sidebar visibility.
      result: pass
      notes: clearingFilters() returns a clean query with the existing sort. The clear coordinator action leaves the per-window sidebar binding untouched; coordinator test verifies reset and no-op behavior.
    - criterion: Add generated-fixture tests for reset semantics and summary values where testable without UI.
      result: pass
      notes: LibraryFacetTests covers all summary dimensions and reset against generated query-controller rows; LibraryBrowsingCoordinatorTests covers complete reset and no-op behavior.
    - criterion: Keep query execution index-backed and selection behavior unchanged.
      result: pass
      notes: Clear reloads the browsing window through the existing index-backed library path and resynchronizes UUID-based selection. Existing selection and query controller tests pass.
  checks_run:
    - swift test --filter LibraryFacetTests|LibraryBrowsingCoordinatorTests — exit 0; 29 tests passed, 0 failures.
    - git diff --check f7995bc7^ f7995bc7 — passed.
    - Reviewed the toolbar, LibraryQuery summary/reset, coordinator reload, and selection synchronization paths; no security, maintainability, or performance blockers found.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T17:15:07.274Z
  session: 01MV4322BNP5W67EC4
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - library
  - filtering
  - verification
created: 2026-10-11T14:38:36.053Z
updated: 2026-10-24T13:04:50.559Z
blockers: []
order: n
board: product
---

## Objective

Make the Library toolbar summarize all active query filters and provide a single action to clear them.

## Context

KRMA-862 adds a toolbar summary and Clear action for camera/lens metadata facets. Existing flag/rating filtering and text search also live in the Library query, but are not included in that summary or cleared by that action. The acceptance criterion asks for active filters to be summarized and clearable in one action.

## Acceptance criteria

- [ ] When any Library query filter is active, the toolbar summary exposes the active metadata facets, flag/rating filter, and search text in an accessible, readable way.
- [ ] One toolbar action resets the complete LibraryQuery filter state while preserving the chosen sort and sidebar visibility.
- [ ] Add generated-fixture tests for reset semantics and summary values where they can be tested without UI.
- [ ] Keep query execution index-backed and selection behavior unchanged.

## Implementation notes

Parent: KRMA-862. Continue on the current branch and follow its verification findings.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-11T17:15:07.274Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] When any Library query filter is active, the toolbar summary exposes active metadata facets, flag/rating filter, and search text accessibly and readably. (pass) — The query summary covers camera, lens, and location facets, flag, rating, and search text in stable order. Toolbar text has a full accessibility label; clear action is explicitly labeled.
- [x] One toolbar action resets the complete LibraryQuery filter state while preserving chosen sort and sidebar visibility. (pass) — clearingFilters() returns a clean query with the existing sort. The clear coordinator action leaves the per-window sidebar binding untouched; coordinator test verifies reset and no-op behavior.
- [x] Add generated-fixture tests for reset semantics and summary values where testable without UI. (pass) — LibraryFacetTests covers all summary dimensions and reset against generated query-controller rows; LibraryBrowsingCoordinatorTests covers complete reset and no-op behavior.
- [x] Keep query execution index-backed and selection behavior unchanged. (pass) — Clear reloads the browsing window through the existing index-backed library path and resynchronizes UUID-based selection. Existing selection and query controller tests pass.
Checks run:
- swift test --filter LibraryFacetTests|LibraryBrowsingCoordinatorTests — exit 0; 29 tests passed, 0 failures.
- git diff --check f7995bc7^ f7995bc7 — passed.
- Reviewed the toolbar, LibraryQuery summary/reset, coordinator reload, and selection synchronization paths; no security, maintainability, or performance blockers found.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV4322BNP5W67EC4
Summary: Verified all-filter Library toolbar summary and clear action; focused tests pass.
