---
id: KRMA-880
title: "Library filters: capture-date range facet (store sortable ISO date in index summary)"
type: feature
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Store a sortable ISO capture date in package index summaries at import and through resumable legacy backfill.
      result: pass
      notes: Import and backfill paths populate captureDateISO; missing dates use an empty value and unread summaries remain eligible for repair.
    - criterion: Provide an inclusive whole-day capture-date range facet with date-picker controls and correct bounds/counts.
      result: pass
      notes: Facet queries include both endpoints and exclude empty or unread dates.
    - criterion: Accept only valid capture dates for date-range filtering.
      result: pass
      notes: Verification found malformed and impossible dates were accepted; parser and day conversion now validate separators and Gregorian calendar days.
  checks_run:
    - swift test --filter LibraryFacetTests (20 tests passed)
    - swift test --filter CaptureMetadataBackfillTests (2 tests passed)
    - git diff --check (passed)
  findings:
    - "Fixed: sortable capture-date parsing accepted impossible calendar dates and malformed separators, which could place invalid metadata in date filters."
  fixes:
    - Validated EXIF date shape, time fields, and Gregorian month/day ranges; reject malformed ISO day values before range conversion (commit 7de20eede7cdefe104c070e6a944bd3e9b08c75f).
  verification_commits:
    - "68294151"
    - 7de20eede7cdefe104c070e6a944bd3e9b08c75f
    - 7de20eed
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T17:34:57.211Z
  session: 01MV43QZJRB4WPOGI2
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - library
  - filtering
  - metadata
created: 2026-10-11T14:33:20.468Z
updated: 2026-10-11T17:34:57.214Z
depends_on:
  - KRMA-862
blockers: []
order: y
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T17:29:52.695Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 7de20eed
  - "68294151"
  - 7de20eede7cdefe104c070e6a944bd3e9b08c75f
---

## Objective

Library filters: capture-date range facet (store sortable ISO date in index summary)

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — claude @ 2026-10-11T14:33:28.634Z

Split from KRMA-862. PortablePackageAssetSummary.captureDate is a locale-formatted display string (DateFormatter .medium/.short), not safely range-comparable. Needs a sortable ISO-8601 field with resumable backfill, then a date-range facet on LibraryFacetSelection.

### Comment — claude @ 2026-10-11T17:29:49.039Z

Added PortablePackageAssetSummary.captureDateISO (sortable local ISO-8601, empty = read/no date), filled at import and by the existing resumable capture-metadata backfill. Date range facet (.captureDate, day-number ranges) in LibraryFacetSelection with DatePicker UI, counts/bounds, and tests; format doc updated.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-11T17:34:57.211Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Store a sortable ISO capture date in package index summaries at import and through resumable legacy backfill. (pass) — Import and backfill paths populate captureDateISO; missing dates use an empty value and unread summaries remain eligible for repair.
- [x] Provide an inclusive whole-day capture-date range facet with date-picker controls and correct bounds/counts. (pass) — Facet queries include both endpoints and exclude empty or unread dates.
- [x] Accept only valid capture dates for date-range filtering. (pass) — Verification found malformed and impossible dates were accepted; parser and day conversion now validate separators and Gregorian calendar days.
Checks run:
- swift test --filter LibraryFacetTests (20 tests passed)
- swift test --filter CaptureMetadataBackfillTests (2 tests passed)
- git diff --check (passed)
Findings:
- Fixed: sortable capture-date parsing accepted impossible calendar dates and malformed separators, which could place invalid metadata in date filters.
Fixes:
- Validated EXIF date shape, time fields, and Gregorian month/day ranges; reject malformed ISO day values before range conversion (commit 7de20eede7cdefe104c070e6a944bd3e9b08c75f).
Verification commits:
- 68294151
- 7de20eede7cdefe104c070e6a944bd3e9b08c75f
- 7de20eed
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV43QZJRB4WPOGI2
Summary: Verification passed: capture-date facet, strict date validation, and resumable backfill verified.
