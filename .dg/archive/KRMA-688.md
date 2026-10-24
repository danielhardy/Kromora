---
id: KRMA-688
title: ThumbnailSwitchLifecycleTests is flaky under the fast parallel test lane
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Identify the source of the parallel-only flakiness in ThumbnailSwitchLifecycleTests.
      result: pass
      notes: "Root cause confirmed: stale PreviewSurface frames from a prior asset could satisfy image != nil checks before the current asset's render had actually been requested, and an exact-byte pixel comparison did not allow for Core Image's documented ~0.0003% one-byte rounding variation between renders."
    - criterion: scripts/ci-tests.sh fast passes this suite reliably across several consecutive runs.
      result: pass
      notes: Ran the isolated ThumbnailSwitchLifecycleTests filter with swift test --parallel 3 consecutive times (exit 0 each) and the full required scripts/ci-tests.sh fast lane 2 consecutive times (1331/1331 passing, exit 0 each), combined with the implementer's 3 prior consecutive fast-lane passes.
  checks_run:
    - swift build
    - swift test --parallel --filter ThumbnailSwitchLifecycleTests (x3, all exit 0)
    - scripts/ci-tests.sh fast (x2, 1331/1331 passing, exit 0 each)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T21:29:36.214Z
  session: 01MULR9KZAFSRUNY53
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-28T20:35:05.136Z
updated: 2026-09-28T21:29:36.216Z
parent: KRMA-687
blockers: []
order: a0
board: product
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

### Comment — codex @ 2026-09-28T21:24:18.130Z

Identified parallel-only failures as stale PreviewSurface frames being mistaken for the selected asset, plus an exact-byte assertion that ignored documented one-byte Core Image variation. Synchronization now follows current-asset render requests before checking request geometry, and pixel comparisons use tolerance 1. Focused tests passed; scripts/ci-tests.sh fast passed three consecutive runs (1,331 tests each). Commit: fc3bb17.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-28T21:29:36.214Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Identify the source of the parallel-only flakiness in ThumbnailSwitchLifecycleTests. (pass) — Root cause confirmed: stale PreviewSurface frames from a prior asset could satisfy image != nil checks before the current asset's render had actually been requested, and an exact-byte pixel comparison did not allow for Core Image's documented ~0.0003% one-byte rounding variation between renders.
- [x] scripts/ci-tests.sh fast passes this suite reliably across several consecutive runs. (pass) — Ran the isolated ThumbnailSwitchLifecycleTests filter with swift test --parallel 3 consecutive times (exit 0 each) and the full required scripts/ci-tests.sh fast lane 2 consecutive times (1331/1331 passing, exit 0 each), combined with the implementer's 3 prior consecutive fast-lane passes.
Checks run:
- swift build
- swift test --parallel --filter ThumbnailSwitchLifecycleTests (x3, all exit 0)
- scripts/ci-tests.sh fast (x2, 1331/1331 passing, exit 0 each)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULR9KZAFSRUNY53
Summary: Verified: parallel-only ThumbnailSwitchLifecycleTests flakiness fix (fc3bb17) confirmed stable across repeated fast-lane runs; no further findings.
