---
id: KRMA-726
title: Sharpening controls have no visible effect
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce the report and determine why Sharpening had no visible result
      result: pass
      notes: "Root cause: CIUnsharpMask was applied to the original image instead of the current result, discarding prior stages; fixed in RenderPipeline.applyDetailControls."
    - criterion: Non-neutral settings visibly affect detail; neutral preserves pixels; monotonic and within ranges
      result: pass
      notes: DetailAdjustments now clamps every property on mutation and keeps fractional radius; tests show Amount 25/50/100 monotonically increases high-frequency energy and neutral is pixel-exact.
    - criterion: Consistent in preview and export and survives persistence/reopen
      result: pass
      notes: Shared render pipeline used by both paths; persistence round-trip test added.
    - criterion: Deterministic rendering regression coverage
      result: pass
      notes: RenderPipelineTests measure high-frequency energy on a deterministic fixture.
  checks_run:
    - swift test --filter RenderPipelineTests (50 tests, 2 skipped, 0 failures)
    - swift test --filter EffectsInspectorTests (10 tests, 0 failures)
    - git diff --check (clean)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-29T23:11:15.639Z
  session: 01MUNAI7OU97RJBEFP
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - sharpening
  - rendering
  - quality
created: 2026-09-29T21:51:01.529Z
updated: 2026-09-29T23:11:15.642Z
blockers: []
order: t
board: product
context:
  files:
    - Sources/KromoraKit/Models/RenderPipeline.swift
    - Sources/KromoraKit/Views/EffectsInspectorView.swift
    - Tests/KromoraKitTests/RenderPipelineTests.swift
    - Tests/KromoraKitTests/EffectsInspectorTests.swift
  docs: []
  issues:
    - KRMA-598
  commands:
    - swift test --filter RenderPipelineTests
    - swift test --filter EffectsInspectorTests
    - git diff --check
---

## Objective

Make the Sharpening controls produce a visible, predictable change in rendered photos.

## Context

The user reports that adjusting Sharpening does not appear to change the photo. The controls should
create a perceptible sharpening effect at non-neutral values while leaving the image unchanged at
neutral settings.

## Acceptance criteria

- [ ] Reproduce the report with representative image detail and determine why changing Sharpening
      does not produce a visible result.
- [ ] Non-neutral sharpening settings visibly affect rendered detail; neutral settings preserve
      the unsharpened result, with controls behaving monotonically and within their documented
      ranges.
- [ ] The adjustment is consistent in interactive preview and exported output and survives edit
      persistence/reopen.
- [ ] Add deterministic rendering regression coverage that verifies a measurable pixel/detail
      change without relying on a subjective visual assertion alone.

## Implementation notes

Trace the sharpening controls from inspector values through edit state to the shared render and
export paths. Use a deterministic high-detail image fixture and report the tested settings and
observable result. KRMA-598 introduced the controls and is useful implementation context.

### Comment — codex @ 2026-09-29T23:05:37.513Z

Implemented and verified sharpening control behavior. Detail values now stay within their declared ranges, fractional Radius values survive initialization and decoding, and sharpening runs on the current image result so preceding noise reduction is retained. Added deterministic high-frequency energy coverage showing Amount 25/50/100 increases detail monotonically and neutral preserves exact pixels, plus persistence round-trip coverage. Checks: swift test --filter RenderPipelineTests (49 tests, 2 skipped, 0 failures); swift test --filter EffectsInspectorTests (9 passed); git diff --check. Commit: 175e45a.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-29T23:11:15.639Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce the report and determine why Sharpening had no visible result (pass) — Root cause: CIUnsharpMask was applied to the original image instead of the current result, discarding prior stages; fixed in RenderPipeline.applyDetailControls.
- [x] Non-neutral settings visibly affect detail; neutral preserves pixels; monotonic and within ranges (pass) — DetailAdjustments now clamps every property on mutation and keeps fractional radius; tests show Amount 25/50/100 monotonically increases high-frequency energy and neutral is pixel-exact.
- [x] Consistent in preview and export and survives persistence/reopen (pass) — Shared render pipeline used by both paths; persistence round-trip test added.
- [x] Deterministic rendering regression coverage (pass) — RenderPipelineTests measure high-frequency energy on a deterministic fixture.
Checks run:
- swift test --filter RenderPipelineTests (50 tests, 2 skipped, 0 failures)
- swift test --filter EffectsInspectorTests (10 tests, 0 failures)
- git diff --check (clean)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUNAI7OU97RJBEFP
Summary: Verified KRMA-726: sharpening now runs on the post-noise-reduction result, detail values are clamped in range (fractional radius preserved), with deterministic detail-energy regression tests.
