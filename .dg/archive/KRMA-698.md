---
id: KRMA-698
title: Pre-existing KeyMonitorTests retouch-shortcut failures in the serial lane
type: bug
status: done
priority: low
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Reproduce testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime and testRetouchShortcutsArmCycleOverlayAndExitInTwoSteps failures via swift test --filter KeyMonitorTests
      result: pass
      notes: Reproduced prior to fix per issue transcript; confirmed the committed fix (92e3514) resolves both, verified independently with a fresh swift test --filter KeyMonitorTests run (19 passed, 0 failures).
    - criterion: Identify the regression (or environment cause) behind the retouch-shortcut key handling failures
      result: pass
      notes: Root cause confirmed by reading Sources/KromoraKit/Views/KeyboardShortcuts.swift:475-484 — the 'q' shortcut guards on vm.navigation.isEdit. The two tests constructed KeyMonitor without first navigating the view model into Edit, so production behavior (correctly refusing the shortcut outside Edit) was misread as a bug. Not a KeyMonitor regression.
    - criterion: Fix so KeyMonitorTests passes in both --filter isolation and the full render-ui-serial lane
      result: pass
      notes: "Fix adds XCTAssertTrue(viewModel.navigate(to: .edit)) before monitor construction in both tests (commit 92e3514). Verified swift test --filter KeyMonitorTests (19/19 passed) and scripts/ci-tests.sh serial (443 executed, 1 skipped, 0 failures)."
  checks_run:
    - swift test --filter KeyMonitorTests
    - scripts/ci-tests.sh serial
  findings: []
  fixes: []
  verification_commits: []
  actor: claude
  resolved_model: sonnet
  completed_at: 2026-09-28T23:01:27.765Z
  session: 01MULUKIEBAWBUMDBH
creation_provenance:
  runner: claude
  model: sonnet
  actor: claude
labels:
  - verification
created: 2026-09-28T22:19:43.071Z
updated: 2026-09-28T23:01:27.767Z
parent: KRMA-691
blockers: []
order: a0
board: product
---

## Objective

`KeyMonitorTests` has 13 failing assertions across `testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime` and `testRetouchShortcutsArmCycleOverlayAndExitInTwoSteps` in the `render-ui-serial` CI lane. Confirmed pre-existing and unrelated to KRMA-691 (reproduces identically with `Sources/KromoraKit/Views/ContentView.swift` reverted to its last committed state at `18cb3a0`).

## Context

Found while verifying KRMA-691 ("Prevent dramatic library reflow when returning from Edit mode"). `swift test --filter KeyMonitorTests` fails deterministically (not flaky) both with and without the KRMA-691 change and its dead-code cleanup applied. The `q` retouch-arm shortcut and the cycle/overlay/exit shortcut sequence produce unexpected non-nil `monitor.handle(...)` results and wrong `isRetouchCanvasActive`/`isCropToolActive` state, suggesting a KeyMonitor or crop/retouch interaction regression unrelated to library navigation.

## Acceptance criteria

- [ ] Reproduce `testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime` and `testRetouchShortcutsArmCycleOverlayAndExitInTwoSteps` failures via `swift test --filter KeyMonitorTests`.
- [ ] Identify the regression (or environment cause) behind the retouch-shortcut key handling failures.
- [ ] Fix so `KeyMonitorTests` passes in both `--filter` isolation and the full `render-ui-serial` lane.

## Implementation notes

Verification transcript for reference: 13 failures at `Tests/KromoraKitTests/KeyMonitorTests.swift` lines 547-561 and 575-577.

### Comment — codex @ 2026-09-28T22:56:48.754Z

Updated both retouch shortcut tests to enter Edit before invoking the Edit-only q shortcut. The failures were caused by test setup leaving the view model in its default Library workspace; production shortcut behavior was correct. Verified with swift test --filter KeyMonitorTests (19 passed) and scripts/ci-tests.sh serial (443 executed, 1 skipped, 0 failures). Commit: 92e3514.

## Agent log

<!-- Generated summaries only. Detailed activity lives in events.jsonl. -->

- 2026-09-28T23:01:27.765Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Reproduce testArmingRetouchClosesAnActiveCropSoOnlyOneCanvasToolOwnsInputAtATime and testRetouchShortcutsArmCycleOverlayAndExitInTwoSteps failures via swift test --filter KeyMonitorTests (pass) — Reproduced prior to fix per issue transcript; confirmed the committed fix (92e3514) resolves both, verified independently with a fresh swift test --filter KeyMonitorTests run (19 passed, 0 failures).
- [x] Identify the regression (or environment cause) behind the retouch-shortcut key handling failures (pass) — Root cause confirmed by reading Sources/KromoraKit/Views/KeyboardShortcuts.swift:475-484 — the 'q' shortcut guards on vm.navigation.isEdit. The two tests constructed KeyMonitor without first navigating the view model into Edit, so production behavior (correctly refusing the shortcut outside Edit) was misread as a bug. Not a KeyMonitor regression.
- [x] Fix so KeyMonitorTests passes in both --filter isolation and the full render-ui-serial lane (pass) — Fix adds XCTAssertTrue(viewModel.navigate(to: .edit)) before monitor construction in both tests (commit 92e3514). Verified swift test --filter KeyMonitorTests (19/19 passed) and scripts/ci-tests.sh serial (443 executed, 1 skipped, 0 failures).
Checks run:
- swift test --filter KeyMonitorTests
- scripts/ci-tests.sh serial
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: claude
Resolved model: sonnet
Pickup session: 01MULUKIEBAWBUMDBH
Summary: Verified: retouch-shortcut test failures were missing Edit-workspace setup, not a KeyMonitor regression. q guards on vm.navigation.isEdit (KeyboardShortcuts.swift:475-484); fix adds navigate(to: .edit) before monitor construction. swift test --filter KeyMonitorTests: 19/19 passed. scripts/ci-tests.sh serial: 443 executed, 1 skipped, 0 failures.
