---
id: KRMA-324
title: Presented-frame vs rebuild histogram parity coverage on exposure/WB fixtures
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Presented-frame histogram matches rebuild histogram on exposure/white-balance stress fixtures within a recorded tolerance
      result: pass
      notes: testPresentedFrameHistogramMatchesRebuildOnExposureAndWhiteBalanceFixtures compares red/green/blue/luma per-bin counts between engine.histogram(presentedImage:) and engine.histogram(source:document:) on high-exposure, warm-white-balance, and combined fixtures, tolerance 4 counts/bin; both paths share tallyHistogram and the request's own renderScale, so the comparison is apples-to-apples.
  checks_run:
    - "swift test --filter HistogramTests: 10/10 pass, stable across 3 reruns"
    - "swift build: clean"
    - "scripts/ci-tests.sh fast: 667/667 pass"
    - "scripts/ci-tests.sh serial: 322/322 pass"
    - "git diff --check on HistogramTests.swift: clean"
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-09T18:23:47.006Z
  session: 01MTUFBOXK4W77V4M5
creation_provenance:
  runner: pi
  model: openrouter/meta/muse-spark-1.3-contributor
  actor: pi
labels:
  - verification
created: 2026-09-09T16:56:16.418Z
updated: 2026-09-10T12:53:56.823Z
parent: KRMA-310
order: a0
board: product
---

## Objective

Presented-frame vs rebuild histogram parity coverage on exposure/WB fixtures

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — pi @ 2026-09-09T16:56:21.483Z

Parent: KRMA-310 (counterpoint verification follow-up). KRMA-310's HistogramParityTest acceptance item was covered in substance by testTheEngineTalliesThePresentedImageWithoutRebuildingTheSource (proves the presented frame is the tally input) but no test directly compares presented-frame bins against rebuild bins on exposure/white-balance stress fixtures. Add a HistogramTests parity case: render the preview via the engine, tally it through histogram(presentedImage:) and through histogram(source:document:), assert per-bin distance within a recorded tolerance. No product change; test only.

### Comment — codex @ 2026-09-09T18:20:13.310Z

Implemented in commit fb9ca0b. Added HistogramTests coverage that renders completed preview frames, tallies presentedImage and source/document rebuild paths at the same preview scale, and checks red/green/blue/luma per-bin distance across high-exposure, warm-white-balance, and combined stress fixtures with a recorded tolerance of 4 counts. Verification: focused HistogramTests 10/10; swift build; ci-tests.sh fast 667/667; ci-tests.sh serial 322/322; git diff --check; dg validate OK (pre-existing unknown pickup-runner model warning).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-09T18:23:47.006Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Presented-frame histogram matches rebuild histogram on exposure/white-balance stress fixtures within a recorded tolerance (pass) — testPresentedFrameHistogramMatchesRebuildOnExposureAndWhiteBalanceFixtures compares red/green/blue/luma per-bin counts between engine.histogram(presentedImage:) and engine.histogram(source:document:) on high-exposure, warm-white-balance, and combined fixtures, tolerance 4 counts/bin; both paths share tallyHistogram and the request's own renderScale, so the comparison is apples-to-apples.
Checks run:
- swift test --filter HistogramTests: 10/10 pass, stable across 3 reruns
- swift build: clean
- scripts/ci-tests.sh fast: 667/667 pass
- scripts/ci-tests.sh serial: 322/322 pass
- git diff --check on HistogramTests.swift: clean
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTUFBOXK4W77V4M5
Summary: Verified: independent review of HistogramTests parity coverage confirms per-bin presented-vs-rebuild comparison on exposure/WB/combined fixtures with recorded tolerance; no product code touched; fast 667/667, serial 322/322, focused suite 10/10 stable across reruns.
