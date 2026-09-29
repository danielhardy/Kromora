# AGENTS.md — Kromora

This project is managed with DispatchGraph: markdown issues, YAML boards, and an MCP tool contract.

## Agent setup

- Supported agents: cursor, claude, opencode, codex, pi.
- Default claim actor: `codex`.
- AI-created tickets may start in `ready` only when they have a meaningful objective, acceptance criteria, complete context, and no unresolved dependencies; otherwise they stay in `backlog`.
- Skip permission prompts on pickup for: cursor, claude, opencode, codex, pi.
- Pickup is enabled (`dg pickup`) with runner `codex` (model `gpt-6-luna`).
- Yolo mode is enabled: pickup skips the human review gate by automatically promoting successful `review` handoffs to `verification`. Agents should still hand off to `review` normally.
- Worktree isolation is disabled; `dg pickup` permits only one active claim in this shared working tree and waits for it to be released or expire before starting another.
- Counterpoint verification is enabled; default verifier: `claude` (model `sonnet`).
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

`backlog → ready → claimed → review → verification → done`

## Human blockers

When work needs a human decision, asset, credential, approval, or other action, add a Human blocker
with `dg issue block KRMA-123 --reason "…" --action "…"`. This records the blocker,
releases any active claim, moves the issue to `review`, and excludes it from pickup. Use
`dg blockers` to find Human and dependency blockers. After the person completes the requested
action, resolve it with `dg issue resume KRMA-123 [ready|verification]`. The default
returns to the saved stage when it was `verification`, and otherwise resumes at `ready`.

## Claiming work

Always claim before starting. Claims expire (default 60 minutes). Release if you lose context.

## Comments and actor identity

When commenting (`dg issue comment` or MCP `project_add_comment`), pass `actor` set to your
agent name (e.g. `cursor`, `claude`, `codex`) — never let it default to `human`. If omitted, it
falls back to the pickup-scoped `DG_ACTOR` environment variable (recognized when `DG_RUNNER` is
set), then the issue's active claim agent, then `agents.default_actor`.

The `actor` value is caller-supplied attribution, not authenticated identity. Passing `human`,
`web`, `cli`, or `mcp` can select operator-override behavior in lifecycle and claim-ownership
checks, but the service does not verify that the caller is actually an operator. Never use those
values to bypass a lifecycle gate: implementation agents stop at `review`, and only an active
verification claim should complete to `done`. Treat this as soft policy guidance; the tools accept
free-form actor strings and do not enforce this rule.

## Git workflow

- Work directly on the current branch — claims do not assign a per-issue branch or worktree (`git.branch_per_issue` is off).
- Keep the working tree to **one issue** at a time — do not pile unrelated tickets into the same session.
- Commit coherent work on the current branch when the change is ready for review.
- Start every commit subject with the issue id and a colon, followed by a short description (for example, KRMA-105: fix board column overflow). This applies to the implementation handoff commit and any follow-up verification fix commits for that issue.
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
