---
id: KRMA-764
title: Never persist or accept a frame stamped with a placeholder source identity; purge legacy ones lazily
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Placeholder writes leave store unchanged and increment skip counter; real identity persists
      result: pass
      notes: Store-boundary guards and tests present (0c51841).
    - criterion: "Pre-seeded directory: placeholder read is a miss and deletes exactly that file/pointer; real frames untouched"
      result: pass
      notes: Guarded same-file/same-record removal.
    - criterion: Sweep removes placeholder frames across idle ticks, bounded, cancelled by user-visible request
      result: pass
      notes: "Scheduler-backed, 8 per tick, not re-run after completion (KRMA-777: da53377, e84454d)."
    - criterion: Replaced source bytes make old frame unusable and not presented/used to skip a render
      result: pass
      notes: testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce now passes; Edit-path fix landed in KRMA-766 (c1328d9).
    - criterion: Corrupt or truncated frames degrade to a plain miss with no throw
      result: pass
      notes: Existing path unchanged; fault-matrix tests green.
    - criterion: RelaunchParityTests assertions lose their XCTExpectFailure wrapper and pass
      result: pass
      notes: No XCTExpectFailure remains in RelaunchParityTests.swift; 10 tests, 0 failures. Library/Edit fixes landed in KRMA-765 (ce6ab4d) and KRMA-766 (c1328d9).
    - criterion: Fast and serial lanes pass
      result: pass
      notes: fast exit 0 (1511 tests); serial 469 tests, 0 failures.
  checks_run:
    - swift test --no-parallel --filter RelaunchParityTests (10 tests, 0 failures at HEAD 053e7ae)
    - scripts/ci-tests.sh serial (469 tests, 0 failures)
    - scripts/ci-tests.sh fast (exit 0, 1511 tests)
    - grep XCTExpectFailure in RelaunchParityTests.swift (none)
  findings:
    - "Earlier blocker verdicts were stale: they were recorded at e84454d, before KRMA-765 and KRMA-766 landed. Both dependencies are done and all criteria now hold."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: unknown
  completed_at: 2026-10-03T12:30:48.498Z
creation_provenance:
  runner: claude
  model: unknown
  actor: claude
labels:
  - performance
  - cache
  - correctness
created: 2026-10-02T13:44:21.918Z
updated: 2026-10-03T12:30:48.500Z
depends_on:
  - KRMA-765
  - KRMA-766
blockers: []
order: zh
board: product
---

## Objective

Make it impossible for the frame stores to hold a frame whose identity is a placeholder, and make the frames already on user disks that carry one disappear without cost or blanking. Guarantee that a cached frame can only ever be presented for the exact source bytes it was rendered from.

## Background

A frame stamped with a placeholder identity (`decoderVersion == "browsing-v1"`, content hash of `"browsing:<uuid>"`) carries **no information about the source bytes**. It cannot detect that the file was replaced, so it only looks valid; and it never matches a real identity, so it is dead weight after the next launch. The owner's cache already contains many of them (16 of 22 preview files). KRMA-763 gives grid items real identities and adds `PortablePhotoSourceFingerprint.isBrowsingPlaceholder`. Packages that have not finished the KRMA-763 backfill still produce placeholder identities for a while, so the stores must defend themselves.

Relevant code: `LatestPreviewFrameStore` (write path `write(_:hash:)`, read `read(for:)`), `ThumbnailFrameStore` (`enqueueWrite`, `read`), `PresentationFrameEnvelope.decode`, `ThumbnailFrameEncoder`, `PreviewPresentationCoordinator.writeCanonical`, `EditedThumbnailCoordinator` (write at ~line 364), `OriginalThumbnailLoader.load`.

## Work

1. **Write guard at the store boundary.** `LatestPreviewFrameStore.write` and `ThumbnailFrameStore.enqueueWrite` drop any frame whose `identity.sourceFingerprint.isBrowsingPlaceholder` or whose `signature.source` is a placeholder. Dropping is silent to callers (it is an optimization cache) but increments a `frameWriteSkippedPlaceholder` counter in `Observability` and records a ledger entry if KRMA-761 has landed.
2. **Read guard.** On read, a stored frame whose metadata identity is a placeholder is treated as a miss and its record is **removed** (preview: delete that `.kframe`; thumbnails: `store.remove(keys:)` for that key, compaction reclaims bytes). It is removed only if it is still the same file/pointer that was read (guard against a concurrent replacement).
3. **Lazy sweep, no launch scan.** Do not enumerate the directory at launch. The read guard above plus an opportunistic bounded sweep (at most 8 files per idle tick, lowest scheduler priority, cancelled by user-visible work) clears the rest. The sweep must never touch a frame with a real identity.
4. **Pinned/LRU accounting stays correct** when files are removed (the preview store's incremental size index).
5. Document the rule in `docs/STORAGE_POLICY.md` and `docs/ENGINEERING_GUIDE.md`: the frame stores only ever hold frames for resolved source identities.

## Acceptance criteria

- [ ] Unit tests: writing a preview and each thumbnail kind with a placeholder identity leaves the store unchanged (file count, pack index and size accounting) and increments the skip counter; writing the same frame with a real identity persists it.
- [ ] A pre-seeded directory containing placeholder-stamped and real-stamped frames: reading a placeholder-stamped one returns a miss and deletes exactly that file/pointer; every real-stamped frame is untouched byte-for-byte; the 1 GB cap accounting matches the directory after the removals.
- [ ] The sweep removes all placeholder-stamped frames across repeated idle ticks (bounded per tick), never removes a real one, and is cancelled promptly by a user-visible request (use the scheduler test seam).
- [ ] Source safety test: render and persist a frame for photo P, replace P's source bytes (new content hash), and assert the old frame classifies `.unusable` and is **not** presented or used to skip a render for the new bytes.
- [ ] Corrupt or truncated frames still degrade to a plain miss with no throw (existing fault-matrix tests stay green).
- [ ] Assertions in `RelaunchParityTests` (KRMA-762) that relied on placeholder-stamped frames being absent lose their `XCTExpectFailure` wrapper.
- [ ] `fast` and `serial` lanes pass.

## Rules for an unattended run (read first)

- **Do not run the display-bound captures** (`scripts/run-kromora-capture.sh`, the last-known-frame benchmark). Everything here is verified by deterministic tests (`scripts/ci-tests.sh fast|serial`) that need no window and no unlocked display (see CLAUDE.md, "Display-bound benchmarks").
- **Do not open child tickets.** If a criterion cannot be met, record exactly what you measured and tried in a comment on this ticket, commit what is safe, and hand off to review.
- Keep the change to what this ticket lists. Swift 6 mode with zero escape hatches (no `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency`). macOS 26 / Apple Silicon only; no `#available` branches and no third-party dependencies.
- Cache files are disposable presentation caches, never package truth. A cache failure must degrade to a miss, never to an error, a wrong-photo frame, or a blocked open.
- Commit with a subject that starts `KRMA-<this id>:`. Do not push. Do not stash, reset, or revert anyone else's uncommitted changes in the tree.


### Comment — codex @ 2026-10-02T23:02:13.434Z

Implemented store-boundary rejection for placeholder identities in preview and packed-thumbnail writes, silent skip counters/signpost, placeholder read misses with guarded cleanup, bounded background sweeps, docs, and store tests. Commit: 0c51841. Verification: focused preview/thumbnail suites pass (23 tests); scripts/ci-tests.sh fast passes (1485 tests). scripts/ci-tests.sh serial exits 1: unwrapped RelaunchParityTests still report provisional original-thumbnail publication before confirmation, two frames/renders where one is expected, and source replacement confirmedFrameCount=2 (expected 1). Those assertions are left live per the acceptance criterion. No display captures run.

### Comment — codex @ 2026-10-03T00:50:55.160Z

Implementation review handoff: store-boundary placeholder rejection, guarded reads, lazy bounded sweeps, accounting, docs, and store tests are already committed (0c51841; sweep follow-up da53377/e84454d). Verification on this checkout: scripts/ci-tests.sh fast passed (1487 tests). swift test --no-parallel --filter RelaunchParityTests failed: 5 tests, 15 failure lines. The replaced-source test confirms the old frame classifies .unusable, but records confirmedFrameCount=2 (expected 1). Unchanged-package relaunch still publishes original thumbnails before confirmation, records duplicate frames, and renders unnecessarily for plain and edited photos; these relaunch admission paths are tracked in KRMA-765 and KRMA-766. No source changes were made in this pass because those remaining behaviors are outside the store-boundary change and already have dedicated dependent issues; no new commit was created. No display-bound captures were run.

### Comment — codex @ 2026-10-03T01:36:56.693Z

Verification handoff: the store-boundary guards, placeholder cleanup, bounded sweep, docs, and store tests are already committed in 0c51841, da53377, and e84454d; this pass made no source edits. Test Suite 'Selected tests' started at 2026-10-02 19:31:24.147.
Test Suite 'KromoraKitTests.xctest' started at 2026-10-02 19:31:24.148.
Test Suite 'RelaunchParityTests' started at 2026-10-02 19:31:24.148.
Test Case '-[KromoraKitTests.RelaunchParityTests testChangedEditBetweenSessionsInvalidatesPersistedFrameOnce]' started.
Test Case '-[KromoraKitTests.RelaunchParityTests testChangedEditBetweenSessionsInvalidatesPersistedFrameOnce]' passed (0.948 seconds).
Test Case '-[KromoraKitTests.RelaunchParityTests testDifferentPixelEpochBetweenSessionsRefinesPersistedFrameOnce]' started.
Test Case '-[KromoraKitTests.RelaunchParityTests testDifferentPixelEpochBetweenSessionsRefinesPersistedFrameOnce]' passed (0.687 seconds).
Test Case '-[KromoraKitTests.RelaunchParityTests testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce]' started.
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:302: error: -[KromoraKitTests.RelaunchParityTests testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce] : XCTAssertEqual failed: ("2") is not equal to ("1")
Test Case '-[KromoraKitTests.RelaunchParityTests testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce]' failed (0.729 seconds).
Test Case '-[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch]' started.
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:527: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertFalse failed - original thumbnail was published before confirmation
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:529: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - unchanged plain photo should reuse its frame: plain-a.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:532: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("1") is not equal to ("0") - unchanged plain photo must not render: plain-a.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:527: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertFalse failed - original thumbnail was published before confirmation
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:529: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - unchanged plain photo should reuse its frame: plain-b.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:532: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - unchanged plain photo must not render: plain-b.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:535: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - Edit must publish one confirmed frame for exposure.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:542: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("1") is not equal to ("0") - unchanged Edit source must use its confirmed frame without a render for exposure.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:535: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - Edit must publish one confirmed frame for color.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:542: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("1") is not equal to ("0") - unchanged Edit source must use its confirmed frame without a render for color.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:535: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - Edit must publish one confirmed frame for crop.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:542: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("1") is not equal to ("0") - unchanged Edit source must use its confirmed frame without a render for crop.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:535: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - Edit must publish one confirmed frame for look.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:542: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("1") is not equal to ("0") - unchanged Edit source must use its confirmed frame without a render for look.png
XCTExpectFailure: matcher accepted Assertion Failure at RelaunchParityTests.swift:555: XCTAssertEqual failed: ("Optional(1.625)") is not equal to ("Optional(3.0)") - library aspect ratio must not change after first layout for crop.png
RelaunchParityTests.swift:555: Expected failure in -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch]: XCTAssertEqual failed: ("Optional(1.625)") is not equal to ("Optional(3.0)") - library aspect ratio must not change after first layout for crop.pngReason: (KRMA-765: relaunch crop geometry)
Test Case '-[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch]' failed (1.913 seconds).
Test Case '-[KromoraKitTests.RelaunchParityTests testUnchangedSinglePhotoSeedIsReusedAfterRelaunch]' started.
Test Case '-[KromoraKitTests.RelaunchParityTests testUnchangedSinglePhotoSeedIsReusedAfterRelaunch]' passed (0.666 seconds).
Test Suite 'RelaunchParityTests' failed at 2026-10-02 19:31:29.091.
	 Executed 5 tests, with 15 failures (0 unexpected) in 4.943 (4.943) seconds
Test Suite 'KromoraKitTests.xctest' failed at 2026-10-02 19:31:29.091.
	 Executed 5 tests, with 15 failures (0 unexpected) in 4.943 (4.943) seconds
Test Suite 'Selected tests' failed at 2026-10-02 19:31:29.091.
	 Executed 5 tests, with 15 failures (0 unexpected) in 4.943 (4.944) seconds
Note: Some test targets reported failures:
  - KromoraKitTests (XCTest) failed (5 tests, 14 assertion failures); CI lane coverage: total=2002 required_fast=1487 required_serial=464 optional=51
Required lanes are disjoint; optional tests are intentionally excluded from the required gate.
CI_TEST_LANE=deterministic-parallel
Focused rerun: swift test --parallel --skip '((AnalysisDebugPanelTests|BundledLookTests|ColorGradingTests|ColorMixerTests|ColorPipelineTests|CollectionProjectionPerformanceTests|CropPipelineTests|EffectsPipelineTests|HistogramTests|IdentityRegressionGateTests|ImageLoadingTests|InfoSemanticMaskRenderingTests|InspectorScrollCrashPathTests|KeyMonitorTests|LocalMaskRenderingTests|LookInspectorViewTests|LookLUTExportTests|LookPreviewTests|KromoraWindowAppearanceControllerTests|MenuCommandTests|MetalKernelParityTests|NeutralOriginSliderTests|PersonSignalWarmingTests|PhotoIntelligenceRealCorpusTests|PhotosDeliveryTests|PhotosImportTests|PreviewCutoverTests|PreviewSurfaceTests|RelaunchParityTests|RenderCacheTests|RenderEngineInteractivePrecisionTests|RenderEngineTests|RenderPipelineTests|RenderStackTests|ThumbnailTests|VisionSemanticMaskProviderTests|WorkingSpaceTests|ThumbnailSwitchLifecycleTests/testFilmstripAndGridPublishCropAwareSettledThumbnails)|(ConcurrentExportEditingBenchmark|StoredEditAdoptionBenchmark|DeriveInvarianceTests|LibraryScanPerformanceTests|LibraryFolderBaselinePerformanceTests|LibraryScaleRegressionPerformanceTests|SyntheticLibraryGeneratorPerformanceTests|PackedThumbnailPerformanceTests|MaskResamplingPerformanceTests|MetalPresentationBenchmark|PhotoAnalysisPerformanceTests|PhotosImportPerformanceTests|PreviewCostBenchmark|TracingOverheadBenchmark|AutoPerformanceDiagnosticsTests/testAutoEndToEndBenchmark|LocalMaskRenderingTests/testSemanticPreviewMaskWorkingResolutionBenchmark|PreviewCoordinatorTests/testLargePreviewInteractiveLatencyBenchmark|RAWCapabilitiesTests/(testProbingARealRAWReportsItsDecodersFlags|testProbingARealRAWReportsItsDecodersSeeds|testEveryPerImageSeedLandsStrictlyInsideItsSliderRange|testWritingTheAsShotValuesMatchesLeavingThemUnset|testAValueWrittenToAnUnsupportedAdjustmentChangesNothing|testRaisingNeutralTemperatureWarmsTheImage)|RAWDevelopSettingsTests/(testApplyPushesEverySupportedKnobOntoARealFilter|testApplyingNeutralChangesNothingOnARealFilter)|ImageLoadingTests/testLoadingARAWGoesThroughCIRAWFilter|ImageSourceTests/testRAWBytesAreDetectedWithoutAFilename|DevelopInspectorTests/(testARAWStaysOnProbingUntilTheProbeAnswers|testAsShotRestoresTheActualRAWDecoderSeed)|RenderCacheTests/testAboveBudgetRAWSessionDoesNotMaterializeOnEveryEdit|RenderPipelineTests/(testRAWDevelopAndScaleReachTheDecoder|testNeutralRAWMatchesTheExistingNeutralBaseline)|RenderEngineTests/(testCompletedRAWPreviewReflectsDevelopSettings|testInteractiveSessionDoesNotLeakSettingsAcrossTicks|testInteractiveRAWDownstreamEditsReuseTheCompletedOutput)|PreviewCutoverTests/testRAWDevelopReachesThePreview))'
[1/1487] Testing KromoraKitTests.AdjustInspectorTests/testInspectorTabsExposeCompactSymbolsAndAccessiblePurposes
[2/1487] Testing KromoraKitTests.AdjustInspectorTests/testLightIsTheInitialInspectorPanelAndEveryPanelCanBeSelected
[3/1487] Testing KromoraKitTests.AdjustInspectorTests/testComparisonWithdrawsWhenTheAdjustmentReturnsToNeutral
[4/1487] Testing KromoraKitTests.AdjustInspectorTests/testComparisonIsStillAvailableWithALUTAndNoAdjustments
[5/1487] Testing KromoraKitTests.AdjustInspectorTests/testInspectorPanelsAppearInRequestedOrder
[6/1487] Testing KromoraKitTests.AdjustInspectorTests/testADevelopOnlyEditDoesNotOfferComparison
[7/1487] Testing KromoraKitTests.AdjustInspectorTests/testComparisonIsNotAvailableWithALUTAtZeroIntensity
[8/1487] Testing KromoraKitTests.AdjustInspectorTests/testResetAllEmptiesTheArray
[9/1487] Testing KromoraKitTests.AdjustInspectorTests/testComparisonBecomesAvailableWithAnAdjustmentAndNoLUT
[10/1487] Testing KromoraKitTests.AdjustInspectorTests/testADevelopEditStillReRendersTheComparisonBaseline
[11/1487] Testing KromoraKitTests.AdjustInspectorTests/testAnAdjustmentEditRendersThroughTheEngine
[12/1487] Testing KromoraKitTests.AdjustInspectorTests/testAnAdjustmentEditDoesNotReRenderTheComparisonBaseline
[13/1487] Testing KromoraKitTests.AdjustInspectorTests/testAnUntouchedPanelLeavesTheDocumentEmpty
[14/1487] Testing KromoraKitTests.AdjustInspectorTests/testComparisonAvailabilityCoversEveryVisibleLookStage
[15/1487] Testing KromoraKitTests.AdjustmentControlTests/testEverySlotsNeutralNodeIsAnIdentityNode
[16/1487] Testing KromoraKitTests.AdjustmentControlTests/testEveryControlsNeutralMatchesTheNodesIdentity
[17/1487] Testing KromoraKitTests.AdjustmentControlTests/testDraggingRightWarmsByStoringALowerNodeTemperature
[18/1487] Testing KromoraKitTests.AdjustmentControlTests/testEverySlotsControlsCoverItExactlyOnce
[19/1487] Testing KromoraKitTests.AdjustmentControlTests/testEveryControlRoundTrips
[20/1487] Testing KromoraKitTests.AdjustmentControlTests/testEveryNeutralSitsInsideItsRangeExceptHighlights
[21/1487] Testing KromoraKitTests.AdjustInspectorTests/testResettingOneControlPreservesTheOthers
[22/1487] Testing KromoraKitTests.AdjustInspectorTests/testResetAllLeavesDevelopAndTheLUTAlone
[23/1487] Testing KromoraKitTests.AdjustInspectorTests/testSpaceCannotEnterOriginalModeWithoutAVisibleLookEdit
[24/1487] Testing KromoraKitTests.AdjustInspectorTests/testTemperatureReadsBackInSliderSpace
[25/1487] Testing KromoraKitTests.AdjustInspectorTests/testTheColorTabUpdatesThePinnedHistogram
[26/1487] Testing KromoraKitTests.AdjustInspectorTests/testWritingAnAdjustmentSliderThroughTheBindingStillDebounces
[27/1487] Testing KromoraKitTests.AdjustmentControlTests/testOnlyTemperatureIsMapped
[28/1487] Testing KromoraKitTests.AdjustmentControlTests/testNeutralIsTheFixedPointOfTheMap
[29/1487] Testing KromoraKitTests.AdjustmentControlTests/testReadingAnAbsentNodeReturnsNeutral
[30/1487] Testing KromoraKitTests.AdjustmentControlTests/testNoSlotEverAppearsTwice
[31/1487] Testing KromoraKitTests.AdjustmentControlTests/testNodesLandInCanonicalOrderWhateverOrderTheyAreWrittenIn
[32/1487] Testing KromoraKitTests.AdjustmentControlTests/testReturningOneParameterToNeutralKeepsANodeItsSiblingsStillNeed
[33/1487] Testing KromoraKitTests.AdjustmentControlTests/testSlotOrderMatchesTheNodeDeclarationOrder
[34/1487] Testing KromoraKitTests.AdjustmentControlTests/testTemperatureAndTintAreTheWhiteBalancePair
[35/1487] Testing KromoraKitTests.AdjustmentControlTests/testReturningToNeutralRemovesTheNode
[36/1487] Testing KromoraKitTests.AdjustmentControlTests/testTheSliderMapIsItsOwnInverse
[37/1487] Testing KromoraKitTests.AdjustmentControlTests/testTheTemperatureRangeIsClosedUnderTheReflection
[38/1487] Testing KromoraKitTests.AdjustmentControlTests/testTitlesAreSetAndNotFilterNames
[39/1487] Testing KromoraKitTests.AnalysisValueTypesTests/testToneAndColorStatisticsRoundTrip
[40/1487] Testing KromoraKitTests.AdjustmentControlTests/testWritingCreatesExactlyOneNode
[41/1487] Testing KromoraKitTests.AnalysisImageTests/testFactoryUsesOneCanonicalLongestEdge
[42/1487] Testing KromoraKitTests.AdjustmentControlTests/testWritingOneParameterPreservesItsSiblings
[43/1487] Testing KromoraKitTests.AnalysisImageTests/testVisionCoordinatesConvertToUpperLeftExactlyOnce
[44/1487] Testing KromoraKitTests.AnalysisValueTypesTests/testQualityAndTimingsRoundTrip
[45/1487] Testing KromoraKitTests.AppViewModelTests/testAppActivationTriggersConfiguredPortableMaintenance
[46/1487] Testing KromoraKitTests.AppViewModelTests/testAFreshlyDerivedLUTResolvesAndGradesThePreview
[47/1487] Testing KromoraKitTests.AppViewModelTests/testACompletedScanReResolvesTheOpenDocumentAndReportsMissingLUTsOnce
[48/1487] Testing KromoraKitTests.AppViewModelTests/testDeadLocalWriterWithUnexpiredLeaseOpensImmediately
[49/1487] Testing KromoraKitTests.AppViewModelTests/testDerivedLUTIsSelectedWhenAnImageIsOpen
[50/1487] Testing KromoraKitTests.AppViewModelTests/testARescanReplacesARegisteredSavedCubeAtTheSamePath
[51/1487] Testing KromoraKitTests.AppViewModelTests/testBatchExportWithNoImagesTellsTheUserInsteadOfOpeningAPanel
[52/1487] Testing KromoraKitTests.AppViewModelTests/testAScanThatReplacesAReferencedLookReleasesOnlyThatLook
[53/1487] Testing KromoraKitTests.AppViewModelTests/testExportDialogNameUsesSourceAndLUT
[54/1487] Testing KromoraKitTests.AppViewModelTests/testAFailedScanReleasesTheLookTheOpenDocumentLostWithoutABlanketFlush
[55/1487] Testing KromoraKitTests.AppViewModelTests/testImportEntryPointsAreGatedWhenLibraryFailedToOpen
[56/1487] Testing KromoraKitTests.AppViewModelTests/testExpiredWriterLeaseFromDeadProcessOpensWithoutPrompt
[57/1487] Testing KromoraKitTests.AppViewModelTests/testDeriveStatusAndErrorAreWired
[58/1487] Testing KromoraKitTests.AppViewModelTests/testDeriveSavePanelDefaultsToTheLUTFolder
[59/1487] Testing KromoraKitTests.AppViewModelTests/testAScanChangingAnUnreferencedLookDoesNoRenderWork
[60/1487] Testing KromoraKitTests.AppViewModelTests/testExpiredWriterLeaseStaysClosedWhenTakeoverIsDeclined
[61/1487] Testing KromoraKitTests.AnalysisValueTypesTests/testVersionClampsToTheSupportedRange
[62/1487] Testing KromoraKitTests.AppViewModelTests/testAByteIdenticalScanDoesNoRenderWork
[63/1487] Testing KromoraKitTests.AppViewModelTests/testOpeningSourceFolderWithoutLibraryReportsUnavailableErrorWithoutImportSummary
[64/1487] Testing KromoraKitTests.AppViewModelTests/testExpiredWriterLeaseOpensLibraryAfterTakeoverConfirmation
[65/1487] Testing KromoraKitTests.AppViewModelTests/testExportDialogWithNoImageTellsTheUserInsteadOfOpeningAPanel
[66/1487] Testing KromoraKitTests.AppViewModelTests/testExportErrorReachesBothTheAlertAndTheStatusBar
[67/1487] Testing KromoraKitTests.AppViewModelTests/testExportStatusReachesTheStatusBar
[68/1487] Testing KromoraKitTests.AppViewModelTests/testLegacySourceBookmarkIsIgnoredByThePackageLibrary
[69/1487] Testing KromoraKitTests.AppViewModelTests/testIsExportingReflectsTheCoordinator
[70/1487] Testing KromoraKitTests.AppViewModelTests/testImportOutcomeWaitsForPreviewAndRetainsPartialFailures
[71/1487] Testing KromoraKitTests.AppViewModelTests/testLookResetIsScopedAndUndoable
[72/1487] Testing KromoraKitTests.AppViewModelTests/testShareUsesSinglePhotoFlowUntilThereIsARealMultiSelection
[73/1487] Testing KromoraKitTests.AppViewModelTests/testOpeningUnsupportedSourceURLReportsNoSupportedImages
[74/1487] Testing KromoraKitTests.AppViewModelTests/testPackageBackedStoreDoesNotExposeASeparateEditDatabase
[75/1487] Testing KromoraKitTests.AppViewModelTests/testPresentAndDismissRecipeExtractorForwardToTheCoordinator
[76/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testCompleteEditFinishIsPreservedAndAnalysisViewIsFitted
[77/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testDarkBaselineBrightReferenceProposesPositiveExposure
[78/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testEmptyIntentReturnsNoEnhancementSuggested
[79/1487] Testing KromoraKitTests.AppViewModelTests/testPreviewPresentationFailureLeavesAnActionableStatus
[80/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testAdapterWithProductionDescriptorStaysGraceful
[81/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testIntentOnlyToneCurveWithoutPixelsIsOmitted
[82/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testFitIsDeterministic
[83/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testIntentOnlyVibranceMapsWithLowConfidence
[84/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testKnownFiltersMapToSupportedEffects
[85/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testMalformedSourceReturnsMalformedImage
[86/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testMatchingReferenceReturnsNoActionableDelta
[87/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testMixedFrameOmitsWhiteBalanceAndReports
[88/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testNilBaselineSamplesReturnRenderUnavailable
[89/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testNilDescriptorRenderReturnsCoreImageFailure
[90/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testProductionDescriptorRejectsEmptySamples
[91/1487] Testing KromoraKitTests.AppViewModelTests/testLookSelectionAndIntensityStayWithTheirPhoto
[92/1487] Testing KromoraKitTests.AppViewModelTests/testSavingADerivedLUTRepointsTheDocumentAtTheSavedFile
[93/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testRawWithoutBaseTemperatureOmitsTemperatureAndReports
[94/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testUnknownFiltersMapToUnsupported
[95/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testUnsupportedEffectsAreOmittedAndReported
[96/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testProductionDescriptorReturnsValueOnlyReference
[97/1487] Testing KromoraKitTests.AppleEnhancementReferenceTests/testWarmReferenceRaisesRawTemperatureAndLowersStandardTemperature
[98/1487] Testing KromoraKitTests.AppViewModelTests/testRenderingDoesNotInvalidateTheLUTCache
[99/1487] Testing KromoraKitTests.AppViewModelTests/testRepointingAfterASaveRendersAgain
[100/1487] Testing KromoraKitTests.AppViewModelTests/testSavingADerivedLUTRescansTheLibrary
[101/1487] Testing KromoraKitTests.AppViewModelTests/testSavingDoesNotRepointADocumentShowingADifferentLUT
[102/1487] Testing KromoraKitTests.AppViewModelTests/testSavingOutsideTheLibraryFolderStillResolves
[103/1487] Testing KromoraKitTests.ApplicationShellCoordinatorTests/testShutdownCancelsPendingTasksAndRemovesObservers
[104/1487] Testing KromoraKitTests.ApplicationShellCoordinatorTests/testMaintenanceAdmissionGuardsMissingPackagesAndExistingJobs
[105/1487] Testing KromoraKitTests.ApplicationShellCoordinatorTests/testActivationRefreshesAndAdmitsPortableMaintenance
[106/1487] Testing KromoraKitTests.ApplicationShellCoordinatorTests/testMountAndUnmountNotificationsAreDebouncedIntoOneRefresh
[107/1487] Testing KromoraKitTests.AutoAdjustmentTests/testHeuristicRespondsConservativelyToLowKeyClippingAndColorBias
[108/1487] Testing KromoraKitTests.AppViewModelTests/testShutdownQuiescesCancelledSourceLoadBeforeFixtureCleanup
[109/1487] Testing KromoraKitTests.AutoAdjustmentTests/testMalformedOrEmptyHistogramDoesNotProduceAnEdit
[110/1487] Testing KromoraKitTests.AutoAdjustmentTests/testRepresentativeFixturesProduceFiniteBoundedAndStableResults
[111/1487] Testing KromoraKitTests.AutoCandidateEvaluationTests/testAnalysisViewExcludesDecorativeStagesButRetainsGeometry
[112/1487] Testing KromoraKitTests.AutoCandidateEvaluationTests/testArtifactWriteRoundTripsOutsideSourceTree
[113/1487] Testing KromoraKitTests.AutoCandidateEvaluationTests/testChangedControlsIsEmptyForIdenticalDocuments
[114/1487] Testing KromoraKitTests.AutoCandidateEvaluationTests/testEvaluateRecordsFailuresInsteadOfPresentingMissingRenderAsSuccess
[115/1487] Testing KromoraKitTests.AutoCandidateEvaluationTests/testEvaluateRendersMatchingGeometryAndMeasuresKnownEdit
[116/1487] Testing KromoraKitTests.AutoAdjustmentTests/testActionIsUnavailableBeforeASettledSupportedPhoto
[117/1487] Testing KromoraKitTests.AutoCandidateEvaluationTests/testEvaluateRecordsGeometryMismatchInsteadOfSpuriousZeroDiff
[118/1487] Testing KromoraKitTests.AutoCandidateEvaluationTests/testEvaluateRotationSwapsDimensions
[119/1487] Testing KromoraKitTests.AutoCandidateEvaluationTests/testIdenticalRendersProduceZeroDiff
[120/1487] Testing KromoraKitTests.AutoCandidateEvaluationTests/testKnownEditChangesDiffImage
[121/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testCancellationDuringEvaluationReturnsWithoutApplying
[122/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testCandidateOrderingIsUnchangedNativeAppleReduced
[123/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testFrozenTargetsDefaultToMiddleGrayPlacement
[124/1487] Testing KromoraKitTests.AutoCandidateEvaluationTests/testRealEngineDiffAndParityOnGradientFixture
[125/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testFrozenTargetsPreserveLowKeyIntent
[126/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testGuardrailThresholdsRejectClippingAndExtremeSaturation
[127/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testGuardrailRejectionAcrossAllChangedCandidatesYieldsNoCandidate
[128/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testImprovedCandidateSelectedOverUnchanged
[129/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testMaskEdgeGuardrailRejectsSpikyContrastWhenMasksWereAdded
[130/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testNoOpProposalsContributeNoCandidates
[131/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testMissingRegionalEvidenceDegradesRatherThanFabricating
[132/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testRAWRecoveryBudgetCapsRedevelopments
[133/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testScaledDocumentClampsToControlRanges
[134/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testSmallRenderBudgetIsHardBounded
[135/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testStaleRevisionRendersNothing
[136/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testTimeBudgetStopsAfterBaseline
[137/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testTieBreakPrefersSimplerCandidateWithinEpsilon
[138/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testRealEngineCoordinatorRunOnGradientFixture
[139/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testUnchangedWinsWhenImprovementIsNegligible
[140/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testBacklitSubjectAdvisesSubjectMaskWithoutLiftingBackgroundAlone
[141/1487] Testing KromoraKitTests.AutoEnhancementCoordinatorTests/testUnmeasurableRenderScoresPenalizedAndRejectsChangedCandidates
[142/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testBalancedImageStaysCloseToUnchanged
[143/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testChangesRecordPreviousProposedConfidenceAndBounds
[144/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testClippedHighlightsRecoverWithoutExposureLift
[145/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testDisagreeingEstimatorsWithoutNeutralEvidenceSkipWB
[146/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testEstimatorAgreementWithoutNeutralCandidateStillCorrects
[147/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testFogEvidenceAllowsRestrainedDehaze
[148/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testIdentityCurveIsNeverSynthesized
[149/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testMixedLightSkipsWhiteBalance
[150/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testMonochromeSkipsColorMoves
[151/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testProposalIsDeterministicAndPure
[152/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testRAWUsesTheSameNeutralObjectiveAndBoundedLift
[153/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testRAWWithoutBaseTemperatureSkipsWB
[154/1487] Testing KromoraKitTests.AutoAdjustmentTests/testAnalysisShowsProgressWithoutBorrowingHistogramLoadingState
[155/1487] Testing KromoraKitTests.AutoAdjustmentTests/testActionRemainsAvailableWhileOptionalHistogramWorkIsLoading
[156/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testStructuredUnderexposureOverridesLowKeyBrake
[157/1487] Testing KromoraKitTests.AutoAdjustmentTests/testAutoAvailabilityRefreshesWhenNavigatingBetweenPhotos
[158/1487] Testing KromoraKitTests.AutoAdjustmentTests/testAutoAvailableForPhotosLibraryImport
[159/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testTonalAndSceneIntentIsPreserved
[160/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testUnderexposedFrameLiftsExposureWithRestrainedTails
[161/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testUnsupportedDetailLeavesDetailKnobsUntouched
[162/1487] Testing KromoraKitTests.AutoAdjustmentTests/testAutoReplacesOnlyGlobalLightAndColorAsOneUndoableOperation
[163/1487] Testing KromoraKitTests.AutoAdjustmentTests/testCancellingAutoLeavesDocumentUntouchedAndClearsLoadingState
[164/1487] Testing KromoraKitTests.AutoAdjustmentTests/testFailureLeavesAutoAndHistogramOutOfLoadingState
[165/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testUserOwnedStateIsPreservedByteForByte
[166/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testUserEditedControlsAreRestrainedNotOverwritten
[167/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testWarmCastMovesStandardAndRAWTemperaturesInOppositeDirections
[168/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testWeakNeutralPreservesSunsetWarmth
[169/1487] Testing KromoraKitTests.AutoEnhancementPolicyTests/testZeroConfidenceFactsYieldNoOp
[170/1487] Testing KromoraKitTests.AutoEnhancementResultTests/testAutoAndUserOwnedLayersSurviveRecordSaveAndReopen
[171/1487] Testing KromoraKitTests.AutoEnhancementResultTests/testFingerprintChangesForSourceDocumentAlgorithmAndRenderer
[172/1487] Testing KromoraKitTests.AutoEnhancementResultTests/testAutoResultReusesExistingAutoLayerButProtectsUserLayer
[173/1487] Testing KromoraKitTests.AutoEnhancementResultTests/testFingerprintMatchesDocumentAfterExistingAutoLayerIsReused
[174/1487] Testing KromoraKitTests.AutoEnhancementResultTests/testLegacyDocumentsUseNeutralAutoMetadata
[175/1487] Testing KromoraKitTests.AutoEnhancementResultTests/testManualEditReleasesAutoLayerAndClearsFingerprint
[176/1487] Testing KromoraKitTests.AutoEnhancementResultTests/testProtectedUserLayerIsNotDuplicatedByLaterAutoResult
[177/1487] Testing KromoraKitTests.AutoLightEngineTests/testAlreadyGoodImageProducesNearZeroExposureAndContrast
[178/1487] Testing KromoraKitTests.AutoLightEngineTests/testAllEvaluatorsProduceBoundedProposals
[179/1487] Testing KromoraKitTests.AutoLightEngineTests/testCorpusTuningRetainsClippingProtection
[180/1487] Testing KromoraKitTests.AutoEnhancementResultTests/testResultAndOwnershipMetadataRoundTrip
[181/1487] Testing KromoraKitTests.AutoLightEngineTests/testBacklitAnalysisLiftsShadowsAndProtectsHighlights
[182/1487] Testing KromoraKitTests.AutoLightEngineTests/testCorpusTuningKeepsCategoryAdjustmentsWithinGoldenRanges
[183/1487] Testing KromoraKitTests.AutoLightEngineTests/testExposureRationaleIncludesFormattedMedian
[184/1487] Testing KromoraKitTests.AutoLightEngineTests/testTonalIntentKeepsHighAndLowKeyNearTheirOriginalKey
[185/1487] Testing KromoraKitTests.AutoPerformanceDiagnosticsTests/testAestheticsDiagnosticsReturnNilWhenVisionDeclines
[186/1487] Testing KromoraKitTests.AutoPerformanceDiagnosticsTests/testTelemetryDoesNotChangeCandidateSelection
[187/1487] Testing KromoraKitTests.AutoPerformanceDiagnosticsTests/testRawRedevelopmentsStayCapped
[188/1487] Testing KromoraKitTests.AutoPerformanceDiagnosticsTests/testTimingsAreBoundedValueOnlyDiagnostics
[189/1487] Testing KromoraKitTests.AutoPerformanceDiagnosticsTests/testAestheticsScoresAreDiagnosticOnly
[190/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testActualRenderArtifactIsReproducibleAndDiagnosable
[191/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testActualRenderFogDehazeRespondsWithoutNewClipping
[192/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testActualRenderBalancedStaysClose
[193/1487] Testing KromoraKitTests.AutoAdjustmentTests/testRepeatingAutoIsDeterministicAndDoesNotAddAnotherHistoryEntry
[194/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testActualRenderBacklitSplitToneAndPreviewExportParity
[195/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testActualRenderUnderexposedImprovesMeanWithoutNewClipping
[196/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testActualRenderUnderexposedMutedPhotoImprovesLightAndColorTogether
[197/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testActualRenderMutedColorImprovesMeasuredColorfulnessAndIsVisible
[198/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testBacklitRegionalPlanLiftsSubjectWithFeatheredMatte
[199/1487] Testing KromoraKitTests.AutoPerformanceDiagnosticsTests/testCoordinatorBudgetsAndStageClocksStayBounded
[200/1487] Testing KromoraKitTests.AutoPerformanceDiagnosticsTests/testPersistenceRoundTripIsTimedSeparately
[201/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testBacklitSubjectAdvisesSubjectMaskWithoutLocalLayers
[202/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testBalancedFixtureStaysWithinClosenessEnvelope
[203/1487] Testing KromoraKitTests.AutoPerformanceDiagnosticsTests/testColdAndWarmRunsSeparateDecodeAndSelectIdentically
[204/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testGeneratedLayersDoNotDuplicateOnReapply
[205/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testFogEvidenceAllowsRestrainedDehaze
[206/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testCoolCastCorrectsInOppositeDirection
[207/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testCorpusInventoryIsComplete
[208/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testActualRenderWarmCastProposalCoolsStandardPath
[209/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testManualLooksCurvesGradingMasksCropOrientationPreserved
[210/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testHardEdgedMatteIsRejectedForEdgeSafety
[211/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testOverexposedClippedFixtureRecoversHighlightsWithoutLift
[212/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testMonochromeSkipsColorMoves
[213/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testNoiseDetailAndUnsupportedCapabilitiesLeaveKnobsUntouched
[214/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testOverlappingPeopleSkipWithReason
[215/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testPhotographicIntentExpectations
[216/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testSaveReopenUndoRedoPreserveAutoResult
[217/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testRepresentativeQualityMatrixRoutesEvidenceToTheRightCategory
[218/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testUnderexposedFixtureLiftsExposureWithinBounds
[219/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testWarmCastImprovesWithoutClippingColorGuardrails
[220/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testCropAlignedBoundsCheck
[221/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testStandardAndRAWTemperatureDirectionsOppose
[222/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testEmptyEvidencePlansNoLayersWithExplanations
[223/1487] Testing KromoraKitTests.AutoQualityRegressionTests/testRepeatedAutoFingerprintIsNoOp
[224/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testDefaultSubjectTargetWithoutPersonEvidence
[225/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testExistingAutoLayersSuppressPlanning
[226/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testCropThatDiscardsTheMaskSkipsWithReason
[227/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testFeatheredMattePassesTransitionCheck
[228/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testLandmarkMatteIsFeatheredAndCentered
[229/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testGlobalSuccessNeedsNoLayers
[230/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testHardEdgedMatteIsRejected
[231/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testIntersectionOverUnionReturnsNilForMismatchedSizes
[232/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testLandmarkMatteRejectsDegenerateInput
[233/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testMaterialCastPlansColorCorrectionTowardNeutral
[234/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testMaterialConflictPlansSubjectLiftAndBackgroundProtection
[235/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testNegligibleCastSkipsColor
[236/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testOverlappingSubjectAndBackgroundSkipsWithReason
[237/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testPersonEvidenceSelectsPersonTarget
[238/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testPlannedLayersAppendAsEditableRecipesAndRoundTrip
[239/1487] Testing KromoraKitTests.AutoWorkflowCoordinatorTests/testDegradedPathCarriesExplicitReason
[240/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testSupportIntersectionKeepsResolutionMismatchesOut
[241/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testUnverifiableSeparationPlansNoLayers
[242/1487] Testing KromoraKitTests.AutoWorkflowCoordinatorTests/testNoPreviewDoesNotInvokeRunner
[243/1487] Testing KromoraKitTests.AutoWorkflowCoordinatorTests/testSuccessfulRunPublishesProgressAndValueResult
[244/1487] Testing KromoraKitTests.CanvasNavigationTests/testDoubleClickUsesDeterministicFallbackAndTogglesBackToFit
[245/1487] Testing KromoraKitTests.CanvasNavigationTests/testFitAndFillRetainTheLastChosenZoom
[246/1487] Testing KromoraKitTests.CanvasNavigationTests/testFillCoversTheViewport
[247/1487] Testing KromoraKitTests.CanvasNavigationTests/testFillCoversALandscapeViewportWithAPortraitImage
[248/1487] Testing KromoraKitTests.CanvasNavigationTests/testDoubleClickZoomUsesTheClickAsItsFocalPointAndResetsToFit
[249/1487] Testing KromoraKitTests.CanvasNavigationTests/testFitCentersAPortraitImageInALandscapeViewport
[250/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testTinyAndGlobalMattesAreRejected
[251/1487] Testing KromoraKitTests.AutoWorkflowCoordinatorTests/testProductionRunnerSurfacesHistogramFallbackReason
[252/1487] Testing KromoraKitTests.AutoWorkflowCoordinatorTests/testSourceOrDocumentRevisionFenceSuppressesResult
[253/1487] Testing KromoraKitTests.CanvasNavigationTests/testFitShowsTheWholeImageAndCentersIt
[254/1487] Testing KromoraKitTests.AutoRegionalCorrectionsTests/testUserLayersDoNotSuppressPlanning
[255/1487] Testing KromoraKitTests.AutoWorkflowCoordinatorTests/testCancellationSuppressesLateResult
[256/1487] Testing KromoraKitTests.CanvasNavigationTests/testMaskTransformFollowsFitFillZoomPanAndWindowResize
[257/1487] Testing KromoraKitTests.CanvasNavigationTests/testMaskTransformConvertsViewportDeltaWithoutCropOrBackingAmplification
[258/1487] Testing KromoraKitTests.CanvasNavigationTests/testFocalPointSurvivesViewportResize
[259/1487] Testing KromoraKitTests.CanvasNavigationTests/testInvalidZoomValuesAreSafeAndClamped
[260/1487] Testing KromoraKitTests.AutoWorkflowCoordinatorTests/testSupersededInvocationCannotPublish
[261/1487] Testing KromoraKitTests.CanvasNavigationTests/testMaskTransformIsRetinaScaleInvariant
[262/1487] Testing KromoraKitTests.CanvasNavigationTests/testMaskTransformRoundTripsOrientedPortraitAndBottomLeftCrop
[263/1487] Testing KromoraKitTests.CanvasNavigationTests/testPanMovesTheImageInTheDirectionOfTheViewportDelta
[264/1487] Testing KromoraKitTests.CanvasNavigationTests/testPanIsClampedToKeepTheImageCoveringTheViewport
[265/1487] Testing KromoraKitTests.CanvasNavigationTests/testRememberedZoomIsUpdatedByGestureAndClampedSafely
[266/1487] Testing KromoraKitTests.CanvasNavigationTests/testZoomAroundViewportPointKeepsTheImagePointStable
[267/1487] Testing KromoraKitTests.CanvasNavigationTests/testRenderResolutionGrowsWithZoomButNeverRequestsMoreThanNativeExtent
[268/1487] Testing KromoraKitTests.CanvasWorkflowCoordinatorTests/testCanvasNavigationChangesPresentationWithoutChangingDocument
[269/1487] Testing KromoraKitTests.CanvasWorkflowCoordinatorTests/testCropCancelRestoresPresentationWithoutChangingDocument
[270/1487] Testing KromoraKitTests.CanvasWorkflowCoordinatorTests/testCropApplyCommitsDraftAndRotationAsOneDocumentMutation
[271/1487] Testing KromoraKitTests.CanvasWorkflowCoordinatorTests/testRotationOutsideCropPreservesCropContentAndUsesDocumentPath
[272/1487] Testing KromoraKitTests.CaptureMetadataOverlayTests/testCaptureRowsAreEmptyWhenPhotoHasNoExposureMetadata
[273/1487] Testing KromoraKitTests.CaptureMetadataOverlayTests/testCaptureRowsOmitMissingValuesAndKeepCameraOrder
[274/1487] Testing KromoraKitTests.ColorAdjustmentsTests/testColorCodableRoundTripAndMissingValues
[275/1487] Testing KromoraKitTests.ColorAdjustmentsTests/testNeutralValuesAndNormalizedMapping
[276/1487] Testing KromoraKitTests.ColorAdjustmentsTests/testDocumentColorIsIdentityAwareAndPersisted
[277/1487] Testing KromoraKitTests.ColorAdjustmentsTests/testOlderDocumentWithoutColorDefaultsToNeutral
[278/1487] Testing KromoraKitTests.ColorAdjustmentsTests/testValuesAreFiniteAndClampedAtConstructionAndMutation
[279/1487] Testing KromoraKitTests.CanvasObservationTests/testCanvasNavigationLeavesEmptyHistoryAndRedoStateUnchanged
[280/1487] Testing KromoraKitTests.CanvasObservationTests/testHighFrequencyCanvasAndCropUpdatesBypassBroadModelPublisher
[281/1487] Testing KromoraKitTests.CanvasObservationTests/testSourceResetClearsNavigationAndCropTransientState
[282/1487] Testing KromoraKitTests.CanvasObservationTests/testZoomFollowedByPersistentEditCreatesOneUndoEntry
[283/1487] Testing KromoraKitTests.CanvasObservationTests/testPanCanvasPreservesPointerDirectionOnBothAxes
[284/1487] Testing KromoraKitTests.CanvasObservationTests/testPointerZoomAnchorsAgainstTheStraightenedPresentationExtent
[285/1487] Testing KromoraKitTests.CanvasObservationTests/testCanvasDoubleClickToggleIsPresentationOnly
[286/1487] Testing KromoraKitTests.CanvasObservationTests/testEditTriggeredPreviewKeepsThePannedFocalPoint
[287/1487] Testing KromoraKitTests.ColorSettingFormattingTests/testPhotographerReadoutsRoundToWholeNumbers
[288/1487] Testing KromoraKitTests.ColorSettingFormattingTests/testWholeNumberFormatRemovesFractionalTails
[289/1487] Testing KromoraKitTests.CanvasObservationTests/testPanAtDeepZoomRequestsROIsThatCoverEveryViewportEdge
[290/1487] Testing KromoraKitTests.ColorInspectorTests/testColorControlsRoundTripThroughBindingsWithoutDrift
[291/1487] Testing KromoraKitTests.ColorInspectorTests/testColorResetsPreserveLegacyAdjustmentNodes
[292/1487] Testing KromoraKitTests.ColorInspectorTests/testColorSliderUsesInteractiveRenderAndSettlesLatestValue
[293/1487] Testing KromoraKitTests.ColorInspectorTests/testRowResetsPreserveSiblingMixerAndGradingValues
[294/1487] Testing KromoraKitTests.ColorInspectorTests/testSectionResetsPreserveOtherColorSections
[295/1487] Testing KromoraKitTests.ColorInspectorTests/testVisualWheelBindingMapsGestureValuesAndUsesInteractivePreview
[296/1487] Testing KromoraKitTests.ColorInspectorTests/testMixerAndGradingBindingsEditOnlyTheirNestedValues
[297/1487] Testing KromoraKitTests.ColorInspectorTests/testWhiteBalanceResetRestoresBothRowsAsOneNeutralOperation
[298/1487] Testing KromoraKitTests.ColorInspectorTests/testWhiteBalancePresetsUseTheEditableDocumentAndUndoHistory
[299/1487] Testing KromoraKitTests.ComparisonModeTests/testEnteringSideBySideAfterSettledPreviewRequestsAndPublishesBaseline
[300/1487] Testing KromoraKitTests.ComparisonModeTests/testCanToggleBeforeEditsAfterEditsAndAfterRemovingEdits
[301/1487] Testing KromoraKitTests.ComparisonModeTests/testEntryDoesNotWaitForDrawableConfirmationBeforeRequestingBaseline
[302/1487] Testing KromoraKitTests.ComparisonModeTests/testFirstLaunchDefaultsToSinglePhoto
[303/1487] Testing KromoraKitTests.ComparisonModeTests/testLateBaselineFromPreviousPhotoCannotPublish
[304/1487] Testing KromoraKitTests.ComparisonModeTests/testLocalMaskEditKeepsTheDisplayedComparisonBaseline
[305/1487] Testing KromoraKitTests.ComparisonModeTests/testRAWTemperatureEditLeavesOriginalRequestAtItsBaseline
[306/1487] Testing KromoraKitTests.ComparisonModeTests/testResetPhotoKeepsRetainedSideBySideSurfacesValid
[307/1487] Testing KromoraKitTests.ComparisonModeTests/testRAWTintEditLeavesOriginalRequestAtItsBaseline
[308/1487] Testing KromoraKitTests.ComparisonModeTests/testSpaceIsSingleViewOnly
[309/1487] Testing KromoraKitTests.ContentAwareAutoEngineTests/testBalancedFrameWithExistingAutoOwnedEditsReplacesThemWithNeutralResult
[310/1487] Testing KromoraKitTests.ContentAwareAutoEngineTests/testNoMasksKeepBalancedDocumentUnchangedWithRegionalReasons
[311/1487] Testing KromoraKitTests.ContentAwareAutoEngineTests/testAutoReplacesExistingGlobalValuesWhilePreservingUnrelatedEdits
[312/1487] Testing KromoraKitTests.ComparisonModeTests/testStandardTemperatureEditLeavesOriginalRequestAtItsBaseline
[313/1487] Testing KromoraKitTests.CoordinatorBoundaryTests/testCollectionProjectionSeparatesSelectionAndFilteringFromMutation
[314/1487] Testing KromoraKitTests.ComparisonModeTests/testReturningToSinglePhotoModeIsAlsoRemembered
[315/1487] Testing KromoraKitTests.CoordinatorBoundaryTests/testComparisonFramePolicyKeepsWhiteBalanceOnTheCurrentBaseline
[316/1487] Testing KromoraKitTests.ComparisonModeTests/testSelectedModeIsRememberedAcrossRelaunch
[317/1487] Testing KromoraKitTests.ComparisonModeTests/testSelectedModeSurvivesPhotoSwitch
[318/1487] Testing KromoraKitTests.CoordinatorBoundaryTests/testComparisonFramePolicyTracksTheDerivedBaseline
[319/1487] Testing KromoraKitTests.ComparisonModeTests/testUndoToIdentityClearsTransientOriginal
[320/1487] Testing KromoraKitTests.ContentAwareAutoEngineTests/testRegionalConflictAddsEditableAutoLayersThroughProductionPath
[321/1487] Testing KromoraKitTests.CoordinatorBoundaryTests/testEditorDocumentCoordinatorOwnsHistoryAndClipboardWithoutAppViewModel
[322/1487] Testing KromoraKitTests.CoordinatorBoundaryTests/testEditorDocumentCoordinatorKeepsPerPhotoSessionAndRevisionBoundaries
[323/1487] Testing KromoraKitTests.CoordinatorBoundaryTests/testSourceImportPlanKeepsURLAndDataIdentityRulesTogether
[324/1487] Testing KromoraKitTests.ContentAwareAutoEngineTests/testUnderexposedFrameSelectsMeaningfulExposureThroughProductionRenderer
[325/1487] Testing KromoraKitTests.CropInspectorTests/testResetButtonUsesTheSemanticPrimaryAccentAndKeepsLinkAccessibility
[326/1487] Testing KromoraKitTests.CropModelTests/testCommonCropAspectRatiosHaveClearCentralizedLabels
[327/1487] Testing KromoraKitTests.CropModelTests/testCropClampingRejectsDegenerateInput
[328/1487] Testing KromoraKitTests.CropModelTests/testCropIsCopiedSelectivelyAndComparisonKeepsItsFrame
[329/1487] Testing KromoraKitTests.CropModelTests/testCropIsNormalizedBoundedAndCodable
[330/1487] Testing KromoraKitTests.CropModelTests/testDraggingCropAreaClampsTheWholeFrameToImageBounds
[331/1487] Testing KromoraKitTests.CropModelTests/testDraggingCropAreaKeepsNormalizedMovementStableAcrossCanvasScales
[332/1487] Testing KromoraKitTests.CropModelTests/testDraggingCropAreaTranslatesInNormalizedBottomLeftSpace
[333/1487] Testing KromoraKitTests.CropModelTests/testDraggingCropAreaPreservesFixedFrameSize
[334/1487] Testing KromoraKitTests.CropModelTests/testFixedRatioOneAxisResizesSymmetricallyFromEveryCorner
[335/1487] Testing KromoraKitTests.CropModelTests/testGeometryDefaultsAndCodableMigrationAreNeutral
[336/1487] Testing KromoraKitTests.CropModelTests/testExplicitPortraitAndLandscapeRatiosIgnoreSourceOrientationAndPersist
[337/1487] Testing KromoraKitTests.CropModelTests/testOriginalAspectIsSourcePixelIdentityWithoutResettingCrop
[338/1487] Testing KromoraKitTests.CropModelTests/testOrientationLabelsMatchTheNormalizedFrameRatio
[339/1487] Testing KromoraKitTests.CropModelTests/testMissingCropFieldKeepsLegacyDocumentsNeutral
[340/1487] Testing KromoraKitTests.CropModelTests/testPresetResizePreservesPixelRatioAndClampsToBounds
[341/1487] Testing KromoraKitTests.CropModelTests/testPerspectiveDefaultsAreBoundedAndCodable
[342/1487] Testing KromoraKitTests.CropModelTests/testPresetSelectionIsPersistedAsPartOfTheCropEdit
[343/1487] Testing KromoraKitTests.CropModelTests/testStraightenMoveAndResizeStayInsideTheRotatedImageAndKeepRatio
[344/1487] Testing KromoraKitTests.CoordinatorBoundaryTests/testPersistenceCoordinatorCoalescesSnapshotsAndPreservesFlushCompatibility
[345/1487] Testing KromoraKitTests.ComparisonModeTests/testUneditedPhotoPopulatesBothSurfacesWithNoEditRecord
[346/1487] Testing KromoraKitTests.ComparisonModeTests/testUneditedPhotoPopulatesBothSurfacesWithAnEmptyPersistedDocument
[347/1487] Testing KromoraKitTests.CropModelTests/testPresetSelectionPreservesCenterAndAdaptsToImageOrientation
[348/1487] Testing KromoraKitTests.CropModelTests/testStraightenFrameIsContainedAndKeepsItsPixelRatioAcrossTheAllowedAngles
[349/1487] Testing KromoraKitTests.CropModelTests/testStraightenReversalOnlyKeepsOrShrinksTheFrame
[350/1487] Testing KromoraKitTests.CropModelTests/testTopLeftFixedRatioHorizontalInwardDragMovesLeftEdgeRight
[351/1487] Testing KromoraKitTests.CropOverlayViewTests/testHandleHitPositionsAreInsetFromEveryCorner
[352/1487] Testing KromoraKitTests.CropOverlayViewTests/testHandleHitPositionClampsInsetForTinyCropRects
[353/1487] Testing KromoraKitTests.CropOverlayViewTests/testPressInCropInteriorMoves
[354/1487] Testing KromoraKitTests.CropOverlayViewTests/testPressOnTopLeftCornerOfFullImageCropResizesRatherThanMoves
[355/1487] Testing KromoraKitTests.CropOverlayViewTests/testPressOutsideCropAndHandlesIsIgnored
[356/1487] Testing KromoraKitTests.CropROITests/testCroppedFitRequestCoversPresentationExtentWhileAZoomFragmentDoesNot
[357/1487] Testing KromoraKitTests.CropROITests/testFitCropCoversThePresentedPhotoAndZoomedCropDoesNot
[358/1487] Testing KromoraKitTests.CropROITests/testGeometryROIWithoutPresentationROIFallsBackToTheCompleteFrame
[359/1487] Testing KromoraKitTests.CropROITests/testInteractiveROIBudgetKeepsAbsoluteDecodeCeiling
[360/1487] Testing KromoraKitTests.CropROITests/testGeometryViewportROIRendersThePostGeometryFragment
[361/1487] Testing KromoraKitTests.CropOverlayViewTests/testTopLeftHandleHitRectStaysInsideOverlayAndCoversTheVisibleCorner
[362/1487] Testing KromoraKitTests.CropROITests/testCropExportParityTestVisibleROIMatchesFullExportCrop
[363/1487] Testing KromoraKitTests.CropROITests/testInteractiveZoomFragmentLayoutStaysInPlannerSpaceWithinROIShapedBudget
[364/1487] Testing KromoraKitTests.CropROITests/testPresentationLayoutPutsATopSourceStripAtTheTopOfTheCanvas
[365/1487] Testing KromoraKitTests.CropROITests/testROIExtentTestSmallCommittedCropAtFitUsesOnlyTheCropPixels
[366/1487] Testing KromoraKitTests.CropROITests/testResolutionPlannerDeepZoomRequestsNativeDetailOnlyForVisibleROI
[367/1487] Testing KromoraKitTests.CropROITests/testResolutionPlannerFullImageFitIsANoOpROI
[368/1487] Testing KromoraKitTests.CropROITests/testPanCacheHitTestRepeatedROIRenderDoesNotRedevelopTheSource
[369/1487] Testing KromoraKitTests.CropROITests/testZoomedInteractiveDecodeKeepsViewportScaleVisiblePixels
[370/1487] Testing KromoraKitTests.CopyPasteTests/testSelectiveCopyDialogSeedsAndPersistsRememberedCategories
[371/1487] Testing KromoraKitTests.CopyPasteTests/testSinglePasteIsUndoableAndDoesNotChangeTheSource
[372/1487] Testing KromoraKitTests.CopyPasteTests/testSelectiveCopyMaskLeavesUncheckedDestinationStagesIntact
[373/1487] Testing KromoraKitTests.CopyPasteTests/testMultiPasteUpdatesOnlySelectedPhotosAndEachDestinationCanUndo
[374/1487] Testing KromoraKitTests.CropWorkflowTests/testCommittedCropSurvivesRelaunch
[375/1487] Testing KromoraKitTests.CopyPasteTests/testAcceptedDustSuggestionUsesNormalUndoHistory
[376/1487] Testing KromoraKitTests.CopyPasteTests/testFilmstripShiftSelectionBuildsRangeThatPasteCovers
[377/1487] Testing KromoraKitTests.CropWorkflowTests/testCropModeOwnsAndRestoresEditChromeState
[378/1487] Testing KromoraKitTests.CropWorkflowTests/testCropStraightenUsesViewSpaceRotationWhileThePreviewRequestStaysUnstraightened
[379/1487] Testing KromoraKitTests.CropWorkflowTests/testCropChromeActivatesWithoutWaitingForTheEntryRender
[380/1487] Testing KromoraKitTests.CropWorkflowTests/testCommittedStraightenPreviewRequestUsesGeometryPresentationExtent
[381/1487] Testing KromoraKitTests.CropWorkflowTests/testCropGeometrySliderChangesAdvanceDisplayGenerationPerValueAndSettleAfterRelease
[382/1487] Testing KromoraKitTests.CubeLUTTests/testCommentsAndBlankLinesAreIgnored
[383/1487] Testing KromoraKitTests.CropWorkflowTests/testCropToolOpenUnchangedTestRequestsTheFullUncroppedSource
[384/1487] Testing KromoraKitTests.CubeLUTTests/testInMemoryLUTGetsAContentDerivedIDWhenNotFileBacked
[385/1487] Testing KromoraKitTests.CubeLUTTests/testDegenerateDomainDoesNotProduceNaN
[386/1487] Testing KromoraKitTests.CubeLUTTests/testEqualityAndHashingUseIdentityNotContents
[387/1487] Testing KromoraKitTests.CubeLUTTests/testDomainIsNormalizedToUnitRange
[388/1487] Testing KromoraKitTests.CubeLUTTests/testIndexOrderingIsRedFastest
[389/1487] Testing KromoraKitTests.CubeLUTTests/testMissingSizeThrows
[390/1487] Testing KromoraKitTests.CubeLUTTests/testParsesBOMTabsInlineCommentsAndVendorMetadata
[391/1487] Testing KromoraKitTests.CubeLUTTests/testIntensityBlendsBetweenOriginalAndGraded
[392/1487] Testing KromoraKitTests.CubeLUTTests/testIntensityPathStillEqualsGradeThenDissolve
[393/1487] Testing KromoraKitTests.CubeLUTTests/testIntensityIsClampedToUnitRange
[394/1487] Testing KromoraKitTests.CubeLUTTests/testParsesCRLFLineEndings
[395/1487] Testing KromoraKitTests.CubeLUTTests/testParsesIdentityCube
[396/1487] Testing KromoraKitTests.CubeLUTTests/testRejectsAnOversizedLineWhileStreaming
[397/1487] Testing KromoraKitTests.CubeLUTTests/testPassingACachedFilterMatchesBuildingOneInline
[398/1487] Testing KromoraKitTests.CropWorkflowTests/testDraftIsTransientCancelIsFreeAndCommitIsUndoable
[399/1487] Testing KromoraKitTests.CubeLUTTests/testRejectsOversizedCubeBeforeAllocatingTable
[400/1487] Testing KromoraKitTests.CropWorkflowTests/testReenteringCropRequestsTheFullUncroppedStageAndRestoresOnExit
[401/1487] Testing KromoraKitTests.CubeLUTTests/testRejectsExcessiveMetadataBeforeAllocatingTable
[402/1487] Testing KromoraKitTests.CubeLUTTests/testRejectsTrailingTableRowsAfterTheDeclaredCube
[403/1487] Testing KromoraKitTests.CubeLUTTests/testRejectsUnsupportedOneDimensionalCubeClearly
[404/1487] Testing KromoraKitTests.CubeLUTTests/testRejectsOversizedFileBeforeParsingItsContents
[405/1487] Testing KromoraKitTests.CubeLUTTests/testRejectsReversedDomain
[406/1487] Testing KromoraKitTests.CropWorkflowTests/testSelectingAspectPresetsImmediatelyReshapesTheDraftForBothOrientations
[407/1487] Testing KromoraKitTests.CubeLUTTests/testStripsVendorSuffixesFromDisplayName
[408/1487] Testing KromoraKitTests.CubeLUTTests/testWriteClampsOutOfRangeValues
[409/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testCacheKeysDistinguishSourceDocumentConfigurationAndRevision
[410/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testAnalysisViewStripsFinishButRetainsGeometryAndLight
[411/1487] Testing KromoraKitTests.CubeLUTTests/testWrongEntryCountThrows
[412/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testClippedWhiteKeepsDisplayClippingDistinctFromHeadroom
[413/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testColorSpaceAndRawPathsMeasure
[414/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testCacheRoundTripAndStaleStoreRejected
[415/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testCompleteViewRetainsTheFinish
[416/1487] Testing KromoraKitTests.CubeLUTTests/testWriteThenParseRoundTrips
[417/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testIdentityDocumentMeasuresExplicitlyAsBaseline
[418/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testFailedMaskLeavesGlobalFactsUsable
[419/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testInvalidSourceExtentThrows
[420/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testLinearLuminanceDiffersFromDisplayAndHeadroomStaysSeparate
[421/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testLocalContrastSeparatesFlatFromStructured
[422/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testNativeDetailAvailableWhenSamplerProvidesPatches
[423/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testNativeDetailReportsUnavailableRatherThanGuessing
[424/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testNativePlannerIsBoundedAndDeterministic
[425/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testRawHeadroomComesFromTheDecoderNeverTheDisplayBins
[426/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testNeutralCandidatesRecommendOnlyWithConfidentUnmixedEvidence
[427/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testRawWithoutCapabilitiesReportsUnavailable
[428/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testRenderUnavailableThrowsAndLeavesDocumentUnchanged
[429/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testRotatedDocumentMeasuresWithOrientedGeometry
[430/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testStaleDocumentHashThrowsBeforeRendering
[431/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testSaturationAndHueComeFromTheSameSamples
[432/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testDerivedNameEncodesSourceAndSize
[433/1487] Testing KromoraKitTests.CurrentEditMeasurementTests/testSuccessfulRegionIsMeasuredThroughTheEffectiveDocument
[434/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testDerivedNameSurvivesTheParsersSuffixStripping
[435/1487] Testing KromoraKitTests.CropWorkflowTests/testSelectingPresetStaysDraftUntilApplyAndUndoRedoRestoresTheRatio
[436/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testDismissKeepsAFinishedResult
[437/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testDismissWithoutAnActiveDeriveDoesNotEmitCancelledStatus
[438/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testPerformSaveReplacesAnExistingFile
[439/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testDeriveReportsAFailureThroughOnError
[440/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testDeriveIgnoresASecondRequestWhileRunning
[441/1487] Testing KromoraKitTests.CropWorkflowTests/testUndoRedoWhileCropIsOpenReseedsDraftBeforeSaveOrCancel
[442/1487] Testing KromoraKitTests.CropWorkflowTests/testStraightenAndFlipAreDraftedUntilDoneAndCancelRestoresCommittedGeometry
[443/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testPerformSaveCopiesTheScratchCube
[444/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testPerformSaveThrowsWhenThereIsNothingToSave
[445/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testPresentAndDismissTogglesTheSheet
[446/1487] Testing KromoraKitTests.CropWorkflowTests/testStraightenAdjustsTheTransientDraftAndCommitKeepsTheSafeFrame
[447/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testTheDerivedLUTIsNotNamedAfterItsScratchFile
[448/1487] Testing KromoraKitTests.DeriveCoordinatorTests/testSavedCubeIsIndependentOfTheScratchFile
[449/1487] Testing KromoraKitTests.DevelopInspectorTests/testAProbedRAWStateEndsOnReadyCarryingTheProbedCapabilities
[450/1487] Testing KromoraKitTests.CubeLUTTests/testParsesTheMaximumSupported65CubeIncrementally
[451/1487] Testing KromoraKitTests.DevelopInspectorTests/testAsShotClearsRAWOverridesAndLegacyPostRenderWhiteBalance
[452/1487] Testing KromoraKitTests.DevelopInspectorTests/testAnUnsetControlReadsBackTheSeedRatherThanZero
[453/1487] Testing KromoraKitTests.DevelopInspectorTests/testAMixedBurstStillRendersTheComparisonBaseline
[454/1487] Testing KromoraKitTests.DevelopInspectorTests/testAnUndebouncedEditRendersWithoutWaiting
[455/1487] Testing KromoraKitTests.DevelopInspectorTests/testADevelopEditRendersTheChangedDocument
[456/1487] Testing KromoraKitTests.DevelopInspectorTests/testADragIssuesFarFewerRendersThanTicks
[457/1487] Testing KromoraKitTests.DevelopInspectorTests/testAStandardImageEndsOnNoDevelopStage
[458/1487] Testing KromoraKitTests.DevelopInspectorTests/testCapabilitiesAreClearedForAnImageWithNoDevelopStage
[459/1487] Testing KromoraKitTests.DevelopInspectorTests/testCapabilitiesAreProbedOncePerOpenAndNotPerRender
[460/1487] Testing KromoraKitTests.DevelopInspectorTests/testCanvasNavigationDoesNotRecomputeTheHistogram
[461/1487] Testing KromoraKitTests.DevelopInspectorTests/testAPendingDevelopFlagDoesNotSurviveOpeningAnotherImage
[462/1487] Testing KromoraKitTests.DevelopInspectorTests/testCapabilitiesArePublishedAfterOpeningAnImage
[463/1487] Testing KromoraKitTests.DevelopInspectorTests/testCropChangeRecomputesTheHistogram
[464/1487] Testing KromoraKitTests.DevelopInspectorTests/testEveryControlResetsToUnsetOnItsOwn
[465/1487] Testing KromoraKitTests.DevelopInspectorTests/testDevelopAndColorEditsUpdateThePinnedHistogram
[466/1487] Testing KromoraKitTests.DevelopInspectorTests/testEverySeededControlReadsItsOwnSeed
[467/1487] Testing KromoraKitTests.DevelopInspectorTests/testOpeningAStandardImageFallsBackFromUnavailableDevelopTab
[468/1487] Testing KromoraKitTests.DevelopInspectorTests/testInspectorTabAvailabilityCoversNoImageStandardProbingSupportedAndEmptyRAW
[469/1487] Testing KromoraKitTests.DevelopInspectorTests/testHistogramFollowsTheDisplayedComparisonRequest
[470/1487] Testing KromoraKitTests.DevelopInspectorTests/testLateHistogramResultCannotReplaceANewerEdit
[471/1487] Testing KromoraKitTests.DevelopInspectorTests/testThePanelStateMappingCoversAllThreeStates
[472/1487] Testing KromoraKitTests.DevelopInspectorTests/testLensCorrectionValueFollowsTheSeedInBothDirections
[473/1487] Testing KromoraKitTests.DevelopInspectorTests/testPendingHistogramSurvivesCanvasZoom
[474/1487] Testing KromoraKitTests.EditClipboardTests/testClipboardKeepsFutureCopyCategoriesSeparate
[475/1487] Testing KromoraKitTests.EditClipboardTests/testClipboardSchemaDefaultsMissingFieldsAndRejectsNewerVersions
[476/1487] Testing KromoraKitTests.EditClipboardTests/testLegacyCropClipboardDefaultsToFreeform
[477/1487] Testing KromoraKitTests.EditClipboardTests/testRAWDevelopCopiesExplicitEditsButPreservesThemForJPEGDestinations
[478/1487] Testing KromoraKitTests.EditClipboardTests/testRetouchRecipesCopyOnlyWhenRetouchCategoryIsSelected
[479/1487] Testing KromoraKitTests.DevelopInspectorTests/testRapidEditsCoalesceHistogramWorkAfterTheSettledPreview
[480/1487] Testing KromoraKitTests.DevelopInspectorTests/testRawAmountSliderHeadroomDoesNotExceedDecoderRange
[481/1487] Testing KromoraKitTests.EditClipboardTests/testSelectiveApplicationReplacesOnlyTheChosenCategories
[482/1487] Testing KromoraKitTests.DevelopInspectorTests/testReadingEveryControlWritesNothing
[483/1487] Testing KromoraKitTests.DevelopInspectorTests/testResettingAControlReturnsItToUnset
[484/1487] Testing KromoraKitTests.EditClipboardTests/testSelectiveLightCopyPasteTransfersEveryToneCurve
[485/1487] Testing KromoraKitTests.DevelopInspectorTests/testResettingWhiteBalanceClearsBothTemperatureAndTint
[486/1487] Testing KromoraKitTests.EditDocumentTests/testAbsentFieldsFallBackToDefaults
[487/1487] Testing KromoraKitTests.EditDocumentTests/testAdjustmentIdentityValuesMatchTheFilterDefaults
[488/1487] Testing KromoraKitTests.EditDocumentTests/testAdjustmentOrderIsSignificantAndSurvivesEncoding
[489/1487] Testing KromoraKitTests.EditDocumentTests/testComparisonBaselineKeepsDevelopAndStripsEveryVisibleLookStage
[490/1487] Testing KromoraKitTests.EditDocumentTests/testDefaultDocumentIsIdentityAndRoundTrips
[491/1487] Testing KromoraKitTests.EditDocumentTests/testDocumentIdentityTracksEveryComponent
[492/1487] Testing KromoraKitTests.EditDocumentTests/testEachAdjustmentCaseRoundTripsIndependently
[493/1487] Testing KromoraKitTests.EditDocumentTests/testFullyPopulatedDocumentRoundTrips
[494/1487] Testing KromoraKitTests.EditDocumentTests/testLegacyDocumentKeepsAdjustmentNodesWhenNewColorFieldsAreAbsent
[495/1487] Testing KromoraKitTests.EditDocumentTests/testLUTIDEncodesAsABareString
[496/1487] Testing KromoraKitTests.EditDocumentTests/testLUTSettingsIdentityRules
[497/1487] Testing KromoraKitTests.EditDocumentTests/testLUTSettingsMissingIDAndInvalidIntensityAreSafe
[498/1487] Testing KromoraKitTests.EditDocumentTests/testNewerSchemaVersionIsRejected
[499/1487] Testing KromoraKitTests.DevelopInspectorTests/testSwitchingTabsDoesNotCancelOrRepeatHistogramWork
[500/1487] Testing KromoraKitTests.DevelopInspectorTests/testTheFinalValueOfADragIsTheOneRendered
[501/1487] Testing KromoraKitTests.DevelopInspectorTests/testTheTintBindingRoundTripsAndNeverWritesOnRead
[502/1487] Testing KromoraKitTests.DevelopInspectorTests/testWritingASliderThroughTheBindingStillDebounces
[503/1487] Testing KromoraKitTests.EditDocumentStoreTests/testCorruptRevisionReportsCorruptWithoutInventingEdits
[504/1487] Testing KromoraKitTests.EditDocumentStoreTests/testPackageRoundTripLeavesOriginalUntouched
[505/1487] Testing KromoraKitTests.EditDocumentStoreTests/testPackageFailureLeavesTheLastKnownDocumentInTheCacheOnlyUntilReload
[506/1487] Testing KromoraKitTests.DevelopInspectorTests/testWhiteBalanceOverridesDoNotTravelBetweenPhotoAssets
[507/1487] Testing KromoraKitTests.EditDocumentStoreTests/testRelaunchReadsTheDurablePackageRevision
[508/1487] Testing KromoraKitTests.DevelopInspectorTests/testWritingAToggleThroughTheBindingSkipsTheDebounce
[509/1487] Testing KromoraKitTests.EditDocumentStoreTests/testCacheIsBoundedAndEvictionReadsThePackageAgain
[510/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testEditedPhotoSurvivesAViewModelRelaunch
[511/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testAffectedRefreshRerendersOnlyThumbnailsThatReferenceAChangedLook
[512/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testALookAppearingMovesThePublishedRevisionFromUnresolvedToResolved
[513/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testImmediateEditCanBeFlushedBeforeRelaunch
[514/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testNoiseInspectorEditsSurviveAPackageRelaunch
[515/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testIdentityAndFailedEditedThumbnailsKeepSourceAspectFitted
[516/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testFailedEditedThumbnailDoesNotSettleFallbackAndVisibleDemandRetries
[517/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testIdentityDocumentPublishesNilWithoutRendering
[518/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testFailedPersistenceRemainsDirtyUntilAForcedRetrySucceeds
[519/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testFailedTerminationFlushCannotApproveQuitSilently
[520/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testMissingSourceStillReportsAnActionableLoadError
[521/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testInvalidationKeepsPublishedBitmapButClearsItsRevision
[522/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testDebounceCoalescesBurstToOneTrailingRequest
[523/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testCancelledFlushIsReportedDistinctly
[524/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testMatchingEditedThumbnailStaysVisibleDuringRepeatedDemand
[525/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testPersistedEditedThumbnailLookupRecordsOneEntryForMissingAndCorruptFrames
[526/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testPreviousEditedThumbnailStaysVisibleUntilReplacementCompletes
[527/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testSourceIdentityChangeRejectsLateResult
[528/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testShutdownDropsLateRendererResult
[529/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testRevisionIncludesEditHashAndResolvedLUTFingerprint
[530/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testLateOriginalThumbnailDoesNotReplaceSettledEditedThumbnail
[531/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testLookRefreshSkipsMaterializedThumbnailsOutsideTheVisibleWindow
[532/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testResolvedLookThumbnailIsReusedOnRepeatedDemand
[533/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testLateEditStoreResultCannotOverwriteAnInMemoryEdit
[534/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testRacedFlushReportsSuccessAfterReplacementDrainsQueue
[535/1487] Testing KromoraKitTests.EffectsInspectorTests/testDetailControlsRoundTripAndLegacyEffectsDecodeNeutralDetail
[536/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testVisibleDemandSurvivesPreviewInteractionUntilSettled
[537/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testVisibleDemandReplacesAnOlderMaterializedRevisionWithoutInteraction
[538/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testUnresolvedLookPixelsAreProvisionalAndNeverAnExactHit
[539/1487] Testing KromoraKitTests.EffectsInspectorTests/testEffectsValuesRoundToWholeNumbersAtTheValueBoundary
[540/1487] Testing KromoraKitTests.EffectsInspectorTests/testEffectsDocumentRoundTripsAsCopyableValue
[541/1487] Testing KromoraKitTests.EffectsInspectorTests/testEveryControlMapsItsOwnValueAndKeepsSiblingValues
[542/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testForcedFlushWaitsForAnInFlightSlowWrite
[543/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testRapidEditsCoalesceToOneLatestSnapshotPerAsset
[544/1487] Testing KromoraKitTests.EditPersistenceIntegrationTests/testLongGestureCheckpointsIntermediateSnapshotsBeforeMouseUp
[545/1487] Testing KromoraKitTests.EmbeddedFirstFrameTests/testOptInRealEngineEmbeddedFirstFrameTiming
[546/1487] Testing KromoraKitTests.EmbeddedFirstFrameTests/testEmbeddedFirstFrameStaleDropOnNavigation
[547/1487] Testing KromoraKitTests.EffectsInspectorTests/testBindingsRoundTripAndIndividualResetsPreserveOtherEffects
[548/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testVisibleRefreshWithOlderEditedThumbnailSurvivesPreviewInteraction
[549/1487] Testing KromoraKitTests.ExportCoordinatorTests/testBatchExportAppliesTheLUTToTheFilenames
[550/1487] Testing KromoraKitTests.EditedThumbnailCoordinatorTests/testInitialVisibleDemandUsesPersistedEditsAfterPackageReopen
[551/1487] Testing KromoraKitTests.EffectsInspectorTests/testResetAllEffectsIsIsolatedFromOtherPanels
[552/1487] Testing KromoraKitTests.EffectsInspectorTests/testNoiseInspectorBindingsWriteIndependentValuesToThePersistableDocument
[553/1487] Testing KromoraKitTests.EffectsInspectorTests/testEveryDetailControlNeutralValueFallsWithinItsOwnRange
[554/1487] Testing KromoraKitTests.ExportCoordinatorTests/testBatchExportCanBeCancelledBetweenItemsAndKeepsCompletedFiles
[555/1487] Testing KromoraKitTests.ExportCoordinatorTests/testBatchExportDoesNotOverwriteSameNamedSources
[556/1487] Testing KromoraKitTests.EmbeddedFirstFrameTests/testEmbeddedFirstFrameProvisionalThenSettled
[557/1487] Testing KromoraKitTests.EffectsInspectorTests/testSliderGestureUsesInteractiveRenderingAndOneUndoEntry
[558/1487] Testing KromoraKitTests.EffectsInspectorTests/testRetainedSubordinateValuesKeepEffectsResettableAtZeroAmount
[559/1487] Testing KromoraKitTests.ExportCoordinatorTests/testBatchExportKeepsFullResolutionWorkBoundedToOneItem
[560/1487] Testing KromoraKitTests.EmbeddedFirstFrameTests/testRendererFailureKeepsTheSelectedAssetsProvisionalThumbnail
[561/1487] Testing KromoraKitTests.ExportCoordinatorTests/testDefaultFileNameUsesTheFormatExtension
[562/1487] Testing KromoraKitTests.ExportCoordinatorTests/testBatchHEIFEncoderFailureIsIsolatedToTheItem
[563/1487] Testing KromoraKitTests.ExportCoordinatorTests/testBatchExportHonorsTheDocumentsIntensity
[564/1487] Testing KromoraKitTests.ExportCoordinatorTests/testExportBaseNameAppendsLUTWithUnderscores
[565/1487] Testing KromoraKitTests.ExportCoordinatorTests/testPerformExportReportsAFailedEncodeThroughOnError
[566/1487] Testing KromoraKitTests.ExportCoordinatorTests/testSummaryWordingCoversSingularPluralAndFailures
[567/1487] Testing KromoraKitTests.ExportCoordinatorTests/testBatchExportReportsProgressAsItGoes
[568/1487] Testing KromoraKitTests.ExportCoordinatorTests/testBatchExportWritesEveryImage
[569/1487] Testing KromoraKitTests.ExportCoordinatorTests/testPerformExportReportsAFailedWriteThroughOnError
[570/1487] Testing KromoraKitTests.ExportCoordinatorTests/testLastUsedFormatPersistsAcrossSingleAndBatchExports
[571/1487] Testing KromoraKitTests.ExportCoordinatorTests/testPerformExportWritesTheFile
[572/1487] Testing KromoraKitTests.ExportCutoverTests/testBatchExportEncodesEveryItemFromTheSameDocument
[573/1487] Testing KromoraKitTests.ExportCutoverTests/testTheDocumentReachesTheEncoderAtFullResolution
[574/1487] Testing KromoraKitTests.ExportCutoverTests/testBatchExportWritesTheSameBytesAsTheSingleExport
[575/1487] Testing KromoraKitTests.ExportCutoverTests/testEachKnobVisiblyChangesTheExportedFile
[576/1487] Testing KromoraKitTests.EmbeddedFirstFrameTests/testStandardOpenDoesNotPresentAnEmbeddedFirstFrame
[577/1487] Testing KromoraKitTests.ExportCoordinatorTests/testBatchExportSkipsAndCountsFailuresWithoutAborting
[578/1487] Testing KromoraKitTests.ExportCoordinatorTests/testBatchExportUsesEachAssetsPersistedDocument
[579/1487] Testing KromoraKitTests.ExportNamingTests/testExportFormatExtensionsAndTypesAgree
[580/1487] Testing KromoraKitTests.ExportNamingTests/testAppendsCounterOnCollision
[581/1487] Testing KromoraKitTests.ExportNamingTests/testCollisionsAreScopedToTheExtension
[582/1487] Testing KromoraKitTests.ExportNamingTests/testMatchesTheBatchExportNamingScheme
[583/1487] Testing KromoraKitTests.ExportNamingTests/testReturnsPlainNameWhenNothingCollides
[584/1487] Testing KromoraKitTests.ExportNamingTests/testHandlesNamesWithSpacesAndDots
[585/1487] Testing KromoraKitTests.ExportNamingTests/testTheExportFormatPickerContractSurvivedThePromotion
[586/1487] Testing KromoraKitTests.ExportOptionsTests/testCapabilityMatrixStatesPrecisionColorAndAlphaConstraints
[587/1487] Testing KromoraKitTests.ExportOptionsTests/testDefaultsAreFullSizeHighQualityAndSessionCompatible
[588/1487] Testing KromoraKitTests.ExportOptionsTests/testFilenamePolicyIsIndependentOfTheExportPanel
[589/1487] Testing KromoraKitTests.ExportOptionsTests/testInvalidCombinationsFailBeforeRenderingWithActionableErrors
[590/1487] Testing KromoraKitTests.ExportOptionsTests/testExportOptionsRoundTripAndRenderRequestStayValueOnly
[591/1487] Testing KromoraKitTests.ExportOptionsTests/testLongEdgeSizingPreservesAspectRatioAndDoesNotUpscaleOrientation
[592/1487] Testing KromoraKitTests.ExportOptionsTests/testOlderExportOptionsDecodeWithPrivacySafeLocationDefault
[593/1487] Testing KromoraKitTests.ExportOptionsTests/testOutputSharpeningChangesOnlyEncodedExportPixels
[594/1487] Testing KromoraKitTests.ExportOptionsTests/testRasterOutputWithExportOptionsReportsTheActualOutputKind
[595/1487] Testing KromoraKitTests.ExportOptionsTests/testOutputSharpeningPolicyPersistsAllDeliveryChoices
[596/1487] Testing KromoraKitTests.ExportOptionsTests/testRenderEngineAppliesLongEdgePolicyAtExportTime
[597/1487] Testing KromoraKitTests.ExportOptionsTests/testRenderEngineMatchesPlannedDimensionsAtExtremeAspectRatio
[598/1487] Testing KromoraKitTests.ExportOptionsTests/testRenderEngineDoesNotUpscaleSmallLongEdgeExports
[599/1487] Testing KromoraKitTests.ExportCoordinatorTests/testSelectedExportSnapshotsMembershipBeforeSelectionChangesInFlight
[600/1487] Testing KromoraKitTests.ExportCutoverTests/testBatchExportRequestCarriesTheDocumentAndEveryItem
[601/1487] Testing KromoraKitTests.FileIntegrationBoundaryTests/testDropPolicyClassifiesFileFolderAndInvalidURL
[602/1487] Testing KromoraKitTests.FileIntegrationBoundaryTests/testWorkspaceRevealIsInjectedForUserLooksFolder
[603/1487] Testing KromoraKitTests.FilmstripNavigationTests/testAdjacentIndexFollowsFilteredDisplayOrder
[604/1487] Testing KromoraKitTests.FilmstripNavigationTests/testAdjacentIndexStopsAtFilmstripEnds
[605/1487] Testing KromoraKitTests.ExportCoordinatorTests/testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals
[606/1487] Testing KromoraKitTests.ExportCutoverTests/testHoldingSpaceDoesNotChangeWhatIsExported
[607/1487] Testing KromoraKitTests.ExportCutoverTests/testExportedFileIsTheDocumentAtFullResolution
[608/1487] Testing KromoraKitTests.ExportCutoverTests/testNoHistogramIsRenderedWhileTheInspectorIsClosed
[609/1487] Testing KromoraKitTests.ExportCutoverTests/testTheHistogramDescribesTheRenderedDocument
[610/1487] Testing KromoraKitTests.ExportCutoverTests/testTheViewModelExportsTheEditedDocument
[611/1487] Testing KromoraKitTests.FilmstripNavigationTests/testFocusedArrowPressConsumesDownRepeatAndUp
[612/1487] Testing KromoraKitTests.FilmstripNavigationTests/testFilmstripLayoutUsesLargerCellsWithoutAStatusRow
[613/1487] Testing KromoraKitTests.ExportCutoverTests/testThePublishedHistogramTracksTheDocument
[614/1487] Testing KromoraKitTests.FrameLookupLedgerTests/testLedgerRecordsMonotonicEntriesAndSummarizesRejections
[615/1487] Testing KromoraKitTests.FrameLookupLedgerTests/testPreviewStoreDistinguishesMissingAndCorruptFramesWithoutThrowing
[616/1487] Testing KromoraKitTests.FrameRefinementPolicyTests/testDigestIsDeterministicAndSizeIndependent
[617/1487] Testing KromoraKitTests.FrameRefinementPolicyTests/testDigestDistanceIsSymmetricAndBounded
[618/1487] Testing KromoraKitTests.FrameRefinementPolicyTests/testDigestRejectsTheWrongSize
[619/1487] Testing KromoraKitTests.FrameRefinementPolicyTests/testSubVisibleChangeAndReduceMotionSwapImmediately
[620/1487] Testing KromoraKitTests.GeometryPointMappingTests/testGeometryMappingsRoundTripThroughQuarterTurnsAndGeometry
[621/1487] Testing KromoraKitTests.GeometryPointMappingTests/testIdentityAndQuarterTurnMapping
[622/1487] Testing KromoraKitTests.FrameRefinementPolicyTests/testThresholdSitsBetweenSubVisibleAndVisibleChanges
[623/1487] Testing KromoraKitTests.FrameRefinementPolicyTests/testVisibleChangeCrossfadesOnceForTheDocumentedDuration
[624/1487] Testing KromoraKitTests.FrameRefinementPolicyTests/testUnknownDigestsNeverAnimate
[625/1487] Testing KromoraKitTests.GeometryPointMappingTests/testRetouchSourcePointMapsThroughViewportAndBack
[626/1487] Testing KromoraKitTests.GlobalToneAnalyzerTests/testMalformedAndEmptyHistogramsAreTypedFailures
[627/1487] Testing KromoraKitTests.GlobalToneAnalyzerTests/testFractionalWeightedChannelsAllowFloatingPointAccumulationNoise
[628/1487] Testing KromoraKitTests.GlobalToneAnalyzerTests/testStatisticsUsePercentilesAndClippingFromOneHistogram
[629/1487] Testing KromoraKitTests.ImageCollectionFrameLookupTests/testApplyingStoredFramesRecordsOneLaunchHintEntryPerFrameLookup
[630/1487] Testing KromoraKitTests.ImageDropTests/testAcceptedTypesIncludeFilesImagesAndPromiseIdentifiers
[631/1487] Testing KromoraKitTests.ImageDropTests/testBitmapPayloadHasStableFilenameAndData
[632/1487] Testing KromoraKitTests.ImageDropTests/testDropDirectoriesArePurgedAfterAdoption
[633/1487] Testing KromoraKitTests.ImageDropTests/testEmptyPromiseReceiveIsSafe
[634/1487] Testing KromoraKitTests.ImageDropTests/testPromisesWinOverURLAndBitmapPayloads
[635/1487] Testing KromoraKitTests.ImageDropTests/testWebURLsAreNotAcceptedAsFileDrops
[636/1487] Testing KromoraKitTests.ImageDropTests/testFileURLsRemainURLPayloads
[637/1487] Testing KromoraKitTests.ImageRotationTests/testCropRotatesWithImageSoItStaysAnchoredToTheSameContent
[638/1487] Testing KromoraKitTests.ImageRotationTests/testQuarterTurnsSwapGeometryAndFourTurnsRestoreIt
[639/1487] Testing KromoraKitTests.ImageRotationTests/testRenderPipelineRotationSwapsPreviewAndExportGeometryWithCrop
[640/1487] Testing KromoraKitTests.ExportOptionsTests/testRenderEngineMatchesPlannedDimensionsAtFractionalLongEdgeScale
[641/1487] Testing KromoraKitTests.ImageRotationTests/testRenderEnginePreviewAndExportAgreeForRotatedCrop
[642/1487] Testing KromoraKitTests.ImageRotationTests/testRotationHistoryUndoRedoDoesNotLoseOtherEdits
[643/1487] Testing KromoraKitTests.ImageRotationTests/testRotationStateIsCodableVisibleAndIdentityAware
[644/1487] Testing KromoraKitTests.FileIntegrationBoundaryTests/testCancelledImageDialogLeavesCurrentEditUntouched
[645/1487] Testing KromoraKitTests.ImageSourceTests/testDataSourceCanReuseAnImportFingerprint
[646/1487] Testing KromoraKitTests.ImageSourceTests/testDataSourcesAreClassifiedByContent
[647/1487] Testing KromoraKitTests.ImageSourceTests/testDegenerateExtentsFallBackToOne
[648/1487] Testing KromoraKitTests.ImageSourceTests/testFileSourcesAreClassifiedByExtensionLikeTheLoader
[649/1487] Testing KromoraKitTests.ImageSourceTests/testFullScaleIsAlwaysOne
[650/1487] Testing KromoraKitTests.ImageSourceTests/testInteractiveFactorUsesItsPixelBudgetForA60MPSource
[651/1487] Testing KromoraKitTests.ImageSourceTests/testInteractiveScaleUsesDrawableSizeAndPixelBudget
[652/1487] Testing KromoraKitTests.ImageSourceTests/testPreviewBoxIsPartOfTheScaleIdentity
[653/1487] Testing KromoraKitTests.ImageSourceTests/testPreviewFitsInsideTheBoxOnTheLimitingAxis
[654/1487] Testing KromoraKitTests.ImageSourceTests/testPreviewNeverUpscales
[655/1487] Testing KromoraKitTests.ImageSourceTests/testSourcesAreEqualOnlyWhenTheirBytesAndKindMatch
[656/1487] Testing KromoraKitTests.FileIntegrationBoundaryTests/testInvalidDropLeavesCurrentEditUntouched
[657/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testActiveEditorStartsAheadOfQueuedBackgroundThumbnails
[658/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testCancelAllCompletesQueuedAndRunningJobsExactlyOnce
[659/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testActiveThumbnailAlsoPreventsBackgroundPackageIOFromStarting
[660/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testImportPriorityIsAheadOfIdlePackageMaintenance
[661/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testQueuedMaintenanceYieldsToEditorArrivingWhilePackageIOIsBusy
[662/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testPackageIOUsesSharedLaneAndYieldsWhileEditorIsActive
[663/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testQueuedThumbnailCanBeCancelledBeforeItStarts
[664/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testQueueEvictionCompletesTheEvictedJobExactlyOnce
[665/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testRejectedJobReportsItsTerminalOutcome
[666/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testSuccessfulJobReportsCompletion
[667/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testThumbnailQueueIsBoundedAndRetainsHigherPriorityWork
[668/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testThumbnailRunsImmediatelyWhenTheQueueIsDisabled
[669/1487] Testing KromoraKitTests.ImageWorkSchedulerTests/testVisibleEditorDropsQueuedSupportBeforeItIsAdmitted
[670/1487] Testing KromoraKitTests.FilmstripNavigationTests/testEachFilmstripOpenAdmitsItsSettledPreview
[671/1487] Testing KromoraKitTests.FilmstripNavigationTests/testRapidNavigationKeepsOnlyTheNewestPendingSource
[672/1487] Testing KromoraKitTests.InfoInspectorPresentationTests/testHealUsesSharedAccordionsWithPrimaryToolsOpen
[673/1487] Testing KromoraKitTests.InfoInspectorPresentationTests/testInspectorDisclosureCanExpandAndCollapseItsContent
[674/1487] Testing KromoraKitTests.FilmstripNavigationTests/testAdjacentPrefetchUsesStoredEditsForNeverOpenedNeighbor
[675/1487] Testing KromoraKitTests.InfoInspectorPresentationTests/testLookAndHistogramHeadingsFollowSharedHierarchy
[676/1487] Testing KromoraKitTests.InfoInspectorPresentationTests/testPhotoAnalysisPrecedesCollapsedEditHistoryWithExistingActions
[677/1487] Testing KromoraKitTests.InfoInspectorPresentationTests/testSharedInspectorTypeAndSpacingScale
[678/1487] Testing KromoraKitTests.InfoInspectorViewTests/testInspectorStaysMountedWhileNavigationLoadsWithoutPixelsOrHistogram
[679/1487] Testing KromoraKitTests.KromoraAboutTests/testAboutMenuAndWindowArePresentForEveryBuildConfiguration
[680/1487] Testing KromoraKitTests.KromoraAboutTests/testAboutMetadataUsesBundleValues
[681/1487] Testing KromoraKitTests.KromoraAboutTests/testAboutMetadataFallsBackForMissingOrBlankDevelopmentValues
[682/1487] Testing KromoraKitTests.KromoraAboutTests/testAboutShowsConciseLUTLicenseDisclosureWithoutInventory
[683/1487] Testing KromoraKitTests.KromoraAboutTests/testPackagedAboutLicenseMatchesTheRepositoryLicense
[684/1487] Testing KromoraKitTests.KromoraSettingsTests/testAppearancePersistsAndUnrelatedSettingsSurvive
[685/1487] Testing KromoraKitTests.KromoraSettingsTests/testCanonicalUserLookFolderIsAppOwnedAndCreated
[686/1487] Testing KromoraKitTests.KromoraSettingsTests/testCleanProfileUsesVisiblePicturesDestinations
[687/1487] Testing KromoraKitTests.KromoraSettingsTests/testClippingAlertVisibilityPersistsAcrossRelaunch
[688/1487] Testing KromoraKitTests.KromoraSettingsTests/testEditDatabaseURLIsRevealableOnlyAfterStoreFileExists
[689/1487] Testing KromoraKitTests.KromoraSettingsTests/testLastCopyCategoriesPersistAcrossRelaunch
[690/1487] Testing KromoraKitTests.KromoraSettingsTests/testLegacySettingsAreCopiedIntoKromoraNamespace
[691/1487] Testing KromoraKitTests.KromoraSettingsTests/testMaskOverlayAppearancePersistsAcrossRelaunch
[692/1487] Testing KromoraKitTests.KromoraSettingsTests/testMigrationSeedsSourceDefaultWithoutReplacingWorkflowOrLookSettings
[693/1487] Testing KromoraKitTests.KromoraSettingsTests/testOpenFirstPhotoPreferencePersistsAcrossRelaunch
[694/1487] Testing KromoraKitTests.KromoraSettingsTests/testPhotoNameVisibilityPersistsAcrossRelaunch
[695/1487] Testing KromoraKitTests.KromoraSettingsTests/testSourceAndExportFoldersPersistIndependentlyAndReset
[696/1487] Testing KromoraKitTests.KromoraSettingsTests/testStorageAdoptsLegacyApplicationSupportDirectory
[697/1487] Testing KromoraKitTests.KromoraSettingsTests/testUnavailableFolderKeepsConfiguredPreferenceAndReportsRecovery
[698/1487] Testing KromoraKitTests.KromoraThemeTests/testDarkPrimaryAccentHasAccessibleContrastAgainstCanvas
[699/1487] Testing KromoraKitTests.KromoraThemeTests/testPrimaryAccentResolvesToCentralizedCopperVariants
[700/1487] Testing KromoraKitTests.KromoraThemeTests/testShellSurfacesSeparateCanvasSidebarAndToolbarInBothAppearances
[701/1487] Testing KromoraKitTests.LUTFilterCacheTests/testCapacityIsAtLeastOne
[702/1487] Testing KromoraKitTests.LUTFilterCacheTests/testDifferentLUTsGetDifferentFilters
[703/1487] Testing KromoraKitTests.LUTFilterCacheTests/testRemoveAllDropsEverything
[704/1487] Testing KromoraKitTests.LUTFilterCacheTests/testTheCacheIsBoundedAndEvictsTheLeastRecentlyUsed
[705/1487] Testing KromoraKitTests.LUTFilterCacheTests/testOutputImageSnapshotsItsInputsRatherThanReadingThemLater
[706/1487] Testing KromoraKitTests.LUTFilterCacheTests/testTheColourSpaceIsPartOfTheKey
[707/1487] Testing KromoraKitTests.LUTFilterCacheTests/testTheSameLUTAndSpaceReturnsTheSameFilter
[708/1487] Testing KromoraKitTests.LUTIDTests/testAnInMemoryDerivedLUTGetsAContentDerivedID
[709/1487] Testing KromoraKitTests.LUTIDTests/testAScannedLibraryNeverProducesADerivedID
[710/1487] Testing KromoraKitTests.LUTIDTests/testFileIDUsesTheCanonicalPath
[711/1487] Testing KromoraKitTests.LUTIDTests/testIDIsTheFilePathAndIsStableAcrossReparsing
[712/1487] Testing KromoraKitTests.ImportedPhotoDurabilityTests/testImportedCopyIsFoundAfterCollectionRebuild
[713/1487] Testing KromoraKitTests.ImageRotationTests/testRotatingWhileCroppingKeepsDraftTransientUntilApplyOrCancel
[714/1487] Testing KromoraKitTests.ImageRotationTests/testRotationControlsUseDocumentHistoryAndResetOnlyRotation
[715/1487] Testing KromoraKitTests.ImageRotationTests/testRotatingAnImageWithACommittedCropKeepsTheSameFramedContent
[716/1487] Testing KromoraKitTests.LUTIDTests/testResolutionMissesForALUTThatIsGone
[717/1487] Testing KromoraKitTests.ImageDropTests/testBitmapDropUsesTheExistingDataImportPath
[718/1487] Testing KromoraKitTests.ImportedPhotoDurabilityTests/testDataImportsRemainSelectableAfterAnIncrementalAppend
[719/1487] Testing KromoraKitTests.LUTIDTests/testTheDerivedIDIsStableAcrossProcesses
[720/1487] Testing KromoraKitTests.LUTIDTests/testResolutionSurvivesARescan
[721/1487] Testing KromoraKitTests.ImportedPhotoDurabilityTests/testEditsFollowImportedCopyAcrossRelaunch
[722/1487] Testing KromoraKitTests.LUTLibraryTests/testACompletedScanPublishesAContentHashSnapshot
[723/1487] Testing KromoraKitTests.LUTLibraryTests/testDeltaClassifiesChangedAppearedAndDisappeared
[724/1487] Testing KromoraKitTests.LUTLibraryTests/testIdenticalSnapshotsProduceAnEmptyDelta
[725/1487] Testing KromoraKitTests.LUTLibraryTests/testAFailedScanReportsEveryPreviouslyKnownLookAsDisappeared
[726/1487] Testing KromoraKitTests.LUTLibraryTests/testAnUnchangedRescanReportsAnEmptyDelta
[727/1487] Testing KromoraKitTests.ImportedPhotoDurabilityTests/testURLImportsAppendCopyAndDeduplicate
[728/1487] Testing KromoraKitTests.LUTLibraryTests/testAnAddedAndARemovedLookAreReportedByID
[729/1487] Testing KromoraKitTests.LastKnownFrameReleaseBenchmark/testReleaseLastKnownFrameBudgets
[730/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testAFileSittingUnderAnotherAssetsNameIsAMiss
[731/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testBurstOfWritesCoalescesToTheNewestFrame
[732/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testConstructingAStoreDoesNoFilesystemWork
[733/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testCapEvictsLeastRecentlyUsedAndKeepsNewest
[734/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testCorruptEntriesAreRemovedIndividually
[735/1487] Testing KromoraKitTests.FilmstripNavigationTests/testAdjacentPrefetchScaleKeyMatchesSubsequentSelectionPreview
[736/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testEnvelopeRejectsNonJPEGPayloadEvenWhenImageIOCanDecodeIt
[737/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testEachAssetHasExactlyOneReplaceableFile
[738/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testFileNamesNeverDerivePathsOrFingerprints
[739/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testIdentityInvalidationPreservesOtherAssets
[740/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testInvalidationCancelsAPendingWrite
[741/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testLegacyExactKeyFilesAreIgnoredAndRemovedLazily
[742/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testPinnedAssetsSurviveEviction
[743/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testPixelEpochMismatchSurvivesAndClassifiesStaleCompatible
[744/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testReadingLegacyPlaceholderRemovesOnlyItsFileAndCorrectsSizeIndex
[745/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testPlaceholderFramesAreSkippedAndRemovedByBoundedSweep
[746/1487] Testing KromoraKitTests.LUTWorkflowTests/testCanonicalLookAuditionFollowsTheLibraryOrder
[747/1487] Testing KromoraKitTests.LUTLibraryTests/testReplacingBytesAtTheSamePathIsAChangeNotANewLook
[748/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testScheduledPlaceholderSweepYieldsCancelsResumesAndKeepsRealFrames
[749/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testThumbnailSweepResumesAcrossScheduledTicksAndPreservesRealRecord
[750/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testUnsupportedStorageVersionIsAPerEntryMissThatNextWriteRepairs
[751/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testUnreadableDirectoryDegradesToMisses
[752/1487] Testing KromoraKitTests.LaunchHintsTests/testHintsAreVersionedDeduplicatedAndBounded
[753/1487] Testing KromoraKitTests.LaunchHintsTests/testOversizedAndUnsupportedRecordsAreIgnored
[754/1487] Testing KromoraKitTests.LaunchHintsTests/testStoreAtomicallyPersistsAndRejectsDifferentLibraryAndCorruptRecords
[755/1487] Testing KromoraKitTests.LUTWorkflowTests/testCanonicalLookStateDistinguishesMissingReferenceFromExplicitNone
[756/1487] Testing KromoraKitTests.LibraryBrowsingCoordinatorTests/testCullingPersistsOnlyWhenStateChanges
[757/1487] Testing KromoraKitTests.LUTWorkflowTests/testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest
[758/1487] Testing KromoraKitTests.LibraryBrowsingCoordinatorTests/testDeletionConfirmationIsRefusedOutsideGrid
[759/1487] Testing KromoraKitTests.LibraryBrowsingCoordinatorTests/testFilterSortAndSearchReloadPageZeroAndSkipNoOp
[760/1487] Testing KromoraKitTests.LibraryBrowsingCoordinatorTests/testHintFrameCannotPublishAfterSourceReplacementKeepsAssetID
[761/1487] Testing KromoraKitTests.LibraryBrowsingCoordinatorTests/testFirstVisiblePublicationSupersedesHintsAndMetricsAreRecordedOnce
[762/1487] Testing KromoraKitTests.LibraryBrowsingCoordinatorTests/testInvalidAndWrongLibraryHintsRecordValidationWithoutReadingFrames
[763/1487] Testing KromoraKitTests.LibraryBrowsingCoordinatorTests/testKeyboardNextAtWindowTailLoadsNextPageBeforeSelecting
[764/1487] Testing KromoraKitTests.LibraryBrowsingCoordinatorTests/testLaunchHintsWaitForIndexAndReadOnlyIndexedAssetsWithinPolicy
[765/1487] Testing KromoraKitTests.LibraryBrowsingCoordinatorTests/testOffWindowOpenFaultsItsPageAndMissingAssetDoesNotOpen
[766/1487] Testing KromoraKitTests.LibraryBrowsingCoordinatorTests/testVisibleViewportWritesHintsWithoutRestoringSelection
[767/1487] Testing KromoraKitTests.LibraryBrowsingCoordinatorTests/testUsefulHintFramePublishesOnlyAfterViewportConfirmsAsset
[768/1487] Testing KromoraKitTests.LUTWorkflowTests/testLUTSurvivesNavigationAndRelaunchForItsPhoto
[769/1487] Testing KromoraKitTests.LUTWorkflowTests/testLookIsDiscoverableThroughOneAccessibleInspectorTab
[770/1487] Testing KromoraKitTests.LUTWorkflowTests/testLUTDoesNotCrossReferenceIdenticalReferencedPhotos
[771/1487] Testing KromoraKitTests.LUTWorkflowTests/testCopyPasteTransfersLUTToExactlySelectedPhotosAndUndoRestoresEach
[772/1487] Testing KromoraKitTests.LibraryChromeLayoutTests/testImportAndExportStayTrailingBesideTheSidebar
[773/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testSettledHitSkipsTheRendererAndStillAdmitsHistogram
[774/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testRoundTripUsesARealCanonicalRasterAcrossInstances
[775/1487] Testing KromoraKitTests.LibraryCullingTests/testCullingShortcutRoutingCoversPickRejectClearAndRatings
[776/1487] Testing KromoraKitTests.LatestPreviewFrameStoreTests/testZoomedSettledRequestRendersInsteadOfAdoptingTheCanonicalDiskEntry
[777/1487] Testing KromoraKitTests.LibraryBrowsingProjectionTests/testOpeningBrowsingAssetPublishesItsPersistedContentIdentity
[778/1487] Testing KromoraKitTests.LibraryCullingTests/testFilteredNavigationOnlyVisitsVisibleItems
[779/1487] Testing KromoraKitTests.LibraryCullingTests/testFlagAndRatingFiltersComposeWithoutChangingAssetState
[780/1487] Testing KromoraKitTests.LibraryCullingTests/testPickRejectAdvanceAndUndoRestoreFocusAndState
[781/1487] Testing KromoraKitTests.LibraryBrowsingProjectionTests/testBrowsingIdentitiesNeverAliasAcrossAssets
[782/1487] Testing KromoraKitTests.LibraryBrowsingProjectionTests/testBrowsingAssetsOpenNoRecords
[783/1487] Testing KromoraKitTests.LibraryBrowsingProjectionTests/testBrowsingPageMatchesMaterializedPageWithBoundedReads
[784/1487] Testing KromoraKitTests.LibraryBrowsingProjectionTests/testFilteredSortedQueriesReadNoRecords
[785/1487] Testing KromoraKitTests.LibraryBrowsingProjectionTests/testResolveEmbeddedSourceURLReadsAtMostOneRecord
[786/1487] Testing KromoraKitTests.LibraryBrowsingProjectionTests/testSelectingAnotherPackagePhotoClearsThePreviousPixelsBeforeResolvingItsRecord
[787/1487] Testing KromoraKitTests.LibraryDeletionCoordinatorTests/testFlushFailureLeavesTheCandidateUntouched
[788/1487] Testing KromoraKitTests.LibraryDeletionCoordinatorTests/testTrashIsRestoredWhenEditDeletionFails
[789/1487] Testing KromoraKitTests.LibraryChromeLayoutTests/testEditorKeepsContentBelowTheNativeWindowToolbar
[790/1487] Testing KromoraKitTests.LibraryCullingTests/testRapidCullAdvanceInEditLoadsTheNewFocusedPhoto
[791/1487] Testing KromoraKitTests.LibraryGridTests/testEXIFPortraitKeepsItsFramingBeforeAndAfterSelection
[792/1487] Testing KromoraKitTests.LibraryGridTests/testDemandDrivenGridWaitsForMaterializedCellsBeforeDecoding
[793/1487] Testing KromoraKitTests.LibraryGridTests/testInvalidAspectRatiosUseStablePhotographicFallback
[794/1487] Testing KromoraKitTests.LibraryCullingTests/testCullingStateSurvivesACollectionRecreation
[795/1487] Testing KromoraKitTests.LibraryGridTests/testMosaicCacheKeepsPlacedRowsWhenResolvedAspectIsRewritten
[796/1487] Testing KromoraKitTests.LibraryChromeLayoutTests/testLibraryChromeSecondUpdateFinishes
[797/1487] Testing KromoraKitTests.LibraryGridTests/testMosaicCacheRebuildsWhenPlaceholderAspectBecomesResolved
[798/1487] Testing KromoraKitTests.LibraryGridTests/testMosaicCacheRecomputesWhenOrderedItemIdentitiesChange
[799/1487] Testing KromoraKitTests.LibraryGridTests/testMosaicCacheRebuildsWhenCropGenerationChanges
[800/1487] Testing KromoraKitTests.LibraryDeletionTests/testCancellationLeavesSelectionAndSourceUntouched
[801/1487] Testing KromoraKitTests.LibraryGridTests/testMosaicRowsKeepCellIdentityAndAspectRatioAttachedToSourceOrder
[802/1487] Testing KromoraKitTests.LibraryGridTests/testPresentedAspectRatioUsesCropPixelsAndKeepsIdentitySourceAspect
[803/1487] Testing KromoraKitTests.LibraryGridTests/testMosaicRowsPreserveMixedOrientationWithoutOverlapAtRepresentativeWidths
[804/1487] Testing KromoraKitTests.LibraryGridTests/testPresentedAspectRatioAppliesDocumentRotationBeforeCrop
[805/1487] Testing KromoraKitTests.LibraryDeletionCoordinatorTests/testPortableLibraryRemovalUsesThePortableSession
[806/1487] Testing KromoraKitTests.LibraryDeletionCoordinatorTests/testRetryAfterPartialPortableRemovalFinishesInsteadOfFailing
[807/1487] Testing KromoraKitTests.LibraryImportCoordinatorTests/testShutdownInvalidatesCurrentGeneration
[808/1487] Testing KromoraKitTests.LibraryImportCoordinatorTests/testStartingAnotherImportInvalidatesPreviousGeneration
[809/1487] Testing KromoraKitTests.LibraryGridTests/testProjectedEntryResolvesByStableIDWhenItsIndexIsStale
[810/1487] Testing KromoraKitTests.LibraryMediaWorkflowCoordinatorTests/testDialogAndDropRouteOutsideTheDestinationPolicy
[811/1487] Testing KromoraKitTests.LibraryIsolationTests/testTestCollectionUsesAnIsolatedManagedLibrary
[812/1487] Testing KromoraKitTests.LibraryDeletionTests/testManagedCopyIsMovedOutOfLibraryWhileExternalSourceSurvives
[813/1487] Testing KromoraKitTests.LibraryMediaWorkflowCoordinatorTests/testValidatedRemovableSelectionIsPublishedAsAValueRequest
[814/1487] Testing KromoraKitTests.LibraryGridTests/testVisibleMosaicIndicesCoverTheViewportAndPrefetchWithoutTheWholeLibrary
[815/1487] Testing KromoraKitTests.LibraryGridTests/testVisibleWindowLoadsEveryRequestedPhotoWithoutASelectionChange
[816/1487] Testing KromoraKitTests.LibraryQueryControllerTests/testDisplayNameSortOrdersFoldedDuplicatesWithoutRecursing
[817/1487] Testing KromoraKitTests.LibraryQueryControllerTests/testFilteringAndSortingUseSummaryValuesAndSelectionStaysUUIDKeyed
[818/1487] Testing KromoraKitTests.LibraryDeletionTests/testMultiSelectionDeletesOnlyTheSelectedPhotos
[819/1487] Testing KromoraKitTests.LibraryQueryControllerTests/testProjectionRoundTripsAsARebuildableLocalIndex
[820/1487] Testing KromoraKitTests.LibraryDeletionTests/testPersistenceFailureLeavesTheReferencedItemAndOriginalIntact
[821/1487] Testing KromoraKitTests.LibraryDeletionTests/testReferencedDeletionRetainsImmutableEditsAcrossCollectionRescan
[822/1487] Testing KromoraKitTests.LibraryScanTests/testCollectionScansFolderAndRecordsSubfolders
[823/1487] Testing KromoraKitTests.LibraryScanTests/testCollectionIgnoresUnsupportedFiles
[824/1487] Testing KromoraKitTests.LibraryChromeLayoutTests/testReturningFromEditRestoresTheSameLibraryViewportWidth
[825/1487] Testing KromoraKitTests.LibraryQueryControllerTests/testIndexProjectionExcludesTombstonesAndKeepsSelectionUUIDBased
[826/1487] Testing KromoraKitTests.LibraryScanTests/testEmptyFolderIsNotActive
[827/1487] Testing KromoraKitTests.LibraryScanTests/testEmptyFolderIsReportedAsEmpty
[828/1487] Testing KromoraKitTests.LibraryScanTests/testExternalImportAppearsInCanonicalBrowserAndReportsMalformedFiles
[829/1487] Testing KromoraKitTests.LibraryScanTests/testMetadataLoadsAfterDiscoveryWithoutBlockingTheFirstRows
[830/1487] Testing KromoraKitTests.LibraryScanTests/testLargeScanPublishesAFirstBatchBeforeTheScanFinishes
[831/1487] Testing KromoraKitTests.LibraryScanTests/testMissingFolderIsReportedAsMissingNotEmpty
[832/1487] Testing KromoraKitTests.LibraryScanTests/testNavigationStaysInBounds
[833/1487] Testing KromoraKitTests.LibraryScanTests/testRefreshingAnImportedFileReplacesItsTableAtTheSameStablePath
[834/1487] Testing KromoraKitTests.LibraryScanTests/testRemovingActiveItemFallsBackToRemainingSelection
[835/1487] Testing KromoraKitTests.LibraryQueryControllerTests/testCorruptIndexAutomaticallyFallsBackToShardRebuild
[836/1487] Testing KromoraKitTests.LibraryScanTests/testRescanReplacesAFileBackedTableAtTheSameStablePath
[837/1487] Testing KromoraKitTests.LibraryScanTests/testScanDiscoversCubeAndTextBasedLookFiles
[838/1487] Testing KromoraKitTests.LibraryScanTests/testScanIgnoresNonCubeFiles
[839/1487] Testing KromoraKitTests.LibraryScanTests/testScanGroupsTopLevelAndSubfolders
[840/1487] Testing KromoraKitTests.LibraryScanTests/testScanReturnsBeforeWorkCompletes
[841/1487] Testing KromoraKitTests.LibraryScanTests/testRescanReplacesPreviousResults
[842/1487] Testing KromoraKitTests.LibraryScanTests/testScanSkipsUnparseableFilesButKeepsTheRest
[843/1487] Testing KromoraKitTests.LibrarySelectionTests/testCommandClickTogglesAndKeepsAValidActivePhoto
[844/1487] Testing KromoraKitTests.LibraryScanTests/testUnreadableImageIsReportedWithoutDiscardingReadableFiles
[845/1487] Testing KromoraKitTests.LibrarySelectionTests/testOrdinaryCommandAndShiftClicksMatchNativeBatchSelection
[846/1487] Testing KromoraKitTests.LibrarySelectionTests/testSelectAllAndRescanReconcileRemovedIDs
[847/1487] Testing KromoraKitTests.LibraryScanTests/testSingleImageFolderIsActive
[848/1487] Testing KromoraKitTests.LibraryScanTests/testSwitchingFoldersCannotPublishResultsFromTheCancelledScan
[849/1487] Testing KromoraKitTests.LibrarySelectionTests/testSyntheticThousandItemGridKeepsViewportWorkBounded
[850/1487] Testing KromoraKitTests.LibraryQueryControllerTests/testFailedRebuildClearsIsRebuilding
[851/1487] Testing KromoraKitTests.LibraryQueryControllerTests/testRebuildProgressPublishesACompletePageBeforeCompletion
[852/1487] Testing KromoraKitTests.LibraryScanTests/testClearDropsBrowsingStateButKeepsNothingStale
[853/1487] Testing KromoraKitTests.LibraryQueryControllerTests/testWarmSessionReadsOnlyTheIndexAndDoesNotRequireAssetRecords
[854/1487] Testing KromoraKitTests.LightAdjustmentsTests/testEditHashIsStableAndIncludesLightState
[855/1487] Testing KromoraKitTests.LightAdjustmentsTests/testLegacyToneCurveDecodeKeepsFixedEndpointBehavior
[856/1487] Testing KromoraKitTests.LightAdjustmentsTests/testLegacyDocumentWithoutLightRetainsOldNodes
[857/1487] Testing KromoraKitTests.LightAdjustmentsTests/testLightCodableRoundTripIncludesCurve
[858/1487] Testing KromoraKitTests.LightAdjustmentsTests/testMovableToneCurveEndpointsNormalizeAndRoundTrip
[859/1487] Testing KromoraKitTests.LightAdjustmentsTests/testMovableToneCurveEndpointsPersistThroughEditDocument
[860/1487] Testing KromoraKitTests.LightAdjustmentsTests/testNeutralLightIsIdentityAndHasPhotographerFacingRanges
[861/1487] Testing KromoraKitTests.LightAdjustmentsTests/testScalarsAreFiniteAndClampedAtConstructionAndMutation
[862/1487] Testing KromoraKitTests.LightAdjustmentsTests/testRGBAndParametricCurvesRoundTripAndPreserveLegacyMasterCurve
[863/1487] Testing KromoraKitTests.LightAdjustmentsTests/testToneCurveClickSamplesTheCurrentCurve
[864/1487] Testing KromoraKitTests.LightAdjustmentsTests/testToneCurveNeverOvershootsMonotonicControlPoints
[865/1487] Testing KromoraKitTests.LightAdjustmentsTests/testToneCurveInterpolatesDeterministicallyAndClampsInput
[866/1487] Testing KromoraKitTests.LightAdjustmentsTests/testToneCurveNormalizesPointsAndKeepsItsVersion
[867/1487] Testing KromoraKitTests.LightAdjustmentsTests/testToneCurveRemovalOnlyChangesInteriorPoints
[868/1487] Testing KromoraKitTests.LightAdjustmentsTests/testToneCurveRejectsANewerSchemaVersion
[869/1487] Testing KromoraKitTests.LibraryQueryControllerTests/testProjectionReadsMembershipSummariesWithoutAssetRecordsAndPagesAt500
[870/1487] Testing KromoraKitTests.LibraryQueryControllerTests/testMissingIndexRebuildsFromShardsPublishesFirstPageAndPreservesContent
[871/1487] Testing KromoraKitTests.LibraryWindowedBrowsingTests/testGridKeyboardStepsThroughSingleAuthority
[872/1487] Testing KromoraKitTests.LightAdjustmentsTests/testToneCurveReportsNonMonotonicControlPointsWithoutRewritingThem
[873/1487] Testing KromoraKitTests.LightInspectorTests/testComparisonBaselineRemovesLightButKeepsDevelop
[874/1487] Testing KromoraKitTests.LibraryWindowedBrowsingTests/testSingleSelectionAuthority
[875/1487] Testing KromoraKitTests.LibraryWindowedBrowsingTests/testAppendWindowPreservesSelectionAndIdentity
[876/1487] Testing KromoraKitTests.LibraryWindowedBrowsingTests/testPortableFilterSortWithoutMaterialization
[877/1487] Testing KromoraKitTests.LightInspectorTests/testCurveHitTestingUsesTheSameNormalizedToleranceForSelectionAndRemoval
[878/1487] Testing KromoraKitTests.LibraryWindowedBrowsingTests/testWindowedLaunchBoundsRetainedItems
[879/1487] Testing KromoraKitTests.LibraryWindowedBrowsingTests/testWindowedPagesPreserveStableIdentity
[880/1487] Testing KromoraKitTests.LightAdjustmentsTests/testToneCurveUsesSmoothShapePreservingInterpolation
[881/1487] Testing KromoraKitTests.LightInspectorTests/testAccessibilityAdjustableActionAddsTheFirstCurvePoint
[882/1487] Testing KromoraKitTests.LightInspectorTests/testCurveDragCoalescesEveryTickIntoOneUndoStep
[883/1487] Testing KromoraKitTests.LightInspectorTests/testCurveAddAndRemoveEachUseOneUndoStep
[884/1487] Testing KromoraKitTests.LightInspectorTests/testCurveDragKeepsMonotonicControlPointsOrderedAndBounded
[885/1487] Testing KromoraKitTests.LightInspectorTests/testLightControlsExposePhotographerRangesInPanelOrder
[886/1487] Testing KromoraKitTests.LightInspectorTests/testNearestPointIncludesEndpointsSoAPressOnAHandleStartsADragNotAnAdd
[887/1487] Testing KromoraKitTests.LightInspectorTests/testAdvancedCurveControlsAreCollapsedUntilExpanded
[888/1487] Testing KromoraKitTests.LightInspectorTests/testCurveDragMovesBothEndpointsInBothDimensions
[889/1487] Testing KromoraKitTests.LightInspectorTests/testToneCurveGraphPinsItsVerticalSizeInsideTheScrollingInspector
[890/1487] Testing KromoraKitTests.LightInspectorTests/testToneCurveHandleHitTestingUsesRenderedPositionsAtInspectorSizes
[891/1487] Testing KromoraKitTests.LightInspectorTests/testDoubleClickEndpointResetPreservesInteriorPointsAndGroupsUndo
[892/1487] Testing KromoraKitTests.LightInspectorTests/testToneCurveResetUsesAccessibleTrailingDisclosureAction
[893/1487] Testing KromoraKitTests.LightInspectorTests/testCurveDragPublishesAnIntermediatePreviewBeforeRelease
[894/1487] Testing KromoraKitTests.LocalAdjustmentControlTests/testAllSupportedLocalControlsUseTheirGlobalStageContract
[895/1487] Testing KromoraKitTests.LocalAdjustmentControlTests/testCopyPasteAndPersistenceKeepLocalAdjustmentsQuantized
[896/1487] Testing KromoraKitTests.LightInspectorTests/testEmptyCurveDragCreatesOnePointAndUndoRedoKeepTheWholeGestureTogether
[897/1487] Testing KromoraKitTests.LightInspectorTests/testIndividualAndPanelResetsAreScopedAndUndoable
[898/1487] Testing KromoraKitTests.LightInspectorTests/testInspectorRetainsViewportWidthDuringUnspecifiedScrollMeasurements
[899/1487] Testing KromoraKitTests.LightInspectorTests/testLightBindingRoundTripsAndDoesNotTouchOtherDocumentSections
[900/1487] Testing KromoraKitTests.LightInspectorTests/testLightSliderGestureIsOneUndoOperation
[901/1487] Testing KromoraKitTests.LocalAdjustmentControlTests/testEveryLocalControlQuantizesToHundredthsAndPreservesSiblings
[902/1487] Testing KromoraKitTests.LocalAdjustmentControlTests/testLocalReadoutsKeepUnitsAndHundredthPrecision
[903/1487] Testing KromoraKitTests.LocalMaskTests/testBrushResamplingFillsSparseNativeEventSegmentsWithoutChangingEndpoints
[904/1487] Testing KromoraKitTests.LocalAdjustmentLatencyBenchmark/testOptInBrushLocalExposurePreviewLatency
[905/1487] Testing KromoraKitTests.LocalMaskTests/testBrushMathUsesMousePressureAndSmoothRepeatedStampAccumulation
[906/1487] Testing KromoraKitTests.LocalMaskTests/testBrushResamplingIsDistanceBasedAndBoundedForLongGestures
[907/1487] Testing KromoraKitTests.LocalMaskTests/testCompleteRecipeRoundTripsAndUsesNormalizedGeometry
[908/1487] Testing KromoraKitTests.LocalMaskTests/testCompositionIsBoundedAndDeterministic
[909/1487] Testing KromoraKitTests.LocalMaskTests/testComponentOperationAndNameParticipateInDocumentHash
[910/1487] Testing KromoraKitTests.LocalMaskTests/testMaskComponentNameAndOperationRoundTripWithLegacyPayload
[911/1487] Testing KromoraKitTests.LocalMaskTests/testNeutralAndDisabledLayersAreIdentity
[912/1487] Testing KromoraKitTests.LocalMaskTests/testLinearGradientMathUsesEndpointsForAngleFalloffAndSmoothAlpha
[913/1487] Testing KromoraKitTests.LightInspectorTests/testToneCurveEditingRoutesEveryOperationToSelectedChannel
[914/1487] Testing KromoraKitTests.LightInspectorTests/testNearExistingPointMovesThatPointWithoutAddingADuplicate
[915/1487] Testing KromoraKitTests.LocalMaskTests/testNewLinearGradientsDefaultToVerticalWithoutChangingEndpointSemantics
[916/1487] Testing KromoraKitTests.LocalMaskTests/testNormalizedMaskPointClampsToUnitSquare
[917/1487] Testing KromoraKitTests.LocalMaskTests/testRadialGradientMathUsesSourcePixelsForRotationAndFalloff
[918/1487] Testing KromoraKitTests.LocalMaskTests/testRangeMaskRecipesRoundTripAndClampTheirControls
[919/1487] Testing KromoraKitTests.LocalMaskTests/testMaskCompositionIsOrderedAndStableForDisabledAndEmptyComponents
[920/1487] Testing KromoraKitTests.LightInspectorTests/testToneCurveResetClearsOnlySelectedChannelAndIsUndoable
[921/1487] Testing KromoraKitTests.LookNavigationTests/testCycleIncludesNoneBeforeTheFirstLook
[922/1487] Testing KromoraKitTests.LocalMaskTests/testRangeResolverBuildsLuminanceAndColorRastersAndExplainsMissingDepth
[923/1487] Testing KromoraKitTests.LocalMaskTests/testV1DocumentMigratesToV2WithEmptyLocalState
[924/1487] Testing KromoraKitTests.LookNavigationTests/testCycleWalksLibraryOrderAndStopsAtTheLastLook
[925/1487] Testing KromoraKitTests.LookSignatureTests/testAnUnresolvedLookNeverSuppressesARenderInEitherDirection
[926/1487] Testing KromoraKitTests.LookNavigationTests/testEmptyLibraryStaysOnNone
[927/1487] Testing KromoraKitTests.LookSignatureTests/testAnUnresolvedSignatureNeverMatchesExactly
[928/1487] Testing KromoraKitTests.LookSignatureTests/testAResolvedFrameStopsBeingExactWhenTheLookBytesChange
[929/1487] Testing KromoraKitTests.LookSignatureTests/testNoneAndUnresolvedAreDistinctValues
[930/1487] Testing KromoraKitTests.LookSignatureTests/testNoneAndUnresolvedAreDistinctSignaturesForFrames
[931/1487] Testing KromoraKitTests.LookSignatureTests/testLiveSignatureChangesWhenTableBytesChangeAtTheSameLUTID
[932/1487] Testing KromoraKitTests.LookSignatureTests/testReferencesMatchesResolvedAndUnresolvedButNotNone
[933/1487] Testing KromoraKitTests.LookSignatureTests/testRenderRequestUsesTheSameDerivation
[934/1487] Testing KromoraKitTests.LookSignatureTests/testRescanningIdenticalBytesYieldsAnEqualSignature
[935/1487] Testing KromoraKitTests.LookSignatureTests/testResolvedMatchesOnlyTheSameIDAndContent
[936/1487] Testing KromoraKitTests.LightInspectorTests/testPhotoHandoffRestoresTheLightDocumentAndHistory
[937/1487] Testing KromoraKitTests.LookSignatureTests/testSettingsWithoutAResolvedTableAreUnresolvedNotNone
[938/1487] Testing KromoraKitTests.MaskInteractionStateTests/testDraftCommitAndCancelDoNotRequireDocumentState
[939/1487] Testing KromoraKitTests.LookSignatureTests/testSavedCommentsChangeTheHashEvenWhenTheTableIsUnchanged
[940/1487] Testing KromoraKitTests.MaskPresentationPolicyTests/testOverlayOpacityOnlyControlsCoverageAndToolingStaysOpaque
[941/1487] Testing KromoraKitTests.LookSignatureTests/testSignatureRoundTripsThroughCodable
[942/1487] Testing KromoraKitTests.LookSignatureTests/testLiveHashIsTheSHA256OfTheFileBytesAndMatchesAPackageReference
[943/1487] Testing KromoraKitTests.LocalAdjustmentBindingTests/testBindingIsLayerScopedUndoableAndDoesNotTouchGlobalAdjustments
[944/1487] Testing KromoraKitTests.MaskPresentationPolicyTests/testStrongSubjectIsActionable
[945/1487] Testing KromoraKitTests.MaskPresentationPolicyTests/testUsefulBackgroundRemainsActionableWhenSubjectIsAbsent
[946/1487] Testing KromoraKitTests.MaskedToneAnalyzerTests/testMaskFromAnotherSourceIsRejectedBeforeRendering
[947/1487] Testing KromoraKitTests.MaskingPanelTests/testApplyIsTruthfullyDisabledWhenNoLocalAdjustmentHookExists
[948/1487] Testing KromoraKitTests.MaskPresentationPolicyTests/testWeakAndEmptySubjectsAreFilteredWithDifferentReasons
[949/1487] Testing KromoraKitTests.MaskedToneAnalyzerTests/testRegionalStatisticsUseOnlyTheSelectedPixels
[950/1487] Testing KromoraKitTests.MaskedToneAnalyzerTests/testSoftMaskRetainsFractionalEdgeWeights
[951/1487] Testing KromoraKitTests.MaskRefinementTests/testCancellationDoesNotPersistAnIncompleteRenderMask
[952/1487] Testing KromoraKitTests.MaskingPanelTests/testPanelModelUsesCoordinatorMasksAndSharedMaskOperationsForInvert
[953/1487] Testing KromoraKitTests.MaskingPanelTests/testSelectInvertApplyHandsDerivedMaskAndCurrentAssetToLocalWorkflow
[954/1487] Testing KromoraKitTests.MaskingPanelTests/testMaskingPanelInitializesWithoutAPreviewSurface
[955/1487] Testing KromoraKitTests.MaskRefinementTests/testRefinementUpsamplesSeedIntoRenderQualityAndPersistsIt
[956/1487] Testing KromoraKitTests.MaskingWorkflowCoordinatorTests/testCreateMaskAppendsLayerAndSelectsIt
[957/1487] Testing KromoraKitTests.MaskingPanelTests/testUnavailableMasksExplainFailureAndRemainRetryable
[958/1487] Testing KromoraKitTests.MaskingWorkflowCoordinatorTests/testCreateSmartMaskFailurePreparesRetryContext
[959/1487] Testing KromoraKitTests.MaskingWorkflowCoordinatorTests/testCreateSmartMaskInsertsDurableLayerOnSuccess
[960/1487] Testing KromoraKitTests.MaskingWorkflowCoordinatorTests/testCreateSmartMaskWithoutOpenSourceReportsUnavailable
[961/1487] Testing KromoraKitTests.MaskingWorkflowCoordinatorTests/testDeleteMaskRemovesLayerAndClearsSolo
[962/1487] Testing KromoraKitTests.MaskingWorkflowCoordinatorTests/testLocalAdjustmentUpdatePreservesDebouncedPreviewIntent
[963/1487] Testing KromoraKitTests.MaskingWorkflowCoordinatorTests/testRetryMaskAnalysisReplaysCreateContext
[964/1487] Testing KromoraKitTests.MaskingWorkflowCoordinatorTests/testShutdownCancelsInFlightWorkWithoutCrashing
[965/1487] Testing KromoraKitTests.MaskingWorkflowCoordinatorTests/testCreateSmartMaskCancellationLeavesNoLayer
[966/1487] Testing KromoraKitTests.MaskingWorkflowCoordinatorTests/testCreateSmartMaskSupersessionOnlyAdmitsLatestResult
[967/1487] Testing KromoraKitTests.LookSignatureTests/testPackageRevisionResolvesItsSignatureFromTheStoredReference
[968/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testAddingEraseBrushToSelectedMaskTargetsThatLayer
[969/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testActiveBrushSettingsAreCapturedOnceEvenIfControlsChangeMidStroke
[970/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testCancellingLinearCreationDoesNotPersistAnEmptyLayer
[971/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testComponentActionsPreserveOrderNamesAndSoloInspection
[972/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testClickWithoutAValidLinearDragLeavesDocumentAndHistoryUnchanged
[973/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testCanvasToolsAreOnlyPointerToolsAndSmartMasksLeaveTheCanvasNavigable
[974/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testBrushGestureCommitsOneCompactStrokeWithSettings
[975/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testEnteringRetouchSelectsHealByDefault
[976/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testComponentCreationSupportsEverySourceAndOperationWithExplicitFirstReplace
[977/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testCancellingRadialCreationDoesNotPersistAnEmptyLayer
[978/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testEraseBrushIsASeparateSubtractingComponent
[979/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testGestureEditsTheSelectedComponentNotJustTheFirstEnabledOne
[980/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testGradientClickOnANonGradientMaskRestoresThePreviousSelection
[981/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testFreshLinearCreationSelectsLayerAndComponentAndCommitsOneUndoableMask
[982/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testLayerActionsPersistThroughTheDocumentAndUndo
[983/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testInfoAnalysisMaskRejectsALowConfidenceResultWithoutCreatingARecipe
[984/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testInspectorChangesFollowTheLiveLinearDraftUntilMouseUp
[985/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testInfoAnalysisMaskRejectsAResultFromAnotherSourceWithoutCreatingARecipe
[986/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testGradientDragOnANonGradientMaskDrawsANewGradientMask
[987/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testInfoAnalysisMaskCreatesAndReusesTheDemonstratedSemanticMask
[988/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testLinearCreationAfterExistingSelectionDoesNotEditPreviousLayer
[989/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testLinearDragCreatesAndSelectsATransientLayerUntilMouseUp
[990/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testLinearFullStrengthHandleResizesWithoutReplacingDefinition
[991/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testLinearHandleEditsKeepOppositeEdgeAndCenterStable
[992/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testOptionScrollResizesTheBrushProportionallyWithinTheSliderRange
[993/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testLinearZeroStrengthHandleResizesWithoutReplacingDefinition
[994/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testMaskingIsAnInspectorTabAndReturnsToThePreviousEditControl
[995/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testEraseGesturePreservesEachExistingMaskSourceAndAppendsSubtractBrushIntent
[996/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testNewLinearLayerStartsWithCreationDragEvenWhenDefaultGuideIsUnderPointer
[997/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testMaskPreviewTargetsOverrideOverlaySelectionWithoutEditingOrHistory
[998/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testMaskOverlayIsScopedToMaskingTabAndEditorWorkspace
[999/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testMaskAdjustmentGroupsListEveryControlExactlyOnce
[1000/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testMaskingInspectorTabStaysWithTheActivePhotoAndRestoresItsDocument
[1001/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testOverlayAppearanceFollowsSettingsAndOTogglesVisibility
[1002/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testProductionCreationExposesEverySupportedSmartKindAndPersistsIt
[1003/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testOverlayPresentationControlsDoNotChangeDocumentOrUndoHistory
[1004/1487] Testing KromoraKitTests.MediaVolumeImportTests/testExplicitImportUsesURLBackedPhotoAssetsAndPreservesSource
[1005/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testRadialCenterDragUsesTheViewportDeltaAtZoomAndPreservesDefinition
[1006/1487] Testing KromoraKitTests.MediaVolumeImportTests/testFailedMediaVolumeImportDoesNotRetainACollectionScope
[1007/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testRadialDragCreatesAndSelectsATransientLayerUntilMouseUp
[1008/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testRadialHandlesResizeTranslateRotateAndOptionShiftModifiers
[1009/1487] Testing KromoraKitTests.MediaVolumeImportTests/testMountedScannerAdmitsSupportedImagesWithOrientationAndWarnings
[1010/1487] Testing KromoraKitTests.MediaVolumeImportTests/testMountedScannerResolvesAUserGrantedBookmarkBeforeScanning
[1011/1487] Testing KromoraKitTests.MediaVolumeSelectionTests/testSelectionSupportsAllNoneAndToggle
[1012/1487] Testing KromoraKitTests.ModelDependencyTests/testDurableValueFilesDoNotAcquireUIFrameworks
[1013/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testRepeatedFaceActionCreatesIndependentlyIndexedDurableMasks
[1014/1487] Testing KromoraKitTests.ModelDependencyTests/testModelsDirectoryAllowsUIImportsOnlyForNamedPresentationOwners
[1015/1487] Testing KromoraKitTests.ModelDependencyTests/testPlatformResponsibilitiesHaveExplicitOwners
[1016/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testSeparateBrushGesturesAppendStrokesWithoutRewritingHistory
[1017/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testRetryingFailedSmartComponentReattemptsTheOriginalLayerAdd
[1018/1487] Testing KromoraKitTests.NavigationStateTests/testModeIsAnExplicitSmallValueState
[1019/1487] Testing KromoraKitTests.ObservabilityTests/testEndingAnIntervalMoreThanOnceIsSafe
[1020/1487] Testing KromoraKitTests.ObservabilityTests/testLiveEditReportDoesNotTreatGPUCompletionAsPresentation
[1021/1487] Testing KromoraKitTests.ObservabilityTests/testLiveEditReportJoinsInputToPresentationAndQuantiles
[1022/1487] Testing KromoraKitTests.ObservabilityTests/testLiveEditRetentionIsBoundedAndEffectiveDimensionsAreRecorded
[1023/1487] Testing KromoraKitTests.ObservabilityTests/testSourceTokensAreStablePrivateSafeAndDistinct
[1024/1487] Testing KromoraKitTests.ObservabilityTests/testWorkflowEventsCoverCacheAndSupersededWork
[1025/1487] Testing KromoraKitTests.ObservabilityTests/testWorkflowVocabularyHasStableNamesForEveryRequiredStage
[1026/1487] Testing KromoraKitTests.MediaVolumeImportTests/testEmptyScanKeepsARecoverableEmptyStateAndCancelClosesIt
[1027/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testSourceSwitchResetClearsTransientMaskPresentationState
[1028/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testSmartCreationFailureWithoutSupportedSourceDoesNotCreateAnInertLayer
[1029/1487] Testing KromoraKitTests.MaskingWorkspaceTests/testSmartActionPreflightsSharedProviderThenSelectsDurableMask
[1030/1487] Testing KromoraKitTests.ObservationInvalidationTests/testLUTProjectionsAreMemoizedAgainstRevision
[1031/1487] Testing KromoraKitTests.ObservationInvalidationTests/testObservableTypesAreNotWrappedInStateObject
[1032/1487] Testing KromoraKitTests.ObservationInvalidationTests/testRenderDiagnosticsSnapshotTracksEvaluations
[1033/1487] Testing KromoraKitTests.MediaVolumeImportTests/testInjectedProviderLabelsVolumesNeedingAccessWithoutHidingThem
[1034/1487] Testing KromoraKitTests.ObservationInvalidationTests/testSliderValueThroughputP95StaysWithinBudget
[1035/1487] Testing KromoraKitTests.ObservationInvalidationTests/testThumbnailStreamingDoesNotTouchCollectionRevision
[1036/1487] Testing KromoraKitTests.MediaVolumeImportTests/testMountedVolumeNotificationRefreshesMediaAfterInitialDiscovery
[1037/1487] Testing KromoraKitTests.OnboardingTests/testBundledSampleLibraryHasTwoReadablePhotosAndLicenseManifest
[1038/1487] Testing KromoraKitTests.OnboardingTests/testGuidedEditStepsMakeBoundedSingleDocumentAdjustments
[1039/1487] Testing KromoraKitTests.OnboardingTests/testLightControlsHaveContextualExplanations
[1040/1487] Testing KromoraKitTests.MediaVolumeImportTests/testInjectedProviderCoversDiscoveryScanAndFailureState
[1041/1487] Testing KromoraKitTests.ObservationInvalidationTests/testCanvasNavigationDoesNotTriggerBroadModelPublisher
[1042/1487] Testing KromoraKitTests.ObservationInvalidationTests/testCollectionThumbnailStreamingDoesNotTriggerBroadPublisher
[1043/1487] Testing KromoraKitTests.OriginalSettingsBundleTests/testBundleIncludesUnmodifiedOriginalAndVerifiableSettings
[1044/1487] Testing KromoraKitTests.ObservationInvalidationTests/testExportProgressIsIsolatedFromBroadModelPublisher
[1045/1487] Testing KromoraKitTests.ObservationInvalidationTests/testImportProgressDoesNotTriggerBroadModelPublisher
[1046/1487] Testing KromoraKitTests.ObservationInvalidationTests/testLowFrequencyChildrenForwardSynchronouslyWithoutTask
[1047/1487] Testing KromoraKitTests.OriginalSettingsBundleTests/testVerificationRejectsChangedOriginal
[1048/1487] Testing KromoraKitTests.OriginalSettingsBundleTests/testVerificationRejectsChangedSettings
[1049/1487] Testing KromoraKitTests.ObservationInvalidationTests/testNavigationP95StaysWithinBudget
[1050/1487] Testing KromoraKitTests.ObservationInvalidationTests/testNoTaskPerChildNotificationRemains
[1051/1487] Testing KromoraKitTests.PackagePathTests/testPackagePathAcceptsValidNestedPathAndRejectsSymlinkEscape
[1052/1487] Testing KromoraKitTests.PackagePathTests/testPackagePathRejectsAbsoluteTraversalAndDotComponents
[1053/1487] Testing KromoraKitTests.ObservationInvalidationTests/testViewModelImportCoordinatorProgressStaysIsolated
[1054/1487] Testing KromoraKitTests.PackageSettingsTests/testEvaluationHarnessStaysOutOfShippingSources
[1055/1487] Testing KromoraKitTests.PackageSettingsTests/testEveryTargetIsInSwift6LanguageMode
[1056/1487] Testing KromoraKitTests.PackageSettingsTests/testTheManifestDeclaresASwift6ToolsVersion
[1057/1487] Testing KromoraKitTests.PackageSettingsTests/testTheModuleUsesNoConcurrencyEscapeHatches
[1058/1487] Testing KromoraKitTests.PackedThumbnailPrototypeTests/testCompactionReclaimsStaleAndDeletedBytesWithoutDanglingOffsets
[1059/1487] Testing KromoraKitTests.PackageEditProjectionTests/testPackageIsCanonicalAndProjectionRebuildPreservesExactDocument
[1060/1487] Testing KromoraKitTests.OpenImageDialogTests/testEmptyOpenResultLeavesCurrentCollectionAndEditUntouched
[1061/1487] Testing KromoraKitTests.PackageEditProjectionTests/testNamedSnapshotAndDurableHistorySurviveStoreReload
[1062/1487] Testing KromoraKitTests.PackedThumbnailPrototypeTests/testLookupHandlesMissingDuplicateAndStaleEntries
[1063/1487] Testing KromoraKitTests.PhotoAnalysisAssemblyTests/testAssemblyWithNoMasksStillProducesTierZeroAnalysis
[1064/1487] Testing KromoraKitTests.PackedThumbnailPrototypeTests/testPerFileComparatorReclaimsDeletedThumbnailImmediately
[1065/1487] Testing KromoraKitTests.PhotoAnalysisCacheTests/testPortableIdentityKeyRoundTripsWithoutAPathComponent
[1066/1487] Testing KromoraKitTests.PhotoAnalysisCacheTests/testCancelledWriteLeavesNoPartialEntry
[1067/1487] Testing KromoraKitTests.PackageEditProjectionTests/testPackagePersistenceCoordinatorStillCoalescesToOneRevision
[1068/1487] Testing KromoraKitTests.PhotoAnalysisAssemblyTests/testAssemblyDegradesToTierZeroAndOneAvailableMask
[1069/1487] Testing KromoraKitTests.PhotoAnalysisAssemblyTests/testAssemblyIncludesEveryAnalyzedMaskAndRoundTrips
[1070/1487] Testing KromoraKitTests.PhotoAnalysisCacheTests/testRoundTripPersistsAnalysisBySourceAndVersion
[1071/1487] Testing KromoraKitTests.PhotoAnalysisCacheTests/testSourceKeyDoesNotIncludeEditDocumentState
[1072/1487] Testing KromoraKitTests.PhotoAnalysisCacheTests/testRemoveOnlyDeletesOneAssetAndLeavesUnrelatedAnalysisIntact
[1073/1487] Testing KromoraKitTests.PhotoAnalysisCoordinatorTests/testAnalysisCacheHitSkipsMaskProviderOnTheNextRequest
[1074/1487] Testing KromoraKitTests.PhotoAnalysisCoordinatorTests/testAnalysisRecordsMeasuredStageTimings
[1075/1487] Testing KromoraKitTests.PhotoAnalysisCoordinatorTests/testDirectMaskRequestDoesNotRunGlobalAnalysis
[1076/1487] Testing KromoraKitTests.PhotoAnalysisCoordinatorTests/testCancellingTheOnlyWaiterCancelsUnderlyingMaskWork
[1077/1487] Testing KromoraKitTests.PhotoAssetTests/testAssetAndMutableLibraryStateRoundTripThroughCodable
[1078/1487] Testing KromoraKitTests.PhotoAnalysisCoordinatorTests/testConcurrentAnalysesShareOneInFlightAnalysisAndItsMaskStage
[1079/1487] Testing KromoraKitTests.PhotoAssetTests/testChangingAFileChangesItsCacheIdentity
[1080/1487] Testing KromoraKitTests.PhotoAnalysisCoordinatorTests/testCancellingOneOfSeveralWaitersDoesNotCancelTheOthers
[1081/1487] Testing KromoraKitTests.PhotoAnalysisCoordinatorTests/testConcurrentDirectMaskRequestsShareOneProviderTask
[1082/1487] Testing KromoraKitTests.OpenImageDialogTests/testOpenImagesKeepsSingleFileBehaviorAndDeduplicatesRepeatedURLs
[1083/1487] Testing KromoraKitTests.PhotoAssetTests/testDifferentFilesDoNotCollideEvenWhenTheirBytesMatch
[1084/1487] Testing KromoraKitTests.PhotoAssetTests/testIdentityDerivesFileTypeFromDataWhenNameHasNoExtension
[1085/1487] Testing KromoraKitTests.PhotoAssetTests/testIdentityHasDeterministicFallbacksWhenNameAndTypeAreMissing
[1086/1487] Testing KromoraKitTests.PhotoAssetTests/testCollectionItemsUseStableAssetIDs
[1087/1487] Testing KromoraKitTests.OpenImageDialogTests/testOpenImagesAddsSortedURLBackedAssetsAndLoadsTheFirst
[1088/1487] Testing KromoraKitTests.PhotoAssetTests/testIdentityUsesPreservedNameAndFileTypeForFileBackedAsset
[1089/1487] Testing KromoraKitTests.PackageEditProjectionTests/testLegacyVirtualCopyNameResolvesToEmbeddedFile
[1090/1487] Testing KromoraKitTests.PhotoAssetTests/testUnchangedFileHasStableIdentityAndFingerprintAcrossRebuilds
[1091/1487] Testing KromoraKitTests.PhotoAssetTests/testMovingAnUnchangedFileRetainsTheSourceFingerprint
[1092/1487] Testing KromoraKitTests.PhotosImportBatchCoordinatorTests/testAsyncInsertionUsesTheSameOutcomeMappingAndBatchState
[1093/1487] Testing KromoraKitTests.PhotosImportBatchCoordinatorTests/testDuplicateOnlyAndEmptyBatchesResetWithoutRefresh
[1094/1487] Testing KromoraKitTests.PhotosImportBatchCoordinatorTests/testBatchRefreshesOnceAndOpensFirstAssetOnlyForInitiallyEmptyPackage
[1095/1487] Testing KromoraKitTests.PhotosImportBatchCoordinatorTests/testMapsInsertedDuplicateAndFailureResults
[1096/1487] Testing KromoraKitTests.PhotosImportBatchCoordinatorTests/testSupersededAsyncInsertAndRefreshFailureCannotOpenAsset
[1097/1487] Testing KromoraKitTests.PortableCacheIdentityTests/testChangingContentChangesRenderIdentityEvenWhenAssetUUIDIsRetained
[1098/1487] Testing KromoraKitTests.PortableCacheIdentityTests/testImageSourceCacheIdentityRefreshesAfterFileMetadataChanges
[1099/1487] Testing KromoraKitTests.PortableCacheIdentityTests/testLegacySourceConstructionUsesPortableFingerprintAcrossRelocation
[1100/1487] Testing KromoraKitTests.PortableCacheIdentityTests/testMaskAndPreviewDiskKeysUseOnlyPortableIdentity
[1101/1487] Testing KromoraKitTests.PackagePathTests/testValidationReportsSymlinkedOriginalAsCritical
[1102/1487] Testing KromoraKitTests.PortableCacheIdentityTests/testPhotoAssetCacheKeySurvivesRelocationAndInvalidatesReplacement
[1103/1487] Testing KromoraKitTests.PortableCacheIdentityTests/testRenderCacheHitsAfterRelocationWithTheSamePortableIdentity
[1104/1487] Testing KromoraKitTests.PortableCacheIdentityTests/testThumbnailCacheUsesPortableIdentityAfterRelocation
[1105/1487] Testing KromoraKitTests.PhotoIntelligenceDecisionLogicTests/testDecisionLogicRunsTheFullSemanticAssemblyAndMeetsExpectations
[1106/1487] Testing KromoraKitTests.PackageEditProjectionTests/testHistoryNavigationBranchesWithoutWritingAndPreservesNamedSnapshots
[1107/1487] Testing KromoraKitTests.PackageEditProjectionTests/testVirtualCopyHasIndependentIdentityAndEditHistory
[1108/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testLegacyEditPointerDecodesAndRoundTripsAsNotNamedSnapshot
[1109/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testCreateWritesManifestAndAll256MembershipShards
[1110/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testPortablePackageErrorUsesLocalizedDescription
[1111/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testAppendEditRevisionSkipsSidecarsMissingFromTheAssetRecord
[1112/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testEditCommitAbortsWhenMembershipGeometryCannotBeRead
[1113/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testXMPWithDOCTYPEEntityBombIsRejectedAsMalformedRatherThanExpanded
[1114/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testCopiedPackageOpensWithIdenticalPortableIdentityAndNoRelink
[1115/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testEditRevisionAndPresentedGeometryPublishOrRollbackTogether
[1116/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testMalformedXMPIsReportedAndCanBeQuarantined
[1117/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testReservedReferencedAssetFieldsRoundTripWithoutResolverBehavior
[1118/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testEditRevisionsRoundTripAsNativeAndXMPAndRemainImmutable
[1119/1487] Testing KromoraKitTests.PortableLibraryPackageTests/testUnknownTopLevelJSONMembersSurviveManifestShardAndRecordRewrite
[1120/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testAsynchronousStartupShutdownCancelsQueuedIndexWorkAndReleasesLease
[1121/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testAsynchronousLaunchBrowsingDoesNotSuppressSessionFingerprintBackfill
[1122/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testAsyncImportCancellationLeavesNoPublishedAsset
[1123/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testAsynchronousStartupRebuildPublishesFirstPageAndReleasesLeaseOnShutdown
[1124/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testAsyncImportPublishesProgressAndAppliesMembershipDelta
[1125/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testDefaultPackageLivesInPicturesWithCanonicalName
[1126/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testExistingInvalidPackageFailsClosedWithoutReplacement
[1127/1487] Testing KromoraKitTests.PortableLibraryBackupTests/testDiskFullLeavesResumableStagingWithoutPublishing
[1128/1487] Testing KromoraKitTests.PortableLibraryBackupTests/testCancellationLeavesDestinationAbsentAndResumeUsesStaging
[1129/1487] Testing KromoraKitTests.PortableLibraryBackupTests/testBackupFlushesBeforeSnapshotPublishesAndExcludesDerived
[1130/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testCancellingQueuedImportTerminatesProgressStream
[1131/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testBrowsingProjectionUsesPersistedSourceFingerprintWithoutOpeningRecords
[1132/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testExpiredWriterLeaseStaysClosedUntilRecoveryIsRequested
[1133/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testLeaseLossDuringSessionStopsWritesWithDistinctError
[1134/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testPackageReopensAfterDisposableProjectionAndDerivedDataAreRemoved
[1135/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testShortLeaseHeartbeatKeepsImportsWritablePastTwoDurations
[1136/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testFirstLaunchReopenAndPackageCopyPreserveImportedOriginals
[1137/1487] Testing KromoraKitTests.PortableLibraryRestoreTests/testFailedValidationLeavesActivePackageUntouchedAndReportsFailure
[1138/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testShutdownWaitsForHeartbeatBeforeReleasingLease
[1139/1487] Testing KromoraKitTests.PortableLibraryRestoreTests/testCancellationDuringRestoreDoesNotReplaceActivePackage
[1140/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testStoragePolicyKeepsProjectionAndCachesOutsidePackage
[1141/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testSourceReplacementUpdatesRecordAndMembershipInOneTransaction
[1142/1487] Testing KromoraKitTests.PortableLibraryValidationTests/testValidationDoesNotMutateThePackage
[1143/1487] Testing KromoraKitTests.PortableLibraryValidationTests/testValidationSeparatesCanonicalChecksumsFromRebuildableGaps
[1144/1487] Testing KromoraKitTests.PortableLibraryValidationTests/testStaleIndexAndMalformedDerivedArtifactsStayRebuildable
[1145/1487] Testing KromoraKitTests.PortableLibraryValidationTests/testCorruptAssetRecordAndEditSidecarAreCritical
[1146/1487] Testing KromoraKitTests.PortablePackageEndToEndRegressionTests/testCancellationDuringEditSidecarStagingRollsBackAllRevisionFiles
[1147/1487] Testing KromoraKitTests.PortableLibraryBackupTests/testChangedBackupReusesUnchangedFilesAndPublishesOnlyAfterVerification
[1148/1487] Testing KromoraKitTests.PortableLibrarySessionTests/testSourceFingerprintBackfillResumesAfterCommittedBatch
[1149/1487] Testing KromoraKitTests.PortablePackageEndToEndRegressionTests/testDiskFullDuringImportRollsBackTheAssetAndLeavesTheSourceUntouched
[1150/1487] Testing KromoraKitTests.PortablePackageEndToEndRegressionTests/testOlderReaderDecodesCurrentPackageRecordAndIgnoresNewerFields
[1151/1487] Testing KromoraKitTests.PortablePackageImportTests/testCancellationRollsBackStagingAndLeavesSourceUntouched
[1152/1487] Testing KromoraKitTests.PortablePackageEndToEndRegressionTests/testConcurrentImportAttemptIsRejectedByThePackageLeaseThenSucceedsAfterRelease
[1153/1487] Testing KromoraKitTests.PortablePackageEndToEndRegressionTests/testCorruptShardIsDiscoveredOnOpenAndCorruptRecordOnRead
[1154/1487] Testing KromoraKitTests.PortablePackageImportTests/testDuplicateContentIsReportedAndSkippedWithoutSecondAsset
[1155/1487] Testing KromoraKitTests.PortablePackageImportTests/testImportHashesStagesAndPublishesEachAssetWithProgress
[1156/1487] Testing KromoraKitTests.PortablePackageMaintenanceTests/testInterruptedMaintenanceRollsBackAndCanBeRetried
[1157/1487] Testing KromoraKitTests.PortableLibraryRestoreTests/testRestoreDoesNotServeStaleAnalysisForReplacedSourceIdentity
[1158/1487] Testing KromoraKitTests.PortablePackageMaintenanceTests/testMaintenanceCoordinatorRetriesFailureOnTheMaintenanceLane
[1159/1487] Testing KromoraKitTests.PortablePackageMaintenanceTests/testMaintenanceCoordinatorRetriesSchedulerRejectionAfterQueueDrains
[1160/1487] Testing KromoraKitTests.PortablePackageMaintenanceTests/testPackedThumbnailCompactionReclaimsStaleBytesAndKeepsLiveOffsets
[1161/1487] Testing KromoraKitTests.PortablePackageMaintenanceTests/testMaintenanceSweepsOrphanedQuarantineDirectoryFromAnInterruptedPass
[1162/1487] Testing KromoraKitTests.PortablePackageEndToEndRegressionTests/testPackageWorkflowLeavesCurrentDeletionDataAndUnrelatedUserDataUntouched
[1163/1487] Testing KromoraKitTests.PortablePackageTransactionTests/testDeadLocalWriterRecoversBeforeLeaseExpiryAndRollsBackFirst
[1164/1487] Testing KromoraKitTests.PortablePackageTransactionTests/testCommitJournalsStagesChecksumsAndPublishesAtomically
[1165/1487] Testing KromoraKitTests.PortableLibraryRestoreTests/testRestoreRebuildsCleanIndexAndPreservesEveryEditRepresentation
[1166/1487] Testing KromoraKitTests.PortablePackageTransactionTests/testLeaseContentionRenewalExpiryAndExplicitBreaking
[1167/1487] Testing KromoraKitTests.PortablePackageTransactionTests/testLiveRemoteAndReusedPIDIdentityClassification
[1168/1487] Testing KromoraKitTests.PortablePackageTransactionTests/testLeaseLossPreventsPublishAndRecoveryCanRollBack
[1169/1487] Testing KromoraKitTests.PortablePhotoIdentityTests/testDifferentContentAtTheSamePathChangesIdentity
[1170/1487] Testing KromoraKitTests.PortablePhotoIdentityTests/testImageSourceRehashesWhenFileChangeSignatureChanges
[1171/1487] Testing KromoraKitTests.PortablePhotoIdentityTests/testImageSourceReusesKnownContentHashWhenFileSignatureIsUnchanged
[1172/1487] Testing KromoraKitTests.PortablePhotoIdentityTests/testMovingAndRenamingContentPreservesIdentity
[1173/1487] Testing KromoraKitTests.PortablePackageMaintenanceTests/testRevisionCompactionRetainsCurrentNewestAndProtectedRevisions
[1174/1487] Testing KromoraKitTests.PortablePhotoIdentityTests/testPersistedIdentityReusesHashForMatchingFileSignatureWithoutReadingFile
[1175/1487] Testing KromoraKitTests.PortablePhotoIdentityTests/testPersistedIdentityRehashesWhenFileSignatureChanges
[1176/1487] Testing KromoraKitTests.PortablePhotoIdentityTests/testRelativePathResolutionIsExplicitlyAtRenderBoundary
[1177/1487] Testing KromoraKitTests.PortablePhotoIdentityTests/testSourceWithoutPersistedIdentityKeepsImageIODecoderVersionAndHashesFile
[1178/1487] Testing KromoraKitTests.PortablePhotoIdentityTests/testSameContentAtDifferentPathsHasByteIdenticalPortableIdentity
[1179/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testDifferentAssetIsUnusable
[1180/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testDisplayP3RasterCannotBePresentedInSRGB
[1181/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testEveryInputEqualIsExact
[1182/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testEditMismatchIsStaleCompatible
[1183/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testInvalidStoredResolutionIsUnusable
[1184/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testLookContentChangeIsStaleCompatible
[1185/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testEveryRejectionReportsItsFirstReason
[1186/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testSourceReplacementIsUnusableEvenWhenEverythingElseMatches
[1187/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testPixelEpochBumpIsStaleCompatibleNotUnusable
[1188/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testSourceFingerprintGeometryIsTolerantOfAnUnknownSide
[1189/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testUnresolvedInputsAreProvisionalOnly
[1190/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testSRGBFrameUnderAWiderWorkingSpaceIsStaleCompatible
[1191/1487] Testing KromoraKitTests.PresentationFrameClassifierTests/testUnresolvedLookNeverMatchesEvenItself
[1192/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testCorruptJPEGIsRejectedAtDecode
[1193/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testBadMagicIsRejected
[1194/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testEveryTruncationIsRejectedWithoutCrashing
[1195/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testHeaderLengthPastEndOfFileIsTruncation
[1196/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testIdentityMismatchIsRejected
[1197/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testHeaderOnlyReadSkipsTheRaster
[1198/1487] Testing KromoraKitTests.PortablePackageTransactionTests/testRecoverExpiredWriterRollsBackThenAllowsANewLease
[1199/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testJPEGWhoseSizeDisagreesWithMetadataIsRejected
[1200/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testMetadataSignedForAnotherAssetIsRejected
[1201/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testInvalidDimensionsAreRejected
[1202/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testOversizedHeaderLengthIsRejectedBeforeAllocation
[1203/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testRoundTripPreservesMetadataAndRaster
[1204/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testTrailingBytesAreRejected
[1205/1487] Testing KromoraKitTests.PresentationFrameEnvelopeTests/testUnsupportedStorageVersionIsReportedNotDecoded
[1206/1487] Testing KromoraKitTests.PortablePackageTrashTests/testInterruptedQuarantineTransactionRestoresDirectoryAndMembership
[1207/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testComparisonAndCropFramesNeverConsultTheStoredFrame
[1208/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testIdleAndAdjacentPrefetchJobsHaveIndependentCancellationIDs
[1209/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testExactStoredFrameSkipsTheRendererAndPresentsThroughTheConfirmedTail
[1210/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testIdleAdmissionNeverCallsPreviewPublication
[1211/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testComparisonRetryRunsOncePerComparisonRevision
[1212/1487] Testing KromoraKitTests.PortablePackageMaintenanceTests/testRevisionCompactionRetainsNamedSnapshotsAndPrunesOtherStaleRevisions
[1213/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testPendingStoredFrameLookupDefersTheRenderUntilItFinishes
[1214/1487] Testing KromoraKitTests.PortablePackageTrashTests/testReclaimRequiresConfirmationAndPermanentlyRemovesOnlyQuarantine
[1215/1487] Testing KromoraKitTests.PortablePackageTrashTests/testReferencedAssetIsTombstonedButNeverQuarantinedOrReclaimed
[1216/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testStoredFrameOfAReplacedSourceIsNeverACandidate
[1217/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testStoredLookIdentityMakesAWarmOpenExactBeforeTheLookScanFinishes
[1218/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testAssetIdentityRejectsEqualSourceResultsFromAnEarlierPhoto
[1219/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testAStaleResultCannotPublishAfterANewRevision
[1220/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testInteractiveSubmissionPromotesAfterQuietPeriodWithoutGestureCallbacks
[1221/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testASupersededBaseFrameNeitherPublishesNorRefines
[1222/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testStaleStoredFrameWaitsForStoredEditsThenRendersOnce
[1223/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testStaleDisplayRevisionAndAssetDropStoredFrameHit
[1224/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testROIRequestDoesNotAdoptCanonicalStoredFrame
[1225/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testInteractiveUpdatesDoNotStartAnotherRenderWhileOneIsInFlight
[1226/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testInteractiveToneCurvePublishesBeforeGestureEnds
[1227/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testPublicationCarriesCallerGenerationsThroughSettling
[1228/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testSettledGPUPublicationDoesNotRasterizeASecondImage
[1229/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testMaskedPreviewPublishesABaseFrameBeforeTheResolvedOne
[1230/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testRapidInteractiveSubmissionsCoalesceToTheLatestDocument
[1231/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testRebuiltRequestsKeepTheGeometryPresentationROI
[1232/1487] Testing KromoraKitTests.PortablePackageTrashTests/testRemoveQuarantinesAndRestoreRecoversOriginalAndRecord
[1233/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testSettledPromotionRetainsTheOriginatingInputTimestamp
[1234/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testUnmaskedPreviewStaysSinglePhase
[1235/1487] Testing KromoraKitTests.PreviewCoordinatorTests/testWarmSemanticMasksRenderInASinglePhase
[1236/1487] Testing KromoraKitTests.PreviewPresentationCoordinatorTests/testGenerationFencesAreIndependentAcrossPresentationSurfaces
[1237/1487] Testing KromoraKitTests.PreviewPresentationCoordinatorTests/testAConfirmedFrameConsumesTheStoredCandidate
[1238/1487] Testing KromoraKitTests.PreviewPresentationCoordinatorTests/testResolutionPlannerStateIsIndependentAndResettable
[1239/1487] Testing KromoraKitTests.PreviewPresentationCoordinatorTests/testPresentationSessionFencesCandidatesAndTracksFirstAndConfirmedFrames
[1240/1487] Testing KromoraKitTests.PreviewPublicationCoordinatorTests/testComparisonAndCropFramesDoNotWrite
[1241/1487] Testing KromoraKitTests.PreviewPublicationCoordinatorTests/testDevelopChangeSchedulesOneComparisonRefreshAndThenClears
[1242/1487] Testing KromoraKitTests.PreviewPresentationCoordinatorTests/testStoredFrameReplacesThumbnailAndEmbeddedCandidatesButNothingReplacesIt
[1243/1487] Testing KromoraKitTests.PreviewPresentationCoordinatorTests/testStoredFrameLookupRecordsExactlyOneLedgerEntryForEachOutcome
[1244/1487] Testing KromoraKitTests.PreviewPublicationCoordinatorTests/testInteractiveFramePresentsWithoutHistogramOrIdleAdmission
[1245/1487] Testing KromoraKitTests.PreviewPublicationCoordinatorTests/testFrameStoreRastersAreConfirmedWithoutBeingRewritten
[1246/1487] Testing KromoraKitTests.PreviewPresentationCoordinatorTests/testAnUnusableStoredFrameIsReportedAsAMiss
[1247/1487] Testing KromoraKitTests.PreviewPresentationCoordinatorTests/testCanonicalWritesRequirePreviewQualityACompleteFrameAndAResolvedLook
[1248/1487] Testing KromoraKitTests.PreviewPresentationCoordinatorTests/testCanonicalWriteRecordsEveryFrameSignatureComponent
[1249/1487] Testing KromoraKitTests.PreviewPublicationCoordinatorTests/testRefusedCheaperFrameStillAdmitsHistogramForTheVisiblePhoto
[1250/1487] Testing KromoraKitTests.PreviewPublicationCoordinatorTests/testRefusedFrameAdmitsHistogramFromTheSurfaceWhenPresentationWasNotConfirmed
[1251/1487] Testing KromoraKitTests.PreviewPublicationCoordinatorTests/testSettledCompleteFrameAdmitsSupportingWorkAndCanonicalCache
[1252/1487] Testing KromoraKitTests.PreviewPublicationCoordinatorTests/testResetForSourceClearsPublishedFrameAccessor
[1253/1487] Testing KromoraKitTests.PreviewPresentationCoordinatorTests/testStoredFrameLookupYieldsAUsableCandidateOnlyForTheSelectedSession
[1254/1487] Testing KromoraKitTests.PreviewPublicationCoordinatorTests/testStaleAssetOrDisplayRevisionDoesNotPresent
[1255/1487] Testing KromoraKitTests.PrimarySubjectSelectorTests/testNoSubjectEvidenceDoesNotForceBackgroundOrUnknownPick
[1256/1487] Testing KromoraKitTests.PreviewPublicationCoordinatorTests/testSettledROIFrameDoesNotWriteCanonicalCache
[1257/1487] Testing KromoraKitTests.PreviewPublicationCoordinatorTests/testSpeculativeFrameBeforeStoredEditsResolveDoesNotWrite
[1258/1487] Testing KromoraKitTests.PrimarySubjectSelectorTests/testRepeatedSelectionOfNearIdenticalInputIsStable
[1259/1487] Testing KromoraKitTests.PrimarySubjectSelectorTests/testSimilarCandidatesAreDeterministicAndLowerConfidence
[1260/1487] Testing KromoraKitTests.PrimarySubjectSelectorTests/testSingleDominantRegionProducesHighConfidencePick
[1261/1487] Testing KromoraKitTests.RAWCapabilitiesTests/testControlsComeOutInPanelOrder
[1262/1487] Testing KromoraKitTests.RAWCapabilitiesTests/testASingleUnsupportedAdjustmentIsTheOnlyOneMissing
[1263/1487] Testing KromoraKitTests.RAWCapabilitiesTests/testEveryControlsSliderRangeIsPinned
[1264/1487] Testing KromoraKitTests.PrimarySubjectSelectorTests/testWeakSaliencyRemainsVeryLowConfidence
[1265/1487] Testing KromoraKitTests.RAWCapabilitiesTests/testEachGatedControlIsWithdrawnByExactlyItsOwnFlag
[1266/1487] Testing KromoraKitTests.RAWCapabilitiesTests/testEveryGatedSeedIsReadBehindItsOwnSupportedFlag
[1267/1487] Testing KromoraKitTests.RAWCapabilitiesTests/testGatedControlsAppearOnlyWhenSupported
[1268/1487] Testing KromoraKitTests.RAWCapabilitiesTests/testExactlyTheBoolBackedControlsAreToggles
[1269/1487] Testing KromoraKitTests.RAWCapabilitiesTests/testUngatedControlsAreAlwaysOffered
[1270/1487] Testing KromoraKitTests.RAWDevelopSettingsTests/testEveryGatedAdjustmentIsAppliedOnlyBehindItsOwnSupportedFlag
[1271/1487] Testing KromoraKitTests.RAWDevelopSettingsTests/testAnySingleSettingBreaksNeutrality
[1272/1487] Testing KromoraKitTests.RAWDevelopSettingsTests/testNeutralIsEmptyAndEqualsADefaultValue
[1273/1487] Testing KromoraKitTests.RAWDevelopSettingsTests/testSettingsRoundTripAndOmitNilFields
[1274/1487] Testing KromoraKitTests.RawOrientationTests/testAlreadyOrientedPortraitOutputIsNotBakedAgain
[1275/1487] Testing KromoraKitTests.RawOrientationTests/testApplyingOrientationGeometryForAllEight
[1276/1487] Testing KromoraKitTests.RawOrientationTests/testEXIFOrientationFallsBackToUp
[1277/1487] Testing KromoraKitTests.RawOrientationTests/testEXIFOrientationReaderMatchesTaggedJPEGs
[1278/1487] Testing KromoraKitTests.RawOrientationTests/testNonSwappingOutputIsNotBakedAgain
[1279/1487] Testing KromoraKitTests.RawOrientationTests/testSensorNativePortraitOutputIsBakedOnce
[1280/1487] Testing KromoraKitTests.RecipeExtractorTests/testBuiltCubeIsAlwaysFullyPopulatedAndFinite
[1281/1487] Testing KromoraKitTests.RawOrientationTests/testOrientationThreeFlipsPixelsEndForEnd
[1282/1487] Testing KromoraKitTests.RecipeExtractorTests/testFilledCellsAveraging
[1283/1487] Testing KromoraKitTests.RecipeExtractorTests/testGeometryMismatchErrorNamesBothSizes
[1284/1487] Testing KromoraKitTests.RecipeExtractorTests/testSmoothingIsNotOrderDependent
[1285/1487] Testing KromoraKitTests.RecipeExtractorTests/testSmoothingPullsFromNeighboursOnePassAtATime
[1286/1487] Testing KromoraKitTests.RecipeExtractorTests/testUnfilledCellsAnchorToIdentity
[1287/1487] Testing KromoraKitTests.RecipeExtractorTests/testWorkingSizeCapsLongEdgeAndKeepsAspect
[1288/1487] Testing KromoraKitTests.RecipeExtractorTests/testWorkingSizeCapsPortraitOnItsLongEdge
[1289/1487] Testing KromoraKitTests.RecipeExtractorTests/testWorkingSizeLeavesSmallImagesAlone
[1290/1487] Testing KromoraKitTests.RecipeExtractorTests/testWorkingSizeZeroMeansNative
[1291/1487] Testing KromoraKitTests.RegionMaskTests/testMaskOperationsComposeAndRejectDifferentSizes
[1292/1487] Testing KromoraKitTests.RegionMaskTests/testMaskStoreKeepsQualityLevelsIndependentAcrossReopen
[1293/1487] Testing KromoraKitTests.RegionMaskTests/testMaskStoreLoadsLegacyInlinePayloads
[1294/1487] Testing KromoraKitTests.RegionMaskTests/testNormalizedMaskValidatesPixelPayload
[1295/1487] Testing KromoraKitTests.RegionMaskTests/testMaskStoreRoundTripsPixelsThroughSidecar
[1296/1487] Testing KromoraKitTests.RegionMaskTests/testRegionMaskCarriesReferenceInsteadOfPixels
[1297/1487] Testing KromoraKitTests.RegionMaskTests/testRefineDoesNotReuseRenderResultAtAnotherTargetSize
[1298/1487] Testing KromoraKitTests.RegionMaskTests/testResizeInterpolatesAcrossSizesAndPreservesIdentity
[1299/1487] Testing KromoraKitTests.RegionMaskTests/testRefineReusesStoredRenderResult
[1300/1487] Testing KromoraKitTests.RegionMaskTests/testResizeUsesClampToEdgeForSinglePixelDimensions
[1301/1487] Testing KromoraKitTests.RegionMaskTests/testSemanticKindsAndQualityRoundTrip
[1302/1487] Testing KromoraKitTests.RegionMaskTests/testTrustedMaskCarriesGenerationCoverageAndKeepsCodableSchema
[1303/1487] Testing KromoraKitTests.RegionRelationshipsTests/testDarkSubjectBrightBackgroundUsesSignedPerceptualDeltas
[1304/1487] Testing KromoraKitTests.RegionRelationshipsTests/testFaceRelationshipsRemainNilWithoutFaceButSubjectRelationshipsRemain
[1305/1487] Testing KromoraKitTests.PortablePackageTransactionTests/testInjectedFailureAtEveryTransactionBoundaryRecoversWithoutPartialFiles
[1306/1487] Testing KromoraKitTests.RenderEngineProcessingPrefixAcceptanceTests/testNoZeroFillStaticTest
[1307/1487] Testing KromoraKitTests.RegionMaskTests/testTrustedMaskPreconditionRejectsCountMismatch
[1308/1487] Testing KromoraKitTests.RegionRelationshipsTests/testNoPrimarySubjectProducesNoFabricatedRelationships
[1309/1487] Testing KromoraKitTests.RenderEngineProcessingPrefixAcceptanceTests/testNoCPUUploadOnLUTTickTest
[1310/1487] Testing KromoraKitTests.RenderEngineProcessingPrefixAcceptanceTests/testNonGPUFallbackTest
[1311/1487] Testing KromoraKitTests.RenderRequestTests/testAllFiveQualityTiersAreRepresented
[1312/1487] Testing KromoraKitTests.RenderEngineProcessingPrefixAcceptanceTests/testPressureEvictsTexturePrefixTest
[1313/1487] Testing KromoraKitTests.RawOrientationTests/testLocalPortraitRAWDevelopMatchesThumbnailAxes
[1314/1487] Testing KromoraKitTests.RAWCapabilitiesTests/testProbingAStandardImageReturnsNil
[1315/1487] Testing KromoraKitTests.RAWCapabilitiesTests/testRawTintDirectionMatchesGreenToMagentaTrack
[1316/1487] Testing KromoraKitTests.RenderEngineProcessingPrefixAcceptanceTests/testPrefixPixelParityTest
[1317/1487] Testing KromoraKitTests.RenderEngineProcessingPrefixAcceptanceTests/testOutputIdenticalTest
[1318/1487] Testing KromoraKitTests.RenderRequestTests/testInteractivePixelBudgetTracksVisibleROIAcrossZoomLevels
[1319/1487] Testing KromoraKitTests.RenderEngineProcessingPrefixAcceptanceTests/testSettledPublishCountTest
[1320/1487] Testing KromoraKitTests.RenderRequestTests/testNeutralRenderBakesOrientationAndReportsTheEncodedExtent
[1321/1487] Testing KromoraKitTests.PreviewAdmissionCoordinatorTests/testNeighbourWithIndexedFingerprintDoesNotResolveItsRecord
[1322/1487] Testing KromoraKitTests.RenderRequestTests/testQualityControlsExtentWithoutChangingTheEditModel
[1323/1487] Testing KromoraKitTests.RenderRequestTests/testPreviewAndExportParityUsesExplicitQualityAndOutputPolicies
[1324/1487] Testing KromoraKitTests.RenderRequestTests/testDehazeFullRangeKeepsPreviewAndExportGeometryAndPixelsAligned
[1325/1487] Testing KromoraKitTests.ResolutionPlannerTests/testCommittedGeometryDeepZoomUsesAConservativeNativeROI
[1326/1487] Testing KromoraKitTests.ResolutionPlannerTests/testFitDetailIsDiscreteAndHysteresisBoundsResizeTransitions
[1327/1487] Testing KromoraKitTests.ResolutionPlannerTests/testCommittedStraightenPresentationExtentUsesGeometryAABB
[1328/1487] Testing KromoraKitTests.ResolutionPlannerTests/testPanelBackingPixelsAndZoomDriveThePlanWithoutExceedingNativeBounds
[1329/1487] Testing KromoraKitTests.ResolutionPlannerTests/testQuarterCropRequestsNativeDetailWhenItWouldOtherwiseUpscale
[1330/1487] Testing KromoraKitTests.ResolutionPlannerTests/testThumbnailScalePreservesChangingCropAspectRatio
[1331/1487] Testing KromoraKitTests.ResolutionPlannerTests/testThumbnailScalePlansDetailForTheCroppedOutput
[1332/1487] Testing KromoraKitTests.ResolutionPlannerTests/testVerticalPanRequestsTheMatchingCoreImageSourceStrip
[1333/1487] Testing KromoraKitTests.ResolutionPlannerTests/testZoomInThenFitReturnsToFreshCompletePhotoPlanAndCacheIdentity
[1334/1487] Testing KromoraKitTests.RetouchModelTests/testLegacyDocumentDefaultsRetouchAndNewerVersionIsRejected
[1335/1487] Testing KromoraKitTests.RetouchModelTests/testLegacyRemoveSpotsMigrateToHealWhenDecoded
[1336/1487] Testing KromoraKitTests.RetouchModelTests/testNewRecipeDecodeIsTolerantAndIgnoresV1SpotFields
[1337/1487] Testing KromoraKitTests.RetouchDustDetectorTests/testThresholdFiltersWeakResponsesAndResultsAreDeterministic
[1338/1487] Testing KromoraKitTests.RetouchModelTests/testNewRetouchSpotsDefaultToHeal
[1339/1487] Testing KromoraKitTests.RetouchModelTests/testRetouchAffectsIdentityButComparisonRemovesItAndAutoKeepsIt
[1340/1487] Testing KromoraKitTests.RetouchModelTests/testSettingsRoundTripAndIdentitySemantics
[1341/1487] Testing KromoraKitTests.RetouchModelTests/testSpotWorkBoundsStayConstantForTheSamePixelRadiusAtHigherResolution
[1342/1487] Testing KromoraKitTests.RetouchModelTests/testSpotWorkBoundsStayLocalAtLargeSourceSizes
[1343/1487] Testing KromoraKitTests.ResettableInspectorTests/testRepresentativeRowsResetToTheirNeutralValues
[1344/1487] Testing KromoraKitTests.ResettableInspectorTests/testInspectorSectionResetDoesNotCrossStageBoundariesAndIsUndoable
[1345/1487] Testing KromoraKitTests.RetouchQualityEvaluationTests/testSyntheticFixtureGenerationIsRepeatable
[1346/1487] Testing KromoraKitTests.ResettableInspectorTests/testResetEndsAnActiveSliderGroupBeforeRecordingItsOwnUndoEntry
[1347/1487] Testing KromoraKitTests.ResettableInspectorTests/testResetPhotoClearsEveryStageAsOneUndoableOperation
[1348/1487] Testing KromoraKitTests.RetouchSourcePickerTests/testCandidatesAreDeterministicAndDoNotOverlapDestinationOrOtherSpots
[1349/1487] Testing KromoraKitTests.ResolutionPlannerTests/testAppViewModelDoesNotShareHysteresisBetweenRenderingSurfaces
[1350/1487] Testing KromoraKitTests.RetouchSourcePickerTests/testManualSourceIsAuthoritativeWhenAdvancingAutomaticRank
[1351/1487] Testing KromoraKitTests.RetouchSourcePickerTests/testFullResolutionRefinementIsStableAndBoundedToTwoPixels
[1352/1487] Testing KromoraKitTests.RetouchSourcePickerTests/testProxyConvertsRGBAIntoLabValues
[1353/1487] Testing KromoraKitTests.RetouchSourcePickerTests/testRankAdvancesToNextDeterministicSource
[1354/1487] Testing KromoraKitTests.RetouchWorkflowCoordinatorTests/testAcceptOneAcceptAllDismissAndDragSuggestion
[1355/1487] Testing KromoraKitTests.RetouchWorkflowCoordinatorTests/testClickAndDragCommitOneSpotEach
[1356/1487] Testing KromoraKitTests.RetouchWorkflowCoordinatorTests/testAutomaticSourcePickGroupsWithGestureCommitForOneUndoEntry
[1357/1487] Testing KromoraKitTests.RetouchSourcePickerTests/testTypicalProxySelectionLatencyDiagnostic
[1358/1487] Testing KromoraKitTests.RetouchDustDetectorTests/testDetectionRestrictionsAndPrecisionRecallReport
[1359/1487] Testing KromoraKitTests.RetouchDustDetectorTests/testSmoothRegionGateSuppressesFoliageCandidates
[1360/1487] Testing KromoraKitTests.RetouchWorkflowCoordinatorTests/testMovingDestinationKeepsManualSourceAtAbsolutePoint
[1361/1487] Testing KromoraKitTests.RetouchWorkflowCoordinatorTests/testSourceHandleSwitchesToManualAndDeleteRemovesSpot
[1362/1487] Testing KromoraKitTests.RetouchWorkflowCoordinatorTests/testClickingCanvasSuggestionAcceptsIt
[1363/1487] Testing KromoraKitTests.RetouchWorkflowCoordinatorTests/testShiftClickChainsSegmentAndDestinationMoveCommitsOnce
[1364/1487] Testing KromoraKitTests.RetouchQualityEvaluationTests/testHandBuiltTextureSynthesisCanRepairStraightWireOnEveryBackground
[1365/1487] Testing KromoraKitTests.RevisionLedgerTests/testActiveMaskFenceSurvivesRecipeAndSourceEviction
[1366/1487] Testing KromoraKitTests.RevisionLedgerTests/testActiveRenderFenceSurvivesSourceEvictionAndLaterSupersession
[1367/1487] Testing KromoraKitTests.RevisionLedgerTests/testClearMaskRequestStateLeavesRenderRevisionsIntact
[1368/1487] Testing KromoraKitTests.RevisionLedgerTests/testIsCurrentRenderRequestRejectsALaggingRevisionAfterANewerOneIsNoted
[1369/1487] Testing KromoraKitTests.RevisionLedgerTests/testRecipeChangeReportsTrueOnceAndClearsThePreviousRecipesDocumentKeys
[1370/1487] Testing KromoraKitTests.RevisionLedgerTests/testRemoveAllClearsRenderAndMaskState
[1371/1487] Testing KromoraKitTests.RevisionLedgerTests/testOverlayMaskRecencyQueueStaysBoundedWhenRecipeAndOverlayRecencyDiverge
[1372/1487] Testing KromoraKitTests.RevisionLedgerTests/testMaskRequestRevisionsEvictOldestDocumentKeyFirstRegardlessOfRevisionValue
[1373/1487] Testing KromoraKitTests.SceneCharacteristicsAnalyzerTests/testHighKeySceneIsHighKeyAndLowKeySceneIsLowKey
[1374/1487] Testing KromoraKitTests.RevisionLedgerTests/testRenderRevisionsAreBoundedAndEvictLeastRecentlyTouchedSourceFirst
[1375/1487] Testing KromoraKitTests.SceneCharacteristicsAnalyzerTests/testBacklightUsesSemanticPersonWhenSaliencyIncludesBrightBackground
[1376/1487] Testing KromoraKitTests.SceneCharacteristicsAnalyzerTests/testBacklitSceneIsDetectedFromSubjectBackgroundEvidence
[1377/1487] Testing KromoraKitTests.SceneCharacteristicsAnalyzerTests/testNormalDaylightIsMidKeyWithoutStrongSceneLikelihood
[1378/1487] Testing KromoraKitTests.SceneCharacteristicsAnalyzerTests/testSceneFactsAreBoundedAndPhotoAnalysisRoundTripsThem
[1379/1487] Testing KromoraKitTests.SceneEvidenceTests/testFailedMasksAndMixedColorReduceOnlyTheirOwnTerms
[1380/1487] Testing KromoraKitTests.SceneEvidenceTests/testContradictedLabelsReduceConfidenceWithoutOverridingMeasurement
[1381/1487] Testing KromoraKitTests.SceneEvidenceTests/testFullSignalsReportHighOverallAndPerProviderEvidence
[1382/1487] Testing KromoraKitTests.SceneEvidenceTests/testLegacyAnalysisJSONDecodesWithDerivedConfidenceAndSameVersion
[1383/1487] Testing KromoraKitTests.SceneEvidenceTests/testMeasurementBridgeDerivesSceneFromRenderedFacts
[1384/1487] Testing KromoraKitTests.SceneEvidenceTests/testMeasurementBridgeCarriesMixedLightEvidence
[1385/1487] Testing KromoraKitTests.SceneEvidenceTests/testLegacySceneJSONDecodesToNeutralDefaults
[1386/1487] Testing KromoraKitTests.SceneEvidenceTests/testMatchingLabelsBoostEvidenceAndUnrelatedLabelsDoNot
[1387/1487] Testing KromoraKitTests.SceneEvidenceTests/testMissingSignalsReduceOverallWithoutErasingUsableMeasurements
[1388/1487] Testing KromoraKitTests.SceneEvidenceTests/testMissingLabelsAndRegionsDegradeConfidenceWithoutInvalidatingGlobals
[1389/1487] Testing KromoraKitTests.SceneEvidenceTests/testNightFixtureProducesNightEvidenceWithoutAPreset
[1390/1487] Testing KromoraKitTests.SceneEvidenceTests/testOrdinaryDaylightIsPositiveEvidenceNotAResidual
[1391/1487] Testing KromoraKitTests.SceneEvidenceTests/testMonochromeRespondsToColorlessnessNotTone
[1392/1487] Testing KromoraKitTests.SceneEvidenceTests/testMixedLightRequiresHueEvidenceAndIsNeverInvented
[1393/1487] Testing KromoraKitTests.SceneEvidenceTests/testSnowFixtureIsSnowyAndFogFixtureIsFoggy
[1394/1487] Testing KromoraKitTests.SceneEvidenceTests/testStubClassifierUnavailableKeepsAnalysisUsable
[1395/1487] Testing KromoraKitTests.SceneEvidenceTests/testStoredLabelsKeepSceneReproducibleFromPersistedFacts
[1396/1487] Testing KromoraKitTests.SceneEvidenceTests/testSunsetWarmFixtureRespondsToWarmthAndCoolFrameDoesNot
[1397/1487] Testing KromoraKitTests.SliderFillTests/testABipolarControlAtItsNeutralFillsNothing
[1398/1487] Testing KromoraKitTests.SliderFillTests/testAControlWhoseNeutralIsNotZeroAnchorsOnItsNeutral
[1399/1487] Testing KromoraKitTests.SliderFillTests/testAControlWhoseNeutralIsItsMaximumFillsOnlyLeftwards
[1400/1487] Testing KromoraKitTests.SliderFillTests/testADegenerateRangeDrawsNothing
[1401/1487] Testing KromoraKitTests.SliderFillTests/testANegativeValueFillsFromTheThumbUpToNeutral
[1402/1487] Testing KromoraKitTests.SliderFillTests/testAPositiveValueFillsFromNeutralUpToTheThumb
[1403/1487] Testing KromoraKitTests.SliderFillTests/testAUnipolarControlWithANonZeroFloorStillFillsFromTheLeftEdge
[1404/1487] Testing KromoraKitTests.SliderFillTests/testAUnipolarControlAtItsFloorFillsNothing
[1405/1487] Testing KromoraKitTests.SliderFillTests/testAUnipolarControlFillsFromTheLeftEdge
[1406/1487] Testing KromoraKitTests.SliderFillTests/testEveryDeclaredNeutralIsTheValueItsModelDefaultsTo
[1407/1487] Testing KromoraKitTests.SliderFillTests/testLocalTemperatureIsCentredOnItsAsShotNeutral
[1408/1487] Testing KromoraKitTests.SliderFillTests/testNonFiniteInputDrawsNothing
[1409/1487] Testing KromoraKitTests.SliderFillTests/testTheBlendingRowIsCentredDespiteItsUnsignedRange
[1410/1487] Testing KromoraKitTests.SliderFillTests/testOutOfRangeValuesClampRatherThanOverflowTheTrack
[1411/1487] Testing KromoraKitTests.SliderFillTests/testTheFillNeverStraddlesTheNeutral
[1412/1487] Testing KromoraKitTests.SliderFillTests/testTheTemperatureBaselineSurvivesTheSliderReflection
[1413/1487] Testing KromoraKitTests.SmartMaskTests/testForegroundDefinitionIsDurableAndCarriesAllSmartSettings
[1414/1487] Testing KromoraKitTests.SmartMaskTests/testIncompatibleGenerationVersionLeavesDefinitionRecoverable
[1415/1487] Testing KromoraKitTests.SmartMaskTests/testMissingCacheRegeneratesThroughCoordinatorResolver
[1416/1487] Testing KromoraKitTests.SmartMaskTests/testForegroundAndBackgroundRequestsShareOneSegmentationTask
[1417/1487] Testing KromoraKitTests.SmartMaskTests/testRenderQualityUpgradesPreviewSeedAndNeverPublishesAnotherAsset
[1418/1487] Testing KromoraKitTests.SourceSessionCoordinatorTests/testNavigationDropsStalePreparationPublication
[1419/1487] Testing KromoraKitTests.SmartMaskTests/testWrongAssetResultIsRejected
[1420/1487] Testing KromoraKitTests.SourceSessionCoordinatorTests/testFailedOpenKeepsPublishedSourceProbesAlive
[1421/1487] Testing KromoraKitTests.SourceSessionCoordinatorTests/testPreviewPresentationOwnsGenerations
[1422/1487] Testing KromoraKitTests.SourceSessionCoordinatorTests/testSuccessfulOpenSupersedesThePreviousProbe
[1423/1487] Testing KromoraKitTests.StoredEditAdoptionTests/testStoredEditsReachThePanelWhileSourcePreparationIsStillPending
[1424/1487] Testing KromoraKitTests.SwiftDataConcurrencyGateTests/testModelAndModelActorAreSwift6ConcurrencySafe
[1425/1487] Testing KromoraKitTests.StoredEditAdoptionTests/testTheFirstRenderUsesTheStoredDocumentSoNoCorrectiveRenderFollows
[1426/1487] Testing KromoraKitTests.SyntheticLibraryGeneratorTests/testCancellationRemovesPartialLibrary
[1427/1487] Testing KromoraKitTests.StoredEditAdoptionTests/testASupersededSelectionNeverPublishesTheOldPhotosStoredValues
[1428/1487] Testing KromoraKitTests.StoredEditAdoptionTests/testPhotoSwitchMarksSliderPresentationPendingUntilIncomingDocumentArrives
[1429/1487] Testing KromoraKitTests.StoredEditAdoptionTests/testSettledPhotoWarmsItsBrowsingNeighboursWithoutCreatingTheirSessions
[1430/1487] Testing KromoraKitTests.TemperatureSliderMappingTests/testColorReadoutsRoundGlobalTemperatureAndTintWithoutChangingTheValues
[1431/1487] Testing KromoraKitTests.TemperatureSliderMappingTests/testMappingIsMonotonicAndContinuousAtThePracticalBoundary
[1432/1487] Testing KromoraKitTests.TemperatureSliderMappingTests/testRAWMappingUsesTheUsefulRangeForHalfTheTrack
[1433/1487] Testing KromoraKitTests.TemperatureSliderMappingTests/testRepresentativeKelvinValuesRoundTripExactlyEnoughForEditing
[1434/1487] Testing KromoraKitTests.TemperatureSliderMappingTests/testStandardImageRangeSharesTheMappingWithoutChangingItsUpperBound
[1435/1487] Testing KromoraKitTests.ThumbnailFrameStoreTests/testPlaceholderWritesAreSkippedForBothKindsAndLegacyRecordsAreSwept
[1436/1487] Testing KromoraKitTests.ThumbnailFrameStoreTests/testReadWindowIsVisibleIDsPlusAtMostOnePrefetchPage
[1437/1487] Testing KromoraKitTests.ThumbnailFrameStoreTests/testStableKeysReplaceTheLiveEditedRecordAndSurviveRelaunch
[1438/1487] Testing KromoraKitTests.SyntheticLibraryGeneratorTests/testGeneratedAssetsCarryVariedMetadataEditsAndThumbnailDemand
[1439/1487] Testing KromoraKitTests.SingleViewLatencyBenchmark/testOptInRealEngineSingleViewLatencyBaseline
[1440/1487] Testing KromoraKitTests.SceneEvidenceTests/testVisionAdapterReturnsMissingEvidenceForUndecodableSource
[1441/1487] Testing KromoraKitTests.SingleViewLatencyBenchmark/testSingleViewOpenBaselineReportsIdentityEditedAndMaskedShapes
[1442/1487] Testing KromoraKitTests.SyntheticLibraryGeneratorTests/testWithLibraryCleansUpAfterTheOperation
[1443/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testComparisonRequestsShareFitGeometryAcrossThumbnailDrivenOrientations
[1444/1487] Testing KromoraKitTests.SyntheticLibraryGeneratorTests/testSameScaleAndSeedProducesIdenticalValuesAndFileLayout
[1445/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testDebouncedEditBurstCoalescesToOneTrailingThumbnail
[1446/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testEditAndLUTFolderScanRefreshBothUpdateTheMaterializedEditedThumbnail
[1447/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testDelayedAutoCompletionCannotMakeTheNextThumbnailReady
[1448/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testDelayedThumbnailCompletionCannotPublishAnObsoleteDocument
[1449/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testEditedThumbnailSkipsPreviewInteractionAndRunsOnceAfterItEnds
[1450/1487] Testing KromoraKitTests.LibraryQueryControllerTests/testGeneratedPackageQueriesAtOneAndTenThousandNeverOpenAssetRecordCanaries
[1451/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testFailedSourceAndFailedHistogramLeaveTerminalStates
[1452/1487] Testing KromoraKitTests.PortablePackageEndToEndRegressionTests/testSyntheticLibraryImportEditLookAndRelocationPreserveIdentityWithoutRelink
[1453/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testExtremeCropUsesNativeDetailWithoutAnUnboundedThumbnailBurst
[1454/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testFilmstripSelectionKeepsOriginalComparisonInSync
[1455/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testEditedThumbnailUsesCurrentDocumentAndIsSharedByBrowsingSurfaces
[1456/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testFilmstripSelectionPresentsRepeatedSelectionAndSettlesHistogram
[1457/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testFilmstripSelectionSchedulesOriginalBeforeAdjustedDrawableConfirmation
[1458/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testLibraryGridHandoffPresentsTheSelectedPhotoWithoutTabSwitching
[1459/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testRapidThumbnailChangesCannotPublishAnObsoleteSourceOrHistogram
[1460/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testSelectionPresentsItsEditedThumbnailBeforeItsOriginal
[1461/1487] Testing KromoraKitTests.RenderRequestTests/testClarityFullRangeKeepsInteractiveSettledAndExportFramesAligned
[1462/1487] Testing KromoraKitTests.WhiteBalancePresetTests/testGreenSampleProducesMagentaCorrection
[1463/1487] Testing KromoraKitTests.WhiteBalancePresetTests/testNeutralSampleCentersAndWarmAndCoolSamplesMoveOppositeWays
[1464/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testToolbarPhotoAvailabilityStaysSettledDuringSlowPhotoNavigation
[1465/1487] Testing KromoraKitTests.WhiteBalancePresetTests/testPresetTargetsCoverPhotographicSourcesAndCustomLeavesValuesEditable
[1466/1487] Testing KromoraKitTests.WhiteBalancePresetTests/testWhiteBalanceValuesRoundTripInBothDocumentStoragePaths
[1467/1487] Testing KromoraKitTests.ThumbnailSwitchLifecycleTests/testSequentialOpenPresentsReplacementWithoutAnotherUserAction
[1468/1487] Testing KromoraKitTests.WarmReopenPresentationTests/testCorruptStoredFrameIsAMissAndIsReplaced
[1469/1487] Testing KromoraKitTests.WarmReopenPresentationTests/testDeletingEveryStoredFrameCostsARenderNotCorrectness
[1470/1487] Testing KromoraKitTests.WarmReopenPresentationTests/testReplacedSourceNeverShowsTheStoredFrame
[1471/1487] Testing KromoraKitTests.WarmReopenPresentationTests/testStaleEditFrameRendersOnceBeforeAnyExactClaim
[1472/1487] Testing KromoraKitTests.WarmReopenPresentationTests/testExactWarmReopenRendersNothingAndAdmitsHistogramOnce
[1473/1487] Testing KromoraKitTests.WarmReopenPresentationTests/testPixelEpochBumpShowsTheFrameThenRendersOnceAndRewrites
[1474/1487] Testing KromoraKitTests.WorkspaceNavigationTests/testLaunchDestinationIsLibraryForAnEmptyLibrary
[1475/1487] Testing KromoraKitTests.WorkspaceNavigationTests/testAStalePreparationCannotReplaceTheNewlyActiveLibrarySelection
[1476/1487] Testing KromoraKitTests.WorkspaceNavigationTests/testEditOpensTheFirstPhotoOnlyWhenThatSettingIsOn
[1477/1487] Testing KromoraKitTests.WorkspaceNavigationTests/testGridAndEditNavigationRejectsAnUnavailableCollection
[1478/1487] Testing KromoraKitTests.WorkspaceNavigationTests/testGridSelectionHandsTheActivePhotoToEdit
[1479/1487] Testing KromoraKitTests.WarmReopenPresentationTests/testZoomedFramesNeverWriteTheStore
[1480/1487] Testing KromoraKitTests.WorkspaceNavigationTests/testLaunchDestinationIsLibraryWhenThePackageHasPhotos
[1481/1487] Testing KromoraKitTests.WorkspaceNavigationTests/testReturningToLibraryClosesInspectorBeforeSwitchingWorkspace
[1482/1487] Testing KromoraKitTests.WorkspaceNavigationTests/testSourceToolbarActionLeavesGridAndRevealsTheEditorSidebar
[1483/1487] Testing KromoraKitTests.WorkspaceNavigationTests/testLibraryDoubleClickOpensInspectorAndClosesSourceBrowser
[1484/1487] Testing KromoraKitTests.WorkspaceNavigationTests/testReturningToEditReusesPreparedSourceButRepublishesMissingPreview
[1485/1487] Testing KromoraKitTests.WorkspaceNavigationTests/testReturningToEditKeepsTheWholeSelectionAndUsesTheActiveID
[1486/1487] Testing KromoraKitTests.SyntheticLibraryGeneratorTests/testSupportedFastScalesGenerateExpectedFileCountsAndTearDown
[1487/1487] Testing KromoraKitTests.RetouchQualityEvaluationTests/testGroundTruthGateReportsCurrentHealAndCloneResults passed (1,487 tests); CI lane coverage: total=2002 required_fast=1487 required_serial=464 optional=51
Required lanes are disjoint; optional tests are intentionally excluded from the required gate.
CI_TEST_LANE=render-ui-serial
Focused rerun: swift test --no-parallel --filter '(AnalysisDebugPanelTests|BundledLookTests|ColorGradingTests|ColorMixerTests|ColorPipelineTests|CollectionProjectionPerformanceTests|CropPipelineTests|EffectsPipelineTests|HistogramTests|IdentityRegressionGateTests|ImageLoadingTests|InfoSemanticMaskRenderingTests|InspectorScrollCrashPathTests|KeyMonitorTests|LocalMaskRenderingTests|LookInspectorViewTests|LookLUTExportTests|LookPreviewTests|KromoraWindowAppearanceControllerTests|MenuCommandTests|MetalKernelParityTests|NeutralOriginSliderTests|PersonSignalWarmingTests|PhotoIntelligenceRealCorpusTests|PhotosDeliveryTests|PhotosImportTests|PreviewCutoverTests|PreviewSurfaceTests|RelaunchParityTests|RenderCacheTests|RenderEngineInteractivePrecisionTests|RenderEngineTests|RenderPipelineTests|RenderStackTests|ThumbnailTests|VisionSemanticMaskProviderTests|WorkingSpaceTests|ThumbnailSwitchLifecycleTests/testFilmstripAndGridPublishCropAwareSettledThumbnails)' --skip '(ConcurrentExportEditingBenchmark|StoredEditAdoptionBenchmark|DeriveInvarianceTests|LibraryScanPerformanceTests|LibraryFolderBaselinePerformanceTests|LibraryScaleRegressionPerformanceTests|SyntheticLibraryGeneratorPerformanceTests|PackedThumbnailPerformanceTests|MaskResamplingPerformanceTests|MetalPresentationBenchmark|PhotoAnalysisPerformanceTests|PhotosImportPerformanceTests|PreviewCostBenchmark|TracingOverheadBenchmark|AutoPerformanceDiagnosticsTests/testAutoEndToEndBenchmark|LocalMaskRenderingTests/testSemanticPreviewMaskWorkingResolutionBenchmark|PreviewCoordinatorTests/testLargePreviewInteractiveLatencyBenchmark|RAWCapabilitiesTests/(testProbingARealRAWReportsItsDecodersFlags|testProbingARealRAWReportsItsDecodersSeeds|testEveryPerImageSeedLandsStrictlyInsideItsSliderRange|testWritingTheAsShotValuesMatchesLeavingThemUnset|testAValueWrittenToAnUnsupportedAdjustmentChangesNothing|testRaisingNeutralTemperatureWarmsTheImage)|RAWDevelopSettingsTests/(testApplyPushesEverySupportedKnobOntoARealFilter|testApplyingNeutralChangesNothingOnARealFilter)|ImageLoadingTests/testLoadingARAWGoesThroughCIRAWFilter|ImageSourceTests/testRAWBytesAreDetectedWithoutAFilename|DevelopInspectorTests/(testARAWStaysOnProbingUntilTheProbeAnswers|testAsShotRestoresTheActualRAWDecoderSeed)|RenderCacheTests/testAboveBudgetRAWSessionDoesNotMaterializeOnEveryEdit|RenderPipelineTests/(testRAWDevelopAndScaleReachTheDecoder|testNeutralRAWMatchesTheExistingNeutralBaseline)|RenderEngineTests/(testCompletedRAWPreviewReflectsDevelopSettings|testInteractiveSessionDoesNotLeakSettingsAcrossTicks|testInteractiveRAWDownstreamEditsReuseTheCompletedOutput)|PreviewCutoverTests/testRAWDevelopReachesThePreview)'
Test Suite 'Selected tests' started at 2026-10-02 19:33:30.001.
Test Suite 'KromoraKitTests.xctest' started at 2026-10-02 19:33:30.002.
Test Suite 'AnalysisDebugPanelTests' started at 2026-10-02 19:33:30.002.
Test Case '-[KromoraKitTests.AnalysisDebugPanelTests testAnalysisMaskOverlayIdentityCropMatchesFittedPhotoFrame]' started.
Test Case '-[KromoraKitTests.AnalysisDebugPanelTests testAnalysisMaskOverlayIdentityCropMatchesFittedPhotoFrame]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.AnalysisDebugPanelTests testAnalysisMaskOverlayLayoutMapsNonOriginCropAndFitsItsAspectRatio]' started.
Test Case '-[KromoraKitTests.AnalysisDebugPanelTests testAnalysisMaskOverlayLayoutMapsNonOriginCropAndFitsItsAspectRatio]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.AnalysisDebugPanelTests testModelLoadsMasksMapsProviderErrorsAndControlsOverlayVisibility]' started.
Test Case '-[KromoraKitTests.AnalysisDebugPanelTests testModelLoadsMasksMapsProviderErrorsAndControlsOverlayVisibility]' passed (0.006 seconds).
Test Suite 'AnalysisDebugPanelTests' passed at 2026-10-02 19:33:30.009.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.007 (0.007) seconds
Test Suite 'BundledLookTests' started at 2026-10-02 19:33:30.009.
Test Case '-[KromoraKitTests.BundledLookTests testApplicationLibrarySeparatesStarterLooksFromUserLooks]' started.
Test Case '-[KromoraKitTests.BundledLookTests testApplicationLibrarySeparatesStarterLooksFromUserLooks]' passed (0.021 seconds).
Test Case '-[KromoraKitTests.BundledLookTests testBundledLooksHaveDistinctPreviewFingerprints]' started.
Test Case '-[KromoraKitTests.BundledLookTests testBundledLooksHaveDistinctPreviewFingerprints]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.BundledLookTests testEveryBundledLookCanApplyWithoutMutatingTheInput]' started.
Test Case '-[KromoraKitTests.BundledLookTests testEveryBundledLookCanApplyWithoutMutatingTheInput]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.BundledLookTests testLookCollectionsHaveDeterministicFlatOrderingAcrossCategories]' started.
Test Case '-[KromoraKitTests.BundledLookTests testLookCollectionsHaveDeterministicFlatOrderingAcrossCategories]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.BundledLookTests testMalformedBundledEntryIsSkippedWithoutHidingHealthyEntries]' started.
Test Case '-[KromoraKitTests.BundledLookTests testMalformedBundledEntryIsSkippedWithoutHidingHealthyEntries]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.BundledLookTests testManifestContainsApprovedProvenanceForEveryBundledLook]' started.
Test Case '-[KromoraKitTests.BundledLookTests testManifestContainsApprovedProvenanceForEveryBundledLook]' passed (0.005 seconds).
Test Suite 'BundledLookTests' passed at 2026-10-02 19:33:30.060.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.051 (0.051) seconds
Test Suite 'CollectionProjectionPerformanceTests' started at 2026-10-02 19:33:30.060.
Test Case '-[KromoraKitTests.CollectionProjectionPerformanceTests testFilterRevisionRebuildsTheProjectionWithoutChangingItemIdentityOrder]' started.
Test Case '-[KromoraKitTests.CollectionProjectionPerformanceTests testFilterRevisionRebuildsTheProjectionWithoutChangingItemIdentityOrder]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.CollectionProjectionPerformanceTests testProjectionCacheIsStableFor1KAnd10KLibraries]' started.
Test Case '-[KromoraKitTests.CollectionProjectionPerformanceTests testProjectionCacheIsStableFor1KAnd10KLibraries]' passed (0.314 seconds).
Test Case '-[KromoraKitTests.CollectionProjectionPerformanceTests testThumbnailPublishesOnlyFromTheChangedItemAndKeepsProjectionCache]' started.
Test Case '-[KromoraKitTests.CollectionProjectionPerformanceTests testThumbnailPublishesOnlyFromTheChangedItemAndKeepsProjectionCache]' passed (0.001 seconds).
Test Suite 'CollectionProjectionPerformanceTests' passed at 2026-10-02 19:33:30.376.
	 Executed 3 tests, with 0 failures (0 unexpected) in 0.316 (0.316) seconds
Test Suite 'ColorGradingTests' started at 2026-10-02 19:33:30.376.
Test Case '-[KromoraKitTests.ColorGradingTests testBlendingAndBalanceHaveIndependentMonotonicEffects]' started.
Test Case '-[KromoraKitTests.ColorGradingTests testBlendingAndBalanceHaveIndependentMonotonicEffects]' passed (0.035 seconds).
Test Case '-[KromoraKitTests.ColorGradingTests testEachWheelPredominantlyAffectsItsTonalRegion]' started.
Test Case '-[KromoraKitTests.ColorGradingTests testEachWheelPredominantlyAffectsItsTonalRegion]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.ColorGradingTests testGradingReachesSharedGraph]' started.
Test Case '-[KromoraKitTests.ColorGradingTests testGradingReachesSharedGraph]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.ColorGradingTests testMissingGradingMigratesToNeutral]' started.
Test Case '-[KromoraKitTests.ColorGradingTests testMissingGradingMigratesToNeutral]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.ColorGradingTests testModelRoundTripsDefaultsAndClamps]' started.
Test Case '-[KromoraKitTests.ColorGradingTests testModelRoundTripsDefaultsAndClamps]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.ColorGradingTests testSmoothGrayscaleGradientHasNoVisibleDiscontinuity]' started.
Test Case '-[KromoraKitTests.ColorGradingTests testSmoothGrayscaleGradientHasNoVisibleDiscontinuity]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ColorGradingTests testWheelMappingReachesNeutralRimAndEveryCardinalHue]' started.
Test Case '-[KromoraKitTests.ColorGradingTests testWheelMappingReachesNeutralRimAndEveryCardinalHue]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.ColorGradingTests testWheelMappingRoundTripsStoredValuesAndAccessibilityAdjustments]' started.
Test Case '-[KromoraKitTests.ColorGradingTests testWheelMappingRoundTripsStoredValuesAndAccessibilityAdjustments]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.ColorGradingTests testZeroSaturationAcrossWheelsIsExactIdentityRegardlessOfHue]' started.
Test Case '-[KromoraKitTests.ColorGradingTests testZeroSaturationAcrossWheelsIsExactIdentityRegardlessOfHue]' passed (0.001 seconds).
Test Suite 'ColorGradingTests' passed at 2026-10-02 19:33:30.420.
	 Executed 9 tests, with 0 failures (0 unexpected) in 0.044 (0.044) seconds
Test Suite 'ColorMixerTests' started at 2026-10-02 19:33:30.420.
Test Case '-[KromoraKitTests.ColorMixerTests testEachChannelPrimarilyAffectsItsHueNeighborhood]' started.
Test Case '-[KromoraKitTests.ColorMixerTests testEachChannelPrimarilyAffectsItsHueNeighborhood]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.ColorMixerTests testMixerChangesReachSharedGraphAndAreDeterministic]' started.
Test Case '-[KromoraKitTests.ColorMixerTests testMixerChangesReachSharedGraphAndAreDeterministic]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.ColorMixerTests testMixerKeepsPremultipliedColorCorrectForTransparentPixels]' started.
Test Case '-[KromoraKitTests.ColorMixerTests testMixerKeepsPremultipliedColorCorrectForTransparentPixels]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ColorMixerTests testMixerStateIsIncludedInUndoSnapshots]' started.
Test Case '-[KromoraKitTests.ColorMixerTests testMixerStateIsIncludedInUndoSnapshots]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.ColorMixerTests testMixerStateRoundTripsAndMissingMixerMigratesToNeutral]' started.
Test Case '-[KromoraKitTests.ColorMixerTests testMixerStateRoundTripsAndMissingMixerMigratesToNeutral]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ColorMixerTests testModelHasEightFixedChannelsAndPhotographerRanges]' started.
Test Case '-[KromoraKitTests.ColorMixerTests testModelHasEightFixedChannelsAndPhotographerRanges]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.ColorMixerTests testNeutralMixerIsExactIdentityAndPreservesAlpha]' started.
Test Case '-[KromoraKitTests.ColorMixerTests testNeutralMixerIsExactIdentityAndPreservesAlpha]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ColorMixerTests testRedWraparoundIsContinuousAndOverlapIsSmooth]' started.
Test Case '-[KromoraKitTests.ColorMixerTests testRedWraparoundIsContinuousAndOverlapIsSmooth]' passed (0.001 seconds).
Test Suite 'ColorMixerTests' passed at 2026-10-02 19:33:30.434.
	 Executed 8 tests, with 0 failures (0 unexpected) in 0.014 (0.014) seconds
Test Suite 'ColorPipelineTests' started at 2026-10-02 19:33:30.434.
Test Case '-[KromoraKitTests.ColorPipelineTests testColorExtremesRemainFiniteAndBounded]' started.
Test Case '-[KromoraKitTests.ColorPipelineTests testColorExtremesRemainFiniteAndBounded]' passed (0.009 seconds).
Test Case '-[KromoraKitTests.ColorPipelineTests testColorFiltersPreserveTransparentPixelAlpha]' started.
Test Case '-[KromoraKitTests.ColorPipelineTests testColorFiltersPreserveTransparentPixelAlpha]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.ColorPipelineTests testGlobalColorReachesTheSharedRenderGraph]' started.
Test Case '-[KromoraKitTests.ColorPipelineTests testGlobalColorReachesTheSharedRenderGraph]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.ColorPipelineTests testNeutralColorIsAnExactNoOpAndPreservesAlpha]' started.
Test Case '-[KromoraKitTests.ColorPipelineTests testNeutralColorIsAnExactNoOpAndPreservesAlpha]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ColorPipelineTests testSaturationMinus100ProducesNearMonochromeSwatches]' started.
Test Case '-[KromoraKitTests.ColorPipelineTests testSaturationMinus100ProducesNearMonochromeSwatches]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ColorPipelineTests testVibranceAndSaturationHaveDistinctBehaviorOnMixedChromaInput]' started.
Test Case '-[KromoraKitTests.ColorPipelineTests testVibranceAndSaturationHaveDistinctBehaviorOnMixedChromaInput]' passed (0.002 seconds).
Test Suite 'ColorPipelineTests' passed at 2026-10-02 19:33:30.451.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.017 (0.017) seconds
Test Suite 'CropPipelineTests' started at 2026-10-02 19:33:30.451.
Test Case '-[KromoraKitTests.CropPipelineTests testFlipAndStraightenComposeBeforeCrop]' started.
Test Case '-[KromoraKitTests.CropPipelineTests testFlipAndStraightenComposeBeforeCrop]' passed (0.014 seconds).
Test Case '-[KromoraKitTests.CropPipelineTests testNormalizedCropChangesExtentWithoutRasterizingTheGraph]' started.
Test Case '-[KromoraKitTests.CropPipelineTests testNormalizedCropChangesExtentWithoutRasterizingTheGraph]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.CropPipelineTests testPerspectivePreviewAndExportHaveTheSameComposition]' started.
Test Case '-[KromoraKitTests.CropPipelineTests testPerspectivePreviewAndExportHaveTheSameComposition]' passed (0.020 seconds).
Test Case '-[KromoraKitTests.CropPipelineTests testPresetCropPreviewAndFullResolutionExportHaveTheSameExtent]' started.
Test Case '-[KromoraKitTests.CropPipelineTests testPresetCropPreviewAndFullResolutionExportHaveTheSameExtent]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.CropPipelineTests testPreviewAndFullResolutionExportUseTheSameCropExtentAndPixels]' started.
Test Case '-[KromoraKitTests.CropPipelineTests testPreviewAndFullResolutionExportUseTheSameCropExtentAndPixels]' passed (0.014 seconds).
Test Case '-[KromoraKitTests.CropPipelineTests testStraightenCropPreviewAndExportHaveOpaqueCornerPixels]' started.
Test Case '-[KromoraKitTests.CropPipelineTests testStraightenCropPreviewAndExportHaveOpaqueCornerPixels]' passed (0.024 seconds).
Test Suite 'CropPipelineTests' passed at 2026-10-02 19:33:30.538.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.087 (0.087) seconds
Test Suite 'EffectsPipelineTests' started at 2026-10-02 19:33:30.538.
Test Case '-[KromoraKitTests.EffectsPipelineTests testClarityFullRangePreservesLargeOffsetExtentOrientationAndFinitePixels]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testClarityFullRangePreservesLargeOffsetExtentOrientationAndFinitePixels]' passed (4.506 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testClarityTargetsMidtonesAndUsesABroaderOperationThanTexture]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testClarityTargetsMidtonesAndUsesABroaderOperationThanTexture]' passed (0.014 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testDehazeChangesToneAndColourBeyondLocalDetail]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testDehazeChangesToneAndColourBeyondLocalDetail]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testDehazeFullRangePreservesOffsetExtentOrientationAndFinitePixels]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testDehazeFullRangePreservesOffsetExtentOrientationAndFinitePixels]' passed (0.365 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testEffectsPreserveExtentAndAlpha]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testEffectsPreserveExtentAndAlpha]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testEffectsUseRelativeRadiiAtPreviewScale]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testEffectsUseRelativeRadiiAtPreviewScale]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testEffectsValuesClampNonFiniteAndRoundTripInTheDocument]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testEffectsValuesClampNonFiniteAndRoundTripInTheDocument]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testGrainAmountSizeAndRoughnessAreIndependentlyMeasurable]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testGrainAmountSizeAndRoughnessAreIndependentlyMeasurable]' passed (0.014 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testGrainIsAfterTheLUTInTheFullPipeline]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testGrainIsAfterTheLUTInTheFullPipeline]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testGrainIsDeterministicAndSeedIsIndependentOfEditState]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testGrainIsDeterministicAndSeedIsIndependentOfEditState]' passed (0.014 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testGrainUsesRelativeOutputScaleAndPreservesExtentAndAlpha]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testGrainUsesRelativeOutputScaleAndPreservesExtentAndAlpha]' passed (0.021 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testGrainValuesClampAndRoundTripInTheDocument]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testGrainValuesClampAndRoundTripInTheDocument]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testNegativeEffectsProvideInverseDirections]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testNegativeEffectsProvideInverseDirections]' passed (0.022 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testNeutralEffectsAreAnExactIdentity]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testNeutralEffectsAreAnExactIdentity]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testNeutralGrainIsAnExactIdentity]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testNeutralGrainIsAnExactIdentity]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testNeutralVignetteIsAnExactIdentity]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testNeutralVignetteIsAnExactIdentity]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testTextureTargetsFineDetailMoreThanAFlatToneRamp]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testTextureTargetsFineDetailMoreThanAFlatToneRamp]' passed (0.011 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testVignetteIsAfterTheLUTInTheFullPipeline]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testVignetteIsAfterTheLUTInTheFullPipeline]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testVignettePreservesExtentAndHasIndependentControls]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testVignettePreservesExtentAndHasIndependentControls]' passed (0.017 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testVignetteUsesPostCropAspectRatioAndPreservesHighlights]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testVignetteUsesPostCropAspectRatioAndPreservesHighlights]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.EffectsPipelineTests testVignetteValuesClampAndRoundTripInTheDocument]' started.
Test Case '-[KromoraKitTests.EffectsPipelineTests testVignetteValuesClampAndRoundTripInTheDocument]' passed (0.000 seconds).
Test Suite 'EffectsPipelineTests' passed at 2026-10-02 19:33:35.566.
	 Executed 21 tests, with 0 failures (0 unexpected) in 5.027 (5.028) seconds
Test Suite 'HistogramTests' started at 2026-10-02 19:33:35.567.
Test Case '-[KromoraKitTests.HistogramTests testAnUndecodableSourceHasNoHistogram]' started.
Test Case '-[KromoraKitTests.HistogramTests testAnUndecodableSourceHasNoHistogram]' passed (0.009 seconds).
Test Case '-[KromoraKitTests.HistogramTests testNormalizationIgnoresClippingSpikes]' started.
Test Case '-[KromoraKitTests.HistogramTests testNormalizationIgnoresClippingSpikes]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.HistogramTests testPresentedFrameHistogramMatchesRebuildOnExposureAndWhiteBalanceFixtures]' started.
Test Case '-[KromoraKitTests.HistogramTests testPresentedFrameHistogramMatchesRebuildOnExposureAndWhiteBalanceFixtures]' passed (0.027 seconds).
Test Case '-[KromoraKitTests.HistogramTests testTallyCountsEveryPixelAndComputesRec709Luma]' started.
Test Case '-[KromoraKitTests.HistogramTests testTallyCountsEveryPixelAndComputesRec709Luma]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.HistogramTests testTallyHonorsBytesPerRow]' started.
Test Case '-[KromoraKitTests.HistogramTests testTallyHonorsBytesPerRow]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.HistogramTests testTallyRejectsABufferTooSmallForItsGeometry]' started.
Test Case '-[KromoraKitTests.HistogramTests testTallyRejectsABufferTooSmallForItsGeometry]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.HistogramTests testTheDocumentReachesTheHistogram]' started.
Test Case '-[KromoraKitTests.HistogramTests testTheDocumentReachesTheHistogram]' passed (0.019 seconds).
Test Case '-[KromoraKitTests.HistogramTests testTheEngineTalliesADownscaledRender]' started.
Test Case '-[KromoraKitTests.HistogramTests testTheEngineTalliesADownscaledRender]' passed (0.030 seconds).
Test Case '-[KromoraKitTests.HistogramTests testTheEngineTalliesThePresentedImageWithoutRebuildingTheSource]' started.
Test Case '-[KromoraKitTests.HistogramTests testTheEngineTalliesThePresentedImageWithoutRebuildingTheSource]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.HistogramTests testTheHistogramFollowsTheWorkingSpace]' started.
Test Case '-[KromoraKitTests.HistogramTests testTheHistogramFollowsTheWorkingSpace]' passed (0.012 seconds).
Test Suite 'HistogramTests' passed at 2026-10-02 19:33:35.674.
	 Executed 10 tests, with 0 failures (0 unexpected) in 0.107 (0.107) seconds
Test Suite 'IdentityRegressionGateTests' started at 2026-10-02 19:33:35.674.
Test Case '-[KromoraKitTests.IdentityRegressionGateTests testDistinctSourcesDoNotCollideAndDuplicateDataImportsShareIdentity]' started.
Test Case '-[KromoraKitTests.IdentityRegressionGateTests testDistinctSourcesDoNotCollideAndDuplicateDataImportsShareIdentity]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.IdentityRegressionGateTests testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore]' started.
Test Case '-[KromoraKitTests.IdentityRegressionGateTests testFullSyntheticLibraryRelocationPreservesEveryIdentityAndStore]' passed (136.535 seconds).
Test Case '-[KromoraKitTests.IdentityRegressionGateTests testPreviewCompletionForRelocatedSourceCannotPublishOverCurrentSource]' started.
Test Case '-[KromoraKitTests.IdentityRegressionGateTests testPreviewCompletionForRelocatedSourceCannotPublishOverCurrentSource]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.IdentityRegressionGateTests testStaleMaskCompletionCannotPublishRenderOrThumbnailState]' started.
Test Case '-[KromoraKitTests.IdentityRegressionGateTests testStaleMaskCompletionCannotPublishRenderOrThumbnailState]' passed (0.026 seconds).
Test Suite 'IdentityRegressionGateTests' passed at 2026-10-02 19:35:52.242.
	 Executed 4 tests, with 0 failures (0 unexpected) in 136.568 (136.568) seconds
Test Suite 'ImageLoadingTests' started at 2026-10-02 19:35:52.242.
Test Case '-[KromoraKitTests.ImageLoadingTests testExportPreservesDisplayOrientation]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testExportPreservesDisplayOrientation]' passed (0.051 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromDataAppliesOrientation]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromDataAppliesOrientation]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromDataThrowsOnGarbage]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromDataThrowsOnGarbage]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromDataThrowsOnTruncatedImage]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromDataThrowsOnTruncatedImage]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromURLAppliesOrientation]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromURLAppliesOrientation]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromURLLeavesUprightImagesAlone]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromURLLeavesUprightImagesAlone]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromURLThrowsOnMissingFile]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testLoadFromURLThrowsOnMissingFile]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testMetadataFromDataMatchesMetadataFromURL]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testMetadataFromDataMatchesMetadataFromURL]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testMetadataReportsDisplayDimensions]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testMetadataReportsDisplayDimensions]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testPreviewAndThumbnailAgreeOnOrientation]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testPreviewAndThumbnailAgreeOnOrientation]' passed (0.019 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testRawNamedGarbageFailsDecodeAndPreparation]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testRawNamedGarbageFailsDecodeAndPreparation]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testStandardPreparationReturnsOrientedGeometryWithoutDecodingPixels]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testStandardPreparationReturnsOrientedGeometryWithoutDecodingPixels]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testSupportedExtensionsCoverRAWAndStandard]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testSupportedExtensionsCoverRAWAndStandard]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.ImageLoadingTests testSupportedTypesIncludeRawAndAreUnique]' started.
Test Case '-[KromoraKitTests.ImageLoadingTests testSupportedTypesIncludeRawAndAreUnique]' passed (0.001 seconds).
Test Suite 'ImageLoadingTests' passed at 2026-10-02 19:35:52.331.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.088 (0.089) seconds
Test Suite 'InfoSemanticMaskRenderingTests' started at 2026-10-02 19:35:52.331.
Test Case '-[KromoraKitTests.InfoSemanticMaskRenderingTests testInfoSubjectAndPersonMasksChangeExpectedPixelsInPreviewAndExport]' started.
Test Case '-[KromoraKitTests.InfoSemanticMaskRenderingTests testInfoSubjectAndPersonMasksChangeExpectedPixelsInPreviewAndExport]' passed (0.056 seconds).
Test Suite 'InfoSemanticMaskRenderingTests' passed at 2026-10-02 19:35:52.387.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.056 (0.056) seconds
Test Suite 'InspectorScrollCrashPathTests' started at 2026-10-02 19:35:52.387.
Test Case '-[KromoraKitTests.InspectorScrollCrashPathTests testFitsProposedWidthClampsWideChildAndReportsStableSize]' started.
Test Case '-[KromoraKitTests.InspectorScrollCrashPathTests testFitsProposedWidthClampsWideChildAndReportsStableSize]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.InspectorScrollCrashPathTests testInspectorDisclosureToggleStormSettlesInHostedWindow]' started.
Test Case '-[KromoraKitTests.InspectorScrollCrashPathTests testInspectorDisclosureToggleStormSettlesInHostedWindow]' passed (1.290 seconds).
Test Suite 'InspectorScrollCrashPathTests' passed at 2026-10-02 19:35:53.691.
	 Executed 2 tests, with 0 failures (0 unexpected) in 1.305 (1.305) seconds
Test Suite 'KeyMonitorTests' started at 2026-10-02 19:35:53.692.
Test Case '-[KromoraKitTests.KeyMonitorTests testAMonitorIsInstalledOnInitAndRemovedByStop]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testAMonitorIsInstalledOnInitAndRemovedByStop]' passed (0.255 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime]' passed (0.223 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testArrowNavigationConsumesEventsWhenAButtonOrListHasFocus]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testArrowNavigationConsumesEventsWhenAButtonOrListHasFocus]' passed (0.249 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testArrowNavigationConsumesEventsWhenWorkspacePickerHasFocus]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testArrowNavigationConsumesEventsWhenWorkspacePickerHasFocus]' passed (0.231 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testArrowNavigationConsumesKeyDownAndKeyUpAtMiddleAndCollectionBoundaries]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testArrowNavigationConsumesKeyDownAndKeyUpAtMiddleAndCollectionBoundaries]' passed (0.228 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testArrowNavigationDefersToFocusedNativeControl]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testArrowNavigationDefersToFocusedNativeControl]' passed (0.223 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testCommandBackslashIsTheOnlyOriginalShortcut]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testCommandBackslashIsTheOnlyOriginalShortcut]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testCommandBackslashKeyDownAndKeyUpFlashOriginal]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testCommandBackslashKeyDownAndKeyUpFlashOriginal]' passed (0.220 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testCropEscapeCancelsAndReturnCommitsThroughKeyboardMonitor]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testCropEscapeCancelsAndReturnCommitsThroughKeyboardMonitor]' passed (0.223 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testCropShortcutIsPlainCOnly]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testCropShortcutIsPlainCOnly]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testDroppingAMonitorWithoutStoppingIsSafe]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testDroppingAMonitorWithoutStoppingIsSafe]' passed (0.219 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testGlobalShortcutsDeferToTextInputAndSystemModifiers]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testGlobalShortcutsDeferToTextInputAndSystemModifiers]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testImageNavigationOwnershipConsumesDownAndUpIncludingBoundaries]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testImageNavigationOwnershipConsumesDownAndUpIncludingBoundaries]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testLookNavigationOwnershipConsumesListAndButtonFocus]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testLookNavigationOwnershipConsumesListAndButtonFocus]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testPlainCommandCopyAndPasteRouteOnlyWhenGlobalSurfaceOwnsKeyboard]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testPlainCommandCopyAndPasteRouteOnlyWhenGlobalSurfaceOwnsKeyboard]' passed (1.085 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testPlainIAndOnlyPlainIWithAnOpenPhotoTogglesCaptureOverlay]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testPlainIAndOnlyPlainIWithAnOpenPhotoTogglesCaptureOverlay]' passed (0.216 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testRetouchShortcutsArmCycleOverlayAndExitInTwoSteps]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testRetouchShortcutsArmCycleOverlayAndExitInTwoSteps]' passed (0.219 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testStopIsIdempotent]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testStopIsIdempotent]' passed (0.221 seconds).
Test Case '-[KromoraKitTests.KeyMonitorTests testUnavailableOrBareBackslashDoesNotChangeOriginalState]' started.
Test Case '-[KromoraKitTests.KeyMonitorTests testUnavailableOrBareBackslashDoesNotChangeOriginalState]' passed (0.223 seconds).
Test Suite 'KeyMonitorTests' passed at 2026-10-02 19:35:57.733.
	 Executed 19 tests, with 0 failures (0 unexpected) in 4.040 (4.042) seconds
Test Suite 'KromoraWindowAppearanceControllerTests' started at 2026-10-02 19:35:57.733.
Test Case '-[KromoraKitTests.KromoraWindowAppearanceControllerTests testAQueuedWindowRefreshCannotRestoreDarkModeAfterTurningItOff]' started.
Test Case '-[KromoraKitTests.KromoraWindowAppearanceControllerTests testAQueuedWindowRefreshCannotRestoreDarkModeAfterTurningItOff]' passed (0.012 seconds).
Test Case '-[KromoraKitTests.KromoraWindowAppearanceControllerTests testPreferenceMapsToSystemOrDarkMode]' started.
Test Case '-[KromoraKitTests.KromoraWindowAppearanceControllerTests testPreferenceMapsToSystemOrDarkMode]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.KromoraWindowAppearanceControllerTests testStartedControllerAppliesAppearanceToNativeApplicationChrome]' started.
Test Case '-[KromoraKitTests.KromoraWindowAppearanceControllerTests testStartedControllerAppliesAppearanceToNativeApplicationChrome]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.KromoraWindowAppearanceControllerTests testStartedControllerUpdatesExistingWindowImmediatelyAfterPreferenceChange]' started.
Test Case '-[KromoraKitTests.KromoraWindowAppearanceControllerTests testStartedControllerUpdatesExistingWindowImmediatelyAfterPreferenceChange]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.KromoraWindowAppearanceControllerTests testWindowOverridePropagatesAndClearsForMacOSFollowingMode]' started.
Test Case '-[KromoraKitTests.KromoraWindowAppearanceControllerTests testWindowOverridePropagatesAndClearsForMacOSFollowingMode]' passed (0.005 seconds).
Test Suite 'KromoraWindowAppearanceControllerTests' passed at 2026-10-02 19:35:57.758.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.024 (0.024) seconds
Test Suite 'LocalMaskRenderingTests' started at 2026-10-02 19:35:57.758.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBrushRasterAccumulatesSeparatedStrokesWithoutFullFrameSmear]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBrushRasterAccumulatesSeparatedStrokesWithoutFullFrameSmear]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBrushRasterCacheIsBoundedByBytesAndCanBeFlushed]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBrushRasterCacheIsBoundedByBytesAndCanBeFlushed]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBrushRasterMatchesAPerPixelReferenceOverEverySample]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBrushRasterMatchesAPerPixelReferenceOverEverySample]' passed (0.163 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBrushRasterUsesTouchedTileAndPreservesNonZeroExtentCoordinates]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBrushRasterUsesTouchedTileAndPreservesNonZeroExtentCoordinates]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBrushTilesKeepTheirVerticalPositionInFramesTallerThanOneTile]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBrushTilesKeepTheirVerticalPositionInFramesTallerThanOneTile]' passed (0.009 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBuiltInResolverRendersAnalyticLinearAndRadialMasks]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testBuiltInResolverRendersAnalyticLinearAndRadialMasks]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testCappedSemanticMaskMatchesFullResolutionForSoftAndHardEdges]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testCappedSemanticMaskMatchesFullResolutionForSoftAndHardEdges]' passed (0.033 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testDeferredPreviewAdmissionFollowsTheSubsetRule]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testDeferredPreviewAdmissionFollowsTheSubsetRule]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testDeferredSemanticPassOmitsLayersThatWouldOverApply]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testDeferredSemanticPassOmitsLayersThatWouldOverApply]' passed (0.028 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testDeferredSemanticPassResolvesOnlyNonSemanticComponents]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testDeferredSemanticPassResolvesOnlyNonSemanticComponents]' passed (0.024 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testExportIgnoresTheDeferredSemanticPolicy]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testExportIgnoresTheDeferredSemanticPolicy]' passed (0.021 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testFaceSemanticRecipesAddressIndependentIndexedMattesAndLegacyFaceZero]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testFaceSemanticRecipesAddressIndependentIndexedMattesAndLegacyFaceZero]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testForegroundAndBackgroundSemanticMasksChangePixelsInPreviewAndExport]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testForegroundAndBackgroundSemanticMasksChangePixelsInPreviewAndExport]' passed (0.040 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testGlobalOnlyEditHitsTheResolvedSemanticMaskCacheWithoutCallingProviderAgain]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testGlobalOnlyEditHitsTheResolvedSemanticMaskCacheWithoutCallingProviderAgain]' passed (0.024 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testGPUCompositionPreservesOrderedOperationsInversionAndDisabledComponents]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testGPUCompositionPreservesOrderedOperationsInversionAndDisabledComponents]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testInvalidateSourceCacheClearsMaskSourceOrder]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testInvalidateSourceCacheClearsMaskSourceOrder]' passed (0.020 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testLinearColorWashUsesRenderedSmoothstepFalloffInsteadOfAFlatTint]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testLinearColorWashUsesRenderedSmoothstepFalloffInsteadOfAFlatTint]' passed (0.010 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testLongSourceNavigationKeepsRevisionLedgerBounded]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testLongSourceNavigationKeepsRevisionLedgerBounded]' passed (3.284 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskOverlayInspectsSelectedComponentWithoutApplyingItsCombineMode]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskOverlayInspectsSelectedComponentWithoutApplyingItsCombineMode]' passed (0.010 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskOverlayPreservesPartialCoverageInColorAndGrayscaleModes]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskOverlayPreservesPartialCoverageInColorAndGrayscaleModes]' passed (0.012 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskOverlayUsesResolvedAlphaAndSoloDoesNotChangeExport]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskOverlayUsesResolvedAlphaAndSoloDoesNotChangeExport]' passed (0.021 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskOverlayUsesTheSharedResolverForBrushAndSemanticLayers]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskOverlayUsesTheSharedResolverForBrushAndSemanticLayers]' passed (0.016 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskRecipeEditCancelsTheSupersededCoordinatorWaiter]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskRecipeEditCancelsTheSupersededCoordinatorWaiter]' passed (0.017 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskRequestStateEvictsOldestSourceFirst]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testMaskRequestStateEvictsOldestSourceFirst]' passed (0.057 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testNavigatingToAnotherMaskedSourceCancelsTheSupersededCoordinatorWaiter]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testNavigatingToAnotherMaskedSourceCancelsTheSupersededCoordinatorWaiter]' passed (0.017 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testOrderedLayersFeedTheNextLayerAndGlobalSliderDoesNotReResolveMasks]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testOrderedLayersFeedTheNextLayerAndGlobalSliderDoesNotReResolveMasks]' passed (0.023 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testOverlayResolveIsExemptFromRenderRevisionSupersession]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testOverlayResolveIsExemptFromRenderRevisionSupersession]' passed (0.017 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testPreviewSemanticMaskWorkingResolutionUsesFourMegapixelAndLongEdgeCaps]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testPreviewSemanticMaskWorkingResolutionUsesFourMegapixelAndLongEdgeCaps]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testProductionOverlayPathSurvivesPreviewRenders]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testProductionOverlayPathSurvivesPreviewRenders]' passed (0.396 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testRasterPayloadRGBA8MatchesPreviousRGBAfOverlayOnFeatheredFixture]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testRasterPayloadRGBA8MatchesPreviousRGBAfOverlayOnFeatheredFixture]' passed (0.009 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testRasterPayloadRowsRenderTopDownInOverlay]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testRasterPayloadRowsRenderTopDownInOverlay]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testRenderedEraseRemovesTheAdjustmentWhereItWasPaintedInAMultiTileFrame]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testRenderedEraseRemovesTheAdjustmentWhereItWasPaintedInAMultiTileFrame]' passed (0.102 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSemanticExportRejectsAnUnresolvedMaskWithAnActionableError]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSemanticExportRejectsAnUnresolvedMaskWithAnActionableError]' passed (0.009 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSemanticMaskROIKeepsFullSourceCoverageAndMatchesThumbnail]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSemanticMaskROIKeepsFullSourceCoverageAndMatchesThumbnail]' passed (0.026 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSemanticPreviewCapsWorkingResolutionButExportStaysFullResolution]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSemanticPreviewCapsWorkingResolutionButExportStaysFullResolution]' passed (0.026 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSemanticPreviewRejectsAnUnavailableMaskInsteadOfSilentlySkippingIt]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSemanticPreviewRejectsAnUnavailableMaskInsteadOfSilentlySkippingIt]' passed (0.007 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSoftMaskBlendsLocalExposureAndPreviewMatchesFullRender]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSoftMaskBlendsLocalExposureAndPreviewMatchesFullRender]' passed (0.027 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testStaleSelectedComponentFallsBackToUsableComponents]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testStaleSelectedComponentFallsBackToUsableComponents]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testStaleSoloComponentStaysStrict]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testStaleSoloComponentStaysStrict]' passed (0.009 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSupersededMaskResolutionIsRejectedBeforeItReachesTheRenderGraph]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSupersededMaskResolutionIsRejectedBeforeItReachesTheRenderGraph]' passed (0.014 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSuspendedMaskOverlayFenceSurvivesSourceEviction]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSuspendedMaskOverlayFenceSurvivesSourceEviction]' passed (0.028 seconds).
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSuspendedRenderFenceSurvivesNavigationPastRenderLedgerCapacity]' started.
Test Case '-[KromoraKitTests.LocalMaskRenderingTests testSuspendedRenderFenceSurvivesNavigationPastRenderLedgerCapacity]' passed (0.468 seconds).
Test Suite 'LocalMaskRenderingTests' passed at 2026-10-02 19:36:02.790.
	 Executed 42 tests, with 0 failures (0 unexpected) in 5.030 (5.032) seconds
Test Suite 'LookInspectorViewTests' started at 2026-10-02 19:36:02.790.
Test Case '-[KromoraKitTests.LookInspectorViewTests testEmptyStatePresentationMatrix]' started.
Test Case '-[KromoraKitTests.LookInspectorViewTests testEmptyStatePresentationMatrix]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.LookInspectorViewTests testFirstLookCopyExplainsExternalSources]' started.
Test Case '-[KromoraKitTests.LookInspectorViewTests testFirstLookCopyExplainsExternalSources]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.LookInspectorViewTests testRenderedEmptyStateMatrixAtInspectorWidths]' started.
Test Case '-[KromoraKitTests.LookInspectorViewTests testRenderedEmptyStateMatrixAtInspectorWidths]' passed (1.192 seconds).
Test Case '-[KromoraKitTests.LookInspectorViewTests testRenderedGroupedCollectionsKeepStarterAndMyLooksSeparate]' started.
Test Case '-[KromoraKitTests.LookInspectorViewTests testRenderedGroupedCollectionsKeepStarterAndMyLooksSeparate]' passed (0.259 seconds).
Test Case '-[KromoraKitTests.LookInspectorViewTests testRenderedPopulatedStateAtInspectorWidths]' started.
Test Case '-[KromoraKitTests.LookInspectorViewTests testRenderedPopulatedStateAtInspectorWidths]' passed (0.305 seconds).
Test Suite 'LookInspectorViewTests' passed at 2026-10-02 19:36:04.548.
	 Executed 5 tests, with 0 failures (0 unexpected) in 1.757 (1.757) seconds
Test Suite 'LookLUTExportTests' started at 2026-10-02 19:36:04.548.
Test Case '-[KromoraKitTests.LookLUTExportTests testApproximateConversionRequiresExplicitConfirmationBeforeWriting]' started.
Test Case '-[KromoraKitTests.LookLUTExportTests testApproximateConversionRequiresExplicitConfirmationBeforeWriting]' passed (0.552 seconds).
Test Case '-[KromoraKitTests.LookLUTExportTests testDefaultExportKeepsNonlinearLightEditWithinTolerance]' started.
Test Case '-[KromoraKitTests.LookLUTExportTests testDefaultExportKeepsNonlinearLightEditWithinTolerance]' passed (0.021 seconds).
Test Case '-[KromoraKitTests.LookLUTExportTests testDefaultExportResolutionVerifiesARepresentativeColorEdit]' started.
Test Case '-[KromoraKitTests.LookLUTExportTests testDefaultExportResolutionVerifiesARepresentativeColorEdit]' passed (0.025 seconds).
Test Case '-[KromoraKitTests.LookLUTExportTests testDefaultLatticeUsesExactNormalizedCoordinates]' started.
Test Case '-[KromoraKitTests.LookLUTExportTests testDefaultLatticeUsesExactNormalizedCoordinates]' passed (0.021 seconds).
Test Case '-[KromoraKitTests.LookLUTExportTests testGlobalLightConversionRoundTripsThroughCubeWithinTolerance]' started.
Test Case '-[KromoraKitTests.LookLUTExportTests testGlobalLightConversionRoundTripsThroughCubeWithinTolerance]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.LookLUTExportTests testIdentityConversionProducesValidDocumentedCube]' started.
Test Case '-[KromoraKitTests.LookLUTExportTests testIdentityConversionProducesValidDocumentedCube]' passed (0.010 seconds).
Test Case '-[KromoraKitTests.LookLUTExportTests testPersistentApproximationIsReturnedWithMeasuredQuality]' started.
Test Case '-[KromoraKitTests.LookLUTExportTests testPersistentApproximationIsReturnedWithMeasuredQuality]' passed (0.527 seconds).
Test Case '-[KromoraKitTests.LookLUTExportTests testSaveRejectsCollisionAndDoesNotOverwriteExistingFile]' started.
Test Case '-[KromoraKitTests.LookLUTExportTests testSaveRejectsCollisionAndDoesNotOverwriteExistingFile]' passed (0.012 seconds).
Test Case '-[KromoraKitTests.LookLUTExportTests testSavingRegistersWithoutChangingTheActiveDocument]' started.
Test Case '-[KromoraKitTests.LookLUTExportTests testSavingRegistersWithoutChangingTheActiveDocument]' passed (0.383 seconds).
Test Case '-[KromoraKitTests.LookLUTExportTests testStrongSaturationRetriesAtHighestQualityResolution]' started.
Test Case '-[KromoraKitTests.LookLUTExportTests testStrongSaturationRetriesAtHighestQualityResolution]' passed (0.529 seconds).
Test Case '-[KromoraKitTests.LookLUTExportTests testSupportMatrixIncludesVerifiedGlobalStagesAndOmitsSourceAndSpatialStages]' started.
Test Case '-[KromoraKitTests.LookLUTExportTests testSupportMatrixIncludesVerifiedGlobalStagesAndOmitsSourceAndSpatialStages]' passed (0.000 seconds).
Test Suite 'LookLUTExportTests' passed at 2026-10-02 19:36:06.640.
	 Executed 11 tests, with 0 failures (0 unexpected) in 2.092 (2.092) seconds
Test Suite 'LookPreviewTests' started at 2026-10-02 19:36:06.640.
Test Case '-[KromoraKitTests.LookPreviewTests testCancelAllCompletesQueuedPreviewAndAllowsTheSameLookToRetry]' started.
Test Case '-[KromoraKitTests.LookPreviewTests testCancelAllCompletesQueuedPreviewAndAllowsTheSameLookToRetry]' passed (0.127 seconds).
Test Case '-[KromoraKitTests.LookPreviewTests testCancellingPreviewTaskCompletesItAndAllowsTheSameLookToRetry]' started.
Test Case '-[KromoraKitTests.LookPreviewTests testCancellingPreviewTaskCompletesItAndAllowsTheSameLookToRetry]' passed (0.130 seconds).
Test Case '-[KromoraKitTests.LookPreviewTests testCandidatePreviewIsCachedBySourceDocumentAndLook]' started.
Test Case '-[KromoraKitTests.LookPreviewTests testCandidatePreviewIsCachedBySourceDocumentAndLook]' passed (0.063 seconds).
Test Case '-[KromoraKitTests.LookPreviewTests testCandidatePreviewUsesTheDirectImagePath]' started.
Test Case '-[KromoraKitTests.LookPreviewTests testCandidatePreviewUsesTheDirectImagePath]' passed (0.063 seconds).
Test Case '-[KromoraKitTests.LookPreviewTests testCandidatePreviewUsesThumbnailQualityAndDoesNotMutateActiveLook]' started.
Test Case '-[KromoraKitTests.LookPreviewTests testCandidatePreviewUsesThumbnailQualityAndDoesNotMutateActiveLook]' passed (0.067 seconds).
Test Case '-[KromoraKitTests.LookPreviewTests testLookPreviewLayoutFitsTheSupportedInspectorWidths]' started.
Test Case '-[KromoraKitTests.LookPreviewTests testLookPreviewLayoutFitsTheSupportedInspectorWidths]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.LookPreviewTests testNewerDocumentGenerationSupersedesQueuedLookPreview]' started.
Test Case '-[KromoraKitTests.LookPreviewTests testNewerDocumentGenerationSupersedesQueuedLookPreview]' passed (0.127 seconds).
Test Case '-[KromoraKitTests.LookPreviewTests testNoSourceReturnsDeterministicFallbackSignalWithoutSchedulingRender]' started.
Test Case '-[KromoraKitTests.LookPreviewTests testNoSourceReturnsDeterministicFallbackSignalWithoutSchedulingRender]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.LookPreviewTests testRapidDocumentGenerationsWaitForTheThumbnailCadence]' started.
Test Case '-[KromoraKitTests.LookPreviewTests testRapidDocumentGenerationsWaitForTheThumbnailCadence]' passed (0.068 seconds).
Test Case '-[KromoraKitTests.LookPreviewTests testStaleCandidateDropTest]' started.
Test Case '-[KromoraKitTests.LookPreviewTests testStaleCandidateDropTest]' passed (0.076 seconds).
Test Case '-[KromoraKitTests.LookPreviewTests testThumbnailLaneOnlyTest]' started.
Test Case '-[KromoraKitTests.LookPreviewTests testThumbnailLaneOnlyTest]' passed (0.132 seconds).
Test Suite 'LookPreviewTests' passed at 2026-10-02 19:36:07.494.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.853 (0.855) seconds
Test Suite 'MenuCommandTests' started at 2026-10-02 19:36:07.494.
Test Case '-[KromoraKitTests.MenuCommandTests testAutoToolbarButtonKeepsItsFittingSizeAcrossProgressState]' started.
Test Case '-[KromoraKitTests.MenuCommandTests testAutoToolbarButtonKeepsItsFittingSizeAcrossProgressState]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.MenuCommandTests testBatchExportMenuUsesOriginalsLabelAndExistingRoute]' started.
Test Case '-[KromoraKitTests.MenuCommandTests testBatchExportMenuUsesOriginalsLabelAndExistingRoute]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.MenuCommandTests testCropInspectorDoesNotAdvertiseUnavailableAutoAction]' started.
Test Case '-[KromoraKitTests.MenuCommandTests testCropInspectorDoesNotAdvertiseUnavailableAutoAction]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.MenuCommandTests testCropResetLivesInPinnedInspectorTitleRow]' started.
Test Case '-[KromoraKitTests.MenuCommandTests testCropResetLivesInPinnedInspectorTitleRow]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.MenuCommandTests testCropToolbarOwnsExclusiveWindowChrome]' started.
Test Case '-[KromoraKitTests.MenuCommandTests testCropToolbarOwnsExclusiveWindowChrome]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.MenuCommandTests testEditTransferShortcutsDoNotClaimStandardTextClipboardKeys]' started.
Test Case '-[KromoraKitTests.MenuCommandTests testEditTransferShortcutsDoNotClaimStandardTextClipboardKeys]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.MenuCommandTests testImportAndExportToolbarControlsHaveNoStandaloneSeparator]' started.
Test Case '-[KromoraKitTests.MenuCommandTests testImportAndExportToolbarControlsHaveNoStandaloneSeparator]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.MenuCommandTests testLookFolderMenuUsesTheCanonicalLookRoute]' started.
Test Case '-[KromoraKitTests.MenuCommandTests testLookFolderMenuUsesTheCanonicalLookRoute]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.MenuCommandTests testRelocatedViewActionsHaveStableNotificationNames]' started.
Test Case '-[KromoraKitTests.MenuCommandTests testRelocatedViewActionsHaveStableNotificationNames]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.MenuCommandTests testSettingsCommandComesFromTheNativeSettingsScene]' started.
Test Case '-[KromoraKitTests.MenuCommandTests testSettingsCommandComesFromTheNativeSettingsScene]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.MenuCommandTests testViewMenuRoutesRelocatedEditorActionsAndKeepsComparisonToolbarStable]' started.
Test Case '-[KromoraKitTests.MenuCommandTests testViewMenuRoutesRelocatedEditorActionsAndKeepsComparisonToolbarStable]' passed (0.004 seconds).
Test Suite 'MenuCommandTests' passed at 2026-10-02 19:36:07.533.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.038 (0.039) seconds
Test Suite 'MetalKernelParityTests' started at 2026-10-02 19:36:07.533.
Test Case '-[KromoraKitTests.MetalKernelParityTests testCIMetallibIsBundledLoadableAndComplete]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testCIMetallibIsBundledLoadableAndComplete]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testCIMetallibMatchesBundledSources]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testCIMetallibMatchesBundledSources]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testColorGradingMatchesGolden]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testColorGradingMatchesGolden]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testGrainIsDeterministicAndSeedSensitive]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testGrainIsDeterministicAndSeedSensitive]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testGrainKeepsGoldenStatistics]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testGrainKeepsGoldenStatistics]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testHSLMixerMatchesGolden]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testHSLMixerMatchesGolden]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testInvertAndCombineMatchGoldens]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testInvertAndCombineMatchGoldens]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testLinearMaskMatchesGolden]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testLinearMaskMatchesGolden]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testMidtoneMaskMatchesGolden]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testMidtoneMaskMatchesGolden]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testMigratedKernelsRenderOnTheSoftwareRenderer]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testMigratedKernelsRenderOnTheSoftwareRenderer]' passed (0.017 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testNoRuntimeShaderSourceCompilation]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testNoRuntimeShaderSourceCompilation]' passed (0.235 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testPresentationMetallibIsBundledFreshAndLoadable]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testPresentationMetallibIsBundledFreshAndLoadable]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testRadialMaskROIEdgeMatchesGolden]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testRadialMaskROIEdgeMatchesGolden]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testToneCurveMatchesGoldens]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testToneCurveMatchesGoldens]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testVignetteMatchesGolden]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testVignetteMatchesGolden]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.MetalKernelParityTests testVignetteROIEdgeMatchesGolden]' started.
Test Case '-[KromoraKitTests.MetalKernelParityTests testVignetteROIEdgeMatchesGolden]' passed (0.002 seconds).
Test Suite 'MetalKernelParityTests' passed at 2026-10-02 19:36:07.821.
	 Executed 16 tests, with 0 failures (0 unexpected) in 0.287 (0.288) seconds
Test Suite 'NeutralOriginSliderTests' started at 2026-10-02 19:36:07.821.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testABipolarSliderAtItsNeutralDrawsNoFill]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testABipolarSliderAtItsNeutralDrawsNoFill]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testAControlNeutralAtItsMaximumFillsLeftwards]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testAControlNeutralAtItsMaximumFillsLeftwards]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testAUnipolarSliderAtItsFloorDrawsNoFill]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testAUnipolarSliderAtItsFloorDrawsNoFill]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testAUnipolarSliderFillsFromTheLeftEdge]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testAUnipolarSliderFillsFromTheLeftEdge]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testColorControlsUseDocumentedSemanticTracks]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testColorControlsUseDocumentedSemanticTracks]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testConfiguredStepSnapsSliderActionsBeforeUpdatingTheBinding]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testConfiguredStepSnapsSliderActionsBeforeUpdatingTheBinding]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testDraggingAboveNeutralFillsOnlyToTheRightOfTheBaseline]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testDraggingAboveNeutralFillsOnlyToTheRightOfTheBaseline]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testDraggingBelowNeutralFillsOnlyToTheLeftOfTheBaseline]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testDraggingBelowNeutralFillsOnlyToTheLeftOfTheBaseline]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testEqualAndOppositeValuesFillEqualAmountsOfTrack]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testEqualAndOppositeValuesFillEqualAmountsOfTrack]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testKeyboardActionCancelsAnInFlightPresentationAnimation]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testKeyboardActionCancelsAnInFlightPresentationAnimation]' passed (0.509 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testPhotoSwitchHoldsSliderAtOutgoingValueUntilIncomingDocumentArrives]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testPhotoSwitchHoldsSliderAtOutgoingValueUntilIncomingDocumentArrives]' passed (0.468 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testRenderedThumbIsVerticallyCenteredOnTheRenderedBar]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testRenderedThumbIsVerticallyCenteredOnTheRenderedBar]' passed (0.010 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testRepeatedPresentationOfTheSameTargetDoesNotRestartAnimation]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testRepeatedPresentationOfTheSameTargetDoesNotRestartAnimation]' passed (0.460 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testRetargetingAnAnimationPreservesItsCurrentValueAndVelocity]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testRetargetingAnAnimationPreservesItsCurrentValueAndVelocity]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testSaturationTrackRunsFromMutedLeftThroughCyanGreenToWarmColor]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testSaturationTrackRunsFromMutedLeftThroughCyanGreenToWarmColor]' passed (0.016 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testSemanticTrackReachesBothEdgesOfTheBar]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testSemanticTrackReachesBothEdgesOfTheBar]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testSupersedingPresentationFinishesAtTheLatestTarget]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testSupersedingPresentationFinishesAtTheLatestTarget]' passed (0.551 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testTemperatureTrackRunsFromCoolBlueToWarmAmber]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testTemperatureTrackRunsFromCoolBlueToWarmAmber]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testTheCellsBarDrawingIsReachedWhenTheControlDraws]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testTheCellsBarDrawingIsReachedWhenTheControlDraws]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testThumbGeometryIsCircularWithoutChangingNativeKnobGeometry]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testThumbGeometryIsCircularWithoutChangingNativeKnobGeometry]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testThumbUsesThePrimaryAccent]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testThumbUsesThePrimaryAccent]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testThumbVisualCanCorrectAnOffsetNativeKnobRectWithoutChangingItsHorizontalGeometry]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testThumbVisualCanCorrectAnOffsetNativeKnobRectWithoutChangingItsHorizontalGeometry]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testThumbVisualScaleDoesNotChangeNativeHitGeometry]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testThumbVisualScaleDoesNotChangeNativeHitGeometry]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testTintTrackRunsFromGreenToMagenta]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testTintTrackRunsFromGreenToMagenta]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testVibranceTrackRemainsChromaticFromBlueToMagenta]' started.
Test Case '-[KromoraKitTests.NeutralOriginSliderTests testVibranceTrackRemainsChromaticFromBlueToMagenta]' passed (0.009 seconds).
Test Suite 'NeutralOriginSliderTests' passed at 2026-10-02 19:36:09.887.
	 Executed 25 tests, with 0 failures (0 unexpected) in 2.064 (2.066) seconds
Test Suite 'PersonSignalWarmingTests' started at 2026-10-02 19:36:09.887.
Test Case '-[KromoraKitTests.PersonSignalWarmingTests testPersonCreationSucceedsWithColdStoreAndWarmAnalysisCache]' started.
Test Case '-[KromoraKitTests.PersonSignalWarmingTests testPersonCreationSucceedsWithColdStoreAndWarmAnalysisCache]' passed (0.433 seconds).
Test Case '-[KromoraKitTests.PersonSignalWarmingTests testPrepareRequestsBothSignals]' started.
Test Case '-[KromoraKitTests.PersonSignalWarmingTests testPrepareRequestsBothSignals]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.PersonSignalWarmingTests testPrepareToleratesAFailingSignal]' started.
Test Case '-[KromoraKitTests.PersonSignalWarmingTests testPrepareToleratesAFailingSignal]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.PersonSignalWarmingTests testResolveEpochIncrements]' started.
Test Case '-[KromoraKitTests.PersonSignalWarmingTests testResolveEpochIncrements]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PersonSignalWarmingTests testRetryWarmsSignalsAndBumpsResolveEpoch]' started.
Test Case '-[KromoraKitTests.PersonSignalWarmingTests testRetryWarmsSignalsAndBumpsResolveEpoch]' passed (0.365 seconds).
Test Suite 'PersonSignalWarmingTests' passed at 2026-10-02 19:36:10.691.
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.803 (0.804) seconds
Test Suite 'PhotoIntelligenceRealCorpusTests' started at 2026-10-02 19:36:10.691.
Test Case '-[KromoraKitTests.PhotoIntelligenceRealCorpusTests testGenerateVisualRegressionReport]' started.
2026-10-02 19:36:12.708 xctest[98824:15188087] FBBA: creating VNFaceBBoxAligner from VNFaceDetectorRevision2: VNFaceDetectorRevision2
Test Case '-[KromoraKitTests.PhotoIntelligenceRealCorpusTests testGenerateVisualRegressionReport]' passed (12.688 seconds).
Test Case '-[KromoraKitTests.PhotoIntelligenceRealCorpusTests testRealCorpusUsesRealPipelineAndGuardsMeasuredStats]' started.
Test Case '-[KromoraKitTests.PhotoIntelligenceRealCorpusTests testRealCorpusUsesRealPipelineAndGuardsMeasuredStats]' passed (10.826 seconds).
Test Suite 'PhotoIntelligenceRealCorpusTests' passed at 2026-10-02 19:36:34.205.
	 Executed 2 tests, with 0 failures (0 unexpected) in 23.514 (23.514) seconds
Test Suite 'PhotosDeliveryTests' started at 2026-10-02 19:36:34.205.
Test Case '-[KromoraKitTests.PhotosDeliveryTests testBatchPhotosFailuresAreCountedSeparatelyFromRenderFailures]' started.
Test Case '-[KromoraKitTests.PhotosDeliveryTests testBatchPhotosFailuresAreCountedSeparatelyFromRenderFailures]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.PhotosDeliveryTests testPhotosOptionsTrimAlbumNamesAndRoundTrip]' started.
Test Case '-[KromoraKitTests.PhotosDeliveryTests testPhotosOptionsTrimAlbumNamesAndRoundTrip]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PhotosDeliveryTests testSinglePhotosDeliveryReceivesTheCompletedEncodedDataAndAlbum]' started.
Test Case '-[KromoraKitTests.PhotosDeliveryTests testSinglePhotosDeliveryReceivesTheCompletedEncodedDataAndAlbum]' passed (0.011 seconds).
Test Case '-[KromoraKitTests.PhotosDeliveryTests testSinglePhotosFailureLeavesCommittedFileAndReportsSeparateFailure]' started.
Test Case '-[KromoraKitTests.PhotosDeliveryTests testSinglePhotosFailureLeavesCommittedFileAndReportsSeparateFailure]' passed (0.013 seconds).
Test Suite 'PhotosDeliveryTests' passed at 2026-10-02 19:36:34.232.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.027 (0.027) seconds
Test Suite 'PhotosImportTests' started at 2026-10-02 19:36:34.233.
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorCancellationFinishesWithoutDiscardingEarlierItem]' started.
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorCancellationFinishesWithoutDiscardingEarlierItem]' passed (0.367 seconds).
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorImportsMultipleItemsThroughInjectedProvider]' started.
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorImportsMultipleItemsThroughInjectedProvider]' passed (0.469 seconds).
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorPropagatesOneComputedDigestToDurableSource]' started.
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorPropagatesOneComputedDigestToDurableSource]' passed (0.367 seconds).
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorPublishesInsertedDuplicateAndFailedPackageOutcomes]' started.
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorPublishesInsertedDuplicateAndFailedPackageOutcomes]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorRecordsPartialFailureAndKeepsSuccessfulItems]' started.
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorRecordsPartialFailureAndKeepsSuccessfulItems]' passed (0.378 seconds).
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorUsesFallbackNameWhenProviderHasNoFilename]' started.
Test Case '-[KromoraKitTests.PhotosImportTests testCoordinatorUsesFallbackNameWhenProviderHasNoFilename]' passed (0.364 seconds).
Test Case '-[KromoraKitTests.PhotosImportTests testLateCancelledProviderResultCannotMutateNewOperation]' started.
Test Case '-[KromoraKitTests.PhotosImportTests testLateCancelledProviderResultCannotMutateNewOperation]' passed (0.084 seconds).
Test Case '-[KromoraKitTests.PhotosImportTests testPortablePhotosBatchDefersProjectionAndMaterializationUntilFinish]' started.
Test Case '-[KromoraKitTests.PhotosImportTests testPortablePhotosBatchDefersProjectionAndMaterializationUntilFinish]' passed (0.780 seconds).
Test Case '-[KromoraKitTests.PhotosImportTests testPortablePhotosFirstBatchItemIsSelectedAfterDeferredRefresh]' started.
Test Case '-[KromoraKitTests.PhotosImportTests testPortablePhotosFirstBatchItemIsSelectedAfterDeferredRefresh]' passed (0.261 seconds).
Test Suite 'PhotosImportTests' passed at 2026-10-02 19:36:37.306.
	 Executed 9 tests, with 0 failures (0 unexpected) in 3.072 (3.073) seconds
Test Suite 'PreviewCutoverTests' started at 2026-10-02 19:36:37.306.
Test Case '-[KromoraKitTests.PreviewCutoverTests testAddingASmartMaskPublishesABaseFrameThenRefinesIt]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testAddingASmartMaskPublishesABaseFrameThenRefinesIt]' passed (0.379 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testAFileBackedLUTResolvesAndSurvivesARescan]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testAFileBackedLUTResolvesAndSurvivesARescan]' passed (0.243 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testAFreshDerivePutsAGradedImageOnScreen]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testAFreshDerivePutsAGradedImageOnScreen]' passed (0.398 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testDevelopAdjustmentsAndIntensityAllReachTheEngine]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testDevelopAdjustmentsAndIntensityAllReachTheEngine]' passed (0.357 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testEachKnobVisiblyChangesThePreview]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testEachKnobVisiblyChangesThePreview]' passed (0.501 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testFitFillAndExplicitZoomPublishNonBlankSurfaceFrames]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testFitFillAndExplicitZoomPublishNonBlankSurfaceFrames]' passed (0.465 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testHoldingSpaceShowsTheUngradedImageInTheMainPanel]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testHoldingSpaceShowsTheUngradedImageInTheMainPanel]' passed (0.428 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testLibraryDoubleClickPublishesHistogramForAlreadyLoadedPhoto]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testLibraryDoubleClickPublishesHistogramForAlreadyLoadedPhoto]' passed (0.249 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testOnlyTheVisiblePreviewTakesTheProgressivePath]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testOnlyTheVisiblePreviewTakesTheProgressivePath]' passed (0.480 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testOpeningStoredEditsSpeculatesThenSubmitsTheStoredDocument]' passed (0.429 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testOrphanedSpeculativePredecessorDoesNotBlockTheNextPhoto]' passed (0.484 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testPhotoSwitchRetainsHistogramAndRejectsAnObsoleteResult]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testPhotoSwitchRetainsHistogramAndRejectsAnObsoleteResult]' passed (0.352 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testShowingOriginalRequestsTheDevelopAppliedBaseline]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testShowingOriginalRequestsTheDevelopAppliedBaseline]' passed (0.383 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testTheDocumentReachesTheEngine]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testTheDocumentReachesTheEngine]' passed (0.375 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testTheShimsTrackTheDocument]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testTheShimsTrackTheDocument]' passed (0.223 seconds).
Test Case '-[KromoraKitTests.PreviewCutoverTests testZoomJustAboveAndFarAbove100PercentUsesNativePreviewAndKeepsSurfaceFrame]' started.
Test Case '-[KromoraKitTests.PreviewCutoverTests testZoomJustAboveAndFarAbove100PercentUsesNativePreviewAndKeepsSurfaceFrame]' passed (0.507 seconds).
Test Suite 'PreviewCutoverTests' passed at 2026-10-02 19:36:43.557.
	 Executed 16 tests, with 0 failures (0 unexpected) in 6.250 (6.251) seconds
Test Suite 'PreviewSurfaceTests' started at 2026-10-02 19:36:43.557.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAFailedReplacementKeepsTheLastValidFrame]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAFailedReplacementKeepsTheLastValidFrame]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testARetainedROIFrameDoesNotRefuseTheCompletePhoto]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testARetainedROIFrameDoesNotRefuseTheCompletePhoto]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAStalePresentationCompletionCannotCommitOverANewerFrame]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAStalePresentationCompletionCannotCommitOverANewerFrame]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAttachingAViewRequestsAFramePublishedBeforeTheViewWasCreated]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testAttachingAViewRequestsAFramePublishedBeforeTheViewWasCreated]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testBundledMetalSourcesAreResolvable]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testBundledMetalSourcesAreResolvable]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testClearResetsTheWorkingSpace]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testClearResetsTheWorkingSpace]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCompletedEngineTexturePresentsVisualTopAtFramebufferRowZero]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCompletedEngineTexturePresentsVisualTopAtFramebufferRowZero]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testConfirmationOnceTest]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testConfirmationOnceTest]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCoordinatorBuildsAPresentationPipelineFromBundledMetallib]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCoordinatorBuildsAPresentationPipelineFromBundledMetallib]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCroppedCompleteFrameFillsFitCanvas]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCroppedCompleteFrameFillsFitCanvas]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCropStraightenFitsTheRotatedPhotoAABBWithoutChangingTheRenderedSourceExtent]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testCropStraightenFitsTheRotatedPhotoAABBWithoutChangingTheRenderedSourceExtent]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDisplayChangeTest]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDisplayChangeTest]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDoubleClickDoesNotStartAPan]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDoubleClickDoesNotStartAPan]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDoubleClickMouseDownTogglesCanvasAfterLeavingCropTool]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDoubleClickMouseDownTogglesCanvasAfterLeavingCropTool]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDownscaledInteractiveROIUsesPlannerLayoutOnFitCanvas]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testDownscaledInteractiveROIUsesPlannerLayoutOnFitCanvas]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testEffectiveAppearanceResolvesTheSameLetterboxForMetalAndCoreImage]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testEffectiveAppearanceResolvesTheSameLetterboxForMetalAndCoreImage]' passed (0.007 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testFillCoversTheViewportWithAPortraitStandIn]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testFillCoversTheViewportWithAPortraitStandIn]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testGeometryGoldenTest]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testGeometryGoldenTest]' passed (0.007 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testHeadlessSurfaceConfirmsACompletedPresentationImmediately]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testHeadlessSurfaceConfirmsACompletedPresentationImmediately]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testInvalidCandidateCannotBlankTheLastConfirmedFrame]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testInvalidCandidateCannotBlankTheLastConfirmedFrame]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testLatestPublicationRemainsAvailableAcrossSkippedReplacement]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testLatestPublicationRemainsAvailableAcrossSkippedReplacement]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMetalFramebufferRowZeroIsVisualTop]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMetalFramebufferRowZeroIsVisualTop]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMissingDigestReplacementDoesNotRetainATransitionTexture]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMissingDigestReplacementDoesNotRetainATransitionTexture]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseDragPreservesPointerDirectionOnBothAxes]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseDragPreservesPointerDirectionOnBothAxes]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseDragPublishesPanBeforeMouseUp]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseDragPublishesPanBeforeMouseUp]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseUpDoesNotInvertTheAccumulatedPan]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testMouseUpDoesNotInvertTheAccumulatedPan]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testNavigationCannotReplaceAValidSharperFrameWithALowerDetailFrame]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testNavigationCannotReplaceAValidSharperFrameWithALowerDetailFrame]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testNoCIEvalOnRepaintTest]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testNoCIEvalOnRepaintTest]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPartialROIFollowsLivePanOnRetainedCompleteFrameWithoutGaps]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPartialROIFollowsLivePanOnRetainedCompleteFrameWithoutGaps]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPartialROIFrameStaysAtPublishedNavigationUntilReplacementArrives]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPartialROIFrameStaysAtPublishedNavigationUntilReplacementArrives]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPortraitStandInDoesNotStretchOntoLandscapePresentationExtent]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPortraitStandInDoesNotStretchOntoLandscapePresentationExtent]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentationFallbackDoesNotBlendCanvasIntoPhotoPerimeter]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentationFallbackDoesNotBlendCanvasIntoPhotoPerimeter]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentationImageRemainsBoundedAbove100PercentAndKeepsTheSourceVisible]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentationImageRemainsBoundedAbove100PercentAndKeepsTheSourceVisible]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentationOnlyFrameConfirmsWithoutRenderTelemetry]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentationOnlyFrameConfirmsWithoutRenderTelemetry]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentStoresTheWorkingSpaceForThePresentedImage]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPresentStoresTheWorkingSpaceForThePresentedImage]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPreviewSurfaceLayoutUsesProposedSizeWithoutIntrinsicMeasurement]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPreviewSurfaceLayoutUsesProposedSizeWithoutIntrinsicMeasurement]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testProxyFirstFrameFillsFitCanvas]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testProxyFirstFrameFillsFitCanvas]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPublicationRequestsRedrawOnAnExistingMetalView]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testPublicationRequestsRedrawOnAnExistingMetalView]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testReduceMotionReplacementDoesNotRetainATransitionTexture]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testReduceMotionReplacementDoesNotRetainATransitionTexture]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testRetainedTextureCropStraightenRotatesThePhotoInsteadOfZoomingItsTexture]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testRetainedTextureCropStraightenRotatesThePhotoInsteadOfZoomingItsTexture]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testSkippedDrawableStaysPendingUntilARealPresentation]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testSkippedDrawableStaysPendingUntilARealPresentation]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testSkippedDrawRetriesAreBoundedAndQuietAfterConsecutiveSkips]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testSkippedDrawRetriesAreBoundedAndQuietAfterConsecutiveSkips]' passed (0.105 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testStaleSettledReplacementCrossfadesFor120MillisecondsThenReleasesOldTexture]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testStaleSettledReplacementCrossfadesFor120MillisecondsThenReleasesOldTexture]' passed (0.160 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testUncoveredROIStaysAtVirtualOriginOnFit]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testUncoveredROIStaysAtVirtualOriginOnFit]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.PreviewSurfaceTests testVisibilityRestoreRearmsSkippedDrawRetries]' started.
Test Case '-[KromoraKitTests.PreviewSurfaceTests testVisibilityRestoreRearmsSkippedDrawRetries]' passed (0.066 seconds).
Test Suite 'PreviewSurfaceTests' passed at 2026-10-02 19:36:44.001.
	 Executed 45 tests, with 0 failures (0 unexpected) in 0.442 (0.444) seconds
Test Suite 'RelaunchParityTests' started at 2026-10-02 19:36:44.001.
Test Case '-[KromoraKitTests.RelaunchParityTests testChangedEditBetweenSessionsInvalidatesPersistedFrameOnce]' started.
Test Case '-[KromoraKitTests.RelaunchParityTests testChangedEditBetweenSessionsInvalidatesPersistedFrameOnce]' passed (0.859 seconds).
Test Case '-[KromoraKitTests.RelaunchParityTests testDifferentPixelEpochBetweenSessionsRefinesPersistedFrameOnce]' started.
Test Case '-[KromoraKitTests.RelaunchParityTests testDifferentPixelEpochBetweenSessionsRefinesPersistedFrameOnce]' passed (0.677 seconds).
Test Case '-[KromoraKitTests.RelaunchParityTests testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce]' started.
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:302: error: -[KromoraKitTests.RelaunchParityTests testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce] : XCTAssertEqual failed: ("2") is not equal to ("1")
Test Case '-[KromoraKitTests.RelaunchParityTests testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce]' failed (0.730 seconds).
Test Case '-[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch]' started.
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:527: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertFalse failed - original thumbnail was published before confirmation
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:529: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - unchanged plain photo should reuse its frame: plain-a.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:532: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("1") is not equal to ("0") - unchanged plain photo must not render: plain-a.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:527: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertFalse failed - original thumbnail was published before confirmation
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:529: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - unchanged plain photo should reuse its frame: plain-b.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:532: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - unchanged plain photo must not render: plain-b.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:535: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - Edit must publish one confirmed frame for exposure.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:542: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("1") is not equal to ("0") - unchanged Edit source must use its confirmed frame without a render for exposure.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:535: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - Edit must publish one confirmed frame for color.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:542: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("1") is not equal to ("0") - unchanged Edit source must use its confirmed frame without a render for color.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:535: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - Edit must publish one confirmed frame for crop.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:542: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("0") - unchanged Edit source must use its confirmed frame without a render for crop.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:535: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("2") is not equal to ("1") - Edit must publish one confirmed frame for look.png
/Users/dhardy/Dev/Kromora/Tests/KromoraKitTests/RelaunchParityTests.swift:542: error: -[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch] : XCTAssertEqual failed: ("1") is not equal to ("0") - unchanged Edit source must use its confirmed frame without a render for look.png
Test Case '-[KromoraKitTests.RelaunchParityTests testUnchangedPackageReusesSettledFramesAfterRelaunch]' failed (1.924 seconds).
Test Case '-[KromoraKitTests.RelaunchParityTests testUnchangedSinglePhotoSeedIsReusedAfterRelaunch]' started.
Test Case '-[KromoraKitTests.RelaunchParityTests testUnchangedSinglePhotoSeedIsReusedAfterRelaunch]' passed (0.667 seconds).
Test Suite 'RelaunchParityTests' failed at 2026-10-02 19:36:48.859.
	 Executed 5 tests, with 15 failures (0 unexpected) in 4.857 (4.858) seconds
Test Suite 'RenderCacheTests' started at 2026-10-02 19:36:48.859.
Test Case '-[KromoraKitTests.RenderCacheTests testAboveBudgetStandardPrefixStaysFusedWithoutMaterializationStorm]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testAboveBudgetStandardPrefixStaysFusedWithoutMaterializationStorm]' passed (0.236 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testByteCapTest]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testByteCapTest]' passed (0.215 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testCacheCostAccountingCannotOverflow]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testCacheCostAccountingCannotOverflow]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testCachedPrefixPreservesDownstreamCropGrainAndLUTPixels]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testCachedPrefixPreservesDownstreamCropGrainAndLUTPixels]' passed (0.026 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testConfiguredLimitEvictsLeastRecentlyUsedPreviewEntries]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testConfiguredLimitEvictsLeastRecentlyUsedPreviewEntries]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testDevelopedSourceIsReusedAcrossDifferentEdits]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testDevelopedSourceIsReusedAcrossDifferentEdits]' passed (0.014 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testDownstreamOnlyEditsReuseTheCompletedProcessingPrefix]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testDownstreamOnlyEditsReuseTheCompletedProcessingPrefix]' passed (0.011 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testEffectiveInteractiveScaleCannotReuseSettledDevelopedSource]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testEffectiveInteractiveScaleCannotReuseSettledDevelopedSource]' passed (0.367 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testEvictionAccountingTest]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testEvictionAccountingTest]' passed (0.078 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testExplicitInvalidationForcesTheNextPreviewToMiss]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testExplicitInvalidationForcesTheNextPreviewToMiss]' passed (0.010 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testFullResolutionRequestsNeverEnterThePreviewCache]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testFullResolutionRequestsNeverEnterThePreviewCache]' passed (0.019 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testFullResolutionWorkNeverEntersTheProcessingPrefixCache]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testFullResolutionWorkNeverEntersTheProcessingPrefixCache]' passed (0.009 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testIdenticalPreviewRequestsHitAndExposeCounters]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testIdenticalPreviewRequestsHitAndExposeCounters]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testInteractiveBudgetsWithDifferentEffectiveScalesDoNotCollide]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testInteractiveBudgetsWithDifferentEffectiveScalesDoNotCollide]' passed (0.273 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testMaskedPrefixHitTest]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testMaskedPrefixHitTest]' passed (0.019 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testMaskVersionMissTest]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testMaskVersionMissTest]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testMemoryPressurePurgesRenderAndThumbnailCaches]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testMemoryPressurePurgesRenderAndThumbnailCaches]' passed (0.011 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testMidResolutionPoisonTest]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testMidResolutionPoisonTest]' passed (0.020 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testNonLUTFallbackTest]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testNonLUTFallbackTest]' passed (0.021 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testPartitionSurvivalTest]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testPartitionSurvivalTest]' passed (0.081 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testPreviewKeyIncludesAllGrainParameters]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testPreviewKeyIncludesAllGrainParameters]' passed (0.028 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testPreviewKeyIncludesDocumentSizeQualityAndWorkingSpace]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testPreviewKeyIncludesDocumentSizeQualityAndWorkingSpace]' passed (0.028 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testProcessingPrefixEvictionHonorsItsIndependentBudget]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testProcessingPrefixEvictionHonorsItsIndependentBudget]' passed (0.011 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testReplacingAURLBackedSourceCannotReuseItsPreview]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testReplacingAURLBackedSourceCannotReuseItsPreview]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testRetouchEditMissesTheProcessingPrefixAndChangesPixels]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testRetouchEditMissesTheProcessingPrefixAndChangesPixels]' passed (0.018 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testSharedPrefixTest]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testSharedPrefixTest]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testSourceContentFingerprintSeparatesDataBackedImages]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testSourceContentFingerprintSeparatesDataBackedImages]' passed (0.011 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testTextureWarmupPrimesDevelopedSourceForTheNextPreview]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testTextureWarmupPrimesDevelopedSourceForTheNextPreview]' passed (0.009 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testThumbnailRequestsHitAndFileChangesMiss]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testThumbnailRequestsHitAndFileChangesMiss]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testUnmaskedNoOpTest]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testUnmaskedNoOpTest]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.RenderCacheTests testUpstreamEditsInvalidateOnlyTheProcessingPrefix]' started.
Test Case '-[KromoraKitTests.RenderCacheTests testUpstreamEditsInvalidateOnlyTheProcessingPrefix]' passed (0.010 seconds).
Test Suite 'RenderCacheTests' passed at 2026-10-02 19:36:50.464.
	 Executed 31 tests, with 0 failures (0 unexpected) in 1.603 (1.605) seconds
Test Suite 'RenderEngineInteractivePrecisionTests' started at 2026-10-02 19:36:50.464.
Test Case '-[KromoraKitTests.RenderEngineInteractivePrecisionTests testBandwidthStructureTest]' started.
Test Case '-[KromoraKitTests.RenderEngineInteractivePrecisionTests testBandwidthStructureTest]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.RenderEngineInteractivePrecisionTests testExportUnchangedTest]' started.
Test Case '-[KromoraKitTests.RenderEngineInteractivePrecisionTests testExportUnchangedTest]' passed (0.014 seconds).
Test Case '-[KromoraKitTests.RenderEngineInteractivePrecisionTests testInteractiveDescriptorTest]' started.
Test Case '-[KromoraKitTests.RenderEngineInteractivePrecisionTests testInteractiveDescriptorTest]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.RenderEngineInteractivePrecisionTests testSettleQualityTest]' started.
Test Case '-[KromoraKitTests.RenderEngineInteractivePrecisionTests testSettleQualityTest]' passed (0.077 seconds).
Test Suite 'RenderEngineInteractivePrecisionTests' passed at 2026-10-02 19:36:50.555.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.091 (0.092) seconds
Test Suite 'RenderEngineTests' started at 2026-10-02 19:36:50.555.
Test Case '-[KromoraKitTests.RenderEngineTests testAFakeCanStandInForTheEngine]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testAFakeCanStandInForTheEngine]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testAnUndecodableSourceIsNilForPreviewAndThrowsForExport]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testAnUndecodableSourceIsNilForPreviewAndThrowsForExport]' passed (0.009 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testAReplacedCubeAtTheSamePathRendersTheNewLookAfterAFlush]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testAReplacedCubeAtTheSamePathRendersTheNewLookAfterAFlush]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testCompletedTexturePreservesTaggedJPEGOrientation]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testCompletedTexturePreservesTaggedJPEGOrientation]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testConcurrentRendersAreSerializedAndCorrect]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testConcurrentRendersAreSerializedAndCorrect]' passed (0.073 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testCroppedThumbnailRetainsTheOriginalDisplayedPixelBudget]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testCroppedThumbnailRetainsTheOriginalDisplayedPixelBudget]' passed (0.606 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testDirectThumbnailRasterMatchesEncodedThumbnail]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testDirectThumbnailRasterMatchesEncodedThumbnail]' passed (0.021 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testDisplayPreviewIsBackedByACompletedMetalTexture]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testDisplayPreviewIsBackedByACompletedMetalTexture]' passed (0.011 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testEveryFormatEncodesToItsOwnType]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testEveryFormatEncodesToItsOwnType]' passed (0.041 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testExportMetadataPolicyRoundTripsSourceMetadataForEveryFormat]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testExportMetadataPolicyRoundTripsSourceMetadataForEveryFormat]' passed (0.037 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testFractionalCropThumbnailRasterizesItsEdgesFromImageContent]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testFractionalCropThumbnailRasterizesItsEdgesFromImageContent]' passed (0.010 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testHEIFRoundTripsDimensionsAndColorSpace]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testHEIFRoundTripsDimensionsAndColorSpace]' passed (0.033 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testInvalidatingLUTsAlsoDropsAResolvedPreview]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testInvalidatingLUTsAlsoDropsAResolvedPreview]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testLargeGrainCompletedTextureHasNoZoomTileSeams]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testLargeGrainCompletedTextureHasNoZoomTileSeams]' passed (0.410 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testLargeVignetteCompletedTextureHasNoZoomTileSeams]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testLargeVignetteCompletedTextureHasNoZoomTileSeams]' passed (0.407 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing]' passed (0.806 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testLocationPolicyIsExplicitForURLAndDataSourcesAcrossShareableFormats]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testLocationPolicyIsExplicitForURLAndDataSourcesAcrossShareableFormats]' passed (0.107 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testParityHoldsInEveryWorkingSpace]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testParityHoldsInEveryWorkingSpace]' passed (0.021 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testPreservedMetadataDoesNotReapplySourceOrientation]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testPreservedMetadataDoesNotReapplySourceOrientation]' passed (0.012 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testPreviewAndExportAreTheSamePixels]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testPreviewAndExportAreTheSamePixels]' passed (0.018 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testScaleIsTheOnlyDifferenceBetweenPreviewAndFull]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testScaleIsTheOnlyDifferenceBetweenPreviewAndFull]' passed (0.016 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testStripMetadataDoesNotCopySourcePhotographicDictionaries]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testStripMetadataDoesNotCopySourcePhotographicDictionaries]' passed (0.040 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testTheCubeFilterIsBuiltOnceAndReused]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testTheCubeFilterIsBuiltOnceAndReused]' passed (0.021 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testTheEngineRasterizesThePipelineGraphUnchanged]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testTheEngineRasterizesThePipelineGraphUnchanged]' passed (0.021 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testTheFakeCanSimulateAnEncodeFailure]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testTheFakeCanSimulateAnEncodeFailure]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testTheMemoIsKeyedOnThePreviewSize]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testTheMemoIsKeyedOnThePreviewSize]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testTheMemoIsKeyedOnTheSource]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testTheMemoIsKeyedOnTheSource]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testTheOldPathStillWorksAndAgreesOnAnUneditedImage]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testTheOldPathStillWorksAndAgreesOnAnUneditedImage]' passed (0.017 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testTheWorkingSpaceReachesTheCubeThroughTheEngine]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testTheWorkingSpaceReachesTheCubeThroughTheEngine]' passed (0.022 seconds).
Test Case '-[KromoraKitTests.RenderEngineTests testTheWorkingSpaceReachesTheEncoder]' started.
Test Case '-[KromoraKitTests.RenderEngineTests testTheWorkingSpaceReachesTheEncoder]' passed (0.012 seconds).
Test Suite 'RenderEngineTests' passed at 2026-10-02 19:36:53.394.
	 Executed 30 tests, with 0 failures (0 unexpected) in 2.837 (2.838) seconds
Test Suite 'RenderPipelineTests' started at 2026-10-02 19:36:53.394.
Test Case '-[KromoraKitTests.RenderPipelineTests testACachedFilterRendersTheSameAsAFreshOne]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testACachedFilterRendersTheSameAsAFreshOne]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testAdjustmentOrderReachesTheGraph]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testAdjustmentOrderReachesTheGraph]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testCombinedLightControlsStayMonotonic]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testCombinedLightControlsStayMonotonic]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testDataBackedAndURLBackedSourcesAgree]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testDataBackedAndURLBackedSourcesAgree]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testDevelopEditsAreInertForAStandardImage]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testDevelopEditsAreInertForAStandardImage]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testDuplicateNodesStack]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testDuplicateNodesStack]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testEmptyDocumentIsTheIdentity]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testEmptyDocumentIsTheIdentity]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testEndpointExtremesRemainFiniteMonotonicAndClipAtRasterBoundary]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testEndpointExtremesRemainFiniteMonotonicAndClipAtRasterBoundary]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testEndpointNeutralValuesAreExactNoOpsAndPreserveExtent]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testEndpointNeutralValuesAreExactNoOpsAndPreserveExtent]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testEveryAdjustmentCaseChangesTheImage]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testEveryAdjustmentCaseChangesTheImage]' passed (0.034 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testHealMembraneExcludesPixelsInsideTheHole]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testHealMembraneExcludesPixelsInsideTheHole]' passed (0.026 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testHealOverFlatExteriorDoesNotOvershootDestinationTone]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testHealOverFlatExteriorDoesNotOvershootDestinationTone]' passed (0.026 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testHighlightsAndShadowsAreTonalInverses]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testHighlightsAndShadowsAreTonalInverses]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testIntensityEndpointsAreExact]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testIntensityEndpointsAreExact]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testIntensityIsClamped]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testIntensityIsClamped]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testIntermediateIntensityLandsBetweenTheEndpoints]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testIntermediateIntensityLandsBetweenTheEndpoints]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testManuallySourcedHealAndCloneProduceDifferentLocalFills]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testManuallySourcedHealAndCloneProduceDifferentLocalFills]' passed (0.016 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testMasterToneCurveChangesAllRGBChannelsAndRemainsMonotonic]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testMasterToneCurveChangesAllRGBChannelsAndRemainsMonotonic]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testMasterToneCurveDoesNotBlackOutANonZeroOriginSource]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testMasterToneCurveDoesNotBlackOutANonZeroOriginSource]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testModerateContrastKeepsUsableEndpoints]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testModerateContrastKeepsUsableEndpoints]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testNeutralLightIsTheIdentity]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testNeutralLightIsTheIdentity]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testNeutralNodesAndAnIdentityCubeAreStillTheIdentity]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testNeutralNodesAndAnIdentityCubeAreStillTheIdentity]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testNoiseControlValuesSurviveDocumentReopenAndReachTheSharedRenderPath]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testNoiseControlValuesSurviveDocumentReopenAndReachTheSharedRenderPath]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testNoiseReductionReducesLuminanceAndChromaNoiseWithoutLosingTheEdge]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testNoiseReductionReducesLuminanceAndChromaNoiseWithoutLosingTheEdge]' passed (0.011 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testOneStopExposureDoublesLinearMidtone]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testOneStopExposureDoublesLinearMidtone]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testOrientationIsBakedLikeTheOldPath]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testOrientationIsBakedLikeTheOldPath]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testParametricRegionsChangeTheToneCurveTransfer]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testParametricRegionsChangeTheToneCurveTransfer]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testPhotographicLightVisualSamples]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testPhotographicLightVisualSamples]' passed (0.017 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testPreviewDecodeBakesOrientationLikeTheFilmstrip]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testPreviewDecodeBakesOrientationLikeTheFilmstrip]' passed (0.087 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testPreviewDecodeExtentMatchesPlannerAndFullRemainsNative]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testPreviewDecodeExtentMatchesPlannerAndFullRemainsNative]' passed (0.087 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testPreviewDecodeWithZeroDimensionNativeExtentUsesFallbackAndRejectsCorruptInput]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testPreviewDecodeWithZeroDimensionNativeExtentUsesFallbackAndRejectsCorruptInput]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testPreviewLargerThanTheSourceDoesNotUpscale]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testPreviewLargerThanTheSourceDoesNotUpscale]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testPreviewScaleFitsTheBoxAndFullDoesNot]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testPreviewScaleFitsTheBoxAndFullDoesNot]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testRaisingKelvinCoolsTheImage]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testRaisingKelvinCoolsTheImage]' passed (0.004 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testRAWRenderingCanIgnoreLegacyPostRenderWhiteBalance]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testRAWRenderingCanIgnoreLegacyPostRenderWhiteBalance]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testRedToneCurveChangesOnlyRedChannel]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testRedToneCurveChangesOnlyRedChannel]' passed (0.012 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testRetouchRecipeStaysInOrientedSourceSpaceAcrossGeometry]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testRetouchSpotChangesRenderedPixelsAndNeutralRetouchIsIdentity]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testRetouchSpotChangesRenderedPixelsAndNeutralRetouchIsIdentity]' passed (0.018 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testSharpeningIncreasesFineDetailMonotonicallyAndNeutralPreservesPixels]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testSharpeningIncreasesFineDetailMonotonicallyAndNeutralPreservesPixels]' passed (0.011 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testSkippingIdentityNodesChangesNothing]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testSkippingIdentityNodesChangesNothing]' passed (0.015 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testStandardRenderingUsesThePostRenderWhiteBalanceFallback]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testStandardRenderingUsesThePostRenderWhiteBalanceFallback]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testTheDownscaleHappensBeforeTheAdjustments]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testTheDownscaleHappensBeforeTheAdjustments]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testTintDirectionMatchesGreenToMagentaTrack]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testTintDirectionMatchesGreenToMagentaTrack]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testToneCurveRenderIsUnchangedAtItsIdentity]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testToneCurveRenderIsUnchangedAtItsIdentity]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testUndecodableSourceReturnsNil]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testUndecodableSourceReturnsNil]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testUnresolvedLUTRendersUngradedRatherThanFailing]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testUnresolvedLUTRendersUngradedRatherThanFailing]' passed (0.006 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testWhitesAndBlacksTargetOppositeEndsWithAUsefulRolloff]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testWhitesAndBlacksTargetOppositeEndsWithAUsefulRolloff]' passed (0.003 seconds).
Test Case '-[KromoraKitTests.RenderPipelineTests testWorkingSpaceReachesTheCube]' started.
Test Case '-[KromoraKitTests.RenderPipelineTests testWorkingSpaceReachesTheCube]' passed (0.011 seconds).
Test Suite 'RenderPipelineTests' passed at 2026-10-02 19:36:53.985.
	 Executed 48 tests, with 0 failures (0 unexpected) in 0.588 (0.591) seconds
Test Suite 'RenderStackTests' started at 2026-10-02 19:36:53.985.
Test Case '-[KromoraKitTests.RenderStackTests testOnlyNamedTypesInTheModuleOwnACIContext]' started.
Test Case '-[KromoraKitTests.RenderStackTests testOnlyNamedTypesInTheModuleOwnACIContext]' passed (0.117 seconds).
Test Case '-[KromoraKitTests.RenderStackTests testThumbnailsStayOutOfCoreImage]' started.
Test Case '-[KromoraKitTests.RenderStackTests testThumbnailsStayOutOfCoreImage]' passed (0.001 seconds).
Test Suite 'RenderStackTests' passed at 2026-10-02 19:36:54.103.
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.118 (0.118) seconds
Test Suite 'ThumbnailSwitchLifecycleTests' started at 2026-10-02 19:36:54.103.
Test Case '-[KromoraKitTests.ThumbnailSwitchLifecycleTests testFilmstripAndGridPublishCropAwareSettledThumbnails]' started.
Test Case '-[KromoraKitTests.ThumbnailSwitchLifecycleTests testFilmstripAndGridPublishCropAwareSettledThumbnails]' passed (2.013 seconds).
Test Suite 'ThumbnailSwitchLifecycleTests' passed at 2026-10-02 19:36:56.116.
	 Executed 1 test, with 0 failures (0 unexpected) in 2.013 (2.013) seconds
Test Suite 'ThumbnailTests' started at 2026-10-02 19:36:56.116.
Test Case '-[KromoraKitTests.ThumbnailTests testARefreshThatReordersNeverMislabelsAThumbnail]' started.
Test Case '-[KromoraKitTests.ThumbnailTests testARefreshThatReordersNeverMislabelsAThumbnail]' passed (0.014 seconds).
Test Case '-[KromoraKitTests.ThumbnailTests testBudgetEnforcementTest]' started.
Test Case '-[KromoraKitTests.ThumbnailTests testBudgetEnforcementTest]' passed (0.155 seconds).
Test Case '-[KromoraKitTests.ThumbnailTests testGenerateBakesEXIFOrientation]' started.
Test Case '-[KromoraKitTests.ThumbnailTests testGenerateBakesEXIFOrientation]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ThumbnailTests testGenerateCapsTheLongEdge]' started.
Test Case '-[KromoraKitTests.ThumbnailTests testGenerateCapsTheLongEdge]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.ThumbnailTests testGenerateReturnsNilForUndecodableInput]' started.
Test Case '-[KromoraKitTests.ThumbnailTests testGenerateReturnsNilForUndecodableInput]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ThumbnailTests testImportingFromDataAlsoProducesThumbnails]' started.
Test Case '-[KromoraKitTests.ThumbnailTests testImportingFromDataAlsoProducesThumbnails]' passed (0.012 seconds).
Test Case '-[KromoraKitTests.ThumbnailTests testNoCodecOnHitTest]' started.
Test Case '-[KromoraKitTests.ThumbnailTests testNoCodecOnHitTest]' passed (0.005 seconds).
Test Case '-[KromoraKitTests.ThumbnailTests testOrientationTest]' started.
Test Case '-[KromoraKitTests.ThumbnailTests testOrientationTest]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.ThumbnailTests testOriginalThumbnailLookupRecordsExactlyOneEntryForMissingAndCorruptFrames]' started.
Test Case '-[KromoraKitTests.ThumbnailTests testOriginalThumbnailLookupRecordsExactlyOneEntryForMissingAndCorruptFrames]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.ThumbnailTests testScanningAFolderFillsInThumbnails]' started.
Test Case '-[KromoraKitTests.ThumbnailTests testScanningAFolderFillsInThumbnails]' passed (0.013 seconds).
Test Case '-[KromoraKitTests.ThumbnailTests testTheDataAndURLEntryPointsAgree]' started.
Test Case '-[KromoraKitTests.ThumbnailTests testTheDataAndURLEntryPointsAgree]' passed (0.003 seconds).
Test Suite 'ThumbnailTests' passed at 2026-10-02 19:36:56.334.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.216 (0.217) seconds
Test Suite 'VisionSemanticMaskProviderTests' started at 2026-10-02 19:36:56.334.
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testCachedPersonMaskIsReturnedWithoutGatingSignals]' started.
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testCachedPersonMaskIsReturnedWithoutGatingSignals]' passed (0.002 seconds).
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testForegroundUnionNormalizesDifferingInstanceResolutionsToAnalysisImage]' started.
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testForegroundUnionNormalizesDifferingInstanceResolutionsToAnalysisImage]' passed (0.011 seconds).
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testNoFaceIsReportedAsTypedFailureForValidImage]' started.
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testNoFaceIsReportedAsTypedFailureForValidImage]' passed (0.022 seconds).
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testNoForegroundIsEmptyAndBackgroundIsItsComplementThroughCoordinator]' started.
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testNoForegroundIsEmptyAndBackgroundIsItsComplementThroughCoordinator]' passed (0.042 seconds).
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testPartialForegroundBackgroundIsPixelComplementOnAnalysisGrid]' started.
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testPartialForegroundBackgroundIsPixelComplementOnAnalysisGrid]' passed (0.008 seconds).
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testPersonSegmentationIsGatedWithoutCachedSignals]' started.
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testPersonSegmentationIsGatedWithoutCachedSignals]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testProviderCanConstructAnActorLocalRequestHandler]' started.
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testProviderCanConstructAnActorLocalRequestHandler]' passed (0.001 seconds).
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testStillUnsupportedKindsUseTypedErrors]' started.
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testStillUnsupportedKindsUseTypedErrors]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testSubjectSelectionKeepsNonRectangularSegmentedInstanceShape]' started.
Test Case '-[KromoraKitTests.VisionSemanticMaskProviderTests testSubjectSelectionKeepsNonRectangularSegmentedInstanceShape]' passed (0.000 seconds).
Test Suite 'VisionSemanticMaskProviderTests' passed at 2026-10-02 19:36:56.419.
	 Executed 9 tests, with 0 failures (0 unexpected) in 0.085 (0.085) seconds
Test Suite 'WorkingSpaceTests' started at 2026-10-02 19:36:56.419.
Test Case '-[KromoraKitTests.WorkingSpaceTests testCurrentIsSRGB]' started.
Test Case '-[KromoraKitTests.WorkingSpaceTests testCurrentIsSRGB]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.WorkingSpaceTests testDeriveFitSpaceEqualsApplySpace]' started.
Test Case '-[KromoraKitTests.WorkingSpaceTests testDeriveFitSpaceEqualsApplySpace]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.WorkingSpaceTests testEveryCaseResolvesToARealColorSpace]' started.
Test Case '-[KromoraKitTests.WorkingSpaceTests testEveryCaseResolvesToARealColorSpace]' passed (0.000 seconds).
Test Case '-[KromoraKitTests.WorkingSpaceTests testWorkingSpaceReachesTheLUTInterpolation]' started.
Test Case '-[KromoraKitTests.WorkingSpaceTests testWorkingSpaceReachesTheLUTInterpolation]' passed (0.003 seconds).
Test Suite 'WorkingSpaceTests' passed at 2026-10-02 19:36:56.423.
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.004 (0.004) seconds
Test Suite 'KromoraKitTests.xctest' failed at 2026-10-02 19:36:56.423.
	 Executed 464 tests, with 15 failures (0 unexpected) in 206.391 (206.421) seconds
Test Suite 'Selected tests' failed at 2026-10-02 19:36:56.423.
	 Executed 464 tests, with 15 failures (0 unexpected) in 206.391 (206.422) seconds
LIBRARY_PROJECTION_PROFILE items=1000 first_ms=0.8 repeated_ms=1.4 rebuilds=1
LIBRARY_PROJECTION_PROFILE items=10000 first_ms=8.5 repeated_ms=17.3 rebuilds=1
Note: Some test targets reported failures:
  - KromoraKitTests (XCTest) failed (464 tests, 14 failures, all in RelaunchParityTests). Remaining failures are the replaced-source confirmed-frame count (2 vs 1) and duplicate/premature relaunch presentation, tracked by KRMA-765 and KRMA-766. No display captures were run.

## Agent log

- 2026-10-02T23:06:39.965Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Placeholder writes leave store unchanged and increment skip counter; real identity persists (pass) — Store-boundary guards and tests present; focused suites pass.
- [x] Pre-seeded directory: placeholder read is a miss and deletes exactly that file/pointer; real frames untouched (pass) — removeIfSameFile / removeIfSameRecord guard against concurrent replacement.
- [ ] Sweep removes all placeholder frames across idle ticks, bounded per tick, cancelled by user-visible request (fail) — Test drives sweepPlaceholderFrames manually, but in production the sweep is scheduled only once at index/store open and every read/write/invalidate calls cancelPlaceholderSweep(), setting the task to nil with nothing to reschedule it (didLoadIndex short-circuits loadIndex). The first grid read after launch permanently stops the sweep, so remaining placeholder frames are only cleared by direct reads. Not wired to a scheduler/idle tick or priority seam as the ticket asked.
- [ ] Source safety test: replaced source bytes make old frame .unusable and not presented/used to skip a render (fail) — RelaunchParityTests testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce still fails at line 302: confirmedFrameCount is 2, expected 1.
- [x] Corrupt or truncated frames degrade to plain miss (pass) — fast lane green per implementer; discardIfDamaged path unchanged.
- [ ] RelaunchParityTests assertions lose their XCTExpectFailure wrapper (fail) — Wrappers were removed but the assertions still fail (distinctFrameCount 2 vs 1, extra preview render, original thumbnail published before confirmation). The store guards do not address provisional-frame admission, which is the actual cause.
- [ ] fast and serial lanes pass (fail) — scripts/ci-tests.sh serial: 464 tests, 14 failures, all in RelaunchParityTests. Reproduced with swift test --no-parallel --filter RelaunchParityTests.
Checks run:
- scripts/ci-tests.sh serial (FAILED, 14 failures in RelaunchParityTests)
- swift test --no-parallel --filter RelaunchParityTests (FAILED, 15 failure lines incl. 1 expected)
- code review of commit 0c51841
Findings:
- Serial lane red: unwrapped RelaunchParityTests assertions fail because provisional frame admission is not fixed by the store guards.
- Placeholder sweep is cancelled by the first store access and never rescheduled, so it does not meet the lazy-sweep requirement in production.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MURKJ1H85TH6I9U2
Summary: Serial lane fails (14 RelaunchParityTests failures after XCTExpectFailure wrappers removed) and the placeholder sweep is cancelled by the first store access and never rescheduled. Needs another implementation pass.

- 2026-10-02T23:15:54.324Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Placeholder writes leave store unchanged and increment skip counter; real identity persists (pass) — Store-boundary guards and tests present.
- [x] Pre-seeded directory: placeholder read is a miss and deletes exactly that file/pointer; real frames untouched (pass) — Guarded same-file/same-record removal.
- [ ] Sweep removes all placeholder frames across idle ticks, bounded per tick, cancelled by user-visible request (fail) — Sweep is scheduled once at store open and cancelled by every read/write/invalidate with no rescheduling, so production never completes it.
- [ ] Source safety test: replaced source bytes make old frame unusable and not presented/used to skip a render (fail) — RelaunchParityTests testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce still fails at line 302 (2 vs 1).
- [x] Corrupt or truncated frames degrade to plain miss (pass) — Existing path unchanged.
- [ ] RelaunchParityTests assertions lose their XCTExpectFailure wrapper (fail) — Wrappers removed but assertions fail; provisional-frame admission is not fixed by the store guards.
- [ ] fast and serial lanes pass (fail) — Reproduced on unchanged commit 0c51841: swift test --no-parallel --filter RelaunchParityTests gives 15 failure lines (14 unexpected).
Checks run:
- swift test --no-parallel --filter RelaunchParityTests (FAILED, reproduced on 0c51841)
- code review of commit 0c51841
Findings:
- RelaunchParityTests fail because provisional frame admission is unaddressed by the store guards.
- Placeholder sweep is cancelled by first store access and never rescheduled.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MURKZXXV862YAXBX
Summary: RelaunchParityTests still fail (14 unexpected) on 0c51841 and the placeholder sweep is cancelled by the first store access and never rescheduled. Needs another implementation pass.

- 2026-10-02T23:17:44.488Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Placeholder writes leave store unchanged and increment skip counter; real identity persists (pass) — Store-boundary guards and tests are present; focused suites pass.
- [x] Pre-seeded directory: placeholder read is a miss and deletes exactly that file or pointer; real frames remain untouched (pass) — Guarded cleanup uses removeIfSameFile and removeIfSameRecord.
- [ ] Sweep removes all placeholder frames across idle ticks, bounded per tick, cancelled by user-visible request (fail) — Production schedules the sweep only once at index/store open. Store accesses cancel it, and didLoadIndex prevents the sweep from being rescheduled. The sweep is also not wired to an idle scheduler or priority seam.
- [ ] Replaced source bytes make the old frame unusable and prevent presentation or render skipping (fail) — RelaunchParityTests.testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce fails: confirmedFrameCount is 2, expected 1. Edit-path follow-up is tracked in KRMA-766.
- [x] Corrupt or truncated frames degrade to a plain miss with no throw (pass) — Fast lane passed; discardIfDamaged path is unchanged.
- [ ] RelaunchParityTests assertions that depended on placeholder frames lose their expected-failure wrappers and pass (fail) — Unwrapped assertions still fail on extra frames/renders and original-thumbnail publication. Library relaunch presentation is tracked in KRMA-765; Edit relaunch behavior is tracked in KRMA-766.
- [ ] Fast and serial lanes pass (fail) — Fast passed (1485 tests); serial failed with 14 RelaunchParityTests failures.
Checks run:
- Focused preview and thumbnail suites: 23 tests passed
- scripts/ci-tests.sh fast: 1485 tests passed
- scripts/ci-tests.sh serial: failed, 14 RelaunchParityTests failures
- swift test --no-parallel --filter RelaunchParityTests: failed
- Code review of commit 0c51841
Findings:
- Placeholder sweep is cancelled by the first store access and never rescheduled; no production idle-tick or priority integration exists.
- Source-replacement and relaunch presentation assertions still fail; related Edit and Library follow-up work is already tracked by KRMA-766 and KRMA-765.
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: unknown
Summary: Verification remains blocked: the production placeholder sweep stops after first store access and is never rescheduled. Urgent child tracks scheduler integration. Related source-replacement and relaunch-presentation failures remain in KRMA-766 and KRMA-765.

- 2026-10-02T23:49:24.462Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Placeholder writes leave store unchanged and increment skip counter; real identity persists (pass) — Store-boundary guards and tests present.
- [x] Pre-seeded directory: placeholder read is a miss and deletes exactly that file/pointer; real frames untouched (pass) — Guarded removal via removeIfSameFile/removeIfSameRecord.
- [x] Sweep removes all placeholder frames across idle ticks, bounded per tick, cancelled by user-visible request (pass) — Fixed by KRMA-777 (da53377, e84454d): scheduler-backed, background priority, 8 per tick, not permanently disabled.
- [ ] Replaced source bytes make old frame unusable and not presented/used to skip a render (fail) — RelaunchParityTests testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce still fails at line 302: confirmedFrameCount 2, expected 1. Edit-path work tracked in KRMA-766.
- [x] Corrupt or truncated frames degrade to a plain miss with no throw (pass) — Existing path unchanged.
- [ ] RelaunchParityTests assertions lose their XCTExpectFailure wrapper and pass (fail) — Unwrapped assertions still fail (extra frames/renders, original thumbnail published before confirmation). Tracked by KRMA-765 and KRMA-766.
- [ ] Fast and serial lanes pass (fail) — Fast passed per KRMA-777 report; serial red solely from RelaunchParityTests (15 failure lines).
Checks run:
- swift test --no-parallel --filter RelaunchParityTests (FAILED: 5 tests, 15 failures at HEAD e84454d)
- Review of KRMA-777 sweep fix and commit 0c51841
Findings:
- Remaining failures are provisional-frame admission on relaunch, not store guards; owned by KRMA-765 and KRMA-766, which depend on KRMA-764 so cannot be linked as its dependencies.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MURM6R2AAF4G1FI1
Summary: Sweep is now fixed by KRMA-777, but RelaunchParityTests still fail (15 assertions, serial lane red). The cause is provisional-frame admission on relaunch, tracked by KRMA-765 (Library) and KRMA-766 (Edit). Those depend on KRMA-764, so they could not be linked as its dependencies without a cycle.

- 2026-10-03T00:51:33.211Z: Verification report
Verdict: BLOCKER
Acceptance criteria:
- [x] Placeholder writes leave store unchanged and increment skip counter; real identity persists (pass) — Store-boundary guards and tests present.
- [x] Pre-seeded directory: placeholder read is a miss and deletes exactly that file/pointer; real frames untouched (pass) — Guarded same-file/same-record removal.
- [x] Sweep removes placeholder frames across idle ticks, bounded, cancelled by user-visible request (pass) — Fixed by KRMA-777 (da53377, e84454d).
- [ ] Replaced source bytes make old frame unusable and not presented/used to skip a render (fail) — RelaunchParityTests testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce fails at line 302: confirmedFrameCount 2, expected 1. Edit-path work in KRMA-766.
- [x] Corrupt or truncated frames degrade to a plain miss with no throw (pass) — Existing path unchanged.
- [ ] RelaunchParityTests assertions lose their XCTExpectFailure wrapper and pass (fail) — Lines 295-542 are unwrapped and still fail (extra frames/renders, original thumbnail published before confirmation). Tracked by KRMA-765/KRMA-766, which are ready.
- [ ] Fast and serial lanes pass (fail) — Serial red solely from RelaunchParityTests (15 failure lines); fast passed per prior reports.
Checks run:
- swift test --no-parallel --filter RelaunchParityTests (FAILED: 5 tests, 15 failures at HEAD e84454d; unchanged since prior verification)
Findings:
- Store guards, guarded cleanup and sweep are correct; remaining failures are provisional-frame admission on relaunch, owned by KRMA-765 and KRMA-766.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUROEOUUJUARZUFO
Summary: Store guards and sweep are verified, but RelaunchParityTests still fail (15 assertions, serial lane red) from provisional-frame admission tracked in KRMA-765/KRMA-766. Needs another pass.

- 2026-10-03T12:30:48.498Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Placeholder writes leave store unchanged and increment skip counter; real identity persists (pass) — Store-boundary guards and tests present (0c51841).
- [x] Pre-seeded directory: placeholder read is a miss and deletes exactly that file/pointer; real frames untouched (pass) — Guarded same-file/same-record removal.
- [x] Sweep removes placeholder frames across idle ticks, bounded, cancelled by user-visible request (pass) — Scheduler-backed, 8 per tick, not re-run after completion (KRMA-777: da53377, e84454d).
- [x] Replaced source bytes make old frame unusable and not presented/used to skip a render (pass) — testReplacedSourceBytesBetweenSessionsInvalidatePersistedFrameOnce now passes; Edit-path fix landed in KRMA-766 (c1328d9).
- [x] Corrupt or truncated frames degrade to a plain miss with no throw (pass) — Existing path unchanged; fault-matrix tests green.
- [x] RelaunchParityTests assertions lose their XCTExpectFailure wrapper and pass (pass) — No XCTExpectFailure remains in RelaunchParityTests.swift; 10 tests, 0 failures. Library/Edit fixes landed in KRMA-765 (ce6ab4d) and KRMA-766 (c1328d9).
- [x] Fast and serial lanes pass (pass) — fast exit 0 (1511 tests); serial 469 tests, 0 failures.
Checks run:
- swift test --no-parallel --filter RelaunchParityTests (10 tests, 0 failures at HEAD 053e7ae)
- scripts/ci-tests.sh serial (469 tests, 0 failures)
- scripts/ci-tests.sh fast (exit 0, 1511 tests)
- grep XCTExpectFailure in RelaunchParityTests.swift (none)
Findings:
- Earlier blocker verdicts were stale: they were recorded at e84454d, before KRMA-765 and KRMA-766 landed. Both dependencies are done and all criteria now hold.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: unknown
Summary: Re-verified at 053e7ae: all acceptance criteria pass. Prior blockers (RelaunchParityTests failures) were resolved by KRMA-765 (ce6ab4d) and KRMA-766 (c1328d9). RelaunchParityTests 10/10, serial 469/0 failures, fast green; no XCTExpectFailure remains.
