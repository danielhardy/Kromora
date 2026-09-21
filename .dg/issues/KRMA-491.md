---
id: KRMA-491
title: "Flaky: testPanAtDeepZoomRequestsROIsThatCoverEveryViewportEdge fails under parallel load"
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Root cause identified and recorded on this ticket
      result: pass
      notes: The test synchronized only on request count and non-nil ROI, so an older in-flight request could be selected after a pan. It now matches the exact presentationNavigation captured for the current zoom or pan.
    - criterion: The test passes reliably across repeated parallel runs
      result: pass
      notes: The focused test passed 20 repeated runs and scripts/ci-tests.sh fast passed all 1,101 required deterministic parallel tests.
  checks_run:
    - swift test --skip-build --filter CanvasObservationTests/testPanAtDeepZoomRequestsROIsThatCoverEveryViewportEdge --parallel (20 repeated runs)
    - scripts/ci-tests.sh fast (1,101 tests passed)
    - dg validate
    - git diff --check
  findings: []
  fixes: []
  verification_commits:
    - 9883f57
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-20T23:24:59.127Z
  session: 01MUAFX0YFDD3NB7K1
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - testing
  - flaky
created: 2026-09-20T22:34:39.890Z
updated: 2026-09-20T23:24:59.128Z
order: z
board: product
commits:
  - 9883f57
---

## Objective

Flaky: testPanAtDeepZoomRequestsROIsThatCoverEveryViewportEdge fails under parallel load

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — claude @ 2026-09-20T22:34:54.495Z

Found while verifying KRMA-487 (intended parent; CLI cannot set parent). On one parallel 'ci-tests.sh fast' run, CanvasObservationTests.testPanAtDeepZoomRequestsROIsThatCoverEveryViewportEdge failed at CanvasNavigationTests.swift:424 (XCTAssertGreaterThanOrEqual: 10.01 < 80.0). Three isolated reruns and a second full fast-lane run passed, so it is load-dependent and unrelated to the perspective fix (commit 9547056); it sits in the KRMA-482 pan/ROI area (3c942c8). Suspect nextROIRequest picking up a stale request under load. Acceptance: root cause identified and the test passes reliably across repeated parallel runs.

### Comment — codex @ 2026-09-20T23:24:50.210Z

Root cause: nextROIRequest synchronized only on previewRequests count and sourceROI presence. Under load, a superseded render can enter FakeRenderEngine after the pan and be selected before the current ROI, even though the coordinator revision fence later rejects it. The helper now matches the exact presentationNavigation captured for the zoom/pan under test. Verification: 20 repeated focused runs passed; scripts/ci-tests.sh fast passed all 1,101 required parallel tests; dg validate and git diff --check passed. Commit 9883f57.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-20T23:24:59.127Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Root cause identified and recorded on this ticket (pass) — The test synchronized only on request count and non-nil ROI, so an older in-flight request could be selected after a pan. It now matches the exact presentationNavigation captured for the current zoom or pan.
- [x] The test passes reliably across repeated parallel runs (pass) — The focused test passed 20 repeated runs and scripts/ci-tests.sh fast passed all 1,101 required deterministic parallel tests.
Checks run:
- swift test --skip-build --filter CanvasObservationTests/testPanAtDeepZoomRequestsROIsThatCoverEveryViewportEdge --parallel (20 repeated runs)
- scripts/ci-tests.sh fast (1,101 tests passed)
- dg validate
- git diff --check
Findings:
- None
Fixes:
- None
Verification commits:
- 9883f57
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MUAFX0YFDD3NB7K1
Summary: Stabilized the deep-zoom pan ROI test by matching requests to the exact presentation navigation generation under test. Superseded ROI requests can still enter the fake engine under load, but are no longer mistaken for the current pan.
