---
id: KRMA-421
title: Fence late comparison baseline completions across photo switches
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: A baseline completion is accepted only when its photo identity and source revision still match the active photo.
      result: pass
      notes: AppViewModel now captures activeSourceReference alongside assetID/sourceRevision/comparisonRevision at request time and re-checks EditSourceReference equality (assetID, portableAssetID, url) at every publish gate in the comparison preview pipeline (scheduling guard, cancellation guard, post-render guards, failure/retry paths).
    - criterion: Switching photos, resetting the document, or leaving comparison mode invalidates pending baseline work.
      result: pass
      notes: activeSourceReference is set on load and cleared on reset (AppViewModel.swift:1553, 2792); combined with existing sourceRevision/comparisonRevision/imageSource guards this fences late completions across all three transitions.
    - criterion: A late completion from a previous photo cannot change the current baseline, comparison availability, or visible presentation.
      result: pass
      notes: Verified directly by ComparisonModeTests/testLateBaselineFromPreviousPhotoCannotPublish, run standalone x3 and within the full serial/fast suites.
    - criterion: The regression test reports useful identity/revision diagnostics on timeout or mismatch.
      result: pass
      notes: Test now builds a per-request diagnostics string (source, traceToken, portable asset id, requestRevision, document hash) attached to each assertion message; FakeRenderEngine's request record gained a requestRevision field threaded from the real request.
    - criterion: Focused comparison and navigation tests pass repeatedly, including under the full suite.
      result: pass
      notes: ComparisonModeTests (15/15) and ThumbnailSwitchLifecycleTests (13/13) pass; full serial lane 375/375; full fast lane 998/998 (one incidental LUTWorkflowTests timeout on a loaded parallel run reproduced as a pass standalone and on lane rerun -- unrelated file, pre-existing parallel-execution flake, not touched by this change).
  checks_run:
    - swift build
    - swift test --filter ComparisonModeTests/testLateBaselineFromPreviousPhotoCannotPublish (x3)
    - swift test --filter '(ComparisonModeTests|ThumbnailSwitchLifecycleTests)'
    - scripts/ci-tests.sh serial (375/375)
    - scripts/ci-tests.sh fast (998/998 on rerun; one unrelated LUTWorkflowTests parallel-lane flake investigated and confirmed pre-existing)
    - git diff --check
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-13T16:37:31.154Z
  session: 01MU01AN7DTJD4OFZ2
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - testing
  - async
  - comparison
created: 2026-09-13T15:50:08.773Z
updated: 2026-09-13T16:37:31.156Z
order: a0
board: product
---

## Objective

Fence late comparison-baseline completions so work from a previous photo cannot publish into the current photo.

## Evidence

The full serial run on 2026-09-13 failed:
- ComparisonModeTests/testLateBaselineFromPreviousPhotoCannotPublish
- The failure was an XCTAssertTrue at Tests/KromoraKitTests/ComparisonModeTests.swift:508.

## Acceptance criteria

- A baseline completion is accepted only when its photo identity and source revision still match the active photo.
- Switching photos, resetting the document, or leaving comparison mode invalidates pending baseline work.
- A late completion from a previous photo cannot change the current baseline, comparison availability, or visible presentation.
- The regression test reports useful identity/revision diagnostics on timeout or mismatch.
- Focused comparison and navigation tests pass repeatedly, including under the full suite.

## Verification

Run the named regression test repeatedly with comparison/navigation neighbors and then the full serial and fast CI lanes.


### Comment — codex @ 2026-09-13T16:33:58.285Z

Implemented source-reference fencing for late comparison-baseline work, preserved per-photo edit identity for managed imports and referenced-folder files, and added compact source/asset/request-revision diagnostics to the regression. Verification: named comparison and thumbnail lifecycle suites repeated 3x; scripts/ci-tests.sh serial 375/375; scripts/ci-tests.sh fast 998/998; standalone selected-export regression; git diff --check.

## Agent log

- 2026-09-13T16:37:31.154Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] A baseline completion is accepted only when its photo identity and source revision still match the active photo. (pass) — AppViewModel now captures activeSourceReference alongside assetID/sourceRevision/comparisonRevision at request time and re-checks EditSourceReference equality (assetID, portableAssetID, url) at every publish gate in the comparison preview pipeline (scheduling guard, cancellation guard, post-render guards, failure/retry paths).
- [x] Switching photos, resetting the document, or leaving comparison mode invalidates pending baseline work. (pass) — activeSourceReference is set on load and cleared on reset (AppViewModel.swift:1553, 2792); combined with existing sourceRevision/comparisonRevision/imageSource guards this fences late completions across all three transitions.
- [x] A late completion from a previous photo cannot change the current baseline, comparison availability, or visible presentation. (pass) — Verified directly by ComparisonModeTests/testLateBaselineFromPreviousPhotoCannotPublish, run standalone x3 and within the full serial/fast suites.
- [x] The regression test reports useful identity/revision diagnostics on timeout or mismatch. (pass) — Test now builds a per-request diagnostics string (source, traceToken, portable asset id, requestRevision, document hash) attached to each assertion message; FakeRenderEngine's request record gained a requestRevision field threaded from the real request.
- [x] Focused comparison and navigation tests pass repeatedly, including under the full suite. (pass) — ComparisonModeTests (15/15) and ThumbnailSwitchLifecycleTests (13/13) pass; full serial lane 375/375; full fast lane 998/998 (one incidental LUTWorkflowTests timeout on a loaded parallel run reproduced as a pass standalone and on lane rerun -- unrelated file, pre-existing parallel-execution flake, not touched by this change).
Checks run:
- swift build
- swift test --filter ComparisonModeTests/testLateBaselineFromPreviousPhotoCannotPublish (x3)
- swift test --filter '(ComparisonModeTests|ThumbnailSwitchLifecycleTests)'
- scripts/ci-tests.sh serial (375/375)
- scripts/ci-tests.sh fast (998/998 on rerun; one unrelated LUTWorkflowTests parallel-lane flake investigated and confirmed pre-existing)
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MU01AN7DTJD4OFZ2
Summary: Fencing confirmed: comparison-baseline publish gates now check activeSourceReference in addition to assetID/revision guards, blocking late completions across photo switches, resets, and comparison-mode exits. Regression test passes repeatedly standalone and under full serial (375/375) and fast (998/998) lanes; no code changes needed.
