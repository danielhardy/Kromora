---
id: KRMA-318
title: "LUTWorkflowTests regression: previewRequests count assertion fails after KRMA-308/KRMA-315"
type: bug
status: done
priority: medium
verification_agent: pi
verification_model: openrouter/meta/muse-spark-1.3-contributor
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: focused LUTWorkflowTests imported Look selection test passes
      result: pass
      notes: swift test --filter LUTWorkflowTests/testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest
    - criterion: root cause identified and fixed intentionally
      result: pass
      notes: The failure starts at b01de9d; LUMO-308 adds speculative opening work that exposes the test race between import publication and the automatic audition preview. The test now synchronizes on that audition request before measuring the explicit ID-click request.
    - criterion: related LUT workflow coverage remains green
      result: pass
      notes: "swift test --filter LUTWorkflowTests: 6/6 passed"
  checks_run:
    - git diff --check
    - swift test --filter LUTWorkflowTests/testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest
    - swift test --filter LUTWorkflowTests
    - history bisect in throwaway worktrees at 2d4d7b6, b01de9d, and bca796a
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-09T16:23:13.864Z
  session: 01MTUAYY5KZ4OLNEA1
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-09T13:46:25.072Z
updated: 2026-09-10T12:53:56.276Z
parent: KRMA-267
order: x78
board: product
---

## Objective

`swift test` fails deterministically (not flaky) on
`LUTWorkflowTests.testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest` at
`Tests/LumoKitTests/LUTWorkflowTests.swift:182`:

```
XCTAssertGreaterThan failed: ("3") is not greater than ("3")
```

`requestsAfterClick` is not greater than `requestsBeforeClick` — selecting an imported Look by ID
is no longer producing an additional preview request.

## Context

Found while independently verifying KRMA-267 (fuse validation/coverage into mask generation).
Bisected in a throwaway worktree across the current branch's tail:

- `88e6008` (KRMA-304, base) — passes
- `382d71b` (KRMA-267 commit 1) — passes
- `0fed205` (KRMA-267 commit 2, the one under verification) — passes
- `7818f95` (KRMA-305) — passes
- `2d4d7b6` (KRMA-307) — passes
- current `HEAD` / `bca796a` (KRMA-315) — **fails**

So the regression was introduced by `b01de9d` (KRMA-308: protect preview cache from thumbnail
churn) or `bca796a` (KRMA-315: add GPU processing prefix acceptance tests), not by KRMA-267. Not
bisected further between those two. Likely candidate given the title: KRMA-308's preview-cache
protection may now be suppressing/coalescing the Look-selection preview request that this test
counts.

KRMA-267 itself is unaffected — its own tests (RegionMaskTests, MaskRefinementTests,
VisionSemanticMaskProviderTests) all pass, and this failure reproduces identically on both
commits that predate and postdate KRMA-267's changes.

## Acceptance criteria

- [ ] `swift test --filter LUTWorkflowTests/testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest`
      passes.
- [ ] Root cause identified (which of KRMA-308/KRMA-315's preview-cache/prefix changes suppressed
      the request the test expects) and either the production coalescing behavior or the test's
      expectation is fixed intentionally, not just made to pass.

## Implementation notes

Bisect further between `b01de9d` and `bca796a` to isolate the exact commit before diagnosing.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-09T16:23:13.864Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] focused LUTWorkflowTests imported Look selection test passes (pass) — swift test --filter LUTWorkflowTests/testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest
- [x] root cause identified and fixed intentionally (pass) — The failure starts at b01de9d; KRMA-308 adds speculative opening work that exposes the test race between import publication and the automatic audition preview. The test now synchronizes on that audition request before measuring the explicit ID-click request.
- [x] related LUT workflow coverage remains green (pass) — swift test --filter LUTWorkflowTests: 6/6 passed
Checks run:
- git diff --check
- swift test --filter LUTWorkflowTests/testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest
- swift test --filter LUTWorkflowTests
- history bisect in throwaway worktrees at 2d4d7b6, b01de9d, and bca796a
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTUAYY5KZ4OLNEA1
Summary: Fixed the KRMA-308 regression test ordering. The test now waits for the automatic imported-Look audition preview before clearing the selection, then requires the ID-based selection to produce a later matching preview request. Bisected: 2d4d7b6 passes, b01de9d (KRMA-308) fails, and bca796a (KRMA-315) still fails; the production coalescing behavior is intentional and the assertion was racing the queued audition request.
