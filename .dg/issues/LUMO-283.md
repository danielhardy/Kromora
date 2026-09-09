---
id: LUMO-283
title: Split resource-heavy render and UI tests into a serial CI lane
type: task
status: done
priority: medium
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - test-reliability
created: 2026-09-08T14:41:35.468Z
updated: 2026-09-08T19:09:51.085Z
order: a0
board: product
commits:
  - 70ba28edaadf13ae0f8f45c7c70634c22317c52c
verification_report:
  verdict: pass
  acceptance_criteria: []
  checks_run: []
  findings: []
  fixes: []
  verification_commits:
    - 70ba28edaadf13ae0f8f45c7c70634c22317c52c
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-08T19:09:51.083Z
  session: 01MTT1I430J0LX0E9D
---

## Objective\n\nSeparate resource-heavy render, AppKit, and hardware-dependent tests from the normal parallel CI lane.\n\n## Context\n\nThe current CI fast and slow commands both use swift test --parallel. Real Core Image and Metal render tests, AppKit/UI-session tests, and fixture-gated RAW or benchmark work can compete for shared host resources even when test data is isolated. This amplifies timing failures that do not occur when tests run alone.\n\n## Acceptance criteria\n\n- Classify test targets or filters into deterministic fake-engine/model tests and resource-heavy render/UI/hardware tests.\n- Keep the deterministic lane parallel.\n- Run resource-heavy Core Image, Metal, AppKit, and hardware-sensitive tests in a serialized lane or otherwise enforce exclusive execution.\n- Keep benchmarks and RAW-fixture-gated tests opt-in or in their dedicated lane, with clear fixture requirements.\n- Make CI logs identify which lane failed and preserve focused rerun commands.\n- Verify the new CI layout with both lanes on the supported macOS runner.\n\n## Verification\n\nRun the fast lane in parallel and the resource-heavy lane serially. Confirm that the full required CI set is covered without duplicate or silently skipped tests.\n


### Comment — codex @ 2026-09-08T19:05:29.834Z

Implemented disjoint CI test lanes via scripts/ci-tests.sh: deterministic/model/fake-engine tests run in parallel, Core Image/render/AppKit/UI tests run serially with --no-parallel, and RAW-fixture/benchmark methods are explicitly opt-in. Added lane coverage auditing, lane-specific failure/rerun logging, and updated CI/docs. Verified: scripts/ci-tests.sh fast (639 passed), serial (275 passed), optional (44 expected skips without fixtures/benchmark inputs), zsh -n, git diff --check, and dg validate. Commit: 70ba28e.

## Agent log

- 2026-09-08T19:09:51.084Z: Verification report
Verdict: PASS
Acceptance criteria:
- None supplied
Checks run:
- None
Findings:
- None
Fixes:
- None
Verification commits:
- 70ba28edaadf13ae0f8f45c7c70634c22317c52c
Actor: claude
Resolved model: sonnet
Pickup session: 01MTT1I430J0LX0E9D
Summary: Verified: independently re-ran all three CI lanes and confirmed the implementer's claimed counts exactly. fast=639/639 passed, serial=275/275 passed, optional=44/44 expected skips (no fixtures/display) - matches audit total=958. Confirmed lane classification is correct by inspecting RAWCapabilitiesTests: XCTSkip-gated real-RAW methods are the only ones routed to optional/serial; deterministic methods in mixed suites correctly stay in the fast lane. zsh -n and git diff --check clean on the commit. Docs (README/CLAUDE.md/PHASE2_SPEC/CODE_REVIEW/realworldtest) consistently updated to 958 methods and the new lane names. No behavioral issues found; no localized fix needed.
