---
id: KRMA-469
title: "Stage 5: Re-inventory AppViewModel and update architecture documentation"
type: task
status: backlog
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - architecture
  - maintainability
  - appviewmodel
created: 2026-09-19T16:27:26.087Z
updated: 2026-09-20T02:20:15.600Z
depends_on:
  - KRMA-465
  - KRMA-466
  - KRMA-467
  - KRMA-468
order: yh
board: product
---

Parent: KRMA-460

## Objective

After Stages 1–4 land, re-inventory `AppViewModel` and update the durable architecture documentation to match actual ownership.

## Ownership contract

- State owned: no new workflow state; record the resulting root boundary and any final thin-façade moves justified by completed ownership extractions.
- Admitted commands: documentation/review of remaining root methods and only façade moves justified by the completed extractions.
- Published values: document the single published active `EditDocument`, source chrome, navigation policy, and status/error presentation as root-owned.
- Revision checks: verify source/document/display fences and the one `updateDocument` commit path remain unchanged.
- Task handles: inventory remaining root task handles; assign extracted workflow handles to their collaborators or explicitly justify any root remainder.
- Shutdown behavior: document composition, cancellation, persistence flush/discard, and collaborator teardown ordering.
- Resource limits: record scheduler/cache/GPU ownership and ensure no duplicate renderer, event bus, document store, or unbounded worker was introduced.

## Scope and acceptance

- [ ] Expected root remainder is confirmed: init/wiring, load sequencer, updateDocument/applyHistoryDocument, published chrome, and shutdown.
- [ ] `docs/APP_ARCHITECTURE.md` and the R5 paragraph in `docs/REPOSITORY_IMPROVEMENT_PLAN.md` are updated if stale.
- [ ] Line-count trend is recorded only as supporting evidence, never as the extraction goal.
- [ ] Focused tests for each landed stage, `swift build`, the relevant fast CI lane, `dg validate`, and `git diff --check` pass.
- [ ] This remains a documentation/review stage; no broad refactor is started here.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
