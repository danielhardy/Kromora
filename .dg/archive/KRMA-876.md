---
id: KRMA-876
title: Extract copy and paste of edits from AppViewModel
type: task
status: done
priority: low
agent: codex
human_review_required: false
model: gpt-6.1-sol
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Coordinator owns copy/paste state and workflow, with focused tests that do not construct AppViewModel
      result: pass
    - criterion: AppViewModel remains the composition root and sole published EditDocument owner with thin forwarders
      result: pass
    - criterion: docs/APP_ARCHITECTURE.md ownership table documents the coordinator boundary
      result: pass
    - criterion: swift build succeeds
      result: pass
    - criterion: scripts/ci-tests.sh fast passes
      result: pass
      notes: All 1,628 required fast tests passed.
  checks_run:
    - swift build (passed)
    - scripts/ci-tests.sh fast (passed; 1,628 tests)
    - git diff --check 2fee1f42^ 2fee1f42 (passed)
  findings: []
  fixes: []
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-11T14:59:44.547Z
  session: 01MV3Y5TFDNI39DN5U
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - architecture
  - maintainability
created: 2026-10-11T13:33:42.635Z
updated: 2026-10-11T14:59:44.550Z
blockers: []
order: v
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-11T14:57:12.971Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

Child of KRMA-460 (reopened 2026-10-11: AppViewModel.swift grew from 4,293 lines at KRMA-469 to 5,738). Extract workflow *ownership* into a focused coordinator; do not just split files. Keep AppViewModel the composition root and sole owner of the published EditDocument (see docs/APP_ARCHITECTURE.md). Swift 6, no escape hatches, no broad AppViewModel back-reference from the new collaborator. Not a release blocker. Acceptance: coordinator owns the state and workflow with focused tests that do not construct AppViewModel; AppViewModel keeps thin forwarders; docs/APP_ARCHITECTURE.md ownership table updated; swift build and scripts/ci-tests.sh fast pass. Section: `// MARK: - Copy and paste` (~310 lines). EditClipboardPayload may already be a value type; the document mutation must still go through updateDocument.


### Comment — codex @ 2026-10-11T14:57:10.013Z

Implemented in 2fee1f42. EditClipboardCoordinator now owns clipboard/category values, selective-copy presentation and remembered choices, validation/status messages, and active/batch paste sequencing through a weak, narrow destination. AppViewModel retains thin command/state forwards and remains the sole published document owner; active edits commit through updateDocument. EditorDocumentCoordinator retains per-photo sessions/history/revisions. Preserved displayed-source identity routing during pending selection, per-photo undo, RAW/raster behavior, forced inactive thumbnail/persistence updates, batch flushes, and no-op write suppression. Updated docs/APP_ARCHITECTURE.md and added five coordinator-only tests without AppViewModel. Verification: swift build passed; scripts/ci-tests.sh fast passed all 1,628 tests; focused coordinator tests passed 5/5; serial keyboard/menu copy-paste tests passed 2/2; git diff --check passed. Initial test compilation reported an existing unused-variable warning in unchanged ColorMixerTests.swift:188. Pre-existing DispatchGraph working-tree changes were left untouched. No blockers.

## Agent log

- 2026-10-11T14:59:44.547Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Coordinator owns copy/paste state and workflow, with focused tests that do not construct AppViewModel (pass)
- [x] AppViewModel remains the composition root and sole published EditDocument owner with thin forwarders (pass)
- [x] docs/APP_ARCHITECTURE.md ownership table documents the coordinator boundary (pass)
- [x] swift build succeeds (pass)
- [x] scripts/ci-tests.sh fast passes (pass) — All 1,628 required fast tests passed.
Checks run:
- swift build (passed)
- scripts/ci-tests.sh fast (passed; 1,628 tests)
- git diff --check 2fee1f42^ 2fee1f42 (passed)
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV3Y5TFDNI39DN5U
Summary: Independent verification passed: coordinator owns copy/paste workflow, tests and docs meet acceptance criteria.
