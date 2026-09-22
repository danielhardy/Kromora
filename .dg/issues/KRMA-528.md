---
id: KRMA-528
title: Extract the Auto workflow and retire or isolate the histogram fallback
type: task
status: ready
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - architecture
  - auto
created: 2026-09-21T20:33:08.755Z
updated: 2026-09-22T00:38:40.142Z
depends_on:
  - KRMA-527
estimate: 8
order: zz
board: product
---

## Objective

Move Auto policy, progress, cancellation, and invocation revision handling out of AppViewModel into a testable AutoWorkflowCoordinator, with one explicit policy for the legacy histogram fallback.

## Context and decision

AppViewModel.runAutoAdjustment is roughly 300 lines and combines the content-aware path with a legacy histogram fallback implemented by AutoAdjustmentAnalyzer. Two policies create two behaviors to explain and test. First establish whether content-aware Auto is always available after a preview exists. If yes, delete AutoAdjustment.swift and the fallback. If not, retain it only as an explicit degraded mode with a user-visible/diagnostic reason.

## Scope

- Define a coordinator that owns Auto invocation revisions, cancellation, progress, candidate evaluation, and the value-only result.
- Keep AppViewModel responsible only for starting the workflow and applying the resulting document change through the normal commit path.
- Ensure stale Auto results cannot overwrite a newer edit/source selection.
- Extract pure/fake-engine tests without constructing AppViewModel.
- Preserve quality regression behavior and any intentional degraded mode contract.
- Update docs/comments to state when fallback is possible and how it is surfaced.

## Acceptance criteria

- [ ] AppViewModel contains no Auto policy logic or histogram analyzer orchestration.
- [ ] The coordinator has fake-engine tests for success, cancellation, superseded invocation, no-preview, and degraded/fallback behavior if retained.
- [ ] The chosen fallback policy is explicit and covered; dead AutoAdjustment.swift is removed if unreachable.
- [ ] Result application respects document/source revision fences and existing undo/persistence semantics.
- [ ] Auto quality regression, fast, serial, and relevant performance checks pass.

## Dependencies and coordination

Depends on CQ-12's diagnostics/evaluation boundary. Coordinate with CQ-14 only to avoid extracting the same AppViewModel code twice.

## Likely files and checks

AppViewModel Auto section, AutoAdjustment.swift, PhotoAnalysis coordinators/policies, AutoCandidateEvaluation/diagnostics, new AutoWorkflowCoordinator, and Auto quality tests.
