---
id: KRMA-740
title: RenderEngineTests local RAW crop-aware thumbnail sizing uses exact float equality (799.9999999999999 vs 800)
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: scripts/ci-tests.sh serial passes on a host with a local RAW fixture (from issue comment)
      result: pass
      notes: Verified the affected RenderEngineTests suite (32 tests) and the local-RAW test with KROMORA_RAW_FIXTURE_DIR=realworldtest; implementer reported full serial lane 455 passed.
    - criterion: Issue template criterion is an empty placeholder
      result: pass
      notes: No concrete criterion beyond the comment's acceptance line.
  checks_run:
    - KROMORA_RAW_FIXTURE_DIR=realworldtest swift test --no-parallel --filter RenderEngineTests (32 passed, 0 failures)
    - KROMORA_RAW_FIXTURE_DIR=realworldtest swift test --no-parallel --filter testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing (1 passed, not skipped)
    - git diff --check (clean)
  findings:
    - "info: Test-only change; 1e-6 accuracy on width/height is appropriate and production keeps unrounded planning, which the test still documents. No correctness, security, or performance concerns."
  fixes: []
  verification_commits:
    - e268cc09
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-10-01T01:16:25.536Z
  session: 01MUOUEOHQSADSFCM8
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
  - testing
created: 2026-10-01T00:51:19.095Z
updated: 2026-10-01T01:16:25.539Z
blockers: []
order: t
board: product
commits:
  - e268cc09
---

## Objective

RenderEngineTests local RAW crop-aware thumbnail sizing uses exact float equality (799.9999999999999 vs 800)

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — claude @ 2026-10-01T00:51:22.915Z

Found during KRMA-739 verification on macOS 27.0 (26A428) with a local RAW fixture present (parent: KRMA-739; the CLI has no parent flag). RenderEngineTests.swift:173 XCTAssertEqual compares RenderScale.preview(maxSize: (300, 799.9999999999999)) to (300, 800): 240/0.3 is not exact in floating point. Unrelated to the grain change, which touches only MetalKernelParityTests and docs. Fix: compare the size with an accuracy (or assert on rounded pixels). Also decide whether production should keep unrounded planning. Acceptance: scripts/ci-tests.sh serial passes on a host with a local RAW fixture.

### Comment — codex @ 2026-10-01T01:15:33.295Z

Updated the local RAW crop-aware sizing test to assert preview width and height with a 1e-6 accuracy tolerance, preserving production's unrounded sizing. Checks: scripts/ci-tests.sh serial (455 passed); KROMORA_RAW_FIXTURE_DIR=realworldtest swift test --no-parallel --filter RenderEngineTests/testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing (1 passed); git diff --check; dg validate (OK, existing model-name warnings). Commit: e268cc0.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-01T01:16:25.536Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] scripts/ci-tests.sh serial passes on a host with a local RAW fixture (from issue comment) (pass) — Verified the affected RenderEngineTests suite (32 tests) and the local-RAW test with KROMORA_RAW_FIXTURE_DIR=realworldtest; implementer reported full serial lane 455 passed.
- [x] Issue template criterion is an empty placeholder (pass) — No concrete criterion beyond the comment's acceptance line.
Checks run:
- KROMORA_RAW_FIXTURE_DIR=realworldtest swift test --no-parallel --filter RenderEngineTests (32 passed, 0 failures)
- KROMORA_RAW_FIXTURE_DIR=realworldtest swift test --no-parallel --filter testLocalRAWEmbeddedPreviewUsesCropAwareThumbnailSizing (1 passed, not skipped)
- git diff --check (clean)
Findings:
- info: Test-only change; 1e-6 accuracy on width/height is appropriate and production keeps unrounded planning, which the test still documents. No correctness, security, or performance concerns.
Fixes:
- None
Verification commits:
- e268cc09
Actor: claude
Resolved model: sonnet
Pickup session: 01MUOUEOHQSADSFCM8
Summary: Verified: crop-aware thumbnail sizing test now tolerates floating-point error; RenderEngineTests and local RAW test pass.
