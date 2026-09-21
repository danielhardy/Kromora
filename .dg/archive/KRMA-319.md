---
id: KRMA-319
title: "KRMA-308 regression: LUT external-import preview-count assertion fails after preview-cache thumbnail-churn protection"
type: bug
status: done
priority: medium
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T16:18:17.582Z
  session: 01MTUASKZXW6UD2TRT
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-09T14:15:01.167Z
updated: 2026-09-10T12:53:56.368Z
parent: KRMA-268
depends_on:
  - KRMA-268
order: x7
board: product
---

## Objective

`LUTWorkflowTests.testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest` fails
deterministically on `main` at `Tests/LumoKitTests/LUTWorkflowTests.swift:182`
(`XCTAssertGreaterThan(requestsAfterClick, requestsBeforeClick)`, both sides equal). Found
during KRMA-268 counterpoint verification; unrelated to KRMA-268's own change.

## Context

Bisected with `swift test --filter LUTWorkflowTests/...` across the commit range between
KRMA-268's last commit (`1731b84`) and current `main` tip (`bca796a`):

- `1731b84` (KRMA-268 tip) — passes
- `0fed205`, `2d4d7b6` — pass
- `b01de9d` (KRMA-308: protect preview cache from thumbnail churn) — **fails**

So the regression was introduced by `b01de9d`. After selecting an imported Look by id (following
`selectLook(nil)` to clear selection, at 200% canvas zoom), no new preview request reaches
`FakeRenderEngine` — the LUT selection preview appears to be getting coalesced/suppressed by the
thumbnail-churn protection added in KRMA-308.

## Acceptance criteria

- [ ] Root-cause why KRMA-308's preview-cache protection suppresses the preview request that
      should fire when a user selects a newly imported Look by id.
- [ ] `testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest` passes again without
      weakening the assertion.
- [ ] No regression in the KRMA-308 fast-lane tests that currently pass.

## Implementation notes

<!-- Approach, constraints, links -->

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-09T16:18:17.582Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTUASKZXW6UD2TRT
Summary: Hardened the external-import LUT preview wait to require a post-click request, preserving the strict count assertion. The KRMA-308 path was async, not suppressing the request; the old helper could be satisfied by the earlier import-audition request.
