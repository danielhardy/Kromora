---
id: LUMO-319
title: "LUMO-308 regression: LUT external-import preview-count assertion fails after preview-cache thumbnail-churn protection"
type: bug
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-09T14:15:01.167Z
updated: 2026-09-09T14:15:16.398Z
parent: LUMO-268
depends_on:
  - LUMO-268
order: y
board: product
---

## Objective

`LUTWorkflowTests.testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest` fails
deterministically on `main` at `Tests/LumoKitTests/LUTWorkflowTests.swift:182`
(`XCTAssertGreaterThan(requestsAfterClick, requestsBeforeClick)`, both sides equal). Found
during LUMO-268 counterpoint verification; unrelated to LUMO-268's own change.

## Context

Bisected with `swift test --filter LUTWorkflowTests/...` across the commit range between
LUMO-268's last commit (`1731b84`) and current `main` tip (`bca796a`):

- `1731b84` (LUMO-268 tip) — passes
- `0fed205`, `2d4d7b6` — pass
- `b01de9d` (LUMO-308: protect preview cache from thumbnail churn) — **fails**

So the regression was introduced by `b01de9d`. After selecting an imported Look by id (following
`selectLook(nil)` to clear selection, at 200% canvas zoom), no new preview request reaches
`FakeRenderEngine` — the LUT selection preview appears to be getting coalesced/suppressed by the
thumbnail-churn protection added in LUMO-308.

## Acceptance criteria

- [ ] Root-cause why LUMO-308's preview-cache protection suppresses the preview request that
      should fire when a user selects a newly imported Look by id.
- [ ] `testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest` passes again without
      weakening the assertion.
- [ ] No regression in the LUMO-308 fast-lane tests that currently pass.

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
