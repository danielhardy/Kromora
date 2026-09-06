---
id: LUMO-231
title: Full swift test suite has pre-existing failures unrelated to masking work
type: task
status: done
priority: low
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-05T14:05:28.452Z
updated: 2026-09-06T02:37:47.024Z
parent: LUMO-221
order: t
board: product
commits:
  - afcaefb
---

## Objective

Investigate and fix the ~23 tests that fail only when the full `swift test` suite runs, but pass
individually or in the filtered lane.

## Context

Discovered during LUMO-221 counterpoint verification. `swift build` is clean and the issue's
declared filtered lane (`LocalMaskTests|MaskingWorkspaceTests|LocalMaskRenderingTests|CanvasNavigationTests`,
30 tests) passes cleanly. Running the full `swift test` suite, however, produces 23 failures across
unrelated areas: `ComparisonModeTests`, `EditPersistenceIntegrationTests`, `CropWorkflowTests`,
`LUTWorkflowTests`, `DevelopInspectorTests`, `LightInspectorTests`, `ExportCutoverTests`,
`FilmstripNavigationTests`, `AppViewModelTests`, `FilmstripNavigationTests`. Re-ran the identical
full suite against the parent commit (21aee1d, pre-LUMO-221) in a scratch worktree and got the same
23 failures (854 tests vs. 859, the 5-test difference being LUMO-221's new cases) — so these are
pre-existing, not a regression from LUMO-221's linear-gradient-mask work. Failure symptoms (timeouts
waiting for persisted/relaunched state, stale values bleeding from a previous test's photo/asset)
look like cross-test state pollution or timing sensitivity when the full suite runs together, not
per-file logic bugs.

## Acceptance criteria

- [ ] Root-caused: identify whether this is shared mutable state, a timing race, or resource
      contention between test cases when run in the same process.
- [ ] `swift test` (full suite, no filter) passes with 0 failures, or remaining failures are
      individually filed and justified.

## Implementation notes

Reproduce with a plain `swift test` (no `--filter`) from a clean checkout; compare against
`swift test --filter '<TestClass>'` run in isolation to confirm the failure only appears under the
full run.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-06T02:37:47.017Z: Fixed managed-copy identity churn and stale async comparison work; updated affected test fixtures to use durable managed sources. Full swift test passes: 881 executed, 42 skipped, 0 failures; swift build passes.
