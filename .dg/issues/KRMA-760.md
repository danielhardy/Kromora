---
id: KRMA-760
title: Show the histogram for an exact stored frame without waiting for source preparation
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Histogram of an exact stored frame is admitted without waiting for source preparation
      result: pass
      notes: Admission is invoked from stored-frame presentation and edit adoption, gated on exact classification.
    - criterion: Provisional/stale/unresolved frames never feed the histogram
      result: pass
      notes: Requires FrameClassifier exact; completion revalidates identity, document, Look, original/crop state.
    - criterion: No duplicate work against the confirmed-frame tail
      result: pass
      notes: Shared HistogramIdentity dedupes in-flight and completed work.
  checks_run:
    - swift build (pass)
    - git diff --check (pass)
    - swift test filtered to admission/presentation/histogram/warm-reopen suites (39 tests, 0 failures)
  findings:
    - "Low, non-blocking: no test directly asserts the histogram starts before source preparation completes; the warm-reopen test covers admit-once only."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-03T07:32:09.884Z
  session: 01MUS2PSCHH9PBHHVN
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - design
created: 2026-10-02T03:33:22.387Z
updated: 2026-10-03T07:32:09.886Z
blockers: []
order: a0
board: product
---

## Objective

Design, and only then build, a way for the histogram of an **exact** stored frame to appear without waiting for source preparation. This is a design ticket for a stronger agent or the owner; it is not for an unattended run.

## Why it is separate

Today the histogram needs a prepared `imageSource` and a presented frame whose `RenderRequest` matches the current document (`PreviewAdmissionCoordinator.updateHistogram`), and an exact stored frame is only recognized at settled-preview admission, which also needs the prepared source. So the histogram cannot start before source preparation (about 290 ms for the benchmark RAW), regardless of how early the panel values arrive. The plan (docs/ and .context/last-known-frame-plan.md) allows the exact frame to feed histogram and supporting work through the confirmed tail but forbids a provisional frame from doing so, so the boundary matters.

## Options to weigh

1. Classify the stored frame as exact before preparation completes. Exact needs only the source identity (known from the record), the edit hash (now available early, KRMA-755), and the resolved Look; if all are known, the frame is exact and its raster is the final pixels, so its histogram is the real histogram. Needs the admission path to stop assuming a prepared source for this one case.
2. Persist a small histogram (for example 256 bins per channel) in the `LatestPreviewFrameStore` envelope beside the raster and show it with an exact hit. Derived data of the same pixels, but it changes the envelope (a `storageFormatVersion` bump, per-entry miss) and has to be invalidated exactly as the frame is.
3. Leave the histogram where it is and only fix queue order (KRMA-759).

## Decide before building

Which of these is worth its complexity once KRMA-757 and KRMA-759 have measured how much of the histogram delay is preparation versus queue. If KRMA-759 closes most of the gap, close this ticket as not needed.


### Comment — codex @ 2026-10-03T07:31:23.295Z

KRMA-757/759 measured 0.075 ms p50 queue wait versus 53.3 ms histogram compute, while source preparation remains about 290 ms. Chose early exact classification (option 1): after the stored raster is presented and source identity, edit hash, and resolved Look are known, tally its own pixels before source preparation. The same content identity deduplicates this work with the confirmed-frame tail; stale and unresolved frames remain excluded. Updated the last-known-frame plan. Checks: swift build, git diff --check, dg validate passed; no tests run. Commit: 053e7ae.

## Agent log

- 2026-10-03T07:32:09.884Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Histogram of an exact stored frame is admitted without waiting for source preparation (pass) — Admission is invoked from stored-frame presentation and edit adoption, gated on exact classification.
- [x] Provisional/stale/unresolved frames never feed the histogram (pass) — Requires FrameClassifier exact; completion revalidates identity, document, Look, original/crop state.
- [x] No duplicate work against the confirmed-frame tail (pass) — Shared HistogramIdentity dedupes in-flight and completed work.
Checks run:
- swift build (pass)
- git diff --check (pass)
- swift test filtered to admission/presentation/histogram/warm-reopen suites (39 tests, 0 failures)
Findings:
- Low, non-blocking: no test directly asserts the histogram starts before source preparation completes; the warm-reopen test covers admit-once only.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUS2PSCHH9PBHHVN
Summary: Verified early exact stored-frame histogram admission; build and 39 related tests pass.
