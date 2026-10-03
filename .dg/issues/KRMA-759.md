---
id: KRMA-759
title: Find and fix what delays the histogram after a photo switch (queue order vs compute)
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Comment gives measured split with sample counts and states which case applies
      result: pass
      notes: "Ticket comment and docs/TESTING.md: 0.013 ms enqueue, 0.075 ms queued, 53.3 ms compute (9 samples); compute-bound."
    - criterion: "If queue order was the cause: test and lower p50"
      result: pass
      notes: Not applicable; queue-order experiment gave 54.4 ms vs 54.1 ms baseline and was removed.
    - criterion: "If not queue order: no product change, numbers in docs/TESTING.md"
      result: pass
      notes: HEAD commit touches only docs/TESTING.md.
    - criterion: Exact-hit bypass and admitted-once behaviour unchanged
      result: pass
      notes: No product source changed.
  checks_run:
    - git show --stat HEAD (docs-only)
    - git diff --check
    - dg validate
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-02T05:23:49.344Z
  session: 01MUQIPD73QKIZWC6I
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - interaction
created: 2026-10-02T03:33:21.222Z
updated: 2026-10-02T05:23:49.346Z
depends_on:
  - KRMA-757
blockers: []
order: a0
board: product
---

## Objective

After a photo switch the histogram appears noticeably later than the photo and the panel values. Find out whether the delay is **time spent waiting in the work queue** or **time spent computing**, and fix the part that is queue order if that is what it is.

## Context

- `PreviewAdmissionCoordinator.updateHistogram` (Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift) enqueues the histogram job on the `.editor` lane at `ImageWorkScheduler.Priority.histogram` (2). The priorities are `activeEditor` 0, `comparison` 1, `histogram` 2, `adjacentFilmstrip` 3, `visibleGrid` 4, `packageIO` 5, `background` 6.
- After a photo confirms, `AppViewModel.adoptStoredEdits` calls `scheduleEditedThumbnailAfterSettle(for:priority: .activeEditor)` and the confirmed-frame tail can schedule a comparison (original) preview at `comparison`. Both outrank the histogram, so the histogram may sit behind two renders that the user is not waiting for.
- The histogram computation itself works on the presented frame at `maxDimension: 512`, so it is expected to be cheap.
- It cannot start before source preparation: it needs `admissionImageSource` and a presented frame whose request matches the current document. Making it independent of preparation is a larger design question tracked separately in KRMA-760; do not attempt it here.
- The previous photo's histogram stays visible on purpose until the new one is published (see the comment in `beginLoad`). Whether to change that is a product decision for the owner; do not change it here, but note in a comment whether it contributes to the perceived lag.

## Work

1. **Measure first.** Use the benchmark from KRMA-757 (`histogramMilliseconds`, `histogram_after_ready`). Add signposts or timestamps (temporary is fine) to split the histogram delay into: time between the confirmed frame and the job being enqueued, time queued before it starts, and compute time. Record the split in a comment on this ticket.
2. **If the time is queue wait**, make the histogram run before the supporting work the user is not waiting for, without starving user-visible renders: for example enqueue the active edited-thumbnail and comparison work after the histogram has been admitted, or give the histogram the same priority as the work that currently outranks it. Keep `activeEditor` interactive renders ahead of it.
3. **If the time is compute**, state the number and stop: record that it is compute-bound and what the evidence is. Do not optimize the histogram kernel here.
4. **If the time is dominated by waiting for source preparation**, state that and stop; that is KRMA-760.

## Acceptance criteria

- [ ] A comment on this ticket gives the measured split (confirmed frame to enqueue, queued, compute) from a Release run of the benchmark, with sample counts, and states which of the three cases above applies.
- [ ] If queue order was the cause: a deterministic test proves the histogram is admitted ahead of the edited-thumbnail and comparison work after a confirmed frame, interactive `activeEditor` renders are still ahead of it, and obsolete histograms still never publish (the existing stale-completion tests stay green). The benchmark's `histogram_after_ready` p50 is lower than the KRMA-757 baseline; record both in docs/TESTING.md.
- [ ] If it was not queue order: no product change, and the numbers are recorded in docs/TESTING.md. That is a complete outcome.
- [ ] Exact-hit bypass and "histogram admitted exactly once" behaviour are unchanged (the existing PreviewPresentationCoordinator, ThumbnailSwitchLifecycle, and AppViewModel suites pass).

## Rules for an unattended run (read first)

- **Do not run the display-bound captures** (`scripts/run-kromora-capture.sh`, the last-known-frame benchmark) and do not add them to this ticket. Everything here is verified by deterministic tests or by `StoredEditAdoptionBenchmark`, which needs no window and no unlocked display (see CLAUDE.md, "Display-bound benchmarks").
- **Do not open child tickets.** If a criterion cannot be met, or the numbers do not improve, record exactly what you measured and tried in a comment on this ticket, commit what is safe, and hand off to review. A measured miss with a profile is an acceptable outcome; a new ticket is not.
- Keep the change to what this ticket lists. Do not touch the slider animation (KRMA-756, in progress), the capture script, or the wall-clock budgets (ADR-LKF-001).
- Commit with a subject that starts `KRMA-<this id>:`. Do not push. Do not stash, reset, or revert anyone elses uncommitted changes in the tree.
- Gate before handoff: `swift test --filter` for the suites you touched, `scripts/ci-tests.sh warning-gate`, `scripts/ci-tests.sh fast`, `swift format lint` on changed Swift files, `git diff --check`, `dg validate`.


### Comment — codex @ 2026-10-02T05:23:23.187Z

Release timing on Apple M4 Pro / macOS 27.2 with DSC01019.ARW: 9 warm-switch samples measured p50 confirmed-frame→enqueue 0.013 ms, queued 0.075 ms, and histogram call 53.3 ms. This is compute-bound. The 30-switch histogram_after_ready p50 was 54.4 ms in the temporary queue-order experiment versus the KRMA-757 baseline of 54.1 ms, so I removed the scheduling experiment and retained no product change. The previous photo's histogram intentionally stays visible until replacement, contributing to the perceived lag. Results are in docs/TESTING.md. Verification: 68 targeted tests pass; fast lane (1,471 tests), warning gate, Release benchmark, git diff --check, and dg validate pass.

## Agent log

- 2026-10-02T05:23:49.344Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Comment gives measured split with sample counts and states which case applies (pass) — Ticket comment and docs/TESTING.md: 0.013 ms enqueue, 0.075 ms queued, 53.3 ms compute (9 samples); compute-bound.
- [x] If queue order was the cause: test and lower p50 (pass) — Not applicable; queue-order experiment gave 54.4 ms vs 54.1 ms baseline and was removed.
- [x] If not queue order: no product change, numbers in docs/TESTING.md (pass) — HEAD commit touches only docs/TESTING.md.
- [x] Exact-hit bypass and admitted-once behaviour unchanged (pass) — No product source changed.
Checks run:
- git show --stat HEAD (docs-only)
- git diff --check
- dg validate
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUQIPD73QKIZWC6I
