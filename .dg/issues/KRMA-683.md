---
id: KRMA-683
title: Investigate Remove render-engine quality regressions
type: task
status: backlog
priority: high
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
  - retouch
  - remove-heal-clone
created: 2026-09-28T04:00:51.636Z
updated: 2026-09-28T04:00:51.636Z
parent: KRMA-665
blockers: []
order: zzzx
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
