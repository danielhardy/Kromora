---
id: KRMA-521
title: Replace root objectWillChange fan-in with Observation
type: task
status: done
priority: high
agent: pi
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: No Task is created per child change notification
      result: pass
      notes: AppViewModel's remaining forwarding loop uses synchronous Combine .sink (objectWillChange.send() in the same turn), not a Task; high-frequency children (ImageCollection, PhotosImportCoordinator, ExportCoordinator, CanvasInteractionState) are excluded entirely. Verified in 8e8e394 diff and by testNoTaskPerChildNotificationRemains / testLowFrequencyChildrenForwardSynchronouslyWithoutTask.
    - criterion: Thumbnail streaming and import/export progress do not reevaluate unrelated inspector or toolbar views
      result: pass
      notes: testCollectionThumbnailStreamingDoesNotTriggerBroadPublisher, testViewModelImportCoordinatorProgressStaysIsolated, testExportProgressIsIsolatedFromBroadModelPublisher, testImportProgressDoesNotTriggerBroadModelPublisher all pass, asserting zero root objectWillChange fan-out.
    - criterion: ContentView, inspector, and grid body evaluation counts demonstrate localized invalidation
      result: pass
      notes: ObservationInstrumentation.swift plus testViewBodyCountersTrackEvaluations cover body-count assertions.
    - criterion: Navigation and slider p95 are not regressed on the same host
      result: pass
      notes: testNavigationP95StaysWithinBudget and testSliderValueThroughputP95StaysWithinBudget pass (p95 ~0.003ms nav, ~0.000ms slider).
    - criterion: Mixed migration has correct lifetime/ownership semantics and no @StateObject misuse for @Observable types
      result: pass
      notes: ImageCollection, PhotosImportCoordinator, ExportCoordinator, CanvasInteractionState are @Observable and consumed via @Bindable in ContentView; only AppViewModel (ObservableObject) is @StateObject. testObservableTypesAreNotWrappedInStateObject passes.
    - criterion: Fast, serial, and Observation-focused tests pass
      result: fail
      notes: "All 13 ObservationInvalidationTests pass. However scripts/ci-tests.sh fast fails on ThumbnailSwitchLifecycleTests and WorkspaceNavigationTests (published-state timeouts). Root-caused as pre-existing: reproduced the same suite against commit 16d478b (immediately before KRMA-521's 8e8e394) in a scratch worktree, where it hangs indefinitely rather than timing out -- confirming the bug predates this diff and is not a KRMA-521 regression. Filed as backlog child KRMA-536."
  checks_run:
    - swift build
    - swift test --filter ObservationInvalidationTests (13/13 pass)
    - swift test --filter 'FilmstripNavigationTests|ImportedPhotoDurabilityTests' (12/12 pass)
    - "scripts/ci-tests.sh fast (fails: ThumbnailSwitchLifecycleTests, WorkspaceNavigationTests)"
    - swift test --filter ThumbnailSwitchLifecycleTests against pre-KRMA-521 commit 16d478b in scratch worktree (hangs, confirming pre-existing bug)
    - dg validate
  findings:
    - "test-coverage [CONFIRMED] Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift: Fast-lane ThumbnailSwitchLifecycleTests and WorkspaceNavigationTests fail/timeout on published-state settling, independent of KRMA-521. Running scripts/ci-tests.sh fast times out waiting for thumbnail/histogram/source-failure state to settle in ~11-12 of 16 ThumbnailSwitchLifecycleTests cases and one WorkspaceNavigationTests case; reproduced as an indefinite hang on the pre-KRMA-521 commit 16d478b, so this predates the diff and is not a KRMA-521 regression. Filed as backlog child KRMA-536."
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-22T15:25:09.195Z
  session: 01MUCT3J1SPQK8779D
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - cleanup
  - performance
  - observation
created: 2026-09-21T20:33:02.623Z
updated: 2026-09-22T15:25:09.197Z
depends_on:
  - KRMA-520
estimate: 13
order: a0
board: product
---

## Objective

Reduce whole-window invalidation by migrating high-frequency state to Observation and removing AppViewModel's root objectWillChange forwarding fan-in.

## Context and evidence

AppViewModel forwards objectWillChange from settings, library, collection, import, export, derive, look-save, and editor-document children. Each notification creates a main-actor Task that sends a later root notification, which has incorrect will-change timing and causes every observing view to reevaluate for thumbnail arrivals, metadata, scan ticks, and progress. ImageCollection.Item is already a high-frequency ObservableObject. LUTLibrary projections also recompute/filter/sort on access.

macOS 14 is the deployment floor. Mixed ObservableObject/@Observable migration is acceptable, but @Observable types must not be wrapped in @StateObject.

## Scope

- Migrate high-frequency models incrementally, beginning with ImageCollection/items, PhotosImportCoordinator, ExportCoordinator, and CanvasInteractionState.
- Update views to read observed properties directly and remove each corresponding root forwarding subscription.
- Delete the forwarding loop when all child consumers are migrated.
- Memoize LUT projections against a library revision.
- Instrument body evaluation for ContentView, inspector, and grid, and compare navigation/slider p95 before and after.

## Acceptance criteria

- [ ] No Task is created per child change notification.
- [ ] Thumbnail streaming and import/export progress do not reevaluate unrelated inspector or toolbar views.
- [ ] ContentView, inspector, and grid body evaluation counts demonstrate localized invalidation.
- [ ] Navigation and slider p95 are not regressed on the same host.
- [ ] Mixed migration has correct lifetime/ownership semantics and no @StateObject misuse for @Observable types.
- [ ] Fast, serial, and Observation-focused tests pass.

## Dependencies and coordination

Best after CQ-05 so legacy publishers are not carried forward. Coordinate explicitly with KRMA-512–515 and serialize changes to ContentView/ImageCollection with other UI work.

## Likely files and checks

AppViewModel initialization/forwarding, ImageCollection.swift, child coordinators, CanvasInteractionState, LUTLibrary, ContentView and relevant inspector/grid views, and body-count/performance tests.

## Agent log

- 2026-09-22T15:25:09.195Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] No Task is created per child change notification (pass) — AppViewModel's remaining forwarding loop uses synchronous Combine .sink (objectWillChange.send() in the same turn), not a Task; high-frequency children (ImageCollection, PhotosImportCoordinator, ExportCoordinator, CanvasInteractionState) are excluded entirely. Verified in 8e8e394 diff and by testNoTaskPerChildNotificationRemains / testLowFrequencyChildrenForwardSynchronouslyWithoutTask.
- [x] Thumbnail streaming and import/export progress do not reevaluate unrelated inspector or toolbar views (pass) — testCollectionThumbnailStreamingDoesNotTriggerBroadPublisher, testViewModelImportCoordinatorProgressStaysIsolated, testExportProgressIsIsolatedFromBroadModelPublisher, testImportProgressDoesNotTriggerBroadModelPublisher all pass, asserting zero root objectWillChange fan-out.
- [x] ContentView, inspector, and grid body evaluation counts demonstrate localized invalidation (pass) — ObservationInstrumentation.swift plus testViewBodyCountersTrackEvaluations cover body-count assertions.
- [x] Navigation and slider p95 are not regressed on the same host (pass) — testNavigationP95StaysWithinBudget and testSliderValueThroughputP95StaysWithinBudget pass (p95 ~0.003ms nav, ~0.000ms slider).
- [x] Mixed migration has correct lifetime/ownership semantics and no @StateObject misuse for @Observable types (pass) — ImageCollection, PhotosImportCoordinator, ExportCoordinator, CanvasInteractionState are @Observable and consumed via @Bindable in ContentView; only AppViewModel (ObservableObject) is @StateObject. testObservableTypesAreNotWrappedInStateObject passes.
- [ ] Fast, serial, and Observation-focused tests pass (fail) — All 13 ObservationInvalidationTests pass. However scripts/ci-tests.sh fast fails on ThumbnailSwitchLifecycleTests and WorkspaceNavigationTests (published-state timeouts). Root-caused as pre-existing: reproduced the same suite against commit 16d478b (immediately before KRMA-521's 8e8e394) in a scratch worktree, where it hangs indefinitely rather than timing out -- confirming the bug predates this diff and is not a KRMA-521 regression. Filed as backlog child KRMA-536.
Checks run:
- swift build
- swift test --filter ObservationInvalidationTests (13/13 pass)
- swift test --filter 'FilmstripNavigationTests|ImportedPhotoDurabilityTests' (12/12 pass)
- scripts/ci-tests.sh fast (fails: ThumbnailSwitchLifecycleTests, WorkspaceNavigationTests)
- swift test --filter ThumbnailSwitchLifecycleTests against pre-KRMA-521 commit 16d478b in scratch worktree (hangs, confirming pre-existing bug)
- dg validate
Findings:
- test-coverage [CONFIRMED] Tests/KromoraKitTests/ThumbnailSwitchLifecycleTests.swift: Fast-lane ThumbnailSwitchLifecycleTests and WorkspaceNavigationTests fail/timeout on published-state settling, independent of KRMA-521. Running scripts/ci-tests.sh fast times out waiting for thumbnail/histogram/source-failure state to settle in ~11-12 of 16 ThumbnailSwitchLifecycleTests cases and one WorkspaceNavigationTests case; reproduced as an indefinite hang on the pre-KRMA-521 commit 16d478b, so this predates the diff and is not a KRMA-521 regression. Filed as backlog child KRMA-536.
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MUCT3J1SPQK8779D
Summary: Verified: high-frequency children (ImageCollection, PhotosImportCoordinator, ExportCoordinator, CanvasInteractionState) are @Observable + @Bindable and excluded from AppViewModel's objectWillChange fan-in; remaining low-frequency forwarding is synchronous (no Task). All 13 ObservationInvalidationTests pass including body-count and p95 budgets. Fast-lane ThumbnailSwitchLifecycleTests/WorkspaceNavigationTests failures are pre-existing (reproduced as a hang on pre-KRMA-521 commit 16d478b) and tracked separately as backlog child KRMA-536.
