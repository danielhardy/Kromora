---
id: LUMO-318
title: "LUTWorkflowTests regression: previewRequests count assertion fails after LUMO-308/LUMO-315"
type: bug
status: backlog
priority: medium
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
parent: LUMO-267
created: 2026-09-09T13:46:25.072Z
updated: 2026-09-09T13:46:25.072Z
order: w
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

Found while independently verifying LUMO-267 (fuse validation/coverage into mask generation).
Bisected in a throwaway worktree across the current branch's tail:

- `88e6008` (LUMO-304, base) — passes
- `382d71b` (LUMO-267 commit 1) — passes
- `0fed205` (LUMO-267 commit 2, the one under verification) — passes
- `7818f95` (LUMO-305) — passes
- `2d4d7b6` (LUMO-307) — passes
- current `HEAD` / `bca796a` (LUMO-315) — **fails**

So the regression was introduced by `b01de9d` (LUMO-308: protect preview cache from thumbnail
churn) or `bca796a` (LUMO-315: add GPU processing prefix acceptance tests), not by LUMO-267. Not
bisected further between those two. Likely candidate given the title: LUMO-308's preview-cache
protection may now be suppressing/coalescing the Look-selection preview request that this test
counts.

LUMO-267 itself is unaffected — its own tests (RegionMaskTests, MaskRefinementTests,
VisionSemanticMaskProviderTests) all pass, and this failure reproduces identically on both
commits that predate and postdate LUMO-267's changes.

## Acceptance criteria

- [ ] `swift test --filter LUTWorkflowTests/testExternalImportCanBeSelectedByIDAndSendsItThroughPreviewRequest`
      passes.
- [ ] Root cause identified (which of LUMO-308/LUMO-315's preview-cache/prefix changes suppressed
      the request the test expects) and either the production coalescing behavior or the test's
      expectation is fixed intentionally, not just made to pass.

## Implementation notes

Bisect further between `b01de9d` and `bca796a` to isolate the exact commit before diagnosing.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->
