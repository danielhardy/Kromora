---
id: KRMA-831
title: Measure writer-lock wait in the production mutation scale probe
type: task
status: backlog
priority: medium
parent: KRMA-829
human_review_required: false
creation_provenance:
  runner: codex
  model: gpt-6.1-sol
  actor: codex
labels:
  - verification
created: 2026-10-08T15:28:30.395Z
updated: 2026-10-08T15:28:30.395Z
blockers: []
order: z
board: product
---

## Objective

Capture the full production rating/flag mutation and subsequent reload, including time waiting for background package repair to release the writer lock.

## Context

Counterpoint verification of KRMA-829 found that `measureProductionLaunch` in `Tests/KromoraKitTests/LibraryScaleRegressionPerformanceTests.swift` calls `session.updateLibraryState` before recording `mutationReloadStart`. The published `production-mutation-reload` metric therefore measures only the post-write browsing reload, excluding the writer-lock wait and package transaction. This is pre-existing instrumentation, not a regression from KRMA-829. The completed three-sample probe proves writes finish and state is visible, but its reload timing cannot quantify the stall that motivated KRMA-829.

Keep the historical evidence intact and explicitly distinguish its measured reload interval from any new full mutation interval. See `docs/LIBRARY_SCALE_REGRESSION.md` and `docs/evidence/library-scale-krma-829.json`.

## Acceptance criteria

- [ ] Measure the full `updateLibraryState` plus browsing reload interval, including writer-lock wait, without hiding it behind a timer started after the write.
- [ ] Exercise a mutation while presented-ratio repair is active using a controlled synchronization boundary rather than depending on incidental task scheduling; retain rating/flag visibility and zero browsing record-read assertions.
- [ ] Publish a three-sample 1k/10k/100k JSON result and document the timing boundary, keeping historical captures accurately labeled and avoiding invalid comparisons between different intervals.

## Implementation notes

This is a non-blocking benchmark-quality follow-up. It does not require product behavior changes. Coordinate metric naming/schema and documentation changes so existing captured evidence remains interpretable. Do not run display-bound capture harnesses for this issue.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
