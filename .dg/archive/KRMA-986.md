---
id: KRMA-986
title: Remove remaining synchronous modal prompts
type: task
status: done
priority: urgent
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Grep of Sources for runModal call expressions lists only the documented KromoraAppDelegate quit-time alert.
      result: pass
      notes: rg -n '\.runModal\s*\(' Sources found only KromoraAppDelegate's quit-time save-failure alert.
    - criterion: Fake-driven tests cover recovery accept and cancel plus quit approval and cancellation.
      result: pass
      notes: AppLaunchTests cover recovery accept/cancel; TerminationGuardTests cover both quit responses through FakeSheets.
    - criterion: swift build, scripts/ci-tests.sh fast, and scripts/ci-tests.sh serial pass.
      result: pass
      notes: swift build exited 0; fast lane exited 0 with 1,851 tests; serial lane exited 0 with 543 tests and 0 failures.
  checks_run:
    - swift build — exit 0
    - scripts/ci-tests.sh fast — exit 0; 1,851 tests
    - scripts/ci-tests.sh serial — exit 0; 543 tests, 0 failures
    - rg -n '\.runModal\s*\(' Sources — exit 0; only the documented KromoraAppDelegate quit-time alert
    - git diff --check — exit 0
  findings: []
  fixes:
    - Preserved the single-window close behavior by keeping applicationShouldTerminateAfterLastWindowClosed enabled, routing last-window close through deferred confirmation and persistence flush.
  verification_commits: []
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T21:42:48.967Z
  session: 01MV77A6RF1BHV235A
creation_provenance:
  runner: codex
  model: unknown
  actor: codex
labels:
  - verification
created: 2026-10-13T21:19:24.455Z
updated: 2026-10-13T21:42:48.970Z
parent: KRMA-948
blockers: []
order: n
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T21:35:49.893Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
---

KRMA-948 verification found runModal calls in AppKitPortablePackageLeaseRecoveryConfirmer and AppKitQuitConfirmation. The launch recovery confirmation runs before a window exists, and applicationShouldTerminate requires a synchronous decision; both currently bypass the sheet seam. Refactor these startup and termination lifecycles to use sheet-compatible asynchronous presentation while preserving recovery accept/cancel behavior and quit/cancel behavior, then remove the remaining runModal calls outside KromoraAppDelegate. Acceptance criteria: grep of Sources for runModal call expressions lists only the documented KromoraAppDelegate quit-time alert; fake-driven tests cover recovery accept and cancel plus quit approval and cancellation; swift build, scripts/ci-tests.sh fast, and scripts/ci-tests.sh serial pass.

## Agent log

- 2026-10-13T21:42:48.967Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Grep of Sources for runModal call expressions lists only the documented KromoraAppDelegate quit-time alert. (pass) — rg -n '\.runModal\s*\(' Sources found only KromoraAppDelegate's quit-time save-failure alert.
- [x] Fake-driven tests cover recovery accept and cancel plus quit approval and cancellation. (pass) — AppLaunchTests cover recovery accept/cancel; TerminationGuardTests cover both quit responses through FakeSheets.
- [x] swift build, scripts/ci-tests.sh fast, and scripts/ci-tests.sh serial pass. (pass) — swift build exited 0; fast lane exited 0 with 1,851 tests; serial lane exited 0 with 543 tests and 0 failures.
Checks run:
- swift build — exit 0
- scripts/ci-tests.sh fast — exit 0; 1,851 tests
- scripts/ci-tests.sh serial — exit 0; 543 tests, 0 failures
- rg -n '\.runModal\s*\(' Sources — exit 0; only the documented KromoraAppDelegate quit-time alert
- git diff --check — exit 0
Findings:
- None
Fixes:
- Preserved the single-window close behavior by keeping applicationShouldTerminateAfterLastWindowClosed enabled, routing last-window close through deferred confirmation and persistence flush.
Verification commits:
- None
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV77A6RF1BHV235A
Summary: Verification passed: build, fast and serial lanes pass; restored last-window termination routing.
