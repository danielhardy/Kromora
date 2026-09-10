---
id: KRMA-320
title: Clean up DispatchGraph runtime artifacts and repository ignore rules
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 7fd6def867934284fb20f14ab24476dce6643f8c
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-09T15:06:02.723Z
  session: 01MTU8CGQLP9CUASED
labels:
  - git
  - maintenance
created: 2026-09-09T14:55:25.592Z
updated: 2026-09-10T12:53:56.474Z
order: a0
board: product
commits:
  - 7fd6def867934284fb20f14ab24476dce6643f8c
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

### Comment — codex @ 2026-09-09T15:04:36.080Z

Implemented and committed in 7fd6def. Added .project/mutations/ and archive/ ignore rules with documented policy that issues/ plus .project/events.jsonl are canonical; verified all 168 archive exports matched canonical issue bodies aside from frontmatter, moved the duplicate archive to a recoverable /tmp backup, preserved and committed all durable issue/event records and the KRMA-279 evidence asset, and left unrelated application test changes untouched. Verification: git diff --cached --check and dg validate passed; validate reports only the pre-existing unknown pickup-runner model warning.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-09T15:06:02.723Z: Verification report
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
- 7fd6def867934284fb20f14ab24476dce6643f8c
Actor: claude
Resolved model: sonnet
Pickup session: 01MTU8CGQLP9CUASED
Summary: Verified: mutations/archive ignore rules correct, durable issue/event history and KRMA-279 evidence asset preserved and committed, dg validate passes with only the pre-existing runner-model warning. No blockers.
