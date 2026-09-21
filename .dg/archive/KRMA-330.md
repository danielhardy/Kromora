---
id: KRMA-330
title: "Embedded first frame: stale-drop regression + opt-in ARW timing coverage"
type: task
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: "EmbeddedFirstFrameStaleDropTest: navigate to B while A's embedded-frame extraction is in flight; A's late JPEG must not publish"
      result: pass
    - criterion: Deterministic injection hook/gate around extraction (no racy timing test)
      result: pass
    - criterion: Opt-in real-ARW timing test following SingleViewLatencyBenchmark pattern (report only, no threshold asserts)
      result: pass
  checks_run:
    - swift build — clean
    - swift test --filter EmbeddedFirstFrameTests — 3 passed, 1 expected skip (LUMO_RAW_FIXTURE_DIR unset)
    - scripts/ci-tests.sh fast — 678 passed
    - git diff --check 9e008d2^ 9e008d2 — clean
    - dg validate — OK (pre-existing agents.pickup.runner model warning only)
  findings:
    - "Non-blocking: EmbeddedFirstFrameGate had an unused hasRequested(named:) helper alongside the used requestedURLs.count check; removed as a localized cleanup (no behavior change)."
  fixes:
    - Removed unused EmbeddedFirstFrameGate.hasRequested(named:) test helper in Tests/LumoKitTests/EmbeddedFirstFrameTests.swift
  verification_commits:
    - 2500b86
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-09T22:53:07.923Z
  session: 01MTUOWXTGPGOBP2TV
creation_provenance:
  runner: pi
  model: openrouter/meta/muse-spark-1.3-contributor
  actor: pi
labels:
  - verification
created: 2026-09-09T22:09:13.355Z
updated: 2026-09-10T12:53:57.393Z
depends_on:
  - KRMA-326
order: a0
board: product
commits:
  - 2500b86
---

## Objective

Embedded first frame: stale-drop regression + opt-in ARW timing coverage

## Context

<!-- Why this work matters -->

## Acceptance criteria

- [ ] 

## Implementation notes

<!-- Approach, constraints, links -->

### Comment — pi @ 2026-09-09T22:09:17.765Z

Parent KRMA-326 verified PASS. Remaining coverage gaps: (1) EmbeddedFirstFrameStaleDropTest — navigate to B while A's 1600px Thumbnails.generate extraction is in flight and assert A's late JPEG is dropped. Needs an injection hook or gate around the extraction to be deterministic; do not add a racy timing test. (2) Opt-in real-ARW timing test following the SingleViewLatencyBenchmark pattern (report provisional-vs-settled, no threshold asserts). Guards (sourceRevision/assetID/previewState==loading/lastPublishedVisibleRequest==nil/isCancelled) were verified by inspection in 9a4894f.

### Comment — codex @ 2026-09-09T22:48:40.706Z

Implemented in 9e008d2. Added an injectable async embedded-frame provider for deterministic extraction gating, a navigation stale-drop regression proving A's late JPEG cannot publish after B, and an opt-in DSC01172.ARW timing report for provisional versus settled milestones. Verification: EmbeddedFirstFrameTests 3 passed / 1 expected skip; required fast lane 678 passed; swift build; git diff --check; dg validate (pre-existing runner-model warning only).

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-09T22:53:07.923Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] EmbeddedFirstFrameStaleDropTest: navigate to B while A's embedded-frame extraction is in flight; A's late JPEG must not publish (pass)
- [x] Deterministic injection hook/gate around extraction (no racy timing test) (pass)
- [x] Opt-in real-ARW timing test following SingleViewLatencyBenchmark pattern (report only, no threshold asserts) (pass)
Checks run:
- swift build — clean
- swift test --filter EmbeddedFirstFrameTests — 3 passed, 1 expected skip (LUMO_RAW_FIXTURE_DIR unset)
- scripts/ci-tests.sh fast — 678 passed
- git diff --check 9e008d2^ 9e008d2 — clean
- dg validate — OK (pre-existing agents.pickup.runner model warning only)
Findings:
- Non-blocking: EmbeddedFirstFrameGate had an unused hasRequested(named:) helper alongside the used requestedURLs.count check; removed as a localized cleanup (no behavior change).
Fixes:
- Removed unused EmbeddedFirstFrameGate.hasRequested(named:) test helper in Tests/LumoKitTests/EmbeddedFirstFrameTests.swift
Verification commits:
- 2500b86
Actor: claude
Resolved model: sonnet
Pickup session: 01MTUOWXTGPGOBP2TV
Summary: Verified KRMA-330: EmbeddedFirstFrameGate injection hook and stale-drop regression correctly exercise the navigation guards (sourceRevision/assetID/previewState/lastPublishedVisibleRequest); opt-in ARW timing test follows the SingleViewLatencyBenchmark report-only pattern. Removed one unused test helper as a localized cleanup.
