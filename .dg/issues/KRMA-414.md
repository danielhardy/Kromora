---
id: KRMA-414
title: "Phase 4.4: quarantine/tombstone remove-from-library and confirmed reclaim-space"
type: feature
status: ready
priority: medium
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - backup
  - recovery
created: 2026-09-12T19:44:26.563Z
updated: 2026-09-13T04:44:03.038Z
depends_on:
  - KRMA-391
order: zzzzzq
board: product
---

## Objective

Implement recoverable "remove from library" (tombstone/quarantine trash) and a separate, explicitly
confirmed reclaim-space action that is the only path that permanently deletes originals — keeping
referenced originals (per ADR-001's reserved schema) untouched.

## Dependencies

- KRMA-391 (transaction/journal layer — quarantine and reclaim must go through the same crash-safe
  commit machinery as any other package write).

## Scope

- Implement "remove from library" as a tombstone/quarantine operation: the asset record is marked
  removed and its original moved to a quarantine area within the package, recoverable until reclaim.
- Implement a separate, explicitly confirmed "reclaim space" action that permanently deletes
  quarantined originals — this is the only operation in the whole package lifecycle allowed to
  permanently delete original photo data, and it requires explicit user confirmation.
- Referenced-asset originals (the schema-reserved-but-unexposed concept from KRMA-391) must never be
  touched by quarantine or reclaim, since the package does not own that original's lifecycle.
- Keep this distinct from and non-overlapping with KRMA-371's existing Library deletion workflow —
  document explicitly how the two relate (e.g. KRMA-371 is the current folder-backed deletion; this
  is the package-native lifecycle) so they are not silently conflated.

## Acceptance criteria

- [ ] "Remove from library" quarantines/tombstones an asset without deleting the original; it is
  recoverable before reclaim.
- [ ] Only the explicit, confirmed reclaim-space action permanently deletes quarantined originals;
  no other path deletes original photo data.
- [ ] Referenced-asset originals are never modified or deleted by quarantine or reclaim (test with a
  referenced-asset-flagged record).
- [ ] The relationship to KRMA-371's existing deletion behavior is documented and KRMA-371 behavior
  itself is unchanged.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Destructive-boundary fault-injection lane: quarantine-then-recover, quarantine-then-reclaim,
referenced-asset protection, and a regression check against KRMA-371's existing deletion tests.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, .dg/decisions/ADR-001-portable-library-package-sequencing-and-safety-b.md
- context.issues: KRMA-393, KRMA-391, KRMA-371
