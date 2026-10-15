---
id: KRMA-956
title: "DECISION: Lightroom-first shortcut conventions (Apple Photos acceptable)"
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: State the Lightroom-first preference and Apple Photos fallback clearly.
      result: pass
      notes: The issue and accepted ADR specify Lightroom as preferred when both apps have a clear equivalent, with Apple Photos acceptable when Lightroom has no clear equivalent or does not fit the action.
    - criterion: Record the decision in DispatchGraph and link it from this issue.
      result: pass
      notes: The issue links the existing accepted ADR-MV8RUOYU.
    - criterion: Keep this issue decision-only; it does not select every exact key binding or require code, tests, or shortcut-list edits.
      result: pass
      notes: The issue scopes exact bindings and implementation changes to separately scoped work.
  checks_run:
    - Read the linked ADR and confirmed it exists and records the accepted Lightroom-first and Apple Photos fallback hierarchy.
    - Reviewed KRMA-956 acceptance criteria and its cited S11 context.
    - No build or test run, as specified for this decision-only issue.
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-15T00:42:28.721Z
  session: 01MV8TCPPQ963JHOZO
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - should-fix
  - decision
  - menus
  - keyboard
created: 2026-10-13T14:48:06.569Z
updated: 2026-10-15T00:42:28.724Z
parent: KRMA-922
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-15T00:41:29.264Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

## Objective

Record the preferred reference for Kromora keyboard shortcut conventions.

## Decision

Prefer Adobe Lightroom as the shortcut reference when Kromora has an equivalent action. Matching Apple Photos is also acceptable, especially when Lightroom has no clear equivalent or its convention does not fit Kromora's action. When both have a clear equivalent, prefer Lightroom because it is likely to be a common starting point for Kromora users.

This settles the product direction only. Exact per-command bindings and any source, test, or shortcut-documentation changes belong in separately scoped implementation work.

Recorded in [ADR-MV8RUOYU](../decisions/ADR-MV8RUOYU-lightroom-first-keyboard-shortcut-conventions-wi.md).

## Context

Review `.context/2026-10-13-release-readiness-review.md` finding S11 (bullets 1-2), which raised the current Delete, Export, and Derive Look bindings in `Sources/KromoraKit/Views/MenuCommands.swift`. The shortcut routing work in KRMA-920 and Undo/Redo work in KRMA-924 are complete; they motivated the original implementation plan but are not prerequisites for recording this convention.

## Acceptance criteria

- [x] State the Lightroom-first preference and Apple Photos fallback clearly.
- [x] Record the decision in DispatchGraph and link it from this issue.
- [x] Keep this issue decision-only; it does not select every exact key binding or require code, tests, or shortcut-list edits.

## Verification

- Confirm the linked ADR exists and records the accepted reference hierarchy.
- No build or test run is needed for this decision-only update.

## Agent log

- 2026-10-15T00:42:28.721Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] State the Lightroom-first preference and Apple Photos fallback clearly. (pass) — The issue and accepted ADR specify Lightroom as preferred when both apps have a clear equivalent, with Apple Photos acceptable when Lightroom has no clear equivalent or does not fit the action.
- [x] Record the decision in DispatchGraph and link it from this issue. (pass) — The issue links the existing accepted ADR-MV8RUOYU.
- [x] Keep this issue decision-only; it does not select every exact key binding or require code, tests, or shortcut-list edits. (pass) — The issue scopes exact bindings and implementation changes to separately scoped work.
Checks run:
- Read the linked ADR and confirmed it exists and records the accepted Lightroom-first and Apple Photos fallback hierarchy.
- Reviewed KRMA-956 acceptance criteria and its cited S11 context.
- No build or test run, as specified for this decision-only issue.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV8TCPPQ963JHOZO
Summary: Verified the decision-only Lightroom-first shortcut convention and linked accepted ADR; no build or tests required.
