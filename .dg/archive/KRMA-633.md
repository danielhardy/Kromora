---
id: KRMA-633
title: Fix pre-existing mask-overlay scoping test failure (testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace)
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Root cause identified for why maskingState.showOverlay does not stay true when the inspector tab changes away from and back to masking (or navigates to .grid/.edit).
      result: pass
      notes: "Confirmed root cause in commit 1e943f4: d23f6f4 changed the clean-photo showOverlay default to false, but mask creation never flipped it back on. MaskingWorkflowCoordinator.swift:382-385 now sets interactionState.showOverlay = true when a mask is created; tab/workspace transitions already preserved masking state correctly."
    - criterion: testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace passes standalone and as part of the full MaskingWorkspaceTests suite.
      result: pass
      notes: swift test --filter MaskingWorkspaceTests/testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace passes standalone; swift test --filter MaskingWorkspaceTests passes with all 44 tests including this one.
    - criterion: No regression in the rest of MaskingWorkspaceTests.
      result: pass
      notes: "Full MaskingWorkspaceTests suite: 44/44 passed, 0 failures."
  checks_run:
    - swift build
    - swift test --filter MaskingWorkspaceTests (44/44 passed)
    - swift test --filter MaskingWorkspaceTests/testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace (standalone, passed)
    - swift test (full suite, temporarily relocating unrelated untracked WIP files Sources/KromoraKit/Models/RetouchModels.swift and Tests/KromoraKitTests/RetouchModelTests.swift that otherwise fail to compile; restored immediately after; 9 pre-existing failures found, all unrelated to masking, filed as KRMA-636)
  findings:
    - "CONFIRMED (test-coverage): Full-suite swift test run surfaces 9 pre-existing, deterministic failures unrelated to masking/overlay (AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent expected 0.25 got 0.48; IdentityRegressionGateTests.testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore; PreviewCutoverTests.testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument and testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto; ThumbnailTests.testImportingFromDataAlsoProducesThumbnails; plus LibraryGridTests and OpenImageDialogTests which fail only under the full-suite run but pass standalone). Filed as child ticket KRMA-636."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T16:54:01.400Z
  session: 01MUIM8650SB7GUQB6
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - masking
created: 2026-09-26T15:32:08.505Z
updated: 2026-09-28T14:41:35.824Z
parent: KRMA-589
blockers: []
order: q98x0znl
board: product
---

## Objective

`MaskingWorkspaceTests.testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace` fails at two
`XCTAssertTrue(viewModel.maskingState.showOverlay)` assertions (currently lines 98 and 104).

## Context

Found during KRMA-589 verification. The failure reproduces both alone and as part of the full
`MaskingWorkspaceTests` suite, and predates KRMA-589: the test file is unchanged since commit
`d23f6f4` (well before KRMA-589's `0df3fe5`), and the failure still reproduces with KRMA-589's
change reverted. It is unrelated to the Photo Analysis mask alignment fix and out of scope for
that ticket.

## Acceptance criteria

- [ ] Root cause identified for why `maskingState.showOverlay` does not stay `true` when the
      inspector tab changes away from and back to masking (or navigates to `.grid`/`.edit`).
- [ ] `testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace` passes standalone and as part of the
      full `MaskingWorkspaceTests` suite.
- [ ] No regression in the rest of `MaskingWorkspaceTests`.


## Objective

Fix pre-existing mask-overlay scoping test failure (testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace)

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-26T16:36:11.188Z

Root cause: d23f6f4 changed the clean-photo showOverlay default to false, but creating a mask did not enable the overlay; tab and workspace transitions were already preserving masking state. Mask creation now enables the overlay while the clean-photo default remains hidden. swift build and git diff --check passed. The targeted test could not compile because pre-existing untracked RetouchModelTests.swift references missing EditDocument.retouch API. Commit: 1e943f4.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-26T16:54:01.400Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Root cause identified for why maskingState.showOverlay does not stay true when the inspector tab changes away from and back to masking (or navigates to .grid/.edit). (pass) — Confirmed root cause in commit 1e943f4: d23f6f4 changed the clean-photo showOverlay default to false, but mask creation never flipped it back on. MaskingWorkflowCoordinator.swift:382-385 now sets interactionState.showOverlay = true when a mask is created; tab/workspace transitions already preserved masking state correctly.
- [x] testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace passes standalone and as part of the full MaskingWorkspaceTests suite. (pass) — swift test --filter MaskingWorkspaceTests/testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace passes standalone; swift test --filter MaskingWorkspaceTests passes with all 44 tests including this one.
- [x] No regression in the rest of MaskingWorkspaceTests. (pass) — Full MaskingWorkspaceTests suite: 44/44 passed, 0 failures.
Checks run:
- swift build
- swift test --filter MaskingWorkspaceTests (44/44 passed)
- swift test --filter MaskingWorkspaceTests/testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace (standalone, passed)
- swift test (full suite, temporarily relocating unrelated untracked WIP files Sources/KromoraKit/Models/RetouchModels.swift and Tests/KromoraKitTests/RetouchModelTests.swift that otherwise fail to compile; restored immediately after; 9 pre-existing failures found, all unrelated to masking, filed as KRMA-636)
Findings:
- CONFIRMED (test-coverage): Full-suite swift test run surfaces 9 pre-existing, deterministic failures unrelated to masking/overlay (AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent expected 0.25 got 0.48; IdentityRegressionGateTests.testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore; PreviewCutoverTests.testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument and testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto; ThumbnailTests.testImportingFromDataAlsoProducesThumbnails; plus LibraryGridTests and OpenImageDialogTests which fail only under the full-suite run but pass standalone). Filed as child ticket KRMA-636.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUIM8650SB7GUQB6
Summary: Verified: root cause and fix for the mask-overlay scoping regression confirmed correct; MaskingWorkspaceTests (44/44) passes standalone and in full. Filed KRMA-636 for 9 unrelated pre-existing swift test failures found during a full-suite run.
