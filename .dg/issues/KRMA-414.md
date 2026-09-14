---
id: KRMA-414
title: "Phase 4.4: quarantine/tombstone remove-from-library and confirmed reclaim-space"
type: feature
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: '"Remove from library" quarantines/tombstones an asset without deleting the original; it is recoverable before reclaim.'
      result: pass
      notes: removeFromLibrary journals a stageMove of the whole Assets/<shard>/<assetID> directory into Recovery/Quarantine/<assetID>, tombstones the membership entry, and marks the record removed; restoreFromQuarantine reverses the move and clears the tombstone. Covered by testRemoveQuarantinesAndRestoreRecoversOriginalAndRecord.
    - criterion: Only the explicit, confirmed reclaim-space action permanently deletes quarantined originals; no other path deletes original photo data.
      result: pass
      notes: reclaimSpace(confirmed:) throws confirmationRequired when confirmed is false; only stageRemoval (restricted by prefix check to Recovery/Quarantine/) performs a destructive commit, and the directory is only truly gone once the transaction reaches state .committed and staging/backups are purged. Covered by testReclaimRequiresConfirmationAndPermanentlyRemovesOnlyQuarantine.
    - criterion: Referenced-asset originals are never modified or deleted by quarantine or reclaim (test with a referenced-asset-flagged record).
      result: pass
      notes: Both removeFromLibrary and reclaimSpace branch on record.source.storage == .referenced and skip all directory moves/removals for referenced assets, only updating the record/membership tombstone. Covered by testReferencedAssetIsTombstonedButNeverQuarantinedOrReclaimed.
    - criterion: The relationship to KRMA-371's existing deletion behavior is documented and KRMA-371 behavior itself is unchanged.
      result: pass
      notes: docs/LIBRARY_PACKAGE_FORMAT.md ("Package-native trash") and docs/LIBRARY_PACKAGE_PLAN.md explicitly state this lifecycle is distinct from and does not call KRMA-371's folder-backed deletion workflow. No KRMA-371 source was touched by the change; full suite (including its existing deletion tests) passes unchanged.
    - criterion: swift build, swift test, dg validate, and git diff --check pass.
      result: pass
      notes: swift build clean; scripts/ci-tests.sh fast (1005 tests) and serial (375 tests) both green; dg validate --json ok:true with only pre-existing unrelated model-name warnings; git diff --check clean.
  checks_run:
    - swift build
    - swift test --filter PortablePackageTrashTests
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
    - dg validate --json
    - git diff --check
  findings:
    - "low/maintainability: PortablePackageTrash.swift defined six unused alias overloads (removeFromLibrary(for:)/removeFromLibrary(assetID:), restoreFromTrash/restoreFromQuarantine(assetID:), reclaimQuarantinedSpace/emptyTrash) that only forwarded to the base method and had zero callers in tests or product code. Fixed: removed as a localized, behavior-preserving cleanup (commit 53f3f07); build and full test suite re-verified green."
  fixes:
    - Removed unused trash API alias overloads in Sources/KromoraKit/Models/PortablePackageTrash.swift (no behavior change; build and full test suite re-verified green).
  verification_commits:
    - 53f3f07
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T18:14:03.690Z
  session: 01MU04PSFR610Y7YKA
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
updated: 2026-09-13T18:14:03.692Z
depends_on:
  - KRMA-391
order: a0
board: product
commits:
  - 53f3f07
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


### Comment — codex @ 2026-09-13T18:09:54.475Z

Implemented package-native quarantine/tombstone removal and explicit confirmation-gated reclaim. Added journaled reversible directory moves and staged removals with crash rollback, removed-record persistence, restore/empty-trash APIs, referenced-asset protection, and KRMA-371 separation docs. Verification: swift build; swift test (1,430 executed, 53 skipped, 0 failures); focused PortablePackageTrashTests (4/4); dg validate --json (OK; existing model-name warnings only); git diff --check. Commit: d7f405f.

## Agent log

- 2026-09-13T18:14:03.690Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] "Remove from library" quarantines/tombstones an asset without deleting the original; it is recoverable before reclaim. (pass) — removeFromLibrary journals a stageMove of the whole Assets/<shard>/<assetID> directory into Recovery/Quarantine/<assetID>, tombstones the membership entry, and marks the record removed; restoreFromQuarantine reverses the move and clears the tombstone. Covered by testRemoveQuarantinesAndRestoreRecoversOriginalAndRecord.
- [x] Only the explicit, confirmed reclaim-space action permanently deletes quarantined originals; no other path deletes original photo data. (pass) — reclaimSpace(confirmed:) throws confirmationRequired when confirmed is false; only stageRemoval (restricted by prefix check to Recovery/Quarantine/) performs a destructive commit, and the directory is only truly gone once the transaction reaches state .committed and staging/backups are purged. Covered by testReclaimRequiresConfirmationAndPermanentlyRemovesOnlyQuarantine.
- [x] Referenced-asset originals are never modified or deleted by quarantine or reclaim (test with a referenced-asset-flagged record). (pass) — Both removeFromLibrary and reclaimSpace branch on record.source.storage == .referenced and skip all directory moves/removals for referenced assets, only updating the record/membership tombstone. Covered by testReferencedAssetIsTombstonedButNeverQuarantinedOrReclaimed.
- [x] The relationship to KRMA-371's existing deletion behavior is documented and KRMA-371 behavior itself is unchanged. (pass) — docs/LIBRARY_PACKAGE_FORMAT.md ("Package-native trash") and docs/LIBRARY_PACKAGE_PLAN.md explicitly state this lifecycle is distinct from and does not call KRMA-371's folder-backed deletion workflow. No KRMA-371 source was touched by the change; full suite (including its existing deletion tests) passes unchanged.
- [x] swift build, swift test, dg validate, and git diff --check pass. (pass) — swift build clean; scripts/ci-tests.sh fast (1005 tests) and serial (375 tests) both green; dg validate --json ok:true with only pre-existing unrelated model-name warnings; git diff --check clean.
Checks run:
- swift build
- swift test --filter PortablePackageTrashTests
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
- dg validate --json
- git diff --check
Findings:
- low/maintainability: PortablePackageTrash.swift defined six unused alias overloads (removeFromLibrary(for:)/removeFromLibrary(assetID:), restoreFromTrash/restoreFromQuarantine(assetID:), reclaimQuarantinedSpace/emptyTrash) that only forwarded to the base method and had zero callers in tests or product code. Fixed: removed as a localized, behavior-preserving cleanup (commit 53f3f07); build and full test suite re-verified green.
Fixes:
- Removed unused trash API alias overloads in Sources/KromoraKit/Models/PortablePackageTrash.swift (no behavior change; build and full test suite re-verified green).
Verification commits:
- 53f3f07
Actor: claude
Resolved model: sonnet
Pickup session: 01MU04PSFR610Y7YKA
Summary: Verified package-native quarantine/reclaim: destructive-boundary fault-injection lane covers quarantine-then-recover, quarantine-then-reclaim, and referenced-asset protection; KRMA-371 separation is documented and its behavior is untouched. Removed unused trash API alias overloads as a localized cleanup. swift build, full fast+serial test suite, dg validate, and git diff --check all pass.
