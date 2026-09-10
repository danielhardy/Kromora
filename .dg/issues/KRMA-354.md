---
id: KRMA-354
title: Reconcile and commit the accumulated dirty worktree
type: task
status: claimed
priority: urgent
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - maintenance
  - git
  - hygiene
created: 2026-09-10T16:03:43.049Z
updated: 2026-09-10T16:32:21.909Z
order: t
board: product
claim:
  actor: codex
  session: 01MTVQWMTWEX45XJAC
  claimed_at: 2026-09-10T16:32:21.908Z
  expires_at: 2026-09-10T17:32:21.908Z
  model: gpt-5.6-luna
---

## Objective

Safely reconcile and commit the accumulated uncommitted work in the current checkout. The worktree must be treated as shared user and agent work: preserve everything until each path has been attributed, reviewed, and placed into a coherent issue-sized commit. Do not solve the problem with a blanket commit or destructive cleanup.

## Evidence at ticket creation

- Branch: `krma-342-auto-evaluation`
- HEAD: `66e5d33` (`KRMA-342: add RenderEngine-backed Auto candidate evaluation foundation`)
- `KRMA-340` is marked `done`, but its frontmatter has `commits: []` and no matching commit exists in git history.
- The worktree reports 192 changed or untracked paths: 163 tracked paths changed and 29 untracked paths.
- The diff is approximately 740 insertions and 8,337 deletions.
- The accumulated changes span documentation, source/test reference comments, scripts, README/CLAUDE guidance, DG configuration/board state, many issue records, and issue assets. This is not a docs-only dirty tree.

## Required reconciliation scope

At minimum, explicitly account for these change clusters:

- KRMA-340 documentation audit: deletion of the prior docs tree, the five replacement current guides, the audit record, and cross-reference updates.
- Script lifecycle cleanup and capture-wrapper changes associated with KRMA-334.
- DG board/config changes, including removal of the visual Blocked column while retaining the blocked status, and any AI ticket creation policy change.
- DG issue lifecycle records, new issue files, verification reports, order changes, events, and screenshot assets.
- README, CLAUDE, scripts/README, source comments, and test comments that refer to renamed or removed documentation.
- Any functional source or test changes that do not belong to the documentation or script work.

## Acceptance criteria

- [ ] Establish the exact pre-reconciliation baseline and preserve all current user/agent changes; do not use `git reset --hard`, `git checkout --`, `git clean`, mass deletion, or equivalent destructive recovery.
- [ ] Produce a path-by-path inventory of all tracked modifications and untracked files, including the issue or intent each path belongs to and any ambiguous ownership.
- [ ] Compare each cluster with its corresponding DispatchGraph issue and existing commits. Identify work that is already committed but has stale or duplicated working-tree bookkeeping.
- [ ] Split the changes into coherent commits that follow the project rule of one issue per commit. Do not combine unrelated product implementation, docs cleanup, script retirement, and tracker repair merely to obtain a clean tree.
- [ ] Ensure KRMA-340 documentation work is committed with its retained docs, deletions, audit record, and required cross-reference edits, or create a clearly scoped follow-up if the current changes cannot be safely attributed to it.
- [ ] Ensure script retirement changes are committed under KRMA-334 or an explicitly justified follow-up, without losing active scripts or capture functionality.
- [ ] Reconcile DG records so no completed issue falsely has an empty commit list, no commit record points to a nonexistent commit, and issue statuses/verification reports match the commits actually present.
- [ ] Review all newly created issue files and assets; preserve legitimate records, attribute them to the correct work, and create follow-up tickets for work that must not be bundled into this recovery.
- [ ] Review the small source/test/README/CLAUDE edits for correctness after documentation renames; retain only intentional reference updates and do not silently alter product behavior.
- [ ] Run `dg validate`, `git diff --check`, repository reference checks, and the relevant build/test lanes for any source-affecting changes.
- [ ] End with a clean worktree for all reconciled scope, or leave only explicitly documented user-owned changes that have been isolated and separately ticketed.
- [ ] Add a completion comment listing the commit(s), the path groups included in each, any intentionally deferred files, checks run, and the final worktree state.

## Guardrails

The ticket is a recovery and commit-hygiene task, not authorization to discard work or rewrite unrelated history. If attribution is uncertain, preserve the files and record the ambiguity in a follow-up issue rather than guessing. Do not amend or rewrite existing commits unless explicitly required to correct a demonstrably incorrect issue reference.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
