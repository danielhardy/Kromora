---
id: KRMA-354
title: Reconcile and commit the accumulated dirty worktree
type: task
status: done
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
updated: 2026-09-10T16:39:25.576Z
order: t
board: product
commits:
  - 1544d61
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

### Comment — codex @ 2026-09-10T16:39:25.573Z

Completion details:

- Baseline: main at 066b0eb, 194 dirty status entries (192 paths plus status accounting); no destructive recovery commands were used.
- b61e093 (KRMA-334): retired mutate-step9.sh, mutate-step10a.sh, run-kromora-118-capture.sh, and run-kromora-123-capture.sh; added scripts/README.md and run-kromora-capture.sh; updated live capture references and test-audit comments.
- 7e42db7 (KRMA-340): deleted the obsolete docs tree, retained five current guides plus DOCUMENTATION_AUDIT.md, and updated README.md, CLAUDE.md, source comments, and test comments.
- 1544d61 (KRMA-354): reconciled DG board/config policy, issue statuses/reports/order/events, commit attribution, new KRMA-334–354 records, and KRMA-336/337/339 screenshot assets. Existing product commits were preserved and not rewritten; completed records for KRMA-335 and KRMA-339 were given their existing commit IDs.
- Checks: dg validate (OK; only pre-existing model/context warnings), git diff --check, zsh -n scripts/*.sh, capture-wrapper help smoke, repository stale-reference scan, swift build, and swift test (1,080 executed, 47 skipped, 0 failures).
- Deferred: a background pickup claimed KRMA-312 after this issue completed; its issue file and the corresponding append-only event-log tail remain untouched for that agent. No product/source work is deferred.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-10T16:38:27.340Z: Reconciled the shared worktree into KRMA-334 script, KRMA-340 documentation, and KRMA-354 DispatchGraph commits; preserved all DG records/assets and verified the final tree.
