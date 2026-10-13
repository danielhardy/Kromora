---
id: KRMA-964
title: "DECISION: virtual copies duplicate the whole original — keep or move to reference-sharing?"
type: task
status: backlog
priority: low
human_review_required: true
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - release-readiness
  - nice-to-have
  - decision
  - library
  - storage
parent: KRMA-922
created: 2026-10-13T14:48:14.220Z
updated: 2026-10-13T14:48:24.186Z
blockers: []
order: zzzh
board: product
---

## Objective

Get a product decision on virtual-copy storage cost and, if the answer is "share", file the design
tickets.

## Context

Review `.context/2026-10-13-release-readiness-review.md` "Nice to have: Virtual copies duplicate the entire original". Today
`PortableLibrarySession.createVirtualCopy(of:)` (~L1167) re-imports the embedded original, so a
virtual copy of a 100 MB RAW costs another 100 MB and a full hash. A true virtual copy would share one
original between assets (reference counting, delete/trash semantics, backup/restore, integrity scrub,
tombstone/quarantine rules; see `docs/STORAGE_POLICY.md` and `docs/LIBRARY_PACKAGE_PLAN.md`).

## Acceptance criteria

- [ ] A comment summarizes: current cost, what sharing would require in the package format (assets that
      reference another asset's original), migration, and risks for backup/restore and delete.
- [ ] The human's decision is recorded (`dg decision`): keep duplicating for MVP (and document it in the
      Info inspector help text and `docs/PRODUCT_SCOPE.md`) or design shared originals.
- [ ] Follow-up tickets exist for whichever path was chosen.

## Implementation notes

Human decision: block with action "Decide: keep full-copy virtual copies for MVP, or share originals".
No source changes here.
