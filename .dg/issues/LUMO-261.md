---
id: LUMO-261
title: Handle assetID collision when relinking onto an existing record
type: task
status: ready
priority: medium
labels:
  - persistence
created: 2026-09-07T01:10:26.550Z
updated: 2026-09-07T04:14:15.550Z
depends_on:
  - LUMO-244
order: xh
board: product
---

## Objective

Decide what relinking onto an occupied `assetID` means. Today it crashes into the unique
constraint.

## Context

`EditRecord.assetID` is `@Attribute(.unique)`, but the relink path in `load(for:)` does
`record.assetID = key` without checking whether a record with `key` already exists (e.g. the
photo was edited under its new identity, then the old file moved back into place). The next
`persist()` throws a unique-constraint violation, reported as `.writeFailure` — and the
in-memory mutation has already rekeyed the object, so retrying the same load fails the same way.

The old dictionary store was last-write-wins here by construction; the constraint changed the
semantics without anyone choosing the new ones.

## Work

- Before rekeying, fetch for an existing record with the target key. On collision, pick and
  document the policy: keep newest (delete the loser), keep existing (discard the incoming
  relink), or surface an actionable status. Keep-newest matches the old store most closely.
- Whichever policy, the load must not leave the context in a state where retry deterministically
  fails.

## Acceptance criteria

- [ ] A relink whose target `assetID` is occupied resolves per the documented policy with no
      uniqueness violation and no poisoned-retry state.
- [ ] New test: two records, relink one onto the other's key, assert policy + subsequent loads
      succeed.
