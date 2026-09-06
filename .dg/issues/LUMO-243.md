---
id: LUMO-243
title: Uncommitted LUMO-235/LUMO-236 masking fixes at risk of loss in shared working tree
type: bug
status: review
priority: high
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - masking
  - editor
  - verification
created: 2026-09-06T04:05:19.885Z
updated: 2026-09-06T14:28:50.285Z
parent: LUMO-234
order: a0
board: product
---

## Objective

Commit (or otherwise reconcile) the code for LUMO-235 and LUMO-236, both of which are recorded
`status: done` with a passing `verification_report`, even though no corresponding commit exists in
git history.

## Context

Discovered while running counterpoint verification for LUMO-234 in this shared (non-worktree)
checkout. At that time `git status --porcelain` showed real, non-trivial modifications to
`Sources/LumoKit/Models/MaskInteractionState.swift`, `Sources/LumoKit/Models/CanvasNavigation.swift`,
`Sources/LumoKit/ViewModels/AppViewModel.swift`, `Sources/LumoKit/ViewModels/AppViewModel+Masking.swift`,
`Sources/LumoKit/Views/MaskingWorkspace.swift`, and both `CanvasNavigationTests.swift` and
`MaskingWorkspaceTests.swift` — none of it staged or committed.

That diff matches the described implementations of:
- LUMO-235 ("Linear gradient: new masks open with unusable controls") — the two-stage
  `beginPendingCreation`/`selectionBeforePendingCreation` draft flow.
- LUMO-236 ("Radial gradient drag translates the mask disproportionately") — the
  `sourceNormalizedDelta(forViewportDelta:)` conversion and its use in `updateMaskGesture`.

Both issue files record `verification_report.verdict: pass` with `verification_commits: []` and
`updated` timestamps of 2026-09-06T03:49Z / 2026-09-06T03:57Z — before LUMO-234's own commit
(b68a39a, 2026-09-06T03:31Z is earlier, but the ticket was updated at 04:02Z; regardless, no
commit for either 235 or 236 exists on this branch). Per `.dg/AGENTS.md`, tickets on this project
run sequentially on the current branch as one commit each, and worktree isolation is disabled, so
only one claim should be active against this tree at a time. Two "done" tickets' worth of work
currently exists only as uncommitted local changes: any `git checkout --`, `git clean`, `git stash
drop`, or reset run against this tree — by a person or another agent — would silently erase both
without the tracker ever reflecting it, since both are already marked `done`.

Confirmed the tree still builds and `swift test --filter 'MaskingWorkspaceTests|CanvasNavigationTests'`
passes with this uncommitted code present alongside LUMO-234's commit, so the code itself is not
obviously broken — this ticket is about the missing commit(s), not a functional defect.

## Acceptance criteria

- [ ] Either commit the current uncommitted working-tree changes as the LUMO-235 and LUMO-236
      implementations (one commit per ticket, referencing the issue id, per the project's git
      workflow), or confirm with a human that the work should be discarded and re-open the tickets
      if so.
- [ ] `git status --porcelain` is clean afterward (aside from any new intended output).
- [ ] `verification_report.verification_commits` on LUMO-235 and LUMO-236 reflects the actual
      commit(s) once this is resolved.

## Implementation notes

Do not run a destructive git operation (`clean`, `stash drop/clear`, `reset --hard`, `checkout --`)
against this tree until this is resolved — that is exactly the data this ticket exists to protect.

### Comment — codex @ 2026-09-06T14:25:42.622Z

Reconciled the orphaned completed masking work in the shared checkout. LUMO-235 is preserved in commit 4d03ede (transient linear-gradient creation, cancel/undo/selection regressions); LUMO-236 is preserved in commit 126f5e3 (viewport-to-source radial translation, geometry regression). Updated LUMO-235 and LUMO-236 verification_commits to those SHAs. Preserved other pre-existing masking edits in reconciliation commit a42c5cf. Verification: swift test --filter 'MaskingWorkspaceTests|CanvasNavigationTests' (42 passed, 0 failed); dg validate OK.

### Comment — claude @ 2026-09-06T14:28:45.287Z

Counterpoint verification (blocker found; returning to review)

LUMO-243's own acceptance criteria are satisfied: LUMO-235 and LUMO-236 are committed (4d03ede,
126f5e3), their verification_commits fields reference those SHAs, and git status --porcelain is
clean of source changes. swift test --filter 'MaskingWorkspaceTests|CanvasNavigationTests' passes
(42/42).

However, the reconciliation itself (commit a42c5cf, made by codex while resolving this ticket) is
not clean:

1. a42c5cf newly wires the production per-layer 'add component' combine-mode submenu
   (MaskingWorkspace.swift) to addSmartMaskComponent — this is the exact function LUMO-251
   (urgent, still backlog/unclaimed) documents as broken: retry after a failed component-add
   analysis either freezes the workspace on 'Analyzing mask…' indefinitely, or fires the wrong
   action. This path was not reachable from production UI before a42c5cf (verified via git show
   c0aed13 vs a42c5cf on MaskingWorkspace.swift); the commit ships a brand-new entry point into a
   known bug, without gating on LUMO-251.
2. a42c5cf also appears to carry LUMO-237's implementation (restoreMaskSelection() call plus the
   two LocalMaskRenderingTests named in LUMO-237's own checks_run), but LUMO-237.md's
   verification_report.verification_commits is still []. LUMO-237 is therefore in the same
   untraceable, loss-at-risk state LUMO-243 exists to fix — just undiscovered until now.

Filed LUMO-253 (urgent, parent LUMO-243, depends_on LUMO-251) to track both. No local fix applied:
resolving (1) requires a product/UX decision (gate vs. hide vs. fast-follow LUMO-251) that exceeds
a localized safe fix, and (2) is a tracker-metadata correction on another ticket's completed
verification record, not this ticket's code.

Checks run: swift test --filter 'MaskingWorkspaceTests|CanvasNavigationTests' (42 passed, 0
failed); git status --porcelain (clean of source); git show a42c5cf / c0aed13 diff comparison;
dg validate.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
