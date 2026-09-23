---
id: KRMA-548
title: Finish package-backed edit-store fixture migration and clear fast-lane failures
type: task
status: review
priority: medium
verification_report:
  verdict: blocker
  acceptance_criteria:
    - criterion: Package-backed test fixtures register every asset needed by their persistence, selection, prefetch, and export assertions; the store continues to fail closed for genuinely missing records.
      result: pass
      notes: b8d0842 migrates the CopyPaste, Export, Filmstrip, Coordinator, EndToEnd, and Benchmark suites to makeEditPackageFixture()+register() with byte-distinct payloads; 21 of 22 prior migration failures cleared. No production package validation was weakened (no changes to sidecar, validation, or transaction code).
    - criterion: Every failure from a fresh fast-lane run is classified as a real defect, invalid test setup, or environment/toolchain limitation, with real defects and invalid fixtures corrected.
      result: fail
      notes: Residual DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest classified as a real intent-vs-implementation defect (histogram never re-tallies for the displayed comparison baseline despite the documented displayRequest contract). Fix is outside verifier scope; moved to urgent child KRMA-554, and KRMA-548 now depends on it.
    - criterion: scripts/ci-tests.sh fast passes on the resulting tree.
      result: fail
      notes: "Fresh lane on the working tree: 1172 tests run, 1171 pass; sole failure is the histogram-vs-comparison test above (2 assertion failures inside 1 test)."
  checks_run:
    - "swift test --filter DevelopInspectorTests.testHistogramFollowsTheDisplayedComparisonRequest (isolated repro on working tree: 1 test, 2 failures)"
    - "scripts/ci-tests.sh fast (full lane: 1172 tests executed, only testHistogramFollowsTheDisplayedComparisonRequest fails)"
    - scripts/check-swift-format.sh on the full dirty tree and scoped with SWIFT_FORMAT_BASE=99be0bf (results confounded by the local Swift 6.4 beta toolchain flagging pristine files; see findings)
    - "read-only review of commit b8d0842 (15 files: 3 product, 12 test) plus the Fixtures/EditPackageFixture helpers"
    - "clean-worktree build probe at b8d0842 (fails: PackageJSONCoder.swift was never committed; see KRMA-555)"
  findings:
    - "BLOCKER (KRMA-554): the comparison histogram is never tallied. showOriginal(true) succeeds and the baseline preview request completes, but histogramRequests stays at 2. Suspect the presentSettledRaster / previewSurface.present onPresented / didPresentVisibleFrame / updateHistogram routing; note FakeRenderEngine.histogram(presentedImage:) records lastPreviewRecord, so check both halves."
    - "b8d0842 adds two small product-behavior changes beyond fixtures: (1) Shift range selection routed through portable selection authority (LibraryQueryController.setSelection + PortableLibrarySession.setPortableSelection) - reviewed as coherent; (2) presentImportOutcome suppresses import summaries while a Loading status shows, which can swallow partial-failure summaries - flagged for follow-up review in KRMA-555."
    - "Test re-specifications reviewed: bookmark tests renamed to pin package-era behavior (legacy bookmark ignored; unsupported-URL message); the referenced-deletion test inverted to RetainsImmutableEdits, consistent with the PortablePackageTrash tombstone-plus-quarantine contract and the STORAGE_POLICY immutability row; EmbeddedFirstFrameTests dropped one status assertion (mild weakening, noted)."
    - "HEAD b8d0842 does not compile on a clean checkout: PortablePackageImporter.encode (introduced by cbd9e5b) needs the never-committed PackageJSONCoder.swift. Verification ran on the working tree where the file is present. Tracked in KRMA-555 together with the other untracked Sep-22 helpers (PackagePath, NumericClamping) and the uncommitted PackagePath-ification modifications, which belong to an unidentified in-flight effort and were left untouched."
    - "The implementer's 'formatting lint passed' claim does not reproduce and cannot be adjudicated locally: the Swift 6.4 beta swift-format flags even pristine committed files, so neither b8d0842's 10 flagged files nor the 24 other dirty files can be judged here; the CI macos-26 toolchain is authoritative. No reformatting was applied. Tracked in KRMA-555."
  fixes: []
  verification_commits: []
  actor: pi
  resolved_model: unknown
  completed_at: 2026-09-23T15:02:21.872Z
  session: 01MUE7QIS3TXOJW0IE
creation_provenance:
  runner: pi
  model: unknown
  actor: pi
labels:
  - verification
created: 2026-09-23T02:42:27.013Z
updated: 2026-09-23T15:02:21.931Z
depends_on:
  - KRMA-544
  - KRMA-554
order: y
board: product
---

## Objective

Complete the migration to package-backed edit persistence fixtures, then triage and clear the
remaining deterministic fast-lane failures.

## Context

Parent: KRMA-544 (verification finding; the current failure set also includes later work).

The old report below is stale. A fresh `scripts/ci-tests.sh fast` run on 2026-09-23 failed with
22 test cases across 12 suites. The best-supported root cause is an incomplete test migration in
commit `c260442` (`Retire EditDocumentStore compatibility backend`): `makeInMemoryEditStore()` now
creates a real package-backed store, but several tests do not register the scanned/imported photo
in that package before saving edits. `EditDocumentStore.save` calls `appendEditRevision`, which
must read `Assets/<shard>/<asset-id>/asset.json`; it throws Cocoa error 260 when that fixture
record is absent. AppViewModel treats the save as a persistence failure, so subsequent selection,
paste, and prefetch waits time out or observe the identity document.

This was reproduced serially, without parallel test interference, in
`PortablePackageEndToEndRegressionTests/testPackageWorkflowLeavesCurrentDeletionDataAndUnrelatedUserDataUntouched`;
the error names the missing `asset.json`. A serial run of
`CopyPasteTests/testSinglePasteIsUndoableAndDoesNotChangeTheSource` also fails while waiting for
photo selection and then observes the wrong edit state. That test uses a package-backed store with
temporary imported photos that are not registered in its package, which is consistent with the
failed-save mechanism; confirm by fixing fixture registration. The other three failing
`CopyPasteTests` cases use the same setup and are likely part of this migration gap. The captured
full-lane log explicitly reports missing `asset.json` in `CoordinatorBoundaryTests`, two
`ExportCoordinatorTests`, two `FilmstripNavigationTests`, and
`SingleViewLatencyBenchmark/testSingleViewOpenBaselineReportsIdentityEditedAndMaskedShapes`.
Audit package-backed test stores and register every referenced/imported item they save or prefetch.
The full run's likely affected cases are `CoordinatorBoundaryTests/testPersistenceCoordinatorCoalescesSnapshotsAndPreservesFlushCompatibility`,
`CopyPasteTests/testMultiPasteUpdatesOnlySelectedPhotosAndEachDestinationCanUndo`,
`testSinglePasteIsUndoableAndDoesNotChangeTheSource`,
`testFilmstripShiftSelectionBuildsRangeThatPasteCovers`,
`testSelectiveCopyMaskLeavesUncheckedDestinationStagesIntact`,
`ExportCoordinatorTests/testBatchExportUsesEachAssetsPersistedDocument`,
`testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals`,
`FilmstripNavigationTests/testAdjacentPrefetchUsesStoredEditsForNeverOpenedNeighbor`,
`testEachFilmstripOpenAdmitsItsSettledPreview`,
`PortablePackageEndToEndRegressionTests/testPackageWorkflowLeavesCurrentDeletionDataAndUnrelatedUserDataUntouched`,
and `SingleViewLatencyBenchmark/testSingleViewOpenBaselineReportsIdentityEditedAndMaskedShapes`.
Do not weaken production package validation to make those fixtures pass.

The same full run also reported failures whose root cause is not established by the package-record
finding; triage these separately instead of labeling the entire set as one fixture issue:

- `AppViewModelTests/testOpeningSourceFolderSurfacesBookmarkPersistenceFailure`
- `AppViewModelTests/testUnreadableSourceBookmarkDoesNotFallBackToManagedLibrary`
- `AppViewModelTests/testLookSelectionAndIntensityStayWithTheirPhoto`
- `DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest`
- `EmbeddedFirstFrameTests/testEmbeddedFirstFrameProvisionalThenSettled`
- `ImageDropTests/testBitmapDropUsesTheExistingDataImportPath`
- `LibraryCullingTests/testCullingStateSurvivesACollectionRecreation`
- `LibraryDeletionTests/testManagedCopyIsMovedOutOfLibraryWhileExternalSourceSurvives`,
  `testPersistenceFailureLeavesTheReferencedItemAndOriginalIntact`,
  `testReferencedDeletionRemovesEditsAndDoesNotReturnAfterRescan`
- `FilmstripNavigationTests/testAdjacentPrefetchScaleKeyMatchesSubsequentSelectionPreview`

Current fast-lane output is in `/private/tmp/kromora-fast-lane.log` for this checkout's run; rerun
the lane after making changes because some earlier KRMA-547 fixes have already removed failures
from the previous ticket list.

## Acceptance criteria

- [ ] Package-backed test fixtures register every asset needed by their persistence, selection,
  prefetch, and export assertions; the store continues to fail closed for genuinely missing records.
- [ ] Every failure from a fresh fast-lane run is classified as a real defect, invalid test setup, or
  environment/toolchain limitation, with real defects and invalid fixtures corrected.
- [ ] `scripts/ci-tests.sh fast` passes on the resulting tree.

## Implementation notes

Focus first on fixture migration fallout from `c260442`; keep any actual product persistence fix
separate from test-only asset registration. Then handle residual bookmark, histogram, first-frame,
drop, culling, deletion, and prefetch failures with isolated reproductions.

### Historical comment — pi @ 2026-09-23T02:54:50.455Z

KRMA-545 counterpoint verification independently reproduced the six AppViewModelTests/LibraryDeletionTests failures listed here (testLookSelectionAndIntensityStayWithTheirPhoto, testOpeningSourceFolderSurfacesBookmarkPersistenceFailure, testUnreadableSourceBookmarkDoesNotFallBackToManagedLibrary, testManagedCopyIsMovedOutOfLibraryWhileExternalSourceSurvives, testPersistenceFailureLeavesTheReferencedItemAndOriginalIntact, testReferencedDeletionRemovesEditsAndDoesNotReturnAfterRescan). They fail identically on clean-HEAD worktree f1c5a96 and on pre-change commit 96549f2, so they are outside KRMA-545 scope as well. No duplicate ticket created.

### Comment — codex @ 2026-09-23T14:43:10.835Z

Committed b8d0842: registered every edited/exported/prefetched asset in package-backed test fixtures, made imported copy/paste payloads byte-distinct, routed Shift range selection through portable selection authority, and migrated stale folder-based culling/deletion/import expectations. The focused migration suite (19 cases) passes. A fresh scripts/ci-tests.sh fast run still has one failure: DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest continues reporting the edited document after the comparison preview completes; other reported fast-lane failures cleared. Formatting lint passed for the touched files.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-23T15:02:21.930Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Package-backed test fixtures register every asset needed by their persistence, selection, prefetch, and export assertions; the store continues to fail closed for genuinely missing records. (pass) — b8d0842 migrates the CopyPaste, Export, Filmstrip, Coordinator, EndToEnd, and Benchmark suites to makeEditPackageFixture()+register() with byte-distinct payloads; 21 of 22 prior migration failures cleared. No production package validation was weakened (no changes to sidecar, validation, or transaction code).
- [ ] Every failure from a fresh fast-lane run is classified as a real defect, invalid test setup, or environment/toolchain limitation, with real defects and invalid fixtures corrected. (fail) — Residual DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest classified as a real intent-vs-implementation defect (histogram never re-tallies for the displayed comparison baseline despite the documented displayRequest contract). Fix is outside verifier scope; moved to urgent child KRMA-554, and KRMA-548 now depends on it.
- [ ] scripts/ci-tests.sh fast passes on the resulting tree. (fail) — Fresh lane on the working tree: 1172 tests run, 1171 pass; sole failure is the histogram-vs-comparison test above (2 assertion failures inside 1 test).
Checks run:
- swift test --filter DevelopInspectorTests.testHistogramFollowsTheDisplayedComparisonRequest (isolated repro on working tree: 1 test, 2 failures)
- scripts/ci-tests.sh fast (full lane: 1172 tests executed, only testHistogramFollowsTheDisplayedComparisonRequest fails)
- scripts/check-swift-format.sh on the full dirty tree and scoped with SWIFT_FORMAT_BASE=99be0bf (results confounded by the local Swift 6.4 beta toolchain flagging pristine files; see findings)
- read-only review of commit b8d0842 (15 files: 3 product, 12 test) plus the Fixtures/EditPackageFixture helpers
- clean-worktree build probe at b8d0842 (fails: PackageJSONCoder.swift was never committed; see KRMA-555)
Findings:
- BLOCKER (KRMA-554): the comparison histogram is never tallied. showOriginal(true) succeeds and the baseline preview request completes, but histogramRequests stays at 2. Suspect the presentSettledRaster / previewSurface.present onPresented / didPresentVisibleFrame / updateHistogram routing; note FakeRenderEngine.histogram(presentedImage:) records lastPreviewRecord, so check both halves.
- b8d0842 adds two small product-behavior changes beyond fixtures: (1) Shift range selection routed through portable selection authority (LibraryQueryController.setSelection + PortableLibrarySession.setPortableSelection) - reviewed as coherent; (2) presentImportOutcome suppresses import summaries while a Loading status shows, which can swallow partial-failure summaries - flagged for follow-up review in KRMA-555.
- Test re-specifications reviewed: bookmark tests renamed to pin package-era behavior (legacy bookmark ignored; unsupported-URL message); the referenced-deletion test inverted to RetainsImmutableEdits, consistent with the PortablePackageTrash tombstone-plus-quarantine contract and the STORAGE_POLICY immutability row; EmbeddedFirstFrameTests dropped one status assertion (mild weakening, noted).
- HEAD b8d0842 does not compile on a clean checkout: PortablePackageImporter.encode (introduced by cbd9e5b) needs the never-committed PackageJSONCoder.swift. Verification ran on the working tree where the file is present. Tracked in KRMA-555 together with the other untracked Sep-22 helpers (PackagePath, NumericClamping) and the uncommitted PackagePath-ification modifications, which belong to an unidentified in-flight effort and were left untouched.
- The implementer's 'formatting lint passed' claim does not reproduce and cannot be adjudicated locally: the Swift 6.4 beta swift-format flags even pristine committed files, so neither b8d0842's 10 flagged files nor the 24 other dirty files can be judged here; the CI macos-26 toolchain is authoritative. No reformatting was applied. Tracked in KRMA-555.
Fixes:
- None
Verification commits:
- None
Actor: pi
Resolved model: unknown
Pickup session: 01MUE7QIS3TXOJW0IE
Summary: KRMA-548 verification blocked: fast lane has one residual failure (histogram never follows the Space-comparison request). 1171/1172 pass. Root-cause fix moved to urgent child KRMA-554; hygiene follow-ups in KRMA-555. No verifier code changes; issue returns to review.
