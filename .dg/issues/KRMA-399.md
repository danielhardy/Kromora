---
id: KRMA-399
title: "Phase 1.3: migrate EditRecord persistence and current-data disposition"
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: EditRecord/EditStore persistence keys exclusively off the new opaque identity
      result: pass
      notes: EditRecord.assetID is a UUID (PortablePhotoAssetID); load/save/delete/fetch predicates key on that UUID. sourcePath/sourceFileName/sourceBookmark are relinking hints only.
    - criterion: Current-data disposition documented and implemented
      result: pass
      notes: docs/EDIT_STORE_IDENTITY_DISPOSITION.md records the found state (no shipped user data), the human approval recorded in ADR-001 (approved 2026-09-13), and the clean-slate implementation.
    - criterion: No existing local EditStore data silently dropped/corrupted/rewritten
      result: pass
      notes: App now opens a separate EditStore.v2.store container; legacy EditStore.store path is left untouched (verified in EditDocumentStore.makeDefaultStore and defaultFileURL/portableStoreFileURL, plus testPortableStoreUsesExplicitCleanSlateFileBoundary).
    - criterion: KRMA-371 deletion behavior unchanged and not bundled
      result: pass
      notes: No deletion-workflow changes present in the diff; delete(for:) logic is unchanged aside from the identity key type.
    - criterion: swift build, swift test, dg validate, git diff --check pass
      result: pass
      notes: swift build clean; fast lane 949/949 passed; serial lane 371/371 passed; dg validate OK (only pre-existing unrelated model-name warnings); git diff --check clean.
  checks_run:
    - swift build
    - scripts/ci-tests.sh fast (949/949 passed)
    - scripts/ci-tests.sh serial (371/371 passed)
    - dg validate
    - git diff --check
    - manual review of EditRecord.swift, EditDocumentStore.swift, EditSourceReference, ExportCoordinator/SourceImportPlan/AppViewModel portableIdentity plumbing, docs/EDIT_STORE_IDENTITY_DISPOSITION.md, ADR-001 approval record
  findings:
    - "Minor style: stray dedent on the openImage(url:) missing-item fallback call in AppViewModel.swift (4-space instead of matching 12-space block indent), no functional effect. Fixed as a localized change."
  fixes:
    - "Sources/KromoraKit/ViewModels/AppViewModel.swift: restored correct indentation on the load(...) fallback call in openImage(url:); no behavior change."
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T04:58:31.556Z
  session: 01MTZCC5KHT4T4UBCK
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - library
  - architecture
  - identity
  - persistence
created: 2026-09-12T19:44:13.371Z
updated: 2026-09-13T04:58:31.559Z
depends_on:
  - KRMA-397
order: a0
board: product
---

## Objective

Migrate durable edit persistence (`EditRecord` and related SwiftData `EditStore` code) onto the new
opaque identity, and document/exercise the approved disposition of current local `EditStore` data —
without silently deleting or migrating anything if the no-shipped-user-data premise turns out to be
wrong.

## Dependencies

- The core-identity-types ticket (consumes `PhotoAssetID`/`PhotoSourceFingerprint`).
- Human approval of the current-data disposition (per ADR-001 and KRMA-390's own stated dependency).
  If this approval has not been recorded by the time this ticket is picked up, move it to `blocked`
  with `blocked_action` requesting the decision rather than guessing.

## Scope

- Update `EditRecord` and its persistence path to use the new identity instead of path/inode/mtime.
- Document the actual current-data situation found in the shipped app (confirm or refute "no shipped
  user data exists") and implement whichever disposition is approved: e.g. a one-time, explicit,
  reversible migration of existing local `EditStore` records to the new identity, or a documented
  clean-slate reset — never a silent drop.
- Preserve current editor and import behavior for the migration path: after migration, existing edits
  must still resolve to the same photo and same develop settings.
- Explicitly keep KRMA-371 (Library deletion) behavior out of this ticket's scope — do not bundle
  deletion-workflow changes here.

## Acceptance criteria

- [ ] `EditRecord`/`EditStore` persistence keys exclusively off the new opaque identity.
- [ ] The current-data disposition is documented (what was found, what was approved, what was done)
  and, if migration was approved, a migration path exists and is tested; if a clean slate was
  approved, that is explicit and irreversible-data-loss risk is called out rather than hidden.
- [ ] No existing local `EditStore` data is silently dropped, corrupted, or rewritten without the
  documented, approved disposition.
- [ ] KRMA-371 deletion behavior is unchanged and not bundled into this change.
- [ ] `swift build`, `swift test`, `dg validate`, and `git diff --check` pass.

## Verification lane

Persistence/unit lane for `EditRecord`/`EditStore`, plus a manual or scripted migration-path check
against a representative pre-migration `EditStore.store` fixture (synthetic, not real user data).

## Context

- context.files: Sources/KromoraKit (EditRecord, EditStore, EditPersistenceCoordinator)
- context.docs: docs/LIBRARY_PACKAGE_PLAN.md, .dg/decisions/ADR-001-portable-library-package-sequencing-and-safety-b.md
- context.issues: KRMA-390, KRMA-384


### Comment — codex @ 2026-09-13T04:55:23.371Z

Implemented opaque EditRecord/EditStore persistence and documented the approved current-data disposition. EditRecord.assetID is now UUID-backed PortablePhotoAssetID; explicit identities flow through source-import, preview, clipboard, and export persistence paths. The app opens a separate EditStore.v2.store clean-slate container, leaves legacy EditStore.store untouched, and retains locator fields only as operational relinking hints. Added Codable compatibility bridging and regression tests for relocation-stable UUID lookup, UUID-only records, and the explicit file boundary. KRMA-371 deletion behavior remains unchanged/out of scope. Verification: swift build passed; swift test passed (1369 executed, 52 skipped, 0 failures); focused EditDocumentStoreTests passed (19/19); dg validate OK; git diff --check passed. The repository has unrelated pre-existing Swift-format violations in the shared dirty worktree; acceptance checks above are green.

## Agent log

- 2026-09-13T04:58:31.557Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] EditRecord/EditStore persistence keys exclusively off the new opaque identity (pass) — EditRecord.assetID is a UUID (PortablePhotoAssetID); load/save/delete/fetch predicates key on that UUID. sourcePath/sourceFileName/sourceBookmark are relinking hints only.
- [x] Current-data disposition documented and implemented (pass) — docs/EDIT_STORE_IDENTITY_DISPOSITION.md records the found state (no shipped user data), the human approval recorded in ADR-001 (approved 2026-09-13), and the clean-slate implementation.
- [x] No existing local EditStore data silently dropped/corrupted/rewritten (pass) — App now opens a separate EditStore.v2.store container; legacy EditStore.store path is left untouched (verified in EditDocumentStore.makeDefaultStore and defaultFileURL/portableStoreFileURL, plus testPortableStoreUsesExplicitCleanSlateFileBoundary).
- [x] KRMA-371 deletion behavior unchanged and not bundled (pass) — No deletion-workflow changes present in the diff; delete(for:) logic is unchanged aside from the identity key type.
- [x] swift build, swift test, dg validate, git diff --check pass (pass) — swift build clean; fast lane 949/949 passed; serial lane 371/371 passed; dg validate OK (only pre-existing unrelated model-name warnings); git diff --check clean.
Checks run:
- swift build
- scripts/ci-tests.sh fast (949/949 passed)
- scripts/ci-tests.sh serial (371/371 passed)
- dg validate
- git diff --check
- manual review of EditRecord.swift, EditDocumentStore.swift, EditSourceReference, ExportCoordinator/SourceImportPlan/AppViewModel portableIdentity plumbing, docs/EDIT_STORE_IDENTITY_DISPOSITION.md, ADR-001 approval record
Findings:
- Minor style: stray dedent on the openImage(url:) missing-item fallback call in AppViewModel.swift (4-space instead of matching 12-space block indent), no functional effect. Fixed as a localized change.
Fixes:
- Sources/KromoraKit/ViewModels/AppViewModel.swift: restored correct indentation on the load(...) fallback call in openImage(url:); no behavior change.
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MTZCC5KHT4T4UBCK
Summary: KRMA-399 passes verification: EditRecord/EditStore now key persistence exclusively on opaque PortablePhotoAssetID UUIDs, the legacy EditStore.store is left untouched behind a new EditStore.v2.store container, and the approved clean-slate current-data disposition is documented in docs/EDIT_STORE_IDENTITY_DISPOSITION.md with human approval recorded in ADR-001. KRMA-371 deletion behavior is unchanged. swift build, the fast (949/949) and serial (371/371) test lanes, dg validate, and git diff --check all pass. Applied one trivial indentation fix in AppViewModel.swift (no behavior change).
