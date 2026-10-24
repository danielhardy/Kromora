---
id: KRMA-751
title: Deflake EmbeddedFirstFrameTests after KRMA-743 deferred source load
type: bug
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: EmbeddedFirstFrameTests pass 10/10 under the CPU-load repro.
      result: pass
      notes: 10 consecutive runs with 2x ncpu busy processes; 4 tests pass, 1 opt-in real-RAW test skipped by design, 0 failures.
    - criterion: scripts/ci-tests.sh fast passes.
      result: pass
      notes: Ran twice, exit 0.
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast (x2)
    - swift test --skip-build --filter EmbeddedFirstFrameTests x10 under 2x ncpu CPU load
  findings:
    - "info: the default OriginalThumbnailLoader closure is duplicated in ImageCollection.init, AppViewModel.init and the test helper. Minor; mirrors the existing embeddedFirstFrameProvider pattern. Not worth a ticket."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-01T22:58:49.901Z
  session: 01MUQ4Q9GASS3BIB5Z
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - reliability
  - testing
created: 2026-10-01T21:06:39.529Z
updated: 2026-10-01T22:58:49.904Z
parent: KRMA-734
blockers: []
order: a0
board: product
---

## Objective

Make the fast lane deterministic again for `EmbeddedFirstFrameTests` after KRMA-743 moved `beginLoad` one `Task.yield()` after `load()`.

## Evidence (KRMA-734 verification)

- `scripts/ci-tests.sh fast` failed in two consecutive full runs at HEAD 1145f266 plus verification fix b83a4cd9: `testEmbeddedFirstFrameProvisionalThenSettled` (EmbeddedFirstFrameTests.swift:112, :120) and once `testRendererFailureKeepsTheSelectedAssetsProvisionalThumbnail` (:184).
- Reproduces in isolation under CPU load (`yes` x 2*ncpu): 2 of 3 runs fail. The pre-743 baseline bc473576 passes 4 of 4 under the same load; cd21acc7 (KRMA-743) is the first bad commit (bisected).
- Diagnosis: the presentation session reports `candidateSource = originalThumbnail` (16x12, no native presentation extent, `sourceImage == nil`). The collection's real background thumbnail loader now finishes before the deferred `beginLoad` runs, so `beginLoad` presents the original thumbnail as the candidate and the embedded-JPEG first frame is rejected by the `candidateSource == nil` guard (and the second test's seeded 3x2 thumbnail is replaced by the loader's 16x12). Before 743, `beginLoad` ran synchronously inside the selection, before the loader could win.

## Work

Make the outcome deterministic: inject or suppress the thumbnail generator in these tests (a thumbnail provider seam on the collection, as `embeddedFirstFrameProvider` already is), or choose the candidate at selection time inside `load()`. Do not widen assertions to accept either candidate. Rerun the fast lane at least 3 times and the load repro.

## Acceptance criteria

- [ ] EmbeddedFirstFrameTests pass 10/10 under the CPU-load repro.
- [ ] `scripts/ci-tests.sh fast` passes.


### Comment — claude @ 2026-10-01T22:02:37.365Z

Implemented in 1ea93f49. ImageCollection and AppViewModel take an originalThumbnailProvider (default: the real OriginalThumbnailLoader), mirroring embeddedFirstFrameProvider; the first-frame tests suppress the thumbnail rather than widening assertions. This completes the work the stopped agent left uncommitted, plus one assertion it had not updated: testEmbeddedFirstFrameStaleDropOnNavigation expected a thumbnail-sized presentation extent, but with the thumbnail suppressed the embedded JPEG is the provisional frame and is deliberately stretched across the native frame, so it now asserts the native size. Evidence: EmbeddedFirstFrameTests pass 10 of 10 under CPU load (20 busy processes on 10 cores), where the verifier saw 2 of 3 fail; full gate on 4bbc5c5f: warning-gate clean, fast pass, serial 455 tests pass, identity 4 tests pass (all green).

## Agent log

- 2026-10-01T22:58:49.901Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] EmbeddedFirstFrameTests pass 10/10 under the CPU-load repro. (pass) — 10 consecutive runs with 2x ncpu busy processes; 4 tests pass, 1 opt-in real-RAW test skipped by design, 0 failures.
- [x] scripts/ci-tests.sh fast passes. (pass) — Ran twice, exit 0.
Checks run:
- swift build
- scripts/ci-tests.sh fast (x2)
- swift test --skip-build --filter EmbeddedFirstFrameTests x10 under 2x ncpu CPU load
Findings:
- info: the default OriginalThumbnailLoader closure is duplicated in ImageCollection.init, AppViewModel.init and the test helper. Minor; mirrors the existing embeddedFirstFrameProvider pattern. Not worth a ticket.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUQ4Q9GASS3BIB5Z
Summary: Verified 1ea93f49: originalThumbnailProvider injection makes EmbeddedFirstFrameTests deterministic; fast lane passes and the tests pass 10/10 under 2x-ncpu CPU load. No fixes needed.
