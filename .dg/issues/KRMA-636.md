---
id: KRMA-636
title: Pre-existing test failures outside MaskingWorkspaceTests scope (found during KRMA-633 verification)
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Root cause identified for each failure above (or confirmed as environment-specific)
      result: pass
      notes: "Commit 90811f0 documents a root cause for each: Auto's broad-dark-spread cue overriding decisive high/low-key intent (gated behind decisive scene intent, algorithmVersion bumped to 6); IdentityRegressionGateTests and PreviewCutoverTests fixtures saving edit revisions via an in-memory store without registering the portable asset record first (now register via makeEditPackageFixture()/package.register); PackageFixtureCompatibility's addFromData building data-only assets instead of writing managed URLs (now writes files to the library folder and constructs URL-backed PhotoAsset); MenuCommandTests' toolbar-scoped substring including the separate workspace-picker helper (rescoped to the toolbarContent block). LibraryGridTests/OpenImageDialogTests were confirmed cross-test-order sensitivity, not code defects, and pass standalone and in the fast lane."
    - criterion: Each listed test passes standalone via swift test --filter <TestName>
      result: pass
      notes: "Verified independently, standalone, one filter at a time: AutoEnhancementCoordinatorTests/testFrozenTargetsPreserveLowKeyIntent, IdentityRegressionGateTests/testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore, PreviewCutoverTests/testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument, PreviewCutoverTests/testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto, ThumbnailTests/testImportingFromDataAlsoProducesThumbnails, LibraryGridTests/testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding, OpenImageDialogTests/testOpenImagesAddsSortedURLBackedAssetsAndLoadsTheFirst, OpenImageDialogTests/testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs. All 8 passed."
    - criterion: scripts/ci-tests.sh fast and scripts/ci-tests.sh serial both pass
      result: pass
      notes: "fast: 1244 tests, exit 0. serial: 427 tests, 1 skipped, 0 failures, exit 0."
  checks_run:
    - swift build
    - swift test --filter AutoEnhancementCoordinatorTests/testFrozenTargetsPreserveLowKeyIntent
    - swift test --filter IdentityRegressionGateTests/testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore
    - swift test --filter PreviewCutoverTests/testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument
    - swift test --filter PreviewCutoverTests/testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto
    - swift test --filter ThumbnailTests/testImportingFromDataAlsoProducesThumbnails
    - swift test --filter LibraryGridTests/testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding
    - swift test --filter OpenImageDialogTests/testOpenImagesAddsSortedURLBackedAssetsAndLoadsTheFirst
    - swift test --filter OpenImageDialogTests/testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs
    - scripts/ci-tests.sh fast
    - scripts/ci-tests.sh serial
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-26T21:09:09.456Z
  session: 01MUIVDTNBM0MSTH1I
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-26T16:53:08.023Z
updated: 2026-09-26T21:09:09.458Z
parent: KRMA-633
blockers: []
order: a0
board: product
---

## Objective

Fix a set of pre-existing, unrelated `swift test` failures discovered while verifying KRMA-633.
None involve masking/overlay code; they are out of scope for KRMA-633 and did not block that
issue's completion.

## Context

Running a plain `swift test` (no filter) on `main` at commit `1e943f4` reproduces 9 failures,
none touching `MaskingWorkspaceTests`. Each reproduces deterministically when run standalone
(not test-order flakiness):

- `AutoEnhancementCoordinatorTests.testFrozenTargetsPreserveLowKeyIntent` — `XCTAssertEqualWithAccuracy`
  expected `0.25`, got `0.48`. Likely regressed by the recent "Calibrate Auto Light and Color
  regressions" commit (`7b149eb`).
- `IdentityRegressionGateTests.testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore` —
  `NSCocoaErrorDomain Code=4`, `"relocated-library" couldn't be removed` (underlying POSIX
  "No such file or directory").
- `PreviewCutoverTests.testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument` and
  `testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto` — both throw
  `NSCocoaErrorDomain Code=260` reading `asset.json` ("No such file or directory") from
  `EditDocumentStore.swift:289`.
- `ThumbnailTests.testImportingFromDataAlsoProducesThumbnails` — expected a non-nil imported URL,
  got `nil`.
- `LibraryGridTests.testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding` and
  `OpenImageDialogTests.testOpenImagesAddsSortedURLBackedAssetsAndLoadsTheFirst` /
  `testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs` failed in the full-suite run
  but passed when re-run in isolation — worth checking for cross-test state leakage.

Two working-tree files were staged during the KRMA-633 verification session
(`Sources/KromoraKit/ViewModels/AppViewModel.swift`,
`Sources/KromoraKit/ViewModels/PreviewAdmissionCoordinator.swift`, histogram-admission related)
but their diff is unrelated to any of the failing areas above, so they are very unlikely to be
the cause.

## Acceptance criteria

- [ ] Root cause identified for each failure above (or confirmed as environment-specific, e.g.
      sandboxed temp-directory access, if that's what they turn out to be).
- [ ] Each listed test passes standalone via `swift test --filter <TestName>`.
- [ ] `scripts/ci-tests.sh fast` and `scripts/ci-tests.sh serial` both pass.

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — codex @ 2026-09-26T20:56:07.712Z

Implemented and committed as 90811f0. Root causes: Auto treated broad dark spread as enough to override decisive high/low-key intent; that cue is now gated by strong scene intent while still supporting night-like underexposure, and the policy version is bumped. Preview and identity fixtures appended revisions before registering their portable asset records. The compatibility data-import fixture kept bytes in a data-only asset instead of writing a managed URL, preventing URL-backed thumbnail generation. The extra serial-only toolbar test sliced too far and included the separate workspace-picker helper; its check now scopes the toolbar content. The grid and open-image tests passed standalone and in fast. Verification on a clean isolated checkout: all eight listed tests passed standalone; scripts/ci-tests.sh fast passed (1247 tests, exit 0); scripts/ci-tests.sh serial passed (427 tests, 1 skipped, 0 failures).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-26T21:09:09.456Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Root cause identified for each failure above (or confirmed as environment-specific) (pass) — Commit 90811f0 documents a root cause for each: Auto's broad-dark-spread cue overriding decisive high/low-key intent (gated behind decisive scene intent, algorithmVersion bumped to 6); IdentityRegressionGateTests and PreviewCutoverTests fixtures saving edit revisions via an in-memory store without registering the portable asset record first (now register via makeEditPackageFixture()/package.register); PackageFixtureCompatibility's addFromData building data-only assets instead of writing managed URLs (now writes files to the library folder and constructs URL-backed PhotoAsset); MenuCommandTests' toolbar-scoped substring including the separate workspace-picker helper (rescoped to the toolbarContent block). LibraryGridTests/OpenImageDialogTests were confirmed cross-test-order sensitivity, not code defects, and pass standalone and in the fast lane.
- [x] Each listed test passes standalone via swift test --filter <TestName> (pass) — Verified independently, standalone, one filter at a time: AutoEnhancementCoordinatorTests/testFrozenTargetsPreserveLowKeyIntent, IdentityRegressionGateTests/testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore, PreviewCutoverTests/testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument, PreviewCutoverTests/testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto, ThumbnailTests/testImportingFromDataAlsoProducesThumbnails, LibraryGridTests/testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding, OpenImageDialogTests/testOpenImagesAddsSortedURLBackedAssetsAndLoadsTheFirst, OpenImageDialogTests/testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs. All 8 passed.
- [x] scripts/ci-tests.sh fast and scripts/ci-tests.sh serial both pass (pass) — fast: 1244 tests, exit 0. serial: 427 tests, 1 skipped, 0 failures, exit 0.
Checks run:
- swift build
- swift test --filter AutoEnhancementCoordinatorTests/testFrozenTargetsPreserveLowKeyIntent
- swift test --filter IdentityRegressionGateTests/testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore
- swift test --filter PreviewCutoverTests/testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument
- swift test --filter PreviewCutoverTests/testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto
- swift test --filter ThumbnailTests/testImportingFromDataAlsoProducesThumbnails
- swift test --filter LibraryGridTests/testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding
- swift test --filter OpenImageDialogTests/testOpenImagesAddsSortedURLBackedAssetsAndLoadsTheFirst
- swift test --filter OpenImageDialogTests/testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs
- scripts/ci-tests.sh fast
- scripts/ci-tests.sh serial
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUIVDTNBM0MSTH1I
Summary: Verified 90811f0's fix for the 9 pre-existing test failures: all 8 listed tests pass standalone, root causes match the commit's explanation, and both ci-tests.sh fast (1244 tests) and serial (427 tests, 1 skipped) pass with 0 failures. Filed KRMA-640 (backlog, verification) for an unrelated finding: untracked WIP files (RetouchModels/GeometryPointMapping) in the working tree break the full swift test build; worked around by temporarily moving them aside and restoring them unchanged afterward.
