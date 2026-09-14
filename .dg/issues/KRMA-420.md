---
id: KRMA-420
title: Stabilize Auto adjustment loading and failure state transitions
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Auto analysis publishes its own loading/progress state immediately and does not borrow or overwrite histogram loading state.
      result: pass
      notes: AppViewModel publishes .analyzing and autoAdjustmentProgress=0 synchronously before starting the task; all later phase progress is owned by Auto, while isHistogramLoading remains controlled only by the Info histogram workflow. StatusBar renders the determinate Auto progress.
    - criterion: Auto failure completion is delivered deterministically and leaves both Auto and histogram out of loading states.
      result: pass
      notes: The failure regression uses a unique analysis cache and no-mask/no-scene coordinator, waits for the histogram request and nil completion events, then joins waitForAutoAdjustmentCompletion before asserting failed state, nil Auto progress, and false histogram loading.
    - criterion: Cancellation, success, no-op, and failure paths remain distinct and do not publish stale state.
      result: pass
      notes: Centralized publishAutoAdjustmentState clears progress for terminal states; existing cancellation, success, repeated no-op, supersession, and navigation coverage remains green.
    - criterion: Tests use explicit synchronization at the relevant coordinator milestones rather than arbitrary sleeps or polling.
      result: pass
      notes: Auto integration tests now synchronize on FakeRenderEngine histogram request/completion events and AppViewModel Auto task completion; the former completion sleeps/polling loops were removed from those paths.
    - criterion: Focused Auto tests pass repeatedly, and the full serial suite no longer reports these failures.
      result: pass
      notes: The two named tests passed in five consecutive runs; AutoAdjustmentTests passed 12/12; neighboring Auto suites passed 90/90; scripts/ci-tests.sh serial passed 375/375.
  checks_run:
    - swift test --no-parallel --filter AutoAdjustmentTests — 12/12 pass
    - five consecutive focused runs of the two named tests — 10/10 executions pass
    - swift test --no-parallel --filter AutoEnhancementCoordinatorTests|AutoEnhancementResultTests|AutoCandidateEvaluationTests|AutoEnhancementPolicyTests|AutoLightEngineTests|AutoRegionalCorrectionsTests|ContentAwareAutoEngineTests — 90/90 pass
    - scripts/ci-tests.sh serial — 375/375 pass
    - scripts/ci-tests.sh fast — Auto tests pass; lane otherwise reproduces four unrelated parallel failures in ComparisonModeTests, ExportCoordinatorTests, LUTWorkflowTests, and MaskingWorkspaceTests
    - dg validate --json — OK with pre-existing model/context warnings
    - git diff --check — pass
  findings:
    - "The required fast lane reproduced four unrelated parallel-environment failures on both runs: ComparisonModeTests/testLateBaselineFromPreviousPhotoCannotPublish, ExportCoordinatorTests/testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals, LUTWorkflowTests/testLUTSurvivesNavigationAndRelaunchForItsPhoto, and MaskingWorkspaceTests/testInfoAnalysisMaskCreatesAndReusesTheDemonstratedSemanticMask (including temporary SQLite teardown I/O errors). The Auto tests passed in both fast runs and the complete serial lane passed."
  fixes:
    - Added independent determinate Auto progress publication and centralized state/progress terminal transitions in AppViewModel.
    - Updated StatusBar to display Auto progress when available.
    - Replaced Auto integration polling/sleeps with explicit FakeRenderEngine events and task completion; isolated the legacy histogram tests from shared PhotoAnalysis cache/Vision timing.
  verification_commits:
    - df5a113
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-13T16:16:52.389Z
  session: 01MU00ACV5F6WSAM1H
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - testing
  - async
  - auto
created: 2026-09-13T15:49:21.831Z
updated: 2026-09-13T16:16:52.391Z
order: zzzzzx
board: product
commits:
  - df5a113
---

## Objective

Make Auto adjustment loading, progress, and failure transitions deterministic and correctly isolated from histogram state.

## Evidence

The full serial run on 2026-09-13 reported failures in:
- AutoAdjustmentTests/testAnalysisShowsProgressWithoutBorrowingHistogramLoadingState
- AutoAdjustmentTests/testFailureLeavesAutoAndHistogramOutOfLoadingState

The first test observed a missing loading state and nil progress where Optional(0.0) was expected. The second timed out waiting for the Auto failure state.

## Acceptance criteria

- Auto analysis publishes its own loading/progress state immediately and does not borrow or overwrite histogram loading state.
- Auto failure completion is delivered deterministically and leaves both Auto and histogram out of loading states.
- Cancellation, success, no-op, and failure paths remain distinct and do not publish stale state.
- Tests use explicit synchronization at the relevant coordinator milestones rather than arbitrary sleeps or polling.
- Focused Auto tests pass repeatedly, and the full serial suite no longer reports these failures.

## Verification

Run the two named tests repeatedly, the neighboring AutoAdjustment/AutoEnhancement suites, then the full serial and fast CI lanes. Record any remaining intermittent failures separately.

## Agent log

- 2026-09-13T16:16:52.389Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Auto analysis publishes its own loading/progress state immediately and does not borrow or overwrite histogram loading state. (pass) — AppViewModel publishes .analyzing and autoAdjustmentProgress=0 synchronously before starting the task; all later phase progress is owned by Auto, while isHistogramLoading remains controlled only by the Info histogram workflow. StatusBar renders the determinate Auto progress.
- [x] Auto failure completion is delivered deterministically and leaves both Auto and histogram out of loading states. (pass) — The failure regression uses a unique analysis cache and no-mask/no-scene coordinator, waits for the histogram request and nil completion events, then joins waitForAutoAdjustmentCompletion before asserting failed state, nil Auto progress, and false histogram loading.
- [x] Cancellation, success, no-op, and failure paths remain distinct and do not publish stale state. (pass) — Centralized publishAutoAdjustmentState clears progress for terminal states; existing cancellation, success, repeated no-op, supersession, and navigation coverage remains green.
- [x] Tests use explicit synchronization at the relevant coordinator milestones rather than arbitrary sleeps or polling. (pass) — Auto integration tests now synchronize on FakeRenderEngine histogram request/completion events and AppViewModel Auto task completion; the former completion sleeps/polling loops were removed from those paths.
- [x] Focused Auto tests pass repeatedly, and the full serial suite no longer reports these failures. (pass) — The two named tests passed in five consecutive runs; AutoAdjustmentTests passed 12/12; neighboring Auto suites passed 90/90; scripts/ci-tests.sh serial passed 375/375.
Checks run:
- swift test --no-parallel --filter AutoAdjustmentTests — 12/12 pass
- five consecutive focused runs of the two named tests — 10/10 executions pass
- swift test --no-parallel --filter AutoEnhancementCoordinatorTests|AutoEnhancementResultTests|AutoCandidateEvaluationTests|AutoEnhancementPolicyTests|AutoLightEngineTests|AutoRegionalCorrectionsTests|ContentAwareAutoEngineTests — 90/90 pass
- scripts/ci-tests.sh serial — 375/375 pass
- scripts/ci-tests.sh fast — Auto tests pass; lane otherwise reproduces four unrelated parallel failures in ComparisonModeTests, ExportCoordinatorTests, LUTWorkflowTests, and MaskingWorkspaceTests
- dg validate --json — OK with pre-existing model/context warnings
- git diff --check — pass
Findings:
- The required fast lane reproduced four unrelated parallel-environment failures on both runs: ComparisonModeTests/testLateBaselineFromPreviousPhotoCannotPublish, ExportCoordinatorTests/testSelectedExportContainsExactlyTheLibrarySelectionAndUsesOriginals, LUTWorkflowTests/testLUTSurvivesNavigationAndRelaunchForItsPhoto, and MaskingWorkspaceTests/testInfoAnalysisMaskCreatesAndReusesTheDemonstratedSemanticMask (including temporary SQLite teardown I/O errors). The Auto tests passed in both fast runs and the complete serial lane passed.
Fixes:
- Added independent determinate Auto progress publication and centralized state/progress terminal transitions in AppViewModel.
- Updated StatusBar to display Auto progress when available.
- Replaced Auto integration polling/sleeps with explicit FakeRenderEngine events and task completion; isolated the legacy histogram tests from shared PhotoAnalysis cache/Vision timing.
Verification commits:
- df5a113
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MU00ACV5F6WSAM1H
Summary: Implemented deterministic Auto lifecycle state. Auto now publishes an independent determinate progress value from analyzing through applying and clears it on ready, cancellation, failure, supersession, navigation, and preview failure. The Auto tests now isolate the legacy histogram path from shared analysis cache state and synchronize on renderer events plus task completion. Focused Auto tests pass repeatedly; serial lane is fully green.
