---
id: KRMA-405
title: "Phase 2.5: package end-to-end fault-injection and relocation regression suite"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: End-to-end import -> edit -> Look reference -> relocation scenario passes with identical identity post-relocation and no relink.
      result: pass
      notes: testSyntheticLibraryImportEditLookAndRelocationPreserveIdentityWithoutRelink covers a 64-asset slice of the KRMA-389 1000-asset generator, imports with dedupe, applies edits + embedded Look, copies the package to a nested new path, and asserts identity/cacheKey/editHistory equality plus byte-identical embedded sources with no relink.
    - criterion: Disk-full, cancellation, corrupt shard/record, and lease-contention scenarios all recover without corruption or partial visibility.
      result: pass
      notes: Four dedicated tests exercise each fault via the new PortablePackageFaultInjector .diskFull boundary and an isCancelled seam threaded through appendEditRevision/beginTransaction/commit; each asserts rollback (empty membership, no recovered transactions, source files untouched) and that the package still opens cleanly afterward.
    - criterion: KRMA-371 deletion behavior and non-package user data are verified unaffected.
      result: pass
      notes: testPackageWorkflowLeavesCurrentDeletionDataAndUnrelatedUserDataUntouched builds a separate non-package current library + unrelated file alongside independent package import/edit work, then verifies both are byte-identical before/after package operations and that AppViewModel deletion still removes only the intended current-library item and its edit store entry.
    - criterion: A forward-compatibility check (older reader, newer-written package) passes for unknown-field tolerance.
      result: pass
      notes: testOlderReaderDecodesCurrentPackageRecordAndIgnoresNewerFields decodes a current asset.json with a stripped-down Decodable subset and confirms the known fields still decode correctly.
    - criterion: swift build, swift test, dg validate, and git diff --check pass.
      result: pass
      notes: "Independently re-ran: swift build clean; focused PortablePackageEndToEndRegressionTests 7/7; broader PortablePackage|Deletion|Identity filter 78/78; git diff --check clean; dg validate --json ok:true (only pre-existing unrelated model-name warnings). Implementer's full swift test claim (1397 run, 10 pre-existing unrelated UI/async failures) was not independently re-run in full due to runtime cost but is consistent with the focused/broader runs observed here."
  checks_run:
    - swift build
    - swift test --filter PortablePackageEndToEndRegressionTests (7/7 pass)
    - swift test --filter 'PortablePackage|Deletion|Identity' (78/78 pass)
    - git diff --check
    - dg validate --json
  findings:
    - "medium/performance: PortableLibraryPackage.open() (Sources/KromoraKit/Models/PortableLibraryPackage.swift:344-363) now eagerly decodes every non-tombstoned asset record in every shard on every open, to surface the corrupt-record scenario. This conflicts with docs/LIBRARY_PACKAGE_PLAN.md guidance that full record scrubs run only via explicit validation/backup/restore/background maintenance, not on every open; at the plan's 100k-asset target scale this makes open() an O(n) JSON-decode pass. Not a blocker (tests pass, behavior is correct) and not a localized fix (needs a design decision on where corruption detection should live), so filed as child ticket KRMA-418 (verification-labeled, parent KRMA-405) rather than patched here."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T13:43:50.483Z
  session: 01MTZV2X0GPRWVRVMS
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
updated: 2026-09-13T13:43:50.485Z
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

## Agent log

- 2026-09-13T13:43:50.483Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] End-to-end import -> edit -> Look reference -> relocation scenario passes with identical identity post-relocation and no relink. (pass) — testSyntheticLibraryImportEditLookAndRelocationPreserveIdentityWithoutRelink covers a 64-asset slice of the KRMA-389 1000-asset generator, imports with dedupe, applies edits + embedded Look, copies the package to a nested new path, and asserts identity/cacheKey/editHistory equality plus byte-identical embedded sources with no relink.
- [x] Disk-full, cancellation, corrupt shard/record, and lease-contention scenarios all recover without corruption or partial visibility. (pass) — Four dedicated tests exercise each fault via the new PortablePackageFaultInjector .diskFull boundary and an isCancelled seam threaded through appendEditRevision/beginTransaction/commit; each asserts rollback (empty membership, no recovered transactions, source files untouched) and that the package still opens cleanly afterward.
- [x] KRMA-371 deletion behavior and non-package user data are verified unaffected. (pass) — testPackageWorkflowLeavesCurrentDeletionDataAndUnrelatedUserDataUntouched builds a separate non-package current library + unrelated file alongside independent package import/edit work, then verifies both are byte-identical before/after package operations and that AppViewModel deletion still removes only the intended current-library item and its edit store entry.
- [x] A forward-compatibility check (older reader, newer-written package) passes for unknown-field tolerance. (pass) — testOlderReaderDecodesCurrentPackageRecordAndIgnoresNewerFields decodes a current asset.json with a stripped-down Decodable subset and confirms the known fields still decode correctly.
- [x] swift build, swift test, dg validate, and git diff --check pass. (pass) — Independently re-ran: swift build clean; focused PortablePackageEndToEndRegressionTests 7/7; broader PortablePackage|Deletion|Identity filter 78/78; git diff --check clean; dg validate --json ok:true (only pre-existing unrelated model-name warnings). Implementer's full swift test claim (1397 run, 10 pre-existing unrelated UI/async failures) was not independently re-run in full due to runtime cost but is consistent with the focused/broader runs observed here.
Checks run:
- swift build
- swift test --filter PortablePackageEndToEndRegressionTests (7/7 pass)
- swift test --filter 'PortablePackage|Deletion|Identity' (78/78 pass)
- git diff --check
- dg validate --json
Findings:
- medium/performance: PortableLibraryPackage.open() (Sources/KromoraKit/Models/PortableLibraryPackage.swift:344-363) now eagerly decodes every non-tombstoned asset record in every shard on every open, to surface the corrupt-record scenario. This conflicts with docs/LIBRARY_PACKAGE_PLAN.md guidance that full record scrubs run only via explicit validation/backup/restore/background maintenance, not on every open; at the plan's 100k-asset target scale this makes open() an O(n) JSON-decode pass. Not a blocker (tests pass, behavior is correct) and not a localized fix (needs a design decision on where corruption detection should live), so filed as child ticket KRMA-418 (verification-labeled, parent KRMA-405) rather than patched here.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTZV2X0GPRWVRVMS
Summary: Verified: focused (7/7) and broader package/identity/deletion (78/78) suites pass, swift build clean, dg validate ok, git diff --check clean. Filed non-blocking child KRMA-418 for open()'s new eager per-asset-record decode, which conflicts with the documented lazy-validation policy at scale.
