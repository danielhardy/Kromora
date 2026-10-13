---
id: KRMA-919
title: Investigate intermittent stored-edit adoption supersession failure
type: task
status: done
priority: low
human_review_required: false
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Determine whether the failure is a product race or a test synchronization issue under parallel execution.
      result: pass
      notes: The stale materialization is fenced by loadRequestGeneration. The original placeholder assertion was invalid under legitimate idle neighbour warming.
    - criterion: Ensure a superseded photo's delayed materialization cannot publish after another photo becomes active, and make the regression deterministic under the fast lane.
      result: pass
      notes: The regression now asserts the active editor photo, ready preview state, and edit navigation after releasing the stale request.
    - criterion: swift test --filter 'StoredEditAdoptionTests/testSlowMaterializationCannotReopenSupersededPhoto' passes.
      result: pass
    - criterion: scripts/ci-tests.sh fast exits 0.
      result: pass
  checks_run:
    - swift test --filter 'StoredEditAdoptionTests/testSlowMaterializationCannotReopenSupersededPhoto' (exit 0; 1 test passed)
    - scripts/ci-tests.sh fast (exit 0; 1,804 tests)
  findings: []
  fixes: []
  verification_commits:
    - 9c66f1fe
  actor: codex
  resolved_model: gpt-6-luna
  completed_at: 2026-10-13T17:10:09.256Z
  session: 01MV6XO4L867OGADZR
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
created: 2026-10-13T01:50:05.794Z
updated: 2026-10-13T17:18:06.743Z
parent: KRMA-917
blockers: []
order: a0
board: product
footprint:
  source: observed
  paths: []
  observed:
    paths: []
    captured_at: 2026-10-13T17:06:45.398Z
    unavailable_reason: "missing_commits: no implementation commits are recorded"
commits:
  - 9c66f1fe
---

## Objective

Investigate an intermittent failure in the stored-edit adoption supersession regression under the parallel fast lane.

## Context

During independent verification of KRMA-917, the first `scripts/ci-tests.sh fast` run failed once in `StoredEditAdoptionTests.testSlowMaterializationCannotReopenSupersededPhoto` at `Tests/KromoraKitTests/StoredEditAdoptionTests.swift:364`, on the assertion that the superseded photo remains a browsing placeholder after delayed materialization is released. The same test passed immediately when rerun alone, and the full fast lane passed on a subsequent run. The observation is intermittent and outside KRMA-917's dust-suggestion test change.

## Acceptance criteria

- [ ] Determine whether the failure is a product race or a test synchronization issue under parallel execution.
- [ ] Ensure a superseded photo's delayed materialization cannot publish after another photo becomes active, and make the regression deterministic under the fast lane.
- [ ] `swift test --filter 'StoredEditAdoptionTests/testSlowMaterializationCannotReopenSupersededPhoto'` passes.
- [ ] `scripts/ci-tests.sh fast` exits 0.

## Implementation notes

Keep the stored-edit adoption ownership/supersession contract intact. If the production path is correct, tighten the test's synchronization rather than adding scheduling delays to production code.

### Comment — claude @ 2026-10-13T14:48:41.543Z

Release-readiness review (2026-10-13) found the same test also hangs in teardown when waitUntil throws before gate.release(oneID) (shutdown awaits the gated task forever). Concrete fix + timeout tolerance is tracked in KRMA-927; coordinate rather than duplicate.

### Comment — claude @ 2026-10-13T17:06:41.531Z

Test synchronization issue, not a product race. The superseded open is fenced by loadRequestGeneration (AppViewModel ~L2093) and never changes the active photo. The failing assertion expected one.png to stay a placeholder, but once two.png is idle, PreviewAdmissionCoordinator.warmBrowsingNeighbourDocuments legitimately resolves adjacent placeholders (one.png is a neighbour), so it raced under parallel load. Test now asserts sourceName/previewState/navigation stay on two.png. Filtered suite and scripts/ci-tests.sh fast pass (exit 0). The teardown hang / timeout tolerance remains for KRMA-927.

### Comment — claude @ 2026-10-13T17:13:33.812Z

KRMA-927 (8e2fa611) releases the MaterializationGate on every exit path (teardown releaseAll) and raises the wait timeouts to 30 s.

### Comment — codex @ 2026-10-13T17:18:06.742Z

KRMA-927 is independently verified and completed. The gate release is registered in teardown for every gated test, and the async wait deadline is now 30 s. The 1 ms timeout proof failed cleanly in 1.5 s without hanging; the StoredEditAdoptionTests suite passed three consecutive runs. One unrelated parallel fast-lane scratch-directory collision is tracked as KRMA-968.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-10-13T17:10:09.256Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Determine whether the failure is a product race or a test synchronization issue under parallel execution. (pass) — The stale materialization is fenced by loadRequestGeneration. The original placeholder assertion was invalid under legitimate idle neighbour warming.
- [x] Ensure a superseded photo's delayed materialization cannot publish after another photo becomes active, and make the regression deterministic under the fast lane. (pass) — The regression now asserts the active editor photo, ready preview state, and edit navigation after releasing the stale request.
- [x] swift test --filter 'StoredEditAdoptionTests/testSlowMaterializationCannotReopenSupersededPhoto' passes. (pass)
- [x] scripts/ci-tests.sh fast exits 0. (pass)
Checks run:
- swift test --filter 'StoredEditAdoptionTests/testSlowMaterializationCannotReopenSupersededPhoto' (exit 0; 1 test passed)
- scripts/ci-tests.sh fast (exit 0; 1,804 tests)
Findings:
- None
Fixes:
- None
Verification commits:
- 9c66f1fe
Actor: codex
Resolved model: gpt-6-luna
Pickup session: 01MV6XO4L867OGADZR
Summary: Pass: superseded materialization remains fenced; regression checks pass.
