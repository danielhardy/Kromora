---
id: LUMO-253
title: Unattributed reconciliation commit (a42c5cf) exposes the known-broken addSmartMaskComponent retry path in production and leaves LUMO-237 untraced
type: bug
status: backlog
priority: urgent
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - masking
  - verification
created: 2026-09-06T14:28:13.713Z
updated: 2026-09-06T14:28:13.713Z
parent: LUMO-243
depends_on:
  - LUMO-251
order: zzzzzz
board: product
---

## Objective

Fix two problems in commit `a42c5cf` ("chore: reconcile pending masking work"), created during
LUMO-243's reconciliation of the shared working tree:

1. It newly wires the production per-layer "add component" combine-mode submenu
   (`MaskingWorkspace.swift`) to `addSmartMaskComponent`, which is the exact function LUMO-251
   (urgent, still `backlog`) documents as broken: after a failed component-add analysis, retry
   either freezes the workspace on "Analyzing mask…" indefinitely, or fires the wrong action. This
   path was not reachable from production UI before `a42c5cf`; the commit ships a new, real
   entry point into a known bug, without gating on LUMO-251.
2. The same commit also carries what looks like LUMO-237's implementation ("Foreground and
   Background mask components have no observable effect" — `restoreMaskSelection()` call in
   `AppViewModel.swift`, plus the `testSemanticPreviewRejectsAnUnavailableMaskInsteadOfSilentlySkippingIt`
   / `testForegroundAndBackgroundSemanticMasksChangePixelsInPreviewAndExport` tests named in
   LUMO-237's own `checks_run`), but LUMO-237.md's `verification_report.verification_commits` is
   still `[]`. Nothing in the tracker points LUMO-237 at `a42c5cf`, so LUMO-237 is currently in the
   exact same untraceable, loss-at-risk state that LUMO-243 was created to fix — just for a
   different ticket.

## Context

Found during LUMO-243 counterpoint verification. `a42c5cf` was made by `codex` as an
unattributed "chore" commit (no issue id in the message) bundling multiple tickets' worth of
functional changes together, which is exactly the failure mode
`CLAUDE.md`'s "Agent & workflow safety" section warns about (side-effect commits made silently by
an agent outside the normal one-ticket-one-commit flow). Diff comparison:

- `git show c0aed13 -- Sources/LumoKit/Views/MaskingWorkspace.swift` (LUMO-238's commit) only adds
  the top-level "Add Mask" menu's Smart masks section, calling `viewModel.createSmartMask`.
- `git show a42c5cf -- Sources/LumoKit/Views/MaskingWorkspace.swift` adds a *second*, previously
  absent Smart masks section inside the per-layer combine-mode ("add/subtract/intersect")
  submenu, calling `viewModel.addSmartMaskComponent` — the function LUMO-251 already flags as
  having no working retry path.

## Acceptance criteria

- [ ] The per-layer combine-mode submenu does not expose `addSmartMaskComponent`-backed smart
      mask kinds in production until LUMO-251's retry-context fix lands (either gate/hide it, or
      fix LUMO-251 first and merge in either order with the dependency wired as it is here).
- [ ] LUMO-237.md's `verification_report.verification_commits` is updated to reference the commit
      that actually carries its implementation (`a42c5cf`, or a follow-up commit if the content is
      re-split), so LUMO-237 is no longer untraceable in git history.
- [ ] `a42c5cf`'s bundled changes are (retroactively, via commit message / ticket linkage, not a
      history rewrite) attributed to the tickets they implement rather than left as an anonymous
      "chore" commit.

## Implementation notes

Do not rewrite git history to "fix" `a42c5cf`'s attribution — it is already on `main`. Fix
forward: update `LUMO-237.md`'s `verification_commits`, and address the premature
`addSmartMaskComponent` UI exposure by coordinating with LUMO-251 (add the gating/hide here, or
land it as part of LUMO-251's own fix).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
