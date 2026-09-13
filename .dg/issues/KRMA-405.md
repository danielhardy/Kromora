---
id: KRMA-405
title: "Phase 2.5: package end-to-end fault-injection and relocation regression suite"
type: task
status: verification
priority: high
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - persistence
  - import
created: 2026-09-12T19:44:18.665Z
updated: 2026-09-13T13:25:38.779Z
depends_on:
  - KRMA-402
  - KRMA-403
  - KRMA-404
order: a0
board: product
---

## Objective

Close out Phase 2 with the consolidated fault-injection and relocation regression suite that proves
format, transactions, import, and sidecars hold together end to end — the acceptance bar KRMA-391 is
measured against.

## Dependencies

- The package-format, transaction-protocol, copy-on-import, and edit-sidecar tickets (this exercises
  all four together; do not start until they have landed).

## Scope

- Build end-to-end scenarios combining import + edit + Look reference + relocation: import a
  synthetic library (KRMA-389 generator) into a package, apply edits, copy the package to a new
  path/filesystem, and verify identical asset/edit/cache identity with no relink.
- Extend fault injection to full import-through-commit sequences (not just isolated transaction
  boundaries): disk-full during import, cancellation during edit-sidecar write, corrupt shard/record
  discovered on open, and lease contention during a concurrent import attempt.
- Verify current deletion behavior (KRMA-371) and current user data remain unaffected — this suite
  must include a check that no existing non-package library data is touched.
- Verify compatibility: a package written by this version opens correctly by a reader that only
  understands an older subset of fields (simulate via a stripped-down record).

## Acceptance criteria

- [ ] End-to-end import → edit → Look reference → relocation scenario passes with identical identity
  post-relocation and no relink.
- [ ] Disk-full, cancellation, corrupt shard/record, and lease-contention scenarios all recover
  without corruption or partial visibility.
- [ ] KRMA-371 deletion behavior and non-package user data are verified unaffected.
- [ ] A forward-compatibility check (older reader, newer-written package) passes for unknown-field
  tolerance.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Persistence/import fault-injection lane, end-to-end, including clean-profile package-copy tests and
filesystem relocation. This is the gate KRMA-391's own acceptance criteria reference; no UI
performance claim is accepted here (that is KRMA-392/393's scope).

## Context

- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, docs/TESTING.md
- context.issues: KRMA-391, KRMA-389


### Comment — codex @ 2026-09-13T13:25:29.754Z

Implemented KRMA-405 in 6462688. Added PortablePackageEndToEndRegressionTests covering synthetic import → edit → embedded Look → relocation identity/no-relink, disk-full import rollback, edit-sidecar cancellation rollback, corrupt shard/record open validation, lease contention, KRMA-371/current-library data isolation, and older-reader field tolerance. Added fault-injector/cancellation seams to import and sidecar paths and open-time catalog/record validation. Verification: focused suite 7/7; package/identity/deletion focused suite 37/37; swift build; git diff --check; dg validate --json. Full swift test: 1397 run, 52 skipped, 10 pre-existing unrelated UI/async failures.
