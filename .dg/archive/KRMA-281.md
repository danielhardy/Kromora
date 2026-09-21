---
id: KRMA-281
title: Replace polling-based async test waits with deterministic synchronization
type: task
status: done
priority: high
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Shared polling helpers and highest-value timing-sensitive tests identified and migrated
      result: pass
    - criterion: Explicit source-preparation, preview, histogram, and encode milestones available from FakeRenderEngine
      result: pass
    - criterion: Arbitrary debounce/wait sleep removed from migrated render lifecycle tests where fake milestones are available
      result: pass
    - criterion: Timeouts include request counts/revisions/state context and throw to stop the affected test
      result: pass
    - criterion: Focused and full parallel verification pass
      result: pass
  checks_run:
    - "swift test --parallel: 957 tests completed with 0 failures; expected fixture-gated skips retained"
    - "swift test --filter LumoKitTests.(PreviewCutoverTests|ExportCutoverTests|ThumbnailSwitchLifecycleTests|FilmstripNavigationTests): 31 tests, 0 failures, 1 expected RAW skip"
    - "git diff --check: passed"
    - Targeted audit confirmed no sourcePreparationCount/previewRequests/histogramRequests/encodeRequests polling loops or 150 ms sleep remain in migrated tests
  findings: []
  fixes: []
  verification_commits:
    - ae7c7d1
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-08T18:35:20.011Z
  session: 01MTSZZ03ME9F6XR9B
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - test-reliability
created: 2026-09-08T14:41:34.333Z
updated: 2026-09-10T12:53:53.144Z
order: t
board: product
commits:
  - ae7c7d1
---

## Objective\n\nReplace wall-clock polling and arbitrary sleeps in asynchronous tests with deterministic synchronization.\n\n## Context\n\nThe parallel suite contains many wait loops using Task.sleep and short polling intervals. Examples include FilmstripNavigationTests.swift:61-73, PreviewCutoverTests.swift:36-45, and ExportCutoverTests.swift:57-64. Under concurrent SwiftData, filesystem, Core Image, and Metal load, valid work can miss 2-10 second deadlines. FakeRenderEngine already exposes request recording and gates that can provide stronger synchronization points.\n\n## Acceptance criteria\n\n- Identify the shared polling helpers and the highest-value timing-sensitive tests.\n- Add explicit expectations, continuations, or AsyncStream events for source preparation, preview completion, histogram work, encode requests, and other fake-engine milestones.\n- Replace arbitrary debounce sleeps with an injectable test clock or scheduler where practical.\n- Timeout failures include the relevant request counts, revisions, and state.\n- A timeout stops the affected test instead of producing cascading unwrap or state failures.\n- Focused tests remain deterministic across repeated runs and the full parallel suite shows no timing-only failures in the migrated areas.\n\n## Verification\n\nRun each migrated test repeatedly in isolation and with swift test --parallel. Retain bounded timeout guards so deadlocks still fail clearly.\n

## Agent log

- 2026-09-08T18:35:20.012Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Shared polling helpers and highest-value timing-sensitive tests identified and migrated (pass)
- [x] Explicit source-preparation, preview, histogram, and encode milestones available from FakeRenderEngine (pass)
- [x] Arbitrary debounce/wait sleep removed from migrated render lifecycle tests where fake milestones are available (pass)
- [x] Timeouts include request counts/revisions/state context and throw to stop the affected test (pass)
- [x] Focused and full parallel verification pass (pass)
Checks run:
- swift test --parallel: 957 tests completed with 0 failures; expected fixture-gated skips retained
- swift test --filter LumoKitTests.(PreviewCutoverTests|ExportCutoverTests|ThumbnailSwitchLifecycleTests|FilmstripNavigationTests): 31 tests, 0 failures, 1 expected RAW skip
- git diff --check: passed
- Targeted audit confirmed no sourcePreparationCount/previewRequests/histogramRequests/encodeRequests polling loops or 150 ms sleep remain in migrated tests
Findings:
- None
Fixes:
- None
Verification commits:
- ae7c7d1
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTSZZ03ME9F6XR9B
Summary: Replaced migrated async test polling with FakeRenderEngine AsyncStream lifecycle events and bounded diagnostic waits.
