---
id: KRMA-881
title: "Library filters: focal length, ISO, aperture facets with resumable summary backfill"
type: feature
status: done
priority: medium
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Add focal length, ISO, and aperture numeric ranges to Library facet selection and filtering.
      result: pass
      notes: Range values are persisted, applied inclusively, and photos without metadata do not match an active range.
    - criterion: Populate capture settings in portable package summaries, including a resumable repair for older packages.
      result: pass
      notes: Repair processes one shard at a time, preserves concurrent summary fields, leaves unreadable or unprocessed fields as retry markers, and publishes repaired summaries to the index.
    - criterion: Expose the range facets in the Library sidebar and document the package summary fields.
      result: pass
  checks_run:
    - scripts/ci-tests.sh fast — passed (exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T17:32:18.120Z
  session: 01MV43M1M0YIAU8W4F
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - library
  - filtering
  - metadata
created: 2026-10-11T14:33:21.168Z
updated: 2026-10-11T17:32:18.124Z
depends_on:
  - KRMA-862
blockers: []
order: w
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T17:22:27.976Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Library filters: focal length, ISO, aperture facets with resumable summary backfill

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — claude @ 2026-10-11T14:33:29.496Z

Split from KRMA-862. Needs summary schema fields + resumable repair (pattern: presentedAspectRatio/sourceFingerprint), docs/LIBRARY_PACKAGE_FORMAT.md update, and range controls. Extend LibraryFacetSelection.

### Comment — claude @ 2026-10-11T17:22:24.515Z

Added captureSettings summary field, focal length/ISO/aperture range facets with sidebar sliders, and a resumable per-shard background backfill (also fills nil coarseLocation). Docs and tests updated; ci-tests fast passes.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-11T17:32:18.120Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Add focal length, ISO, and aperture numeric ranges to Library facet selection and filtering. (pass) — Range values are persisted, applied inclusively, and photos without metadata do not match an active range.
- [x] Populate capture settings in portable package summaries, including a resumable repair for older packages. (pass) — Repair processes one shard at a time, preserves concurrent summary fields, leaves unreadable or unprocessed fields as retry markers, and publishes repaired summaries to the index.
- [x] Expose the range facets in the Library sidebar and document the package summary fields. (pass)
Checks run:
- scripts/ci-tests.sh fast — passed (exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV43M1M0YIAU8W4F
Summary: Independent verification passed: range facets and resumable summary backfill reviewed; scripts/ci-tests.sh fast passed (exit 0). No findings or verification fixes.
