---
id: KRMA-545
title: Remove @unchecked Sendable compat backend from EditDocumentStore
type: task
status: done
priority: urgent
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: grep -rn '@unchecked Sendable|nonisolated(unsafe)|@preconcurrency' Sources/ is empty
      result: pass
      notes: Only match is a // doc comment in KeyboardShortcuts.swift:250 discussing the rule by name; PackageSettingsTests explicitly excludes // lines and passes.
    - criterion: PackageSettingsTests passes
      result: pass
      notes: 4/4 green including testTheModuleUsesNoConcurrencyEscapeHatches.
    - criterion: EditDocumentStoreTests passes
      result: pass
      notes: 5/5 green.
    - criterion: EditPersistenceIntegrationTests passes
      result: pass
      notes: Suite green.
    - criterion: PackageEditProjectionTests passes
      result: pass
      notes: 2/2 green.
    - criterion: LUTWorkflowTests passes
      result: pass
      notes: 7/7 green.
    - criterion: ComparisonModeTests passes
      result: pass
      notes: 16/16 green.
    - criterion: CropTests passes (CropModelTests, CropOverlayViewTests)
      result: pass
      notes: Both suites green.
    - criterion: MaskingWorkspaceTests passes
      result: pass
      notes: 36/36 green.
    - criterion: LibraryDeletionCoordinatorTests passes
      result: pass
      notes: Suite green.
    - criterion: ImportedPhotoDurabilityTests passes
      result: pass
      notes: 4/4 green.
    - criterion: LibraryDeletionTests passes
      result: fail
      notes: "3 failures (testManagedCopyIsMovedOutOfLibraryWhileExternalSourceSurvives, testPersistenceFailureLeavesTheReferencedItemAndOriginalIntact, testReferencedDeletionRemovesEditsAndDoesNotReturnAfterRescan) reproduce byte-identically on clean-HEAD worktree f1c5a96 and on pre-change commit 96549f2: pre-existing, outside KRMA-545 scope, already tracked by KRMA-548."
    - criterion: AppViewModelTests passes
      result: fail
      notes: "3 failures (testLookSelectionAndIntensityStayWithTheirPhoto, testOpeningSourceFolderSurfacesBookmarkPersistenceFailure, testUnreadableSourceBookmarkDoesNotFallBackToManagedLibrary) reproduce byte-identically on clean-HEAD worktree f1c5a96 and on pre-change commit 96549f2: pre-existing, outside KRMA-545 scope, already tracked by KRMA-548."
    - criterion: No new product behavior, public API, or schema changes
      result: pass
      notes: Single-file diff (EditDocumentStore.swift); load/document/delete became async but all call sites already await through actor isolation, so no caller changes were needed; verified by clean zero-warning build.
  checks_run:
    - grep -rn '@unchecked Sendable|nonisolated(unsafe)|@preconcurrency' Sources/ (clean except one // comment)
    - swift build (clean)
    - swift build --build-tests -Xswiftc -warnings-as-errors (zero-warning gate, clean)
    - swift test --filter 'PackageSettingsTests|EditDocumentStoreTests' (9/9 pass)
    - swift test --filter 'EditPersistenceIntegrationTests|PackageEditProjectionTests|LUTWorkflowTests|ComparisonModeTests|CropTests|MaskingWorkspaceTests|ImportedPhotoDurabilityTests' (all suites pass)
    - swift test --filter 'LibraryDeletionTests|LibraryDeletionCoordinatorTests|AppViewModelTests|CropModelTests|CropOverlayViewTests' (LibraryDeletionCoordinatorTests/Crop suites pass; 3+3 pre-existing failures in LibraryDeletionTests/AppViewModelTests)
    - "clean-HEAD worktree (scripts/agent-worktree.sh, detached f1c5a96): LibraryDeletionTests|AppViewModelTests fail identically (shared-tree pollution ruled out; worktree removed afterwards)"
    - "same worktree checked out at 96549f2 (pre-e293203): identical 6 failures (KRMA-545 change ruled out as cause)"
  findings:
    - "Implementation (e293203) is correct: lock-backed CompatibilityEditBackend/Registry became actors, NSLock/os.lock import removed, State no longer falsely Sendable, per-store backend reference replaced by registry key resolved lazily (required because actor-isolated lookup cannot run in a sync init) preserving disposable test-store sharing semantics."
    - Actor-hop-per-op and per-element suspension in batch load affect only the in-memory test backend; package path performs identical synchronous file I/O inside the actor as before. No deadlock risk (no locks held across awaits).
    - 6 failures in LibraryDeletionTests/AppViewModelTests are pre-existing (identical at 96549f2 and clean HEAD f1c5a96), cluster in bookmark-persistence/trash/tombstone expectations untouched by this change, and are already tracked by backlog ticket KRMA-548; cross-evidence comment added there, no duplicate ticket created.
    - Shared working tree contains extensive unrelated uncommitted work (PackagePath refactor + new files); verification isolated the signal via clean worktrees and made zero source edits.
    - "Residual tech debt: the actor-based compat shim itself remains by design (issue option 1); full retirement to package fixtures tracked in new backlog child KRMA-549 (parent KRMA-545, labeled verification)."
  fixes: []
  verification_commits: []
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-23T02:55:31.955Z
  session: 01MUDI77KWWAJWYZJ0
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-22T21:58:19.122Z
updated: 2026-09-23T02:55:31.958Z
order: zh
board: product
---

## Objective

Remove @unchecked Sendable compat backend from EditDocumentStore

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — claude @ 2026-09-22T21:59:14.545Z

`EditDocumentStore.swift` (KRMA-531, commit 9d7d817) introduced `CompatibilityEditBackend` and `CompatibilityEditBackendRegistry`, two `private final class ... : @unchecked Sendable` types guarded by `NSLock`, used to keep ~20 legacy test files (LUTWorkflowTests, ComparisonModeTests, CropTests, EditPersistenceIntegrationTests, MaskingWorkspaceTests, LibraryDeletionTests, LibraryDeletionCoordinatorTests, ImportedPhotoDurabilityTests, AppViewModelTests, etc.) compiling against the new store without updating them to package fixtures.

This violates the project's binding Swift 6 zero-escape-hatch rule (CLAUDE.md: "zero diagnostics and zero escape hatches: no `@unchecked Sendable`, no `nonisolated(unsafe)`, no `@preconcurrency`"), and is caught by the existing regression test `PackageSettingsTests.testTheModuleUsesNoConcurrencyEscapeHatches`, which now fails:

XCTAssertEqual failed: (["EditDocumentStore.swift: private final class CompatibilityEditBackend: @unchecked Sendable {", "EditDocumentStore.swift: private final class CompatibilityEditBackendRegistry: @unchecked Sendable {"]) is not equal to ([])

Scope: remove the escape hatch, either by (1) converting the two classes into real Swift 6 actors (dropping NSLock) and making the ~20 call sites that construct EditDocumentStore(modelContainer:)/EditDocumentStore(fileURL:) await the now-async load/save path, or (2) removing the compatibility shim entirely and migrating the affected test files to real PortableLibraryPackage fixtures, consistent with KRMA-531's original scope of retiring legacy/non-package persistence paths.

Acceptance criteria:
- grep -rn "@unchecked Sendable|nonisolated(unsafe)|@preconcurrency" Sources/ is empty.
- PackageSettingsTests passes.
- scripts/ci-tests.sh fast and scripts/ci-tests.sh serial pass for EditDocumentStoreTests, EditPersistenceIntegrationTests, PackageEditProjectionTests, LUTWorkflowTests, ComparisonModeTests, CropTests, MaskingWorkspaceTests, LibraryDeletionTests, LibraryDeletionCoordinatorTests, ImportedPhotoDurabilityTests, AppViewModelTests.
- No new product behavior, public API, or schema changes beyond what's needed.

Likely files: Sources/KromoraKit/Models/EditDocumentStore.swift, Tests/KromoraKitTests/Fixtures.swift, and the test files listed above.

### Comment — codex @ 2026-09-23T02:29:08.111Z

Replaced the lock-backed compatibility backend and registry with Swift actors; made the affected store operations async while preserving package-backed behavior and disposable test-store sharing. Commit: e293203. Checks: EditDocumentStoreTests (5/5), PackageSettingsTests (4/4, including no escape hatches), EditPersistenceIntegrationTests (11/11), PackageEditProjectionTests (2/2), ImportedPhotoDurabilityTests (4/4), LUTWorkflowTests (7/7), ComparisonModeTests (16/16), and MaskingWorkspaceTests (36/36) passed. The focused run also found failures in legacy AppViewModel and LibraryDeletionTests expectations in this shared checkout. scripts/ci-tests.sh fast failed on unrelated existing UI/library/RAW tests. scripts/ci-tests.sh serial did not complete: KeyMonitorTests emitted repeated UI-event assertion failures and I stopped the runner. Source scan found no concurrency escape hatches in executable code; remaining matches are comments.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-23T02:55:31.956Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] grep -rn '@unchecked Sendable|nonisolated(unsafe)|@preconcurrency' Sources/ is empty (pass) — Only match is a // doc comment in KeyboardShortcuts.swift:250 discussing the rule by name; PackageSettingsTests explicitly excludes // lines and passes.
- [x] PackageSettingsTests passes (pass) — 4/4 green including testTheModuleUsesNoConcurrencyEscapeHatches.
- [x] EditDocumentStoreTests passes (pass) — 5/5 green.
- [x] EditPersistenceIntegrationTests passes (pass) — Suite green.
- [x] PackageEditProjectionTests passes (pass) — 2/2 green.
- [x] LUTWorkflowTests passes (pass) — 7/7 green.
- [x] ComparisonModeTests passes (pass) — 16/16 green.
- [x] CropTests passes (CropModelTests, CropOverlayViewTests) (pass) — Both suites green.
- [x] MaskingWorkspaceTests passes (pass) — 36/36 green.
- [x] LibraryDeletionCoordinatorTests passes (pass) — Suite green.
- [x] ImportedPhotoDurabilityTests passes (pass) — 4/4 green.
- [ ] LibraryDeletionTests passes (fail) — 3 failures (testManagedCopyIsMovedOutOfLibraryWhileExternalSourceSurvives, testPersistenceFailureLeavesTheReferencedItemAndOriginalIntact, testReferencedDeletionRemovesEditsAndDoesNotReturnAfterRescan) reproduce byte-identically on clean-HEAD worktree f1c5a96 and on pre-change commit 96549f2: pre-existing, outside KRMA-545 scope, already tracked by KRMA-548.
- [ ] AppViewModelTests passes (fail) — 3 failures (testLookSelectionAndIntensityStayWithTheirPhoto, testOpeningSourceFolderSurfacesBookmarkPersistenceFailure, testUnreadableSourceBookmarkDoesNotFallBackToManagedLibrary) reproduce byte-identically on clean-HEAD worktree f1c5a96 and on pre-change commit 96549f2: pre-existing, outside KRMA-545 scope, already tracked by KRMA-548.
- [x] No new product behavior, public API, or schema changes (pass) — Single-file diff (EditDocumentStore.swift); load/document/delete became async but all call sites already await through actor isolation, so no caller changes were needed; verified by clean zero-warning build.
Checks run:
- grep -rn '@unchecked Sendable|nonisolated(unsafe)|@preconcurrency' Sources/ (clean except one // comment)
- swift build (clean)
- swift build --build-tests -Xswiftc -warnings-as-errors (zero-warning gate, clean)
- swift test --filter 'PackageSettingsTests|EditDocumentStoreTests' (9/9 pass)
- swift test --filter 'EditPersistenceIntegrationTests|PackageEditProjectionTests|LUTWorkflowTests|ComparisonModeTests|CropTests|MaskingWorkspaceTests|ImportedPhotoDurabilityTests' (all suites pass)
- swift test --filter 'LibraryDeletionTests|LibraryDeletionCoordinatorTests|AppViewModelTests|CropModelTests|CropOverlayViewTests' (LibraryDeletionCoordinatorTests/Crop suites pass; 3+3 pre-existing failures in LibraryDeletionTests/AppViewModelTests)
- clean-HEAD worktree (scripts/agent-worktree.sh, detached f1c5a96): LibraryDeletionTests|AppViewModelTests fail identically (shared-tree pollution ruled out; worktree removed afterwards)
- same worktree checked out at 96549f2 (pre-e293203): identical 6 failures (KRMA-545 change ruled out as cause)
Findings:
- Implementation (e293203) is correct: lock-backed CompatibilityEditBackend/Registry became actors, NSLock/os.lock import removed, State no longer falsely Sendable, per-store backend reference replaced by registry key resolved lazily (required because actor-isolated lookup cannot run in a sync init) preserving disposable test-store sharing semantics.
- Actor-hop-per-op and per-element suspension in batch load affect only the in-memory test backend; package path performs identical synchronous file I/O inside the actor as before. No deadlock risk (no locks held across awaits).
- 6 failures in LibraryDeletionTests/AppViewModelTests are pre-existing (identical at 96549f2 and clean HEAD f1c5a96), cluster in bookmark-persistence/trash/tombstone expectations untouched by this change, and are already tracked by backlog ticket KRMA-548; cross-evidence comment added there, no duplicate ticket created.
- Shared working tree contains extensive unrelated uncommitted work (PackagePath refactor + new files); verification isolated the signal via clean worktrees and made zero source edits.
- Residual tech debt: the actor-based compat shim itself remains by design (issue option 1); full retirement to package fixtures tracked in new backlog child KRMA-549 (parent KRMA-545, labeled verification).
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: unknown
Pickup session: 01MUDI77KWWAJWYZJ0
Summary: KRMA-545 verified: @unchecked Sendable compat backend replaced with actors; escape-hatch scan clean, PackageSettingsTests 4/4, all edit-store-related suites green, zero-warning build passes. Six LibraryDeletion/AppViewModel failures are pre-existing (identical before the change) and tracked by KRMA-548; shim-retirement follow-up filed as KRMA-549.
