---
id: KRMA-412
title: "Phase 4.2: library restore with full pre-replace validation"
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
created: 2026-09-12T19:44:24.777Z
updated: 2026-09-13T04:44:01.481Z
depends_on:
  - KRMA-411
order: zzzzz
board: product
---

## Objective

Implement restore: a backup (or any package copy) is only promoted to the active library after it
validates completely, and a clean profile restoring it reproduces every edit exactly.

## Dependencies

- The backup ticket (restore consumes what it produces; the validation logic sibling ticket defines
  the checks restore relies on — coordinate ordering with whichever lands first, but restore must not
  ship without validation available).

## Scope

- Implement a restore flow that takes a backup (or package copy) location and validates it completely
  before making it the active library — the currently-active package must never be replaced with an
  unvalidated or partially-valid candidate.
- On validation failure, restore must fail cleanly, leaving the currently-active package untouched
  and reporting what failed.
- On success, verify from a clean profile (no prior local index/cache) that the restored package
  reproduces every edit exactly, using the index-rebuild-from-shards mechanism from KRMA-392.
- Support cancellation during restore with no partial replacement of the active package.

## Acceptance criteria

- [ ] Restore never replaces the active package until the candidate validates completely.
- [ ] A failed validation leaves the active package untouched and reports the specific failure.
- [ ] A clean-profile restore reproduces every edit exactly (content-level comparison against the
  pre-backup state), verified by an automated test.
- [ ] Cancellation during restore leaves the active package in its prior, untouched state.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Backup/restore fault-injection lane: clean-profile restore correctness, validation-failure handling,
and cancellation-safety of the active package.

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/ENGINEERING_GUIDE.md
- context.issues: KRMA-393, KRMA-392
