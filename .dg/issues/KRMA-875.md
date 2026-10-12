---
id: KRMA-875
title: Extract Look selection workflow from AppViewModel
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: LookSelectionCoordinator owns resolution, derived registry and missing-reference reporting plus selection and audition decisions; focused tests do not construct AppViewModel.
      result: pass
      notes: Ownership is contained in LookSelectionCoordinator.swift; five focused tests exercise it directly.
    - criterion: AppViewModel remains the composition root and sole owner of the published EditDocument, with thin forwarding methods.
      result: pass
      notes: AppViewModel applies returned outcomes through its existing document update path.
    - criterion: docs/APP_ARCHITECTURE.md ownership table updated.
      result: pass
    - criterion: swift build and scripts/ci-tests.sh fast pass.
      result: pass
      notes: Both commands exited 0.
  checks_run:
    - swift build (passed, exit 0)
    - scripts/ci-tests.sh fast (passed, exit 0)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T14:49:45.317Z
  session: 01MV3XSSFG7JKD7QGC
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T13:33:41.719Z
updated: 2026-10-11T14:49:45.320Z
blockers: []
order: v
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T14:47:04.496Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

Child of KRMA-460 (reopened 2026-10-11: AppViewModel.swift grew from 4,293 lines at KRMA-469 to 5,738). Extract workflow *ownership* into a focused coordinator; do not just split files. Keep AppViewModel the composition root and sole owner of the published EditDocument (see docs/APP_ARCHITECTURE.md). Swift 6, no escape hatches, no broad AppViewModel back-reference from the new collaborator. Not a release blocker. Acceptance: coordinator owns the state and workflow with focused tests that do not construct AppViewModel; AppViewModel keeps thin forwarders; docs/APP_ARCHITECTURE.md ownership table updated; swift build and scripts/ci-tests.sh fast pass. Section: `// MARK: - Look selection` (~310 lines). Check overlap with the existing Look coordinators.


### Comment — claude @ 2026-10-11T14:47:04.018Z

Extracted LookSelectionCoordinator (resolution, derived registry, missing-reference report, selection/audition outcomes); AppViewModel keeps thin forwarders and sole document ownership. 5 focused tests without AppViewModel; swift build and scripts/ci-tests.sh fast pass; APP_ARCHITECTURE.md updated.

## Agent log

- 2026-10-11T14:49:45.317Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] LookSelectionCoordinator owns resolution, derived registry and missing-reference reporting plus selection and audition decisions; focused tests do not construct AppViewModel. (pass) — Ownership is contained in LookSelectionCoordinator.swift; five focused tests exercise it directly.
- [x] AppViewModel remains the composition root and sole owner of the published EditDocument, with thin forwarding methods. (pass) — AppViewModel applies returned outcomes through its existing document update path.
- [x] docs/APP_ARCHITECTURE.md ownership table updated. (pass)
- [x] swift build and scripts/ci-tests.sh fast pass. (pass) — Both commands exited 0.
Checks run:
- swift build (passed, exit 0)
- scripts/ci-tests.sh fast (passed, exit 0)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV3XSSFG7JKD7QGC
Summary: Counterpoint verification passed: coordinator extraction meets acceptance criteria; swift build and fast CI lane passed.
