---
id: LUMO-228
title: "Commit LUMO-218/219 local-mask model work: HEAD does not build without untracked files"
type: bug
status: review
priority: urgent
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - blocker
  - masking
created: 2026-09-05T02:33:04.769Z
updated: 2026-09-05T04:03:10.425Z
order: y
board: product
---

## Objective

Land the durable local-mask model as an actual git commit so LUMO-218 and LUMO-219 are reproducible
from a clean checkout.

## Problem

LUMO-219 (`58a690a LUMO-219 render local adjustments through soft masks`) is committed, but its
implementation depends on types and an `EditDocument.localAdjustments` property that were **never
committed**:

- `Sources/LumoKit/Models/LocalMaskModels.swift` (defines `LocalAdjustmentLayer`, `MaskComponent`,
  `MaskCombineMode`, `MaskSource`, `LocalAdjustments`, semantic/brush/linear/radial definitions) is
  untracked (`git ls-files` returns nothing for it).
- The committed `Sources/LumoKit/Models/EditDocument.swift` at HEAD has no `localAdjustments`
  property at all (`git show HEAD:...EditDocument.swift | grep localAdjustments` is empty); the
  property only exists in an uncommitted working-tree modification.
- `Sources/LumoKit/Models/MaskInteractionState.swift` and `Tests/LumoKitTests/LocalMaskTests.swift`
  (LUMO-218's stated deliverables) are also untracked.

Verified reproduction: `scripts/agent-worktree.sh create` a throwaway worktree at current HEAD (tracked
files only) and `swift build` — fails with `error: cannot find type 'LocalAdjustmentLayer' in scope`
and related errors in `RenderPipeline.swift` and `LocalMaskRendering.swift`. A fresh clone or CI
checkout of this branch at HEAD is equally broken.

LUMO-218 is marked `status: done` with `verification_report.verdict: pass`, but that verification
recorded empty `checks_run`/`findings`/`verification_commits` and did not catch that no commit for
LUMO-218 exists at all.

## Acceptance criteria

- [ ] `LocalMaskModels.swift`, `MaskInteractionState.swift`, `Tests/LumoKitTests/LocalMaskTests.swift`,
      and the `EditDocument.localAdjustments` integration (identity/comparison/hash/copy-paste/
      migration) land as a real commit on `main`, scoped to LUMO-218's stated deliverables only.
- [ ] A clean `git worktree` checkout of the resulting HEAD builds (`swift build`) and passes
      `swift test` for the deterministic lane without relying on any untracked file.
- [ ] LUMO-218's issue record reflects the actual commit sha in a follow-up verification note.

## Context

The working tree currently mixes uncommitted changes for several other in-flight tickets
(LUMO-215/217/220-227 among the modified/untracked files in `git status`). Whoever picks this up
should commit only the LUMO-218-scoped files, not the unrelated changes, per the repo's "one issue
per commit" convention in `.dg/AGENTS.md`.


### Comment — codex @ 2026-09-05T04:03:10.033Z

Implemented in commit fe95f16. The LUMO-218 model and document integration are now tracked, so LUMO-219 no longer depends on untracked source files. Remaining in-progress capture work is being preserved separately from the active checkout.
