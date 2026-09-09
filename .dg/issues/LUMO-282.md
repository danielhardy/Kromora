---
id: LUMO-282
title: Add test lifecycle shutdown and await background work before fixture cleanup
type: task
status: done
priority: high
creation_provenance:
  runner: codex
  model: gpt-5.6-luna
  actor: codex
labels:
  - test-reliability
created: 2026-09-08T14:41:34.908Z
updated: 2026-09-08T18:53:23.522Z
order: w
board: product
commits:
  - 67d5a39
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: AppViewModel and related coordinator async work is inventoried and given explicit shutdown ownership
      result: pass
    - criterion: Shutdown cancels work, prevents late publications, and awaits quiescence where safe
      result: pass
    - criterion: TempDirectoryTestCase shuts down retained AppViewModels before fixture deletion
      result: pass
    - criterion: Shutdown is idempotent and normal production launch behavior is unchanged
      result: pass
    - criterion: Regression coverage proves cancelled source work cannot publish into a retired test model
      result: pass
  checks_run:
    - "swift test --parallel: 958 tests, exit code 0"
    - "swift test --parallel --filter AppViewModelTests|EditPersistenceIntegrationTests|FilmstripNavigationTests|PreviewCutoverTests|ExportCutoverTests|AdjustInspectorTests|LightInspectorTests|DevelopInspectorTests|ThumbnailSwitchLifecycleTests: 135 tests, 0 failures, repeated twice"
    - "git diff --check: passed"
    - "dg validate: passed"
  findings: []
  fixes: []
  verification_commits:
    - 67d5a39
  actor: codex
  resolved_model: gpt-5.6-luna
  completed_at: 2026-09-08T18:53:23.519Z
  session: 01MTT0FF694XWWKDQZ
---

## Objective\n\nEnsure test-owned AppViewModel and coordinator work is cancelled and quiesced before temporary fixtures are deleted.\n\n## Context\n\nAppViewModel owns multiple asynchronous tasks for loading, metadata, previews, prefetch, capabilities, comparison, histogram, auto adjustment, and media work. Tests commonly delete temporary source folders during teardown while those tasks may still be running. Late work can then publish stale state, access deleted files, or cause the next test to observe misleading timeouts.\n\n## Acceptance criteria\n\n- Inventory AppViewModel and related coordinator tasks that can outlive a test method.\n- Add an explicit test lifecycle shutdown API or equivalent internal cancellation seam.\n- Shutdown cancels relevant tasks, prevents late publications, and awaits quiescence where safe.\n- Update TempDirectoryTestCase and affected tests to call shutdown before removing temporary directories or stores.\n- Ensure shutdown is idempotent and does not change normal production launch behavior.\n- Add a regression test demonstrating that a cancelled or completed test cannot publish into a later test.\n\n## Verification\n\nRun persistence, filmstrip, preview, export, and inspector tests repeatedly under parallel execution. Confirm no work accesses deleted fixture paths after teardown.\n

## Agent log

- 2026-09-08T18:53:23.520Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] AppViewModel and related coordinator async work is inventoried and given explicit shutdown ownership (pass)
- [x] Shutdown cancels work, prevents late publications, and awaits quiescence where safe (pass)
- [x] TempDirectoryTestCase shuts down retained AppViewModels before fixture deletion (pass)
- [x] Shutdown is idempotent and normal production launch behavior is unchanged (pass)
- [x] Regression coverage proves cancelled source work cannot publish into a retired test model (pass)
Checks run:
- swift test --parallel: 958 tests, exit code 0
- swift test --parallel --filter AppViewModelTests|EditPersistenceIntegrationTests|FilmstripNavigationTests|PreviewCutoverTests|ExportCutoverTests|AdjustInspectorTests|LightInspectorTests|DevelopInspectorTests|ThumbnailSwitchLifecycleTests: 135 tests, 0 failures, repeated twice
- git diff --check: passed
- dg validate: passed
Findings:
- None
Fixes:
- None
Verification commits:
- 67d5a39
Actor: codex
Resolved model: gpt-5.6-luna
Pickup session: 01MTT0FF694XWWKDQZ
Summary: Added explicit AppViewModel/coordinator shutdown barriers, cancellation guards, fixture teardown ownership, and a gated stale-publication regression test.
