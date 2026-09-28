---
id: KRMA-688
title: ThumbnailSwitchLifecycleTests is flaky under the fast parallel test lane
type: bug
status: backlog
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-28T20:35:05.136Z
updated: 2026-09-28T20:35:05.136Z
blockers: []
order: zzzv
board: product
parent: KRMA-687
---

## Objective

Make `ThumbnailSwitchLifecycleTests` reliable under `scripts/ci-tests.sh fast` (`swift test --parallel`).

## Context

Found during KRMA-687 verification. Two separate `swift test --parallel` runs of the required
`fast` lane each failed exactly one test in this suite, but a different test each time:
`testComparisonRequestsShareFitGeometryAcrossThumbnailDrivenOrientations` failed once (mismatched
virtual source bounds), `testFilmstripAndGridPublishCropAwareSettledThumbnails` failed once
(pixel-buffer mismatch). Both pass cleanly every time when run standalone with `swift test --filter`.
This points to shared/contended state (timing, a shared resource, or scheduler-dependent ordering)
that only surfaces when the suite runs concurrently with the rest of the fast lane — unrelated to
KRMA-687's `InspectorDisclosure`/`FitsProposedWidth` changes, which this test file does not touch.

## Acceptance criteria

- [ ] Identify the source of the parallel-only flakiness (shared mutable state, timing assumption, or
      resource contention) in `ThumbnailSwitchLifecycleTests`.
- [ ] `scripts/ci-tests.sh fast` passes this suite reliably across several consecutive runs.

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
