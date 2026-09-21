---
id: KRMA-321
title: "Fast lane red: pre-existing LUTWorkflowTests assertion + ci-tests.sh failure-handler bug"
type: bug
status: done
priority: high
agent: pi
verification_agent: claude
model: openrouter/meta/muse-spark-1.3-contributor
verification_model: sonnet
creation_provenance:
  runner: pi
  model: openrouter/meta/muse-spark-1.3-contributor
  actor: pi
labels:
  - verification
created: 2026-09-09T16:12:47.564Z
updated: 2026-09-10T12:53:56.561Z
parent: KRMA-306
order: zy
board: product
---

## Objective

Fast lane red: pre-existing LUTWorkflowTests assertion + ci-tests.sh failure-handler bug

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — pi @ 2026-09-09T16:12:55.375Z

Found during counterpoint verification of KRMA-306. Evidence: LUTWorkflowTests/testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest fails with 'XCTAssertGreaterThan failed: (3) is not greater than (3)' at Tests/LumoKitTests/LUTWorkflowTests.swift:182, and reproduces on parent commit 7fd6def without the KRMA-306 change (verified in a throwaway worktree), so it is unrelated to interactive 8-bit preview textures. Additionally scripts/ci-tests.sh fails with 'run_lane:8: read-only variable: status' (zsh), which masks the real exit status. Also observed: ThumbnailSwitchLifecycleTests/testEditedThumbnailUsesCurrentDocumentAndIsSharedByBrowsingSurfaces flaked once (XCTAssertNotNil at :63) then passed on rerun; may warrant a look if it recurs.

### Comment — pi @ 2026-09-09T18:07:01.996Z

Fixed both fast-lane bugs.

1) LUTWorkflowTests/testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest: the click section read the preview-request count immediately after selectLook(nil) without settling the clear's async render, then asserted GreaterThan. The Fake log is append-only, so the reported (3)-vs-(3) proves the click waiter timed out first and GreaterThan failed as a knock-on. Hardened the section: snapshot the audition count, wait for the clear's nil-LUT preview to land (unambiguous — Look-browser candidates always carry a concrete Look at hardcoded intensity 1), then take the click baseline; the indexed click waiter is now the sole assertion and the redundant count comparison is removed. Helpers generalized to LUTID?.

2) scripts/ci-tests.sh run_lane used 'local status', which is a read-only special variable in zsh — any lane failure errored with 'run_lane:8: read-only variable: status' and masked the real exit status. Renamed to lane_status; verified failure-branch propagation (exit 1 and 3 preserved) and 'zsh -n' + 'verify' lane.

3) The hedged ThumbnailSwitchLifecycleTests flake recurred during stress (1/6 parallel runs, :63 XCTAssertNotNil on items[0].thumbnail): the test waited for edited-thumbnail request admission, then asserted publication exactly once. Converted both publication asserts to the file's existing waitUntil.

Validation: LUTWorkflowTests 6/6 x5 serial; 6/6 parallel stress runs of LUTWorkflow+ThumbnailSwitch+LookPreview+PreviewCutover clean; full fast lane green (exit 0, 665 tests).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
