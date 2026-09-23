# AGENTS.md — Kromora

This project is managed with DispatchGraph: markdown issues, YAML boards, and an MCP tool contract.

## Agent setup

- Supported agents: cursor, claude, opencode, codex, pi.
- Default claim actor: `codex`.
- AI-created tickets may start in `ready` only when they have a meaningful objective, acceptance criteria, complete context, and no unresolved dependencies; otherwise they stay in `backlog`.
- Skip permission prompts on pickup for: cursor, claude, opencode, codex, pi.
- Pickup is enabled (`dg pickup`) with runner `codex` (model `gpt-5.6-luna`).
- Yolo mode is enabled: pickup skips the human review gate by automatically promoting successful `review` handoffs to `verification`. Agents should still hand off to `review` normally.
- Worktree isolation is disabled; `dg pickup` permits only one active claim in this shared working tree and waits for it to be released or expire before starting another.
- Counterpoint verification is enabled; default verifier: `pi`.
- Pickup automatically moves successful implementation handoffs from `review` to `verification`, releases the implementation lease, and launches the verifier.
- Verification uses its own process pool (max 1), independent from implementation pickup (max 1); worktrees isolate checkouts, but API spend and local services remain shared.
- Verifiers review correctness, maintainability, security, and performance; apply only localized safe fixes; create `verification`-labeled child tickets for broader findings; return blockers to `review`; pass by completing to `done`.
- Verification report contract: every pass records `verdict`, `acceptance_criteria` (each with `criterion`, `result`, and optional `notes`), `checks_run`, `findings`, `fixes`, and `verification_commits` through `project_complete_issue` or `dg issue complete --verification-report '<json>'`. Completion fills `actor` and the resolved pickup `model` authoritatively; use `unknown` when no model was available.
- For an unresolved blocker, create an urgent child dependency, then record it with `dg issue report-blocker <id> --verification-report '<json>' --summary "<plain-text summary>"` or `project_report_verification_blocker`; this persists the report, releases the verifier claim, and returns the issue to `review`. Do not complete a blocker to `done`.
- The structured report is machine-readable input for the completion tool only. Do not paste raw JSON into your final response; end with a concise, normal-text summary of the outcome, checks, findings, fixes, and any child blocker ticket.

## Quick start for agents

1. Prefer MCP tools (`project_get_next_work`, `project_claim_issue`, `project_get_context`) when available.
2. Or use the CLI: `dg next`, `dg issue claim <id>`, `dg context <id>`.
3. Canonical records live in `issues/*.md` (inside the dg space) — edit frontmatter carefully.
4. Append-only history is in `.project/events.jsonl`.
5. Do not invent a parallel task tracker.

## Status lifecycle

`backlog → ready → claimed → blocked → review → verification → done`

## Human intervention blocks

Use the explicit `blocked` status only when work cannot continue until a human provides a decision,
asset, credential, approval, or other action. Record a concise `blocked_reason` and the concrete
`blocked_action` requested from the human (each at most 500 characters). This is separate from
dependency blockers reported by `dg blockers`. A blocked issue is removed from pickup and active
agent claims are released. After the human responds, resume it with an explicit actionable status,
for example `dg issue resume KRMA-123 ready`; the reason and requested action remain
on the issue as history.

## Claiming work

Always claim before starting. Claims expire (default 60 minutes). Release if you lose context.

## Comments

When commenting (`dg issue comment` or MCP `project_add_comment`), pass `actor` set to your
agent name (e.g. `cursor`, `claude`, `codex`) — never let it default to `human`. If omitted, it
falls back to the pickup-scoped `DG_ACTOR` environment variable (recognized when `DG_RUNNER` is
set), then the issue's active claim agent, then `agents.default_actor`.

## Git workflow

- Work directly on the current branch — claims do not assign a per-issue branch or worktree (`git.branch_per_issue` is off).
- Keep the working tree to **one issue** at a time — do not pile unrelated tickets into the same session.
- Commit coherent work on the current branch when the change is ready for review.
- Implementation agents move the issue to `review` with a short summary comment. Do **not** mark `done` or merge unless a human or CI asks you to.
- Verification agents continue in the same working tree using the project Git mode; on pass they may complete to `done` after appending a structured report.
- Push or open a PR only when a human asks or project policy clearly allows it (`git.mode` is manual and `auto_commit` is off by default).

## Implementation handoff termination

After the implementation is complete, verified, and committed:

1. Add the required completion comment.
2. Transition the issue to review using the documented DispatchGraph command.
3. Stop immediately after the handoff succeeds.

Do not inspect or modify DispatchGraph lifecycle bookkeeping after handoff. In particular, do not inspect events or verifier activity, reconcile or repair board state, commit lifecycle changes, run additional status checks, or attempt to advance the issue beyond review. DispatchGraph owns all subsequent lifecycle transitions.

## Context

Each issue may declare `context.files`, `context.docs`, `context.issues`, and `context.commands`.
Request a budgeted context package instead of reading the whole repository.
