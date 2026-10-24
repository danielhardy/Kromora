---
id: KRMA-877
title: Extract export orchestration from AppViewModel
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Export coordinator owns workflow state and orchestration, with focused tests that do not construct AppViewModel.
      result: pass
      notes: ExportWorkflowCoordinator owns panel/share/handoff flows and completion state; focused tests instantiate it with a test destination.
    - criterion: AppViewModel remains the composition root and keeps thin export forwarders.
      result: pass
      notes: AppViewModel provides request snapshots and forwarding methods through ExportWorkflowDestination.
    - criterion: docs/APP_ARCHITECTURE.md ownership table is updated.
      result: pass
      notes: Both coordinator overview and export ownership detail name ExportWorkflowCoordinator.
    - criterion: swift build and scripts/ci-tests.sh fast pass.
      result: pass
      notes: Both commands exited 0; fast lane ran 1,632 required tests. The test build emitted an unrelated unused tuple binding warning in ColorMixerTests.swift.
  checks_run:
    - swift build (passed)
    - scripts/ci-tests.sh fast (passed; 1,632 tests)
    - Independent source, focused test, and architecture documentation review (no actionable findings)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T15:18:42.880Z
  session: 01MV3YTO39PKAKM34T
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T13:33:43.561Z
updated: 2026-10-11T15:18:42.884Z
blockers: []
order: v
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T15:05:20.629Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

Child of KRMA-460 (reopened 2026-10-11: AppViewModel.swift grew from 4,293 lines at KRMA-469 to 5,738). Extract workflow *ownership* into a focused coordinator; do not just split files. Keep AppViewModel the composition root and sole owner of the published EditDocument (see docs/APP_ARCHITECTURE.md). Swift 6, no escape hatches, no broad AppViewModel back-reference from the new collaborator. Not a release blocker. Acceptance: coordinator owns the state and workflow with focused tests that do not construct AppViewModel; AppViewModel keeps thin forwarders; docs/APP_ARCHITECTURE.md ownership table updated; swift build and scripts/ci-tests.sh fast pass. Section: `// MARK: - Export` (~305 lines). Check overlap with ExportCoordinator.


### Comment — claude @ 2026-10-11T15:05:25.544Z

Added ExportWorkflowCoordinator (share, external editor, bundle, panel routing, handoff URLs) behind ExportWorkflowDestination; AppViewModel keeps thin forwarders and request snapshots. ExportCoordinator still owns execution. Focused tests in ExportWorkflowCoordinatorTests; docs/APP_ARCHITECTURE.md updated; swift build and scripts/ci-tests.sh fast pass.

## Agent log

- 2026-10-11T15:18:42.880Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Export coordinator owns workflow state and orchestration, with focused tests that do not construct AppViewModel. (pass) — ExportWorkflowCoordinator owns panel/share/handoff flows and completion state; focused tests instantiate it with a test destination.
- [x] AppViewModel remains the composition root and keeps thin export forwarders. (pass) — AppViewModel provides request snapshots and forwarding methods through ExportWorkflowDestination.
- [x] docs/APP_ARCHITECTURE.md ownership table is updated. (pass) — Both coordinator overview and export ownership detail name ExportWorkflowCoordinator.
- [x] swift build and scripts/ci-tests.sh fast pass. (pass) — Both commands exited 0; fast lane ran 1,632 required tests. The test build emitted an unrelated unused tuple binding warning in ColorMixerTests.swift.
Checks run:
- swift build (passed)
- scripts/ci-tests.sh fast (passed; 1,632 tests)
- Independent source, focused test, and architecture documentation review (no actionable findings)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV3YTO39PKAKM34T
Summary: Independent verification passed: export workflow ownership, thin AppViewModel forwarding, architecture documentation, and declared build/test checks confirmed.
