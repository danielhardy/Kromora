---
id: LUMO-294
title: Cancel superseded Vision mask work promptly on navigation and re-edit
type: bug
status: done
priority: high
verification_agent: pi
model: gpt-5.6-sol
verification_model: openrouter/meta/muse-spark-1.3-contributor
labels:
  - performance
  - preview
  - masks
  - cancellation
created: 2026-09-08T23:48:30.129Z
updated: 2026-09-09T01:32:05.180Z
depends_on:
  - LUMO-292
order: zh
board: product
commits:
  - e9c517a
---

## Objective

Superseded semantic-mask Vision work stops promptly on navigation and re-edit instead of burning CPU/GPU behind the current photo.

## Context

Parent: LUMO-289. RenderEngine.latestMaskRequestRevisions already discards late mask values at the await boundary (Sources/LumoKit/Models/RenderEngine.swift), but the underlying PhotoAnalysisCoordinator in-flight mask tasks (inFlightMasks, Sources/LumoKit/Models/PhotoAnalysis/PhotoAnalysisCoordinator.swift) may run to completion unobserved, and every new displayRevision currently invalidates prior mask requests even when the mask definitions are unchanged.

## Plan

- Propagate cancellation: when a mask request is superseded (newer revision for the same source) or its photo is navigated away from, cancel the coordinator-side task via the existing maskWaiterCancelled path; verify Vision requests actually observe it.
- Avoid invalidating unchanged masks: scope revision bumps so global-look-only edits do not churn mask resolution (mask cache keys already exclude the global look — keep that property and extend the fencing to match).
- Measure with the LUMO-290 harness: rapid filmstrip navigation over masked photos should show cancelled, not completed, superseded mask tasks.

## Acceptance

- Superseded/navigated-away mask tasks cancel promptly (test via in-flight waiter counts or task outcome, not timing).
- Global-only edits do not re-trigger Vision mask work (cache-hit assertion).


### Comment — codex @ 2026-09-09T01:32:04.871Z

Implemented in e9c517a. RenderEngine now owns cancellable waiter tasks for revisioned semantic resolutions: source navigation and mask-recipe changes cancel obsolete waiters through PhotoAnalysisCoordinator, while a mask-topology identity excludes global/local look values so unchanged masks remain shareable and cacheable. Vision synchronous perform calls are wrapped so Swift task cancellation invokes VNRequest.cancel() without concurrency opt-outs. Added deterministic outcome/count tests for navigation, recipe re-edit, and global-only cache reuse. Verification: swift build; LocalMaskRenderingTests (31 tests, 1 opt-in skip); PhotoAnalysisCoordinatorTests (7 passed); VisionSemanticMaskProviderTests (7 passed); SingleViewLatencyBenchmark (2 tests, 1 opt-in skip); CI fast lane (651 passed); CI serial lane (290 passed); git diff --check; dg validate (OK with pre-existing warnings). scripts/check-swift-format.sh remains blocked by pre-existing whole-file formatting violations in the touched legacy files.

## Agent log

- 2026-09-09T01:32:05.177Z: Cancel obsolete semantic mask waiters on source/recipe supersession, propagate cancellation into Vision, and preserve unchanged-mask cache reuse.
