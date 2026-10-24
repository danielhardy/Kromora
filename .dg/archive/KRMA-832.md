---
id: KRMA-832
title: Remove obsolete mosaic aspect projection from square Library grid
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Remove unused aspect fields and mosaic-specific projection invalidation without changing thumbnail arrival, metadata observation, filtering, selection, or paging.
      result: pass
      notes: ThumbnailEntry and CollectionProjection now carry only identity/index projection data. Metadata dimensions apply to the item without invalidating the collection projection; regression coverage confirms cached entry identity/index stay stable.
    - criterion: Update stale mosaic comments and replace grid geometry assertions that inspect per-photo aspect ratios with assertions relevant to the square layout; retain presented-ratio model coverage where other consumers still need it.
      result: pass
      notes: Mosaic-specific comments and aspect-dependent entry assertions are removed. Presented aspect ratio crop/rotation model coverage remains.
    - criterion: Run focused grid, collection projection, metadata, and package browsing tests.
      result: pass
      notes: Focused test selection passed all 70 executed tests; two retired legacy scanner tests were skipped.
  checks_run:
    - "Focused swift test selection for LibraryGridTests, CollectionProjectionPerformanceTests, LibraryScanTests, LibraryBrowsingProjectionTests, and LibraryBrowsingCoordinatorTests: exit 0; 70 tests, 0 failures, 2 retired legacy scanner tests skipped."
    - "git diff --check: exit 0."
  findings: []
  fixes:
    - Added regression assertions that deferred metadata completion preserves projection rebuild count and entry identity/index.
    - Updated the stale LibraryGridTests comment to describe presented geometry without metadata-driven mosaic reflow.
  verification_commits:
    - 489225fc
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T14:41:36.318Z
  session: 01MV3XJPN1WYUGI5LX
creation_provenance:
  runner: codex
  model: gpt-6-sol
  actor: codex
labels:
  - verification
created: 2026-10-08T15:58:33.161Z
updated: 2026-10-11T14:41:36.322Z
parent: KRMA-828
blockers: []
order: y
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T14:37:45.948Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 489225fc
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

- 2026-10-11T14:41:36.318Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Remove unused aspect fields and mosaic-specific projection invalidation without changing thumbnail arrival, metadata observation, filtering, selection, or paging. (pass) — ThumbnailEntry and CollectionProjection now carry only identity/index projection data. Metadata dimensions apply to the item without invalidating the collection projection; regression coverage confirms cached entry identity/index stay stable.
- [x] Update stale mosaic comments and replace grid geometry assertions that inspect per-photo aspect ratios with assertions relevant to the square layout; retain presented-ratio model coverage where other consumers still need it. (pass) — Mosaic-specific comments and aspect-dependent entry assertions are removed. Presented aspect ratio crop/rotation model coverage remains.
- [x] Run focused grid, collection projection, metadata, and package browsing tests. (pass) — Focused test selection passed all 70 executed tests; two retired legacy scanner tests were skipped.
Checks run:
- Focused swift test selection for LibraryGridTests, CollectionProjectionPerformanceTests, LibraryScanTests, LibraryBrowsingProjectionTests, and LibraryBrowsingCoordinatorTests: exit 0; 70 tests, 0 failures, 2 retired legacy scanner tests skipped.
- git diff --check: exit 0.
Findings:
- None
Fixes:
- Added regression assertions that deferred metadata completion preserves projection rebuild count and entry identity/index.
- Updated the stale LibraryGridTests comment to describe presented geometry without metadata-driven mosaic reflow.
Verification commits:
- 489225fc
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV3XJPN1WYUGI5LX
Summary: Verified KRMA-832; focused grid, projection, metadata, and package browsing checks passed.
