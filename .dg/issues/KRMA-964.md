---
id: KRMA-964
title: "DECISION: virtual copies duplicate the whole original — keep or move to reference-sharing?"
type: task
status: done
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
created: 2026-10-13T14:48:14.220Z
updated: 2026-10-15T12:52:20.937Z
parent: KRMA-922
blockers: []
order: zzzzzzq
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-15T06:19:47.795Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
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


### Comment — codex @ 2026-10-15T02:05:54.271Z

Decision: Keep full-copy virtual copies for MVP. Each copy has its own package asset and independent edits/history, but it also reimports and hashes the full original; a 100 MB RAW therefore adds roughly 100 MB per copy. The project owner accepts this storage cost to keep per-asset ownership and package operations simple.

Sharing would require a package-format change so multiple assets can reference a single original, plus migration of existing copies. Delete, trash, reclaim, and quarantine must retain the source until the last dependent copy is removed. Backup, restore, and integrity validation must preserve and verify shared references without dangling or missing originals.

No shared-original design is planned for MVP. Revisit if concrete user demand shows the storage cost is a problem.


### Comment — claude @ 2026-10-15T06:19:39.939Z

Summary: decision recorded as ADR-KRMA-964 (keep full-copy virtual copies for MVP). Cost, format requirements for sharing, migration and backup/delete risks are in the earlier decision comment and the ADR. Follow-up: KRMA-1028 documents the storage cost in the Info inspector help and PRODUCT_SCOPE. No shared-original design ticket, per the decision.


### Comment — claude @ 2026-10-15T12:52:20.426Z

Human sign-off, posted by Claude at Daniel Hardy's direction on 2026-10-15. Daniel reviewed the decision comments and ADR-KRMA-964 and approves: keep full-copy virtual copies for MVP. Acceptance criteria are met: summary comment present, decision recorded in the ADR, follow-up KRMA-1028 filed for the Info inspector help and PRODUCT_SCOPE note. No shared-original design is planned.
