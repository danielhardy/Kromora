---
id: KRMA-253
title: Unattributed reconciliation commit (a42c5cf) exposes the known-broken addSmartMaskComponent retry path in production and leaves KRMA-237 untraced
type: bug
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: The per-layer combine-mode submenu does not expose addSmartMaskComponent-backed smart mask kinds in production until LUMO-251's retry-context fix lands
      result: pass
    - criterion: LUMO-237.md's verification_report.verification_commits is updated to reference the commit that actually carries its implementation
      result: pass
    - criterion: a42c5cf's bundled changes are retroactively attributed to the tickets they implement rather than left as an anonymous chore commit
      result: pass
  checks_run:
    - swift test --filter MaskingWorkspaceTests (30 passed, 0 failures, includes testRetryingFailedSmartComponentReattemptsTheOriginalLayerAdd)
    - swift test --filter LocalMaskRenderingTests (19 passed, 0 failures)
    - dg validate (OK; pre-existing unrelated pickup-runner model warning)
    - git diff --check (clean)
    - git status --porcelain (clean aside from DispatchGraph bookkeeping)
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-07T14:46:41.126Z
  session: 01MTRCRNTV5B7IICZY
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - masking
  - verification
created: 2026-09-06T14:28:13.713Z
updated: 2026-09-10T12:53:50.884Z
parent: KRMA-243
depends_on:
  - KRMA-251
order: a0
board: product
---

## Objective

Fix two problems in commit `a42c5cf` ("chore: reconcile pending masking work"), created during
KRMA-243's reconciliation of the shared working tree:

1. It newly wires the production per-layer "add component" combine-mode submenu
   (`MaskingWorkspace.swift`) to `addSmartMaskComponent`, which is the exact function KRMA-251
   (urgent, still `backlog`) documents as broken: after a failed component-add analysis, retry
   either freezes the workspace on "Analyzing mask…" indefinitely, or fires the wrong action. This
   path was not reachable from production UI before `a42c5cf`; the commit ships a new, real
   entry point into a known bug, without gating on KRMA-251.
2. The same commit also carries what looks like KRMA-237's implementation ("Foreground and
   Background mask components have no observable effect" — `restoreMaskSelection()` call in
   `AppViewModel.swift`, plus the `testSemanticPreviewRejectsAnUnavailableMaskInsteadOfSilentlySkippingIt`
   / `testForegroundAndBackgroundSemanticMasksChangePixelsInPreviewAndExport` tests named in
   KRMA-237's own `checks_run`), but KRMA-237.md's `verification_report.verification_commits` is
   still `[]`. Nothing in the tracker points KRMA-237 at `a42c5cf`, so KRMA-237 is currently in the
   exact same untraceable, loss-at-risk state that KRMA-243 was created to fix — just for a
   different ticket.

## Context

Found during KRMA-243 counterpoint verification. `a42c5cf` was made by `codex` as an
unattributed "chore" commit (no issue id in the message) bundling multiple tickets' worth of
functional changes together, which is exactly the failure mode
`CLAUDE.md`'s "Agent & workflow safety" section warns about (side-effect commits made silently by
an agent outside the normal one-ticket-one-commit flow). Diff comparison:

- `git show c0aed13 -- Sources/LumoKit/Views/MaskingWorkspace.swift` (KRMA-238's commit) only adds
  the top-level "Add Mask" menu's Smart masks section, calling `viewModel.createSmartMask`.
- `git show a42c5cf -- Sources/LumoKit/Views/MaskingWorkspace.swift` adds a *second*, previously
  absent Smart masks section inside the per-layer combine-mode ("add/subtract/intersect")
  submenu, calling `viewModel.addSmartMaskComponent` — the function KRMA-251 already flags as
  having no working retry path.

## Acceptance criteria

- [ ] The per-layer combine-mode submenu does not expose `addSmartMaskComponent`-backed smart
      mask kinds in production until KRMA-251's retry-context fix lands (either gate/hide it, or
      fix KRMA-251 first and merge in either order with the dependency wired as it is here).
- [ ] KRMA-237.md's `verification_report.verification_commits` is updated to reference the commit
      that actually carries its implementation (`a42c5cf`, or a follow-up commit if the content is
      re-split), so KRMA-237 is no longer untraceable in git history.
- [ ] `a42c5cf`'s bundled changes are (retroactively, via commit message / ticket linkage, not a
      history rewrite) attributed to the tickets they implement rather than left as an anonymous
      "chore" commit.

## Implementation notes

Do not rewrite git history to "fix" `a42c5cf`'s attribution — it is already on `main`. Fix
forward: update `KRMA-237.md`'s `verification_commits`, and address the premature
`addSmartMaskComponent` UI exposure by coordinating with KRMA-251 (add the gating/hide here, or
land it as part of KRMA-251's own fix).

### Comment — codex @ 2026-09-07T14:45:21.576Z

Implemented and verified KRMA-253. KRMA-251 is already fixed on this branch (commit 9fe440a), and MaskingWorkspaceTests passed 30/30 including the component retry regression, so the per-layer smart-mask submenu remains enabled. Linked a42c5cf to KRMA-237's verification_commits/commits and KRMA-238's commits. Added the attribution metadata in commit 0ba6afe. Checks: swift test --filter MaskingWorkspaceTests; swift test --filter LocalMaskRenderingTests (19/19); dg validate; git diff --check.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-07T14:46:41.127Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] The per-layer combine-mode submenu does not expose addSmartMaskComponent-backed smart mask kinds in production until KRMA-251's retry-context fix lands (pass)
- [x] KRMA-237.md's verification_report.verification_commits is updated to reference the commit that actually carries its implementation (pass)
- [x] a42c5cf's bundled changes are retroactively attributed to the tickets they implement rather than left as an anonymous chore commit (pass)
Checks run:
- swift test --filter MaskingWorkspaceTests (30 passed, 0 failures, includes testRetryingFailedSmartComponentReattemptsTheOriginalLayerAdd)
- swift test --filter LocalMaskRenderingTests (19 passed, 0 failures)
- dg validate (OK; pre-existing unrelated pickup-runner model warning)
- git diff --check (clean)
- git status --porcelain (clean aside from DispatchGraph bookkeeping)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTRCRNTV5B7IICZY
Summary: Verified: KRMA-251 fix (9fe440a) landed before completion so the production combine-mode submenu's addSmartMaskComponent path is safe; KRMA-237/KRMA-238 commits fields and KRMA-237 verification_commits now reference a42c5cf, resolving the attribution gap. All declared checks reproduced clean.
