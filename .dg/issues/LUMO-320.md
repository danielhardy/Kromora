---
id: LUMO-320
title: Clean up DispatchGraph runtime artifacts and repository ignore rules
type: task
status: claimed
priority: medium
labels:
  - git
  - maintenance
created: 2026-09-09T14:55:25.592Z
updated: 2026-09-09T15:00:40.230Z
order: x7
board: product
claim:
  actor: codex
  session: 01MTU86V1I5Y44K1GT
  claimed_at: 2026-09-09T15:00:40.230Z
  expires_at: 2026-09-09T16:00:40.230Z
  model: gpt-5.6-luna
---

## Objective

Separate disposable DispatchGraph runtime state from durable project records so routine agent
activity does not leave a large, confusing set of untracked files in the working tree.

## Context

DispatchGraph documents `.project/` as local runtime data, while issue Markdown, the append-only
event log, and referenced assets are repository records. The current checkout contains completed
mutation acknowledgements under `.project/mutations/`, a generated index/run state, an untracked
archive snapshot, and an issue-linked evidence image. Resolve each category deliberately rather
than adding a broad `.dg/` ignore rule.

## Acceptance criteria

- [ ] Add an ignore rule for completed/local `.project/mutations/` artifacts, and verify generated
      index/run/lock/pickup state remains ignored.
- [ ] Decide the repository policy for `.dg/archive/`: remove it if it is only a local duplicate
      export, or document and commit it if DispatchGraph requires it as durable history; do not
      silently discard unique issue content.
- [ ] Preserve and commit durable `.dg/issues/*.md` changes and `.dg/.project/events.jsonl`
      updates that correspond to real issue activity.
- [ ] Preserve the issue-linked `.dg/assets/` evidence file; do not ignore the entire assets
      directory unless all references are migrated or the policy explicitly permits it.
- [ ] Finish with one coherent cleanup commit, a clean `git status`, and passing `dg validate`.

## Implementation notes

Inspect tracked/untracked status and references before deleting anything. The cleanup must not
discard active issue records, event history, or referenced evidence, and must not interfere with
any in-progress DispatchGraph claim or verification run. Keep the scope limited to repository
hygiene; do not change application source or tests.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
