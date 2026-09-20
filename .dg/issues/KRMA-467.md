---
id: KRMA-467
title: "Stage 3: Move remaining preview and histogram scheduling ownership"
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
created: 2026-09-19T16:27:24.296Z
updated: 2026-09-19T16:28:46.770Z
depends_on:
  - KRMA-466
order: y
board: product
---

Parent: KRMA-460

## Objective

Move the remaining preview admission/scheduling and histogram admission state out of `AppViewModel` into `PreviewPresentationCoordinator` or a narrow sibling, without making that collaborator own `PreviewSurface` or the published document.

## Ownership contract

- State owned: interactive/settled submit admission, debounce, adjacent prefetch, idle cache-fill admission, comparison retry, and histogram admission state left after KRMA-432.
- Admitted commands: submit interactive/settled preview work, request adjacent prefetch or idle fill, retry comparison, and request histogram work.
- Published values: preview/histogram outcomes and narrow presentation status values; `AppViewModel` remains the published document owner and `PreviewCoordinator` remains the only render-admission owner.
- Revision checks: preserve latest-wins source/document/display fences, comparison generations, and separate idle-vs-prefetch job IDs.
- Task handles: bounded debounce/retry/prefetch/cache-fill tasks with cancellation on supersession, source switch, document replacement, and shutdown.
- Shutdown behavior: cancel scheduler-owned work before preview/cache collaborators are released; retain existing last-valid-frame and failure behavior.
- Resource limits: reuse the existing planners, cache I/O, scheduler lanes, and bounded queues; no second renderer, GPU owner, or unbounded background work.

## Scope and acceptance

- [ ] `RenderRequest` / `RenderEngine` funnel semantics and preview quality/resource policies are preserved.
- [ ] Histogram parity and comparison retry behavior are preserved.
- [ ] Collaborator-level fake-based admission/fence tests exist, with AppViewModel integration coverage for navigation, comparison, and histogram behavior.
- [ ] `load()`, `updateDocument()`, `applyHistoryDocument()`, and `shutdown()` sequencing remain root-owned.
- [ ] Focused tests, `swift build`, the relevant fast CI lane, `dg validate`, and `git diff --check` pass.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
