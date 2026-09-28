---
id: KRMA-683
title: Investigate Remove render-engine quality regressions
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Use the full-engine corpus test to reproduce and localize the standalone-versus-engine quality differences; report affected rows and metrics.
      result: pass
      notes: "Superseded: commit 04100fa removed the Remove render path and corpus test target."
    - criterion: Fix the engine-path defect without weakening KRMA-658 thresholds or changing solver internals unless the evidence places the defect in the solver.
      result: pass
      notes: The regression applied to the now-removed Remove pipeline. No current product path remains to repair, and Remove stays retired per the human direction.
    - criterion: Re-run engine and standalone corpus checks and document the verified result in docs/RETOUCH.md.
      result: pass
      notes: Remove engine/corpus checks are obsolete after retirement; docs/RETOUCH.md now documents supported Heal/Clone behavior.
  checks_run:
    - Reviewed KRMA-681 and retirement commit 04100fa
    - Confirmed KRMA-668 was closed as superseded with the same disposition
  findings: []
  fixes: []
  verification_commits:
    - 04100fa
  actor: codex
  resolved_model: unknown
  completed_at: 2026-09-28T15:30:47.742Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
  - retouch
  - remove-heal-clone
created: 2026-09-28T04:00:51.636Z
updated: 2026-09-28T15:30:47.745Z
parent: KRMA-665
blockers:
  - id: evt_mulddhn6_qd9ddw
    type: human
    reason: KRMA-681 retired Remove and deleted its renderer; this issue's target path and engine corpus test no longer exist. Proceeding requires a product decision.
    action: Choose whether Remove stays retired and KRMA-683 is superseded/re-scoped, or whether Remove should be reintroduced for this fix.
    created_at: 2026-09-28T14:55:34.290Z
    resolved_at: 2026-09-28T14:58:24.871Z
    resolved_by: web
order: zzzh
board: product
context:
  files:
    - Sources/KromoraKit/Models/RenderEngine.swift
    - Sources/KromoraKit/Models/RetouchRenderer.swift
    - Tests/KromoraKitTests/RetouchQualityEvaluationTests.swift
  docs:
    - docs/RETOUCH.md
  issues:
    - KRMA-658
    - KRMA-665
  commands:
    - swift test --filter RetouchQualityEvaluationTests/testRemoveQualityAcrossGroundTruthCorpusThroughRenderEngine
    - swift test --filter RetouchQualityEvaluationTests/testPatchMatchRemoveQualityAcrossGroundTruthCorpus
commits:
  - 04100fa
---

## Objective

Find and correct the Remove render-engine quality regression exposed by running the KRMA-658
ground-truth corpus through the full `RenderEngine` and `RetouchRenderer` pipeline.

## Context

KRMA-668 added a 36-row end-to-end corpus test. On the Apple M4 Pro, only 5/36 rows pass the
existing KRMA-658 limits through the engine, compared with 32/36 through `PatchMatchInpainter`
plus the standalone test composite. Twenty-seven rows change pass/fail verdict. Common regressions
include line defects and small dust/speck cases across sky, cloud, foliage, water, brick, and skin.
The engine result is measured against a clean fixture rendered through the same engine to factor out
decode/color conversion. The failure is localized to the engine integration path: extraction, field
sampling coordinates, membrane, or composition. KRMA-662's solver quality and the documented
thresholds should remain unchanged unless investigation proves otherwise.

## Acceptance criteria

- [ ] Use the full-engine corpus test to reproduce and localize the standalone-versus-engine quality
      differences; report affected rows and metrics.
- [ ] Fix the engine-path defect without weakening KRMA-658 thresholds or changing solver internals
      unless the evidence places the defect in the solver.
- [ ] Re-run engine and standalone corpus checks and document the verified result in `docs/RETOUCH.md`.

## Implementation notes

See `Tests/KromoraKitTests/RetouchQualityEvaluationTests.swift`, especially
`testRemoveQualityAcrossGroundTruthCorpusThroughRenderEngine`, and `docs/RETOUCH.md`. This issue
owns the follow-up implied by KRMA-668's quality finding.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

## Disposition

Superseded by KRMA-681 and commit `04100fa`, which intentionally retired the Remove retouch
pipeline. The reported regression applied to that now-removed pipeline, so there is no current
product path to repair. Remove remains retired.

## HUMAN NOTE
Keep Remove retired. Do not reintroduce the solver, RenderEngine integration, or corpus tests for KRMA-683.

Close KRMA-683 as superseded by the intentional Remove retirement in commit 04100fa. Add a note that the reported regression applied to the now-removed Remove pipeline, so there is no current product path to repair.

- 2026-09-28T15:30:47.742Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Use the full-engine corpus test to reproduce and localize the standalone-versus-engine quality differences; report affected rows and metrics. (pass) — Superseded: commit 04100fa removed the Remove render path and corpus test target.
- [x] Fix the engine-path defect without weakening KRMA-658 thresholds or changing solver internals unless the evidence places the defect in the solver. (pass) — The regression applied to the now-removed Remove pipeline. No current product path remains to repair, and Remove stays retired per the human direction.
- [x] Re-run engine and standalone corpus checks and document the verified result in docs/RETOUCH.md. (pass) — Remove engine/corpus checks are obsolete after retirement; docs/RETOUCH.md now documents supported Heal/Clone behavior.
Checks run:
- Reviewed KRMA-681 and retirement commit 04100fa
- Confirmed KRMA-668 was closed as superseded with the same disposition
Findings:
- None
Fixes:
- None
Verification commits:
- 04100fa
Actor: codex
Resolved model: unknown
Summary: Closed as superseded by KRMA-681: the reported regression affected the intentionally retired Remove pipeline, leaving no current product path to repair.
