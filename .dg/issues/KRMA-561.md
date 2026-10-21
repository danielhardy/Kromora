---
id: KRMA-561
title: Bound asynchronous import waits in KeyMonitorTests
type: bug
status: done
priority: medium
verification_report:
  verdict: pass
  acceptance_criteria:
    - criterion: Each view model in the test uses an independent temporary package and writer lease.
      result: pass
      notes: The 043c2c0 fix introduced distinct temporary package URLs. KRMA-920 later deleted the KeyMonitorTests suite and replaced the monitor architecture.
    - criterion: Each source wait has its own bounded timeout and reports which source failed to open.
      result: pass
      notes: The original fix used independent throwing five-second waits with source-specific timeout messages. The test was later removed with KeyMonitor.
    - criterion: Timeout exits the test instead of repeatedly recording assertions while continuing to wait.
      result: pass
      notes: The original wait throws on timeout; the old monitor-based test and implementation were subsequently removed by KRMA-920.
    - criterion: The focused KeyMonitor test passes.
      result: pass
      notes: The issue handoff records the focused test passing after 043c2c0. KeyMonitorTests.swift was deleted by KRMA-920; current replacement KeyboardCommandRouterTests and KeyboardShortcutCatalogTests both pass.
  checks_run:
    - Reviewed commit 187e09e4, which removes KeyMonitorTests.swift and adds the responder-chain keyboard architecture.
    - swift test --filter KeyboardCommandRouterTests (18 tests passed).
    - swift test --filter KeyboardShortcutCatalogTests (11 tests passed).
    - KeyboardShortcutCatalogTests.testNoKeyEventMonitorsRemainInTheProduct passed.
  findings: []
  fixes: []
  verification_commits: []
  actor: human
  resolved_model: unknown
  completed_at: 2026-10-21T12:33:18.060Z
creation_provenance:
  runner: codex
  model: gpt-6-luna
  actor: codex
labels:
  - verification
created: 2026-09-24T03:11:17.182Z
updated: 2026-10-21T12:33:18.063Z
blockers: []
order: zzzzzq
board: product
---

## Objective
Make the asynchronous photo-open setup in `KeyMonitorTests.testPlainCommandCopyAndPasteRouteOnlyWhenGlobalSurfaceOwnsKeyboard` isolated and bounded so it cannot hang the serial test lane.

## Acceptance criteria
- Each view model in the test uses an independent temporary package and writer lease.
- Each source wait has its own bounded timeout and reports which source failed to open.
- Timeout exits the test instead of repeatedly recording assertions while continuing to wait.
- The focused KeyMonitor test passes.

## Findings
The serial XCTest process was sampled in this test at the wait for `keyboard-text-focus.png`. All three view models used the same default `Test Library.kromoralibrary` path from `makeAppViewModel`, while the first view model remained alive and held its writer lease. The second view model therefore could not open the package. The old `XCTAssertLessThan(Date(), deadline)` only recorded failures and did not stop the loop; the single deadline was also shared by all three imports.

## Files and checks
- `Tests/KromoraKitTests/KeyMonitorTests.swift`
- Focused `KeyMonitorTests.testPlainCommandCopyAndPasteRouteOnlyWhenGlobalSurfaceOwnsKeyboard` passed.


### Comment — codex @ 2026-09-24T03:15:33.442Z

Fixed the serial-lane hang by giving each view model a unique temporary package and replacing the unbounded source waits with independent five-second throwing waits. The focused KeyMonitor test passes in 1.065s. Commit: 043c2c0.

## Agent log

- 2026-10-21T12:33:18.060Z: Verification report
Verdict: PASS
Acceptance criteria:
- [x] Each view model in the test uses an independent temporary package and writer lease. (pass) — The 043c2c0 fix introduced distinct temporary package URLs. KRMA-920 later deleted the KeyMonitorTests suite and replaced the monitor architecture.
- [x] Each source wait has its own bounded timeout and reports which source failed to open. (pass) — The original fix used independent throwing five-second waits with source-specific timeout messages. The test was later removed with KeyMonitor.
- [x] Timeout exits the test instead of repeatedly recording assertions while continuing to wait. (pass) — The original wait throws on timeout; the old monitor-based test and implementation were subsequently removed by KRMA-920.
- [x] The focused KeyMonitor test passes. (pass) — The issue handoff records the focused test passing after 043c2c0. KeyMonitorTests.swift was deleted by KRMA-920; current replacement KeyboardCommandRouterTests and KeyboardShortcutCatalogTests both pass.
Checks run:
- Reviewed commit 187e09e4, which removes KeyMonitorTests.swift and adds the responder-chain keyboard architecture.
- swift test --filter KeyboardCommandRouterTests (18 tests passed).
- swift test --filter KeyboardShortcutCatalogTests (11 tests passed).
- KeyboardShortcutCatalogTests.testNoKeyEventMonitorsRemainInTheProduct passed.
Findings:
- None
Fixes:
- None
Verification commits:
- None
Actor: human
Resolved model: unknown
Summary: Verified as superseded by KRMA-920; the original focused test passed after the fix, and the current keyboard router and catalog suites pass (29 tests).
