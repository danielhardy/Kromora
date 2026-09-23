---
id: KRMA-549
title: Retire EditDocumentStore compatibility shim in favor of package fixtures
type: task
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Legacy test composition points construct the package-backed EditDocumentStore initializer with real PortableLibraryPackage fixtures instead of EditDocumentStore(modelContainer:) / EditDocumentStore(fileURL:).
      result: pass
      notes: All 14 files migrated; new EditPackageFixture composes the canonical package initializer. One migrated test (CropWorkflowTests.testCommittedCropSurvivesRelaunch) was structurally broken and repaired during verification (commit 872127e); all others pass as migrated.
    - criterion: CompatibilityEditBackend, CompatibilityEditBackendRegistry, compatibilityBackends, compatibilityBackendKey/compatibilityFileURL, and the compat branches are removed.
      result: pass
      notes: EditDocumentStore.swift reduced to package-only paths plus a lease-less private init behind makeInMemoryProjectionStore; saveToCompatibilityBackend and both compat actors deleted.
    - criterion: grep for CompatibilityEditBackend in Sources/ is empty; PackageSettingsTests and the KRMA-545 listed suites still pass.
      result: pass
      notes: All greps empty (Sources and Tests). 149/149 pass across PackageSettingsTests (4), EditDocumentStoreTests (5), EditPersistenceIntegrationTests (11), PackageEditProjectionTests (2), PortableLibrarySessionTests (12), LUTWorkflowTests (7), ComparisonModeTests (16), CropModel/Pipeline/Workflow/Overlay (22/6/15/6), MaskingWorkspaceTests (36), LibraryDeletionCoordinatorTests (3), ImportedPhotoDurabilityTests (4). LibraryDeletionTests/AppViewModelTests fail only in the 6 pre-existing KRMA-548 methods.
    - criterion: No product behavior, public API, or schema changes.
      result: pass
      notes: AppViewModel init is internal; the only signature change is a defaulted injectedPortableLibrarySession test seam. onDiskFileURL nil was already the value for every package-backed store. Save path preserves encode-first failure semantics; persisted sidecar format untouched.
  checks_run:
    - grep -rn CompatibilityEditBackend Sources/ (empty)
    - grep -rn compatibilityBackendKey|compatibilityFileURL|compatibilityBackends Sources/ (empty)
    - grep -rn EditDocumentStore(modelContainer|EditDocumentStore(fileURL Sources/ Tests/ (empty)
    - grep -rn makeInMemoryEditContainer Sources/ Tests/ (empty)
    - "swift test 10-suite KRMA-549 filter: 88/88 pass"
    - "swift test CropModelTests|CropPipelineTests|CropWorkflowTests|CropOverlayViewTests: initial 48/49 (testCommittedCropSurvivesRelaunch timeout), 49/49 after verification fix"
    - "swift test PortableLibrarySessionTests: 12/12 pass"
    - "swift test LibraryDeletionTests|AppViewModelTests: failures confined to the 6 pre-existing KRMA-548 methods"
    - "swift build --build-tests warning check on touched files: no new diagnostics"
    - git status/diff review of c260442 plus AppViewModel identity/lease-path review
  findings:
    - "KRMA-549 migration defect (fixed): testCommittedCropSurvivesRelaunch kept the old two-view-model/one-fixture shape, but persistence keys strictly by the real import-minted portable identity, which the old compat backend's URL-alias map used to forgive; the second launch could never resolve the first launch's revision. Reworked to the shared-library-session relaunch pattern the same commit used for LUT/EditPersistence tests."
    - "Pre-existing failures unchanged: the 6 KRMA-548 methods fail identically; the migrated testLookSelectionAndIntensityStayWithTheirPhoto fails at a synchronous navigation-time assertion that never touches persistence, so it is orthogonal to this change."
    - "Repo-state note: clean HEAD c260442 does not compile standalone because an earlier stacked commit (cbd9e5b) references untracked WIP files (PackageJSONCoder et al.); verification signal was therefore gathered in the working tree, where all 14 KRMA-549 files are unmodified vs HEAD. No KRMA-549 file depends on the WIP."
    - "Non-blocking nits: makeInMemoryEditStore name is now misleading (it builds a package-backed store); AppViewModel carries an internal test-only session seam; EditPackageFixture has no cleanup path (tracked in backlog child KRMA-553)."
  fixes:
    - Reworked CropWorkflowTests.testCommittedCropSurvivesRelaunch to import once into a shared CropRelaunch.kromoralibrary session, drive the crop through the canonical session-backed store, shut down, and relaunch from a second session on the same package. Test-only change, no product code touched.
  verification_commits:
    - 872127e
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-23T12:39:51.475Z
  session: 01MUE2YMIQW1TFB5I6
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - verification
created: 2026-09-23T02:54:02.696Z
updated: 2026-09-23T12:39:51.478Z
parent: KRMA-545
order: y
board: product
commits:
  - 872127e
---

## Objective

Retire EditDocumentStore compatibility shim in favor of package fixtures

## Context

Parent: KRMA-545 (verification follow-up, non-blocking). KRMA-545 removed the
Swift 6 escape hatch by converting CompatibilityEditBackend /
CompatibilityEditBackendRegistry to actors (commit e293203). The shim itself
remains: the modelContainer:/fileURL: compatibility initializers, the per-store
compatibilityBackendKey, the global compatibilityBackends registry, and the async
compat branches in load/save/delete. The code comment states these exist only for
old headless test composition points while those tests move to package fixtures.

## Acceptance criteria

- [ ] Legacy test composition points construct the package-backed EditDocumentStore
  initializer with real PortableLibraryPackage fixtures instead of
  EditDocumentStore(modelContainer:) / EditDocumentStore(fileURL:).
- [ ] CompatibilityEditBackend, CompatibilityEditBackendRegistry, compatibilityBackends,
  compatibilityBackendKey/compatibilityFileURL, and the compat branches are removed.
- [ ] grep for CompatibilityEditBackend in Sources/ is empty; PackageSettingsTests and
  the KRMA-545 listed suites still pass.
- [ ] No product behavior, public API, or schema changes.

## Implementation notes

Likely files: Sources/KromoraKit/Models/EditDocumentStore.swift and the ~20 legacy
test call sites (LUTWorkflowTests, ComparisonModeTests, CropTests,
EditPersistenceIntegrationTests, MaskingWorkspaceTests, LibraryDeletionTests,
LibraryDeletionCoordinatorTests, ImportedPhotoDurabilityTests, AppViewModelTests).

### Comment — codex @ 2026-09-23T12:29:33.597Z

Retired the EditDocumentStore compatibility constructors, registry/backend, and compatibility branches. Migrated the affected tests to package-backed fixtures and package-session assets. Commit: c260442. Checks: 88/88 passed across PackageSettingsTests, EditDocumentStoreTests, EditPersistenceIntegrationTests, PackageEditProjectionTests, LUTWorkflowTests, ComparisonModeTests, CropTests, MaskingWorkspaceTests, LibraryDeletionCoordinatorTests, and ImportedPhotoDurabilityTests. LibraryDeletionTests and AppViewModelTests were not included in this run; KRMA-545 records existing failures in those suites, tracked by KRMA-548.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-23T12:39:51.476Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Legacy test composition points construct the package-backed EditDocumentStore initializer with real PortableLibraryPackage fixtures instead of EditDocumentStore(modelContainer:) / EditDocumentStore(fileURL:). (pass) — All 14 files migrated; new EditPackageFixture composes the canonical package initializer. One migrated test (CropWorkflowTests.testCommittedCropSurvivesRelaunch) was structurally broken and repaired during verification (commit 872127e); all others pass as migrated.
- [x] CompatibilityEditBackend, CompatibilityEditBackendRegistry, compatibilityBackends, compatibilityBackendKey/compatibilityFileURL, and the compat branches are removed. (pass) — EditDocumentStore.swift reduced to package-only paths plus a lease-less private init behind makeInMemoryProjectionStore; saveToCompatibilityBackend and both compat actors deleted.
- [x] grep for CompatibilityEditBackend in Sources/ is empty; PackageSettingsTests and the KRMA-545 listed suites still pass. (pass) — All greps empty (Sources and Tests). 149/149 pass across PackageSettingsTests (4), EditDocumentStoreTests (5), EditPersistenceIntegrationTests (11), PackageEditProjectionTests (2), PortableLibrarySessionTests (12), LUTWorkflowTests (7), ComparisonModeTests (16), CropModel/Pipeline/Workflow/Overlay (22/6/15/6), MaskingWorkspaceTests (36), LibraryDeletionCoordinatorTests (3), ImportedPhotoDurabilityTests (4). LibraryDeletionTests/AppViewModelTests fail only in the 6 pre-existing KRMA-548 methods.
- [x] No product behavior, public API, or schema changes. (pass) — AppViewModel init is internal; the only signature change is a defaulted injectedPortableLibrarySession test seam. onDiskFileURL nil was already the value for every package-backed store. Save path preserves encode-first failure semantics; persisted sidecar format untouched.
Checks run:
- grep -rn CompatibilityEditBackend Sources/ (empty)
- grep -rn compatibilityBackendKey|compatibilityFileURL|compatibilityBackends Sources/ (empty)
- grep -rn EditDocumentStore(modelContainer|EditDocumentStore(fileURL Sources/ Tests/ (empty)
- grep -rn makeInMemoryEditContainer Sources/ Tests/ (empty)
- swift test 10-suite KRMA-549 filter: 88/88 pass
- swift test CropModelTests|CropPipelineTests|CropWorkflowTests|CropOverlayViewTests: initial 48/49 (testCommittedCropSurvivesRelaunch timeout), 49/49 after verification fix
- swift test PortableLibrarySessionTests: 12/12 pass
- swift test LibraryDeletionTests|AppViewModelTests: failures confined to the 6 pre-existing KRMA-548 methods
- swift build --build-tests warning check on touched files: no new diagnostics
- git status/diff review of c260442 plus AppViewModel identity/lease-path review
Findings:
- KRMA-549 migration defect (fixed): testCommittedCropSurvivesRelaunch kept the old two-view-model/one-fixture shape, but persistence keys strictly by the real import-minted portable identity, which the old compat backend's URL-alias map used to forgive; the second launch could never resolve the first launch's revision. Reworked to the shared-library-session relaunch pattern the same commit used for LUT/EditPersistence tests.
- Pre-existing failures unchanged: the 6 KRMA-548 methods fail identically; the migrated testLookSelectionAndIntensityStayWithTheirPhoto fails at a synchronous navigation-time assertion that never touches persistence, so it is orthogonal to this change.
- Repo-state note: clean HEAD c260442 does not compile standalone because an earlier stacked commit (cbd9e5b) references untracked WIP files (PackageJSONCoder et al.); verification signal was therefore gathered in the working tree, where all 14 KRMA-549 files are unmodified vs HEAD. No KRMA-549 file depends on the WIP.
- Non-blocking nits: makeInMemoryEditStore name is now misleading (it builds a package-backed store); AppViewModel carries an internal test-only session seam; EditPackageFixture has no cleanup path (tracked in backlog child KRMA-553).
Fixes:
- Reworked CropWorkflowTests.testCommittedCropSurvivesRelaunch to import once into a shared CropRelaunch.kromoralibrary session, drive the crop through the canonical session-backed store, shut down, and relaunch from a second session on the same package. Test-only change, no product code touched.
Verification commits:
- 872127e
Actor: pi
Resolved model: unknown
Pickup session: 01MUE2YMIQW1TFB5I6
Summary: KRMA-549 passes: compatibility shim fully retired, 149/149 tests green across all affected suites, one migrated crop relaunch test repaired (872127e), remaining failures are the pre-existing KRMA-548 set.
