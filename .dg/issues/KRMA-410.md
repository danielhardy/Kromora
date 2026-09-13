---
id: KRMA-410
title: "Phase 3.5: large-library scale and concurrency regression suite vs. baseline"
type: task
status: ready
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - performance
  - index
created: 2026-09-12T19:44:23.060Z
updated: 2026-09-13T04:43:59.851Z
depends_on:
  - KRMA-407
  - KRMA-408
  - KRMA-409
  - KRMA-389
order: zzzzx
board: product
---

## Objective

Close out Phase 3 with the large-library scale and concurrency regression suite, measured against
KRMA-389's committed baseline, and confirm the 100,000-asset exit gate — the acceptance bar KRMA-392
is measured against.

## Dependencies

- All other Phase 3 tickets (`LibraryQueryController`/index projection, index rebuild, scheduler
  lanes, `EditDocumentStore` demotion) — this exercises them together at scale.
- KRMA-389 (baseline to compare against).

## Scope

- Using KRMA-389's generator, run the full warm-launch / first-page / filter / scroll / memory /
  decoded-thumbnail-count / preview-submission-latency suite at 1,000, 10,000, and 100,000 assets
  against the new index-projection-backed library, and compare p95/p99.9 against the committed
  KRMA-389 baseline.
- Verify the hard invariants: a 100,000-asset library materialises neither 100,000 observable
  objects nor 100,000 decoded thumbnails at once; filtering/sorting never leaves the index; selection
  remains UUID-based under scale.
- Verify scheduler fairness at scale: visible/active editor work is not queued behind import/rebuild/
  validation/maintenance even at 100,000 assets.
- Verify package commits remain single-writer under concurrent background package I/O at scale.
- Verify KRMA-371 deletion behavior is unaffected by the index/projection changes.

## Acceptance criteria

- [ ] Scale results at 1k/10k/100k are captured with p95/p99.9 and compared explicitly against the
  KRMA-389 baseline in committed documentation.
- [ ] The 100,000-asset library does not materialise 100,000 observable objects or 100,000 decoded
  thumbnails (verified by instrumentation, not estimation).
- [ ] Scheduler fairness and single-writer package-commit invariants hold at 100,000-asset scale.
- [ ] KRMA-371 deletion behavior is unchanged (regression test).
- [ ] `swift build`, the applicable fast/serial lanes, the benchmark lane, `dg validate`, and
  `git diff --check` pass.

## Verification lane

Large-library performance/concurrency lane at 1k/10k/100k, plus existing render/UI regression lanes.
This is the gate KRMA-392's own acceptance criteria reference.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/AUTO_PERFORMANCE.md, docs/TESTING.md
- context.issues: KRMA-392, KRMA-389
