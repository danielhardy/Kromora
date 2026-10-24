---
id: KRMA-882
title: "Library filters: coarse on-device location facet with No location value"
type: feature
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Imported originals with valid GPS tags receive a one-degree coarse location cell in the package summary, with no precise coordinates stored in the index.
      result: pass
      notes: ImageMetadata computes the rounded cell locally and PortablePackageImporter stores it in the summary. Package format documentation states the stored precision and privacy behavior.
    - criterion: The Location facet distinguishes an asset with confirmed missing GPS (No location) from an unread or legacy asset (Unknown), and selected values filter correctly.
      result: pass
      notes: LibraryFacetTests cover counts and filtering for both values; legacy summaries decode with nil coarseLocation.
    - criterion: Location handling performs no reverse geocoding or network lookup.
      result: pass
      notes: Reviewed the metadata extraction/import path and documentation; no geocoder or network dependency is used.
    - criterion: Invalid GPS values do not crash coarse location extraction.
      result: pass
      notes: Added coordinate-range validation and fixture coverage for valid and out-of-range GPS values.
  checks_run:
    - swift test --filter LibraryFacetTests|PortablePackageImportTests — exit 0; 25 tests passed, 0 failures.
    - swift test --filter ImageLoadingTests/testMetadataRoundsValidGPSAndIgnoresOutOfRangeCoordinates|LibraryFacetTests|PortablePackageImportTests — exit 0; 26 tests passed, 0 failures.
    - Reviewed the implementation, import, facet, persistence/backfill, and package-format paths; no further correctness, maintainability, security, or performance findings.
  findings:
    - Malformed finite GPS coordinates outside legal latitude/longitude ranges could reach integer conversion during cell rounding. Fixed locally by rejecting out-of-range values before conversion.
  fixes:
    - Added latitude/longitude range validation for coarse-cell calculation and generated-JPEG coverage for valid rounding and out-of-range handling.
  verification_commits:
    - 25c04c85
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T17:25:08.423Z
  session: 01MV43CIH7DELEZ663
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - library
  - filtering
  - metadata
created: 2026-10-11T14:33:21.868Z
updated: 2026-10-24T13:04:50.512Z
blockers: []
order: t
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T17:14:20.196Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 25c04c85
---

## Objective

Library filters: coarse on-device location facet with No location value

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — claude @ 2026-10-11T14:33:29.730Z

Split from KRMA-862. Decide on-device-only reverse geocoding (or none), store coarse place in summary, document what is stored and that no network lookup occurs.

### Comment — claude @ 2026-10-11T17:14:20.614Z

Implemented in a25c9560: coarse one-degree location cell (ImageMetadata.coarseLocation -> PortablePackageAssetSummary.coarseLocation at import), Location facet with 'No location' value, no geocoder/network. Legacy assets (nil) show as 'Unknown' until read; no backfill yet — follow-up candidate. Docs in LIBRARY_PACKAGE_FORMAT.md; tests in LibraryFacetTests (LibraryFacetTests + import tests pass).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-11T17:25:08.423Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Imported originals with valid GPS tags receive a one-degree coarse location cell in the package summary, with no precise coordinates stored in the index. (pass) — ImageMetadata computes the rounded cell locally and PortablePackageImporter stores it in the summary. Package format documentation states the stored precision and privacy behavior.
- [x] The Location facet distinguishes an asset with confirmed missing GPS (No location) from an unread or legacy asset (Unknown), and selected values filter correctly. (pass) — LibraryFacetTests cover counts and filtering for both values; legacy summaries decode with nil coarseLocation.
- [x] Location handling performs no reverse geocoding or network lookup. (pass) — Reviewed the metadata extraction/import path and documentation; no geocoder or network dependency is used.
- [x] Invalid GPS values do not crash coarse location extraction. (pass) — Added coordinate-range validation and fixture coverage for valid and out-of-range GPS values.
Checks run:
- swift test --filter LibraryFacetTests|PortablePackageImportTests — exit 0; 25 tests passed, 0 failures.
- swift test --filter ImageLoadingTests/testMetadataRoundsValidGPSAndIgnoresOutOfRangeCoordinates|LibraryFacetTests|PortablePackageImportTests — exit 0; 26 tests passed, 0 failures.
- Reviewed the implementation, import, facet, persistence/backfill, and package-format paths; no further correctness, maintainability, security, or performance findings.
Findings:
- Malformed finite GPS coordinates outside legal latitude/longitude ranges could reach integer conversion during cell rounding. Fixed locally by rejecting out-of-range values before conversion.
Fixes:
- Added latitude/longitude range validation for coarse-cell calculation and generated-JPEG coverage for valid rounding and out-of-range handling.
Verification commits:
- 25c04c85
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV43CIH7DELEZ663
Summary: Verified coarse location facet and no-location handling; rejected invalid GPS ranges to prevent import-time conversion traps.
