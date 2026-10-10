---
id: KRMA-859
title: Characterize and fix possible smart mask dropout when settling to full resolution after zoom
type: bug
status: backlog
priority: low
agent: codex
verification_agent: codex
human_review_required: false
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
created: 2026-10-10T13:08:36.761Z
updated: 2026-10-10T13:08:43.698Z
depends_on:
  - KRMA-849
blockers: []
order: zzzq
board: product
---

## Objective

KRMA-849 stops zoom from publishing a mask-less base frame while the smart mask is warm. A flicker can remain at settle: `SemanticWarmth` still includes `maskQuality`, and the settled full-resolution render uses render-quality masks (`RenderQuality.maskQuality` maps fullResolution/export to `.render`), so the first settled render after a preview-quality session is still two-phase and drops a Person layer from the base frame (`LocalAdjustmentLayer.allowsDeferredSemanticPreview` is false).

## Work

1. Characterize: add a `PreviewCoordinatorTests` case that submits an interactive then a settled/full-resolution request for a warm Person mask and records whether a `.deferSemantic` frame is published. Capture it with `log stream --signpost --predicate 'subsystem == "com.kromora.app" AND category == "workflow"'` on a real photo, expecting `masks=deferred` on the settle.
2. Decide and implement a fix if the characterisation shows a visible dropout, for example keep the last published mask-bearing frame until the refined frame lands, or let the base frame reuse the cached preview-quality mask instead of dropping the layer. Do not reintroduce the original flicker (KRMA-849 test must still pass).

## Acceptance criteria

1. The characterisation test exists and states the intended behavior (no frame without the smart mask between a settled render and its predecessor).
2. If the characterisation fails, the fix makes it pass; otherwise the ticket records measured evidence (signpost capture) that no dropout occurs and closes with the test as a guard.
3. KRMA-849's zoom test and the existing two-phase cold-start test (new/edited smart mask still publishes a base frame) pass.

Depends on KRMA-849. Display-bound benchmarks are not required (CLAUDE.md); use the log capture only as supporting evidence.
